-- Reinício das carreiras (Fase 3 do plano de temporadas). Execução única, numa só transação.
-- Rodar com supabase/maintenance/reset/run.mjs: "dry" ensaia e desfaz tudo; "apply" grava.
-- Pré-requisitos: manutenção ativa, backup privado conferido, foto em reset_rank_snapshot.
-- Se qualquer pontuação do rank geral, posição, moeda, diamante, nível, XP, reputação, credibilidade
-- ou dado de apostas mudar, a transação inteira é desfeita.
create table if not exists public.reset_runs(id serial primary key,at timestamptz not null default now(),applied boolean not null,log jsonb not null);
alter table public.reset_runs enable row level security;
revoke all on public.reset_runs from anon,authenticated;

do $reset$
declare
 apply boolean := __APPLY__;
 c record; x jsonb; n bigint; bad bigint; t0 timestamptz := clock_timestamp();
 log jsonb := '[]'::jsonb;
begin
 perform set_config('statement_timeout','1200s',true);
 if not exists(select 1 from public.reset_rank_snapshot) then raise exception 'Foto dos ranks ausente';end if;

 -- 1. Dados preservados voltam exatamente à foto (a carreira de teste do admin jogou temporadas da Fase 2).
 update public.careers k set level=(s.careers_row->>'level')::int,xp=(s.careers_row->>'xp')::int,
  coins=(s.careers_row->>'coins')::bigint,diamonds=(s.careers_row->>'diamonds')::bigint
 from public.reset_rank_snapshot s where s.career_id=k.id
  and (k.level,k.xp,k.coins,k.diamonds) is distinct from ((s.careers_row->>'level')::int,(s.careers_row->>'xp')::int,(s.careers_row->>'coins')::bigint,(s.careers_row->>'diamonds')::bigint);
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','restore careers','rows',n);
 update public.mgr_coach m set reputation=(s.mgr_coach_row->>'reputation')::numeric
 from public.reset_rank_snapshot s where s.career_id=m.career_id and s.mgr_coach_row is not null and m.reputation<>(s.mgr_coach_row->>'reputation')::numeric;
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','restore reputation','rows',n);
 update public.cw_coach k set credibility=(s.cw_coach_row->>'credibility')::numeric
 from public.reset_rank_snapshot s where s.career_id=k.career_id and s.cw_coach_row is not null and k.credibility<>(s.cw_coach_row->>'credibility')::numeric;
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','restore credibility','rows',n);

 -- 2. Legado: pontos de hoje menos a parte que continua viva (nível, XP, reputação)
 delete from public.career_legacy;
 insert into public.career_legacy(career_id,legacy_points,previous)
 select s.career_id,
  s.points-(s.level*100+floor(coalesce(s.xp,0)/10.0)+round(coalesce(s.reputation,0)*15))::bigint,
  jsonb_build_object('points',s.points,'position',s.position,'titles',s.titles,'wins',s.wins,'draws',s.draws,
   'losses',(s.mgr_coach_row->>'losses')::int,'matches',(s.mgr_coach_row->>'matches')::int,'fired',s.fired,'events',s.events,
   'seasons',(s.mgr_coach_row->>'seasons')::int,'reputation',s.reputation,'credibility',s.credibility,
   'difficulty',s.careers_row->>'difficulty_level',
   'clubs',coalesce((select jsonb_agg(distinct sp.club_id) from public.mgr_spells sp where sp.career_id=s.career_id),'[]'::jsonb))
 from public.reset_rank_snapshot s;
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','legacy','rows',n);

 -- 3. Mundo de cada carreira, cartas, inventário, eventos concluídos e bilhetes encerrados
 for c in select id from public.careers order by created_at loop
  x:=public.career_reset_world(c.id);
 end loop;
 delete from public.base_card_roster;delete from public.base_card_compensations;delete from public.career_card_state;
 delete from public.user_cards;delete from public.reward_boxes;
 delete from public.event_completions;
 delete from public.tickets where status in('won','lost');
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','careers reset','settled_tickets_removed',n);
 update public.careers set difficulty_level='normal',difficulty='standard',country='BR',club_id=null;

 -- 4. Catálogo: saem as 5 competições inglesas, os 44 clubes e os 1.221 atletas (apostas em jogos reais não usam estas tabelas)
 delete from public.sim_promotion_rules r using public.sim_competitions co where co.region='ENG' and co.id in(r.upper_comp,r.lower_comp);
 delete from public.cw_rivalries r using public.sim_clubs cl where cl.region='ENG' and cl.id in(r.club_a,r.club_b);
 delete from public.cw_club_economy_models m using public.sim_clubs cl where cl.region='ENG' and cl.id=m.club_id;
 delete from public.sim_players p using public.sim_clubs cl where cl.region='ENG' and cl.id=p.club_id;
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','english players','rows',n);
 delete from public.sim_competitions where region='ENG';
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','english competitions','rows',n);
 delete from public.sim_clubs where region='ENG';
 get diagnostics n=row_count;
 log:=log||jsonb_build_object('step','english clubs','rows',n);
 delete from public.sim_start_rules where country<>'BR';
 perform public.sim_player_base_refresh();

 -- 5. Rank geral novo: legado + parte viva + contadores novos, sem peso de dificuldade
 create or replace function public.ranking_scores()
  returns table(career_id uuid,nickname text,photo_id text,level integer,club_id text,titles integer,wins integer,draws integer,losses integer,
   reputation numeric,events integer,fired integer,points bigint,created_at timestamptz,xp integer,avatar text,has_photo boolean)
  language sql stable security definer set search_path to 'public' as $f$
  select c.id,c.nickname,c.photo_id,c.level,
   case when mc.status='employed' then mc.club_id end,
   coalesce(mc.titles,0),coalesce(mc.wins,0),coalesce(mc.draws,0),coalesce(mc.losses,0),round(coalesce(mc.reputation,0),1),
   coalesce(ev.n,0)::int,coalesce(mc.fired_count,0),
   (coalesce(lg.legacy_points,0)+c.level*100+floor(coalesce(c.xp,0)/10.0)+round(coalesce(mc.reputation,0)*15)
    +coalesce(mc.titles,0)*500+coalesce(mc.wins,0)*20+coalesce(mc.draws,0)*7+coalesce(ev.n,0)*25-coalesce(mc.fired_count,0)*150)::bigint,
   c.created_at,coalesce(c.xp,0),
   case when pp.avatar_data like 'data:%' then null else pp.avatar_data end,coalesce(pp.avatar_data like 'data:%',false)
  from public.careers c
  left join public.career_legacy lg on lg.career_id=c.id
  left join public.mgr_coach mc on mc.career_id=c.id
  left join public.player_profiles pp on pp.career_id=c.id
  left join (select e.career_id,count(*) n from public.event_completions e group by e.career_id) ev on ev.career_id=c.id
  where c.status='active'
 $f$;

 -- 6. Mundo novo (Brasil + Libertadores), técnico desempregado e 3 propostas da Série A
 for c in select id from public.careers where status='active' order by created_at loop
  perform public.career_begin_unemployed(c.id);
  n:=public.career_reset_offers(c.id);
  if n<>3 then raise exception 'Carreira % recebeu % propostas',c.id,n;end if;
 end loop;
 log:=log||jsonb_build_object('step','worlds and offers','seconds',round(extract(epoch from clock_timestamp()-t0)));

 -- 7. Conferência: qualquer diferença desfaz tudo
 select count(*) into bad from public.reset_rank_snapshot s join public.ranking_scores() r on r.career_id=s.career_id where r.points<>s.points;
 if bad>0 then raise exception 'Pontos do rank geral mudaram em % carreiras',bad;end if;
 select count(*) into bad from public.reset_rank_snapshot s
  join(select r.career_id,row_number() over(order by r.points desc,r.level desc,r.wins desc,r.created_at,r.career_id) pos from public.ranking_scores() r) p on p.career_id=s.career_id
  where p.pos<>s.position and exists(select 1 from public.reset_rank_snapshot o where o.career_id<>s.career_id and o.points=s.points);
 log:=log||jsonb_build_object('step','tied positions reordered','rows',bad);
 select count(*) into bad from public.reset_rank_snapshot s
  join(select r.career_id,row_number() over(order by r.points desc,r.level desc,r.wins desc,r.created_at,r.career_id) pos from public.ranking_scores() r) p on p.career_id=s.career_id
  where p.pos<>s.position and not exists(select 1 from public.reset_rank_snapshot o where o.career_id<>s.career_id and o.points=s.points);
 if bad>0 then raise exception 'Posição do rank geral mudou em % carreiras sem empate',bad;end if;
 select count(*) into bad from public.reset_rank_snapshot s join public.careers k on k.id=s.career_id
  where (k.level,k.xp,k.coins,k.diamonds) is distinct from ((s.careers_row->>'level')::int,(s.careers_row->>'xp')::int,(s.careers_row->>'coins')::bigint,(s.careers_row->>'diamonds')::bigint);
 if bad>0 then raise exception 'Nível, XP, moedas ou diamantes mudaram em % carreiras',bad;end if;
 select count(*) into bad from public.reset_rank_snapshot s join public.mgr_coach m on m.career_id=s.career_id
  where s.mgr_coach_row is not null and m.reputation<>(s.mgr_coach_row->>'reputation')::numeric;
 if bad>0 then raise exception 'Reputação mudou em % carreiras',bad;end if;
 select count(*) into bad from public.cw_coach k left join public.reset_rank_snapshot s on s.career_id=k.career_id
  where k.credibility<>coalesce((s.cw_coach_row->>'credibility')::numeric,65);
 if bad>0 then raise exception 'Credibilidade mudou em % carreiras',bad;end if;
 select count(*) into bad from public.reset_rank_snapshot s left join public.prediction_stats p on p.career_id=s.career_id
  where s.prediction_row is distinct from (case when p.career_id is null then null else to_jsonb(p) end);
 if bad>0 then raise exception 'Rank de apostas mudou em % carreiras',bad;end if;
 select count(*) into bad from public.season_participants pa join public.sim_clubs cl on cl.id=pa.club_id where cl.region='ENG';
 if bad>0 then raise exception 'Clube inglês ainda no modo carreira';end if;
 log:=log||jsonb_build_object('step','checks','ok',true,'seconds',round(extract(epoch from clock_timestamp()-t0)));

 if not apply then raise exception 'DRY RUN OK %',log::text;end if;
 insert into public.reset_runs(applied,log) values(true,log);
end
$reset$;
