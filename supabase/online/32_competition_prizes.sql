-- MODO ONLINE — Fase 30: premiação da Liga e da Copa Online, insígnias de campeão e lances iniciais mais altos.
--
-- Referência é o mercado: destaque sai por $ 440 mil a $ 760 mil, lenda abre em $ 2,5 a 3,5 milhões e o nível Messi
-- (potencial acima de 100) a partir de $ 5 milhões. O prêmio entra no CAIXA do clube (os clubes passam de uma
-- temporada para a outra), para o técnico investir no mercado.
--  • Copa: paga no apito final da final (on_award_cup), não espera a liga.
--  • Liga: paga no fim da temporada (on_award_league), no lugar dos prêmios antigos (caixa só para bots e moedas).
--  • Técnicos recebem também diamantes, energia, XP e (copa) pontos de ranking. Isso vai numa mensagem
--    personalizada na caixa de entrada (player_notices), resgatada pelo técnico. O dinheiro já entra no caixa na hora.
--  • Insígnias (on_honors): "Primeiro Campeão" da liga e da copa existem uma vez só (índice único); os campeões
--    seguintes recebem a insígnia comum de campeão. A insígnia aparece no perfil depois do resgate.
--  • Primeiro campeão: bônus de $ 1 milhão, 300 diamantes e 1 Apito de Ouro (prize_first).
--  • Ranking: os pontos da copa passam a entrar na hora (on_rank_season deixa de somar a copa).
--  • Lances iniciais: lenda $ 2,5 a 3,5 mi, destaque a partir de $ 700 mil (nível Messi segue a partir de $ 5 mi).

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas de prêmio
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.on_config add column if not exists prize_league jsonb not null default '[
 {"cash":5000000,"diamonds":300,"energy":50,"xp":3000},
 {"cash":3500000,"diamonds":180,"energy":35,"xp":2000},
 {"cash":2500000,"diamonds":120,"energy":25,"xp":1500},
 {"cash":1800000,"diamonds":80,"energy":20,"xp":1200},
 {"cash":1400000,"diamonds":50,"energy":15,"xp":900},
 {"cash":1100000,"diamonds":50,"energy":15,"xp":900},
 {"cash":900000,"diamonds":30,"energy":10,"xp":600},
 {"cash":750000,"diamonds":30,"energy":10,"xp":600},
 {"cash":600000,"diamonds":30,"energy":10,"xp":600},
 {"cash":450000,"diamonds":15,"energy":5,"xp":400},
 {"cash":350000,"diamonds":15,"energy":5,"xp":400},
 {"cash":250000,"diamonds":15,"energy":5,"xp":400}]'::jsonb;
alter table public.on_config add column if not exists prize_cup jsonb not null default '{
 "champion":{"cash":3000000,"diamonds":200,"energy":30,"xp":2000},
 "final":{"cash":1500000,"diamonds":90,"energy":20,"xp":1200},
 "sf":{"cash":800000,"diamonds":40,"energy":10,"xp":600},
 "qf":{"cash":400000,"diamonds":10,"energy":5,"xp":200},
 "r1":{"cash":200000,"diamonds":10,"energy":5,"xp":200}}'::jsonb;
alter table public.on_config add column if not exists prize_first jsonb not null default '{"cash":1000000,"diamonds":300,"golden_whistle":1}'::jsonb;
alter table public.on_seasons add column if not exists cup_paid_at timestamptz;
alter table public.on_seasons add column if not exists league_paid_at timestamptz;

-- Insígnias de campeão da Liga (L) e da Copa (C). first: a do primeiro campeão (só uma por competição, para sempre).
create table if not exists public.on_honors(
 id bigint generated always as identity primary key,
 user_id uuid not null,
 comp char(1) not null check (comp in('L','C')),
 first boolean not null default false,
 season_id smallint not null,
 club_id int,
 club_name text,
 awarded_at timestamptz not null default now(),
 claimed_at timestamptz
);
create unique index if not exists on_honors_first on public.on_honors(comp) where first;
create unique index if not exists on_honors_season on public.on_honors(season_id,comp);
alter table public.on_honors enable row level security;
revoke all on public.on_honors from anon,authenticated;

-- Insígnias de um usuário já resgatadas (perfil). Campeão comum vem agrupado com a contagem.
create or replace function public.on_honors_json(p_user uuid) returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(x order by x.rank,x.last desc),'[]'::jsonb) from(
  select case when h.first then 'first_' else '' end||case h.comp when 'L' then 'league' else 'cup' end id,
   case when h.first then 'Primeiro Campeão da '||case h.comp when 'L' then 'Liga' else 'Copa' end||' Online'
    else 'Campeão da '||case h.comp when 'L' then 'Liga' else 'Copa' end||' Online' end label,
   h.first,h.comp,count(*) n,max(h.awarded_at) last,
   jsonb_agg(jsonb_build_object('season',h.season_id,'club',h.club_name) order by h.season_id) seasons,
   case when h.first then 0 else 1 end rank
  from public.on_honors h where h.user_id=p_user and h.claimed_at is not null
  group by h.first,h.comp) x
$$;
revoke all on function public.on_honors_json(uuid) from public,anon,authenticated;

-- Fase que cada clube alcançou na copa: champion, final, sf, qf ou r1 (nulo: não jogou).
create or replace function public.on_cup_reach(p_season smallint,p_club int) returns text
language sql stable security definer set search_path=public as $$
 select case when bool_or(f.stage='final' and f.status='done' and public.on_cup_winner(f)=p_club) then 'champion'
  else (array['r1','qf','sf','final'])[max(f.round)] end
 from public.on_fixtures f where f.season_id=p_season and f.comp='C' and p_club in(f.home,f.away)
$$;
revoke all on function public.on_cup_reach(smallint,int) from public,anon,authenticated;

create or replace function public.on_fmt_money(v bigint) returns text language sql immutable as $$
 select '$ '||replace(to_char(v,'FM999,999,999,999'),',','.')
$$;

-- Entrega a um técnico: dinheiro no caixa agora; diamantes, energia, XP, apito e insígnia pela caixa de entrada.
create or replace function public.on_award(p_season smallint,p_club int,p_comp char,p_place text,p_prize jsonb,p_rank int) returns void
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;s public.on_seasons;cfg public.on_config;v_first boolean:=false;v_cash bigint;rw jsonb:='{}'::jsonb;
 v_title text;v_body text;v_comp text:=case p_comp when 'L' then 'Liga Online' else 'Copa Online' end;v_car uuid;v_honor text;
begin
 select * into k from public.on_clubs where id=p_club for update;
 select * into s from public.on_seasons where id=p_season;
 select * into cfg from public.on_config;
 v_cash:=coalesce((p_prize->>'cash')::bigint,0);
 -- campeão de técnico: insígnia (a primeira de cada competição é a rara, só na liga principal)
 if k.user_id is not null and p_place in('champion','1') then
  if s.kind='main' and not exists(select 1 from public.on_honors where comp=p_comp and first) then
   insert into public.on_honors(user_id,comp,first,season_id,club_id,club_name) values(k.user_id,p_comp,true,p_season,k.id,k.name)
   on conflict do nothing;
   v_first:=found;
  end if;
  if not v_first then
   insert into public.on_honors(user_id,comp,season_id,club_id,club_name) values(k.user_id,p_comp,p_season,k.id,k.name) on conflict do nothing;
  end if;
  v_honor:=case when v_first then 'honor_first_' else 'honor_' end||case p_comp when 'L' then 'league' else 'cup' end;
  if v_first then v_cash:=v_cash+coalesce((cfg.prize_first->>'cash')::bigint,0);end if;
 end if;
 if v_cash>0 then perform public.on_money(k.id,v_cash,'prize',format('%s: %s',v_comp,case p_place when 'champion' then 'campeão' when 'final' then 'vice'
  when 'sf' then 'semifinal' when 'qf' then 'quartas de final' when 'r1' then 'primeira fase' else p_place||'º lugar' end));end if;
 if k.user_id is null then return;end if;

 -- pontos de ranking da copa (a liga segue em on_rank_season)
 if coalesce(p_rank,0)>0 then
  insert into public.on_ranking as r(user_id,points,pts_season,cups) values(k.user_id,p_rank,p_rank,(p_place='champion')::int)
  on conflict(user_id) do update set points=r.points+excluded.points,pts_season=r.pts_season+excluded.pts_season,
   cups=r.cups+excluded.cups,updated_at=now();
 end if;

 rw:=jsonb_strip_nulls(jsonb_build_object(
  'diamonds',nullif(coalesce((p_prize->>'diamonds')::int,0)+case when v_first then coalesce((cfg.prize_first->>'diamonds')::int,0) else 0 end,0),
  'bonus_energy',nullif(coalesce((p_prize->>'energy')::int,0),0),
  'xp',nullif(coalesce((p_prize->>'xp')::int,0),0),
  'golden_whistle',case when v_first then nullif(coalesce((cfg.prize_first->>'golden_whistle')::int,0),0) end));
 if v_honor is not null then rw:=rw||jsonb_build_object(v_honor,1);end if;

 v_title:=case
  when v_first then format('Você é o PRIMEIRO CAMPEÃO DA %s!',upper(v_comp))
  when p_place in('champion','1') then format('Campeão da %s!',v_comp)
  when p_place='final' then format('Vice-campeão da %s',v_comp)
  when p_place='sf' then format('Semifinal da %s',v_comp)
  when p_place='qf' then format('Quartas de final da %s',v_comp)
  when p_place='r1' then format('Participação na %s',v_comp)
  else format('%sº lugar na %s',p_place,v_comp) end;
 v_body:=concat_ws(E'\n',
  case when v_first then format('Parabéns, %s! O %s entra para a história como o primeiro campeão da %s. Essa conquista é única: ninguém mais vai ter a insígnia de Primeiro Campeão.',
    coalesce(public.on_coach_name(k.user_id),'técnico'),k.name,v_comp)
   when p_place in('champion','1') then format('Parabéns, %s! O %s é campeão da %s (temporada %s).',coalesce(public.on_coach_name(k.user_id),'técnico'),k.name,v_comp,p_season)
   else format('%s, o %s terminou a %s com %s.',coalesce(public.on_coach_name(k.user_id),'Técnico'),k.name,v_comp,
    case p_place when 'final' then 'o vice-campeonato' when 'sf' then 'a semifinal' when 'qf' then 'as quartas de final'
     when 'r1' then 'a participação na primeira fase' else p_place||'º lugar' end) end,
  '',
  'PRÊMIOS',
  format('• %s já estão no caixa do clube para investir no mercado.',public.on_fmt_money(v_cash)),
  case when (rw->>'diamonds') is not null then format('• %s diamantes',rw->>'diamonds') end,
  case when (rw->>'bonus_energy') is not null then format('• %s de energia',rw->>'bonus_energy') end,
  case when (rw->>'xp') is not null then format('• %s de XP',replace(to_char((rw->>'xp')::int,'FM999,999'),',','.')) end,
  case when (rw->>'golden_whistle') is not null then format('• %s Apito de Ouro',rw->>'golden_whistle') end,
  case when coalesce(p_rank,0)>0 then format('• %s pontos no ranking (já somados)',p_rank) end,
  case when p_comp='L' then '• Pontos no ranking pela colocação (já somados)' end,
  case when v_honor is not null then format('• Insígnia %s para o seu perfil',
    case when v_first then 'rara "Primeiro Campeão da '||v_comp||'"' else '"Campeão da '||v_comp||'"' end) end,
  '',
  'Toque em Resgatar para receber diamantes, energia, XP'||case when v_honor is not null then ' e a insígnia' else '' end||'.');
 v_car:=public.on_career_of(k.user_id);
 if v_car is not null then
  insert into public.player_notices(career_id,kind,title,body,reward) values(v_car,'reward',left(v_title,120),left(v_body,2000),rw);
 end if;
 insert into public.on_news(club_id,kind,text) values(k.id,'season',format('%s: prêmio de %s no caixa. Resgate o resto na caixa de entrada.',v_title,public.on_fmt_money(v_cash)));
end $$;

-- Copa: paga todos os clubes pela fase alcançada, uma vez, assim que a final termina.
create or replace function public.on_award_cup(p_season smallint) returns boolean
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;rr jsonb;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if s.cup_paid_at is not null then return false;end if;
 if not exists(select 1 from public.on_fixtures where season_id=p_season and comp='C' and stage='final' and status='done') then return false;end if;
 select * into cfg from public.on_config;
 rr:=cfg.rank_rules->'cup';
 for r in select k.id,public.on_cup_reach(p_season,k.id) reach from public.on_clubs k where k.season_id=p_season order by k.id loop
  continue when r.reach is null;
  perform public.on_award(p_season,r.id,'C',r.reach,cfg.prize_cup->r.reach,coalesce((rr->>r.reach)::int,0));
 end loop;
 update public.on_seasons set cup_paid_at=now() where id=p_season;
 return true;
end $$;

-- Liga: paga todos os clubes pela colocação final, uma vez (chamada no fim da temporada).
create or replace function public.on_award_league(p_season smallint) returns boolean
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if s.league_paid_at is not null then return false;end if;
 select * into cfg from public.on_config;
 -- copa antiga não paga (temporada que fechou antes desta fase): paga junto
 perform public.on_award_cup(p_season);
 for r in select x.club_id,x.pos from public.on_rank(p_season) x order by x.pos loop
  perform public.on_award(p_season,r.club_id,'L',r.pos::text,cfg.prize_league->(r.pos-1),0);
 end loop;
 update public.on_seasons set league_paid_at=now() where id=p_season;
 return true;
end $$;

revoke all on function public.on_fmt_money(bigint),public.on_award(smallint,int,char,text,jsonb,int),public.on_award_cup(smallint),
 public.on_award_league(smallint) from public,anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ganchos: copa no fim da final; liga no fim da temporada (no lugar dos prêmios antigos); ranking sem a copa
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 perform public.on_patch('public.on_cup_hook(bigint)',
  ' if not exists(select 1 from public.on_fixtures x where x.season_id=f.season_id and x.status<>''done'') then',
  ' if f.comp=''C'' and f.stage=''final'' then perform public.on_award_cup(f.season_id);end if;
 if not exists(select 1 from public.on_fixtures x where x.season_id=f.season_id and x.status<>''done'') then');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  'for r in select h.* from public.on_history h where h.season_id=p_season order by h.club_id loop',
  'perform public.on_award_league(p_season);
 for r in select h.* from public.on_history h where h.season_id=p_season and false order by h.club_id loop');
 perform public.on_patch('public.on_rank_season(smallint)',
  'v:=coalesce((rr->''league''->>(h.pos-1))::int,0)+coalesce((rr->''cup''->>h.cup)::int,0);',
  'v:=coalesce((rr->''league''->>(h.pos-1))::int,0); -- copa: pontos na hora (on_award_cup)');
 perform public.on_patch('public.on_rank_season(smallint)',
  'values(h.user_id,v,v,(h.pos=1)::int,coalesce(h.cup=''champion'',false)::int,1)',
  'values(h.user_id,v,v,(h.pos=1)::int,0,1)');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Lances iniciais: lenda $ 2,5 a 3,5 mi; destaque a partir de $ 700 mil; nível Messi segue a partir de $ 5 mi
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_start_price(p public.on_players) returns bigint
language sql immutable set search_path=public as $$
 select case when p.legend and p.pot>100 then 5000000+(p.pot-101)*500000
  when p.legend then least(3500000,2500000+greatest(0,p.level-85)*80000)
  when p.level>=81 then 700000+(p.level-81)*50000
  else greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4)) end::bigint
$$;
-- leilões de lenda e destaque abertos e sem lance passam a pedir o novo mínimo
update public.on_lots l set start_price=public.on_start_price(p)
 from public.on_players p where p.id=l.player_id and l.status='open' and l.best_bid is null and l.seller is null and l.featured in(8,9)
  and l.start_price<public.on_start_price(p);

-- Copa já encerrada na temporada em andamento (antes desta fase): paga agora.
select public.on_award_cup(s.id) from public.on_seasons s where s.status='live' and s.cup_paid_at is null;
