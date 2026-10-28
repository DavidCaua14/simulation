-- RELEASE SEASONS V2: fazer backup e executar preflight_seasons.sql antes.
-- Gerado; não edite este arquivo. Todas as alterações são atômicas.
begin;

-- FILE: 15_season_integrity.sql
-- EVOLUÇÃO 15: integridade por carreira e calendário equilibrado.
-- Executar depois de 14, em transação. Não apaga resultados nem recria temporadas.

create unique index if not exists career_seasons_identity_uq on public.career_seasons(id, career_id);
create unique index if not exists mgr_spells_identity_uq on public.mgr_spells(id,career_id);
create unique index if not exists season_fixtures_identity_uq on public.season_fixtures(id, season_id);
create unique index if not exists season_fixtures_pair_uq
 on public.season_fixtures(season_id, competition_id, stage, home_club, away_club);
create unique index if not exists season_fixtures_tie_leg_uq
 on public.season_fixtures(season_id, competition_id, stage, tie_no, leg) where tie_no is not null;

do $$
declare t text;
begin
 foreach t in array array['mgr_matches','mgr_objectives','mgr_messages','mgr_transfers','season_offers','season_transitions'] loop
  if not exists(select 1 from pg_constraint where conname=t||'_season_owner_fk') then
   execute format('alter table public.%I add constraint %I foreign key (%I, career_id) references public.career_seasons(id, career_id)',
                  t,t||'_season_owner_fk',case when t='season_transitions' then 'from_season' else 'season_id' end);
  end if;
 end loop;
 foreach t in array array['mgr_objectives','mgr_coach'] loop
  if not exists(select 1 from pg_constraint where conname=t||'_spell_owner_fk') then
   execute format('alter table public.%I add constraint %I foreign key(spell_id,career_id) references public.mgr_spells(id,career_id)',t,t||'_spell_owner_fk');
  end if;
 end loop;
 if not exists(select 1 from pg_constraint where conname='mgr_matches_fixture_season_fk') then
  alter table public.mgr_matches add constraint mgr_matches_fixture_season_fk
    foreign key(fixture_id,season_id) references public.season_fixtures(id,season_id);
 end if;
end $$;

-- Um clube só pode jogar UMA vez em cada rodada, inclusive como visitante.
-- A chave diferida permite permutar rodadas em uma única transação.
create table if not exists public.season_fixture_slots (
 season_id uuid not null, competition_id text not null, stage text not null, round_no int not null,
 club_id text not null, fixture_id bigint not null references public.season_fixtures(id) on delete cascade,
 primary key(season_id,competition_id,stage,round_no,club_id) deferrable initially deferred
);
alter table public.season_fixture_slots enable row level security;
revoke all on public.season_fixture_slots from public,anon,authenticated;
-- Reconstrução somente deste índice auxiliar; os jogos nunca são apagados.
-- DELETE + INSERT torna a própria migração repetível sem depender de ON CONFLICT em chave diferida.
delete from public.season_fixture_slots;
insert into public.season_fixture_slots
 select season_id,competition_id,stage,round_no,home_club,id from public.season_fixtures
 union all select season_id,competition_id,stage,round_no,away_club,id from public.season_fixtures;

create or replace function public.sim_fixture_integrity()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='UPDATE' and old.status='played' then
  if row(new.season_id,new.competition_id,new.stage,new.round_no,new.group_label,new.tie_no,new.leg,
         new.home_club,new.away_club,new.home_goals,new.away_goals,new.status,new.played_at)
     is distinct from
     row(old.season_id,old.competition_id,old.stage,old.round_no,old.group_label,old.tie_no,old.leg,
         old.home_club,old.away_club,old.home_goals,old.away_goals,old.status,old.played_at)
     or (old.tie_winner is not null and new.tie_winner is distinct from old.tie_winner)
     or (old.home_pens is not null and row(new.home_pens,new.away_pens) is distinct from row(old.home_pens,old.away_pens)) then
   raise exception 'Resultado disputado é imutável: partida %',old.id;
  end if;
 end if;
 if new.home_club=new.away_club then raise exception 'Um clube não pode enfrentar a si mesmo'; end if;
 if new.status='played' and (new.home_goals is null or new.away_goals is null or least(new.home_goals,new.away_goals)<0) then
  raise exception 'Partida encerrada precisa de placar válido';
 end if;
 return new;
end $$;
drop trigger if exists sim_fixture_integrity_trg on public.season_fixtures;
create trigger sim_fixture_integrity_trg before insert or update on public.season_fixtures
 for each row execute function public.sim_fixture_integrity();

create or replace function public.sim_fixture_slots_sync()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 delete from public.season_fixture_slots where fixture_id=new.id;
 insert into public.season_fixture_slots values
 (new.season_id,new.competition_id,new.stage,new.round_no,new.home_club,new.id),
 (new.season_id,new.competition_id,new.stage,new.round_no,new.away_club,new.id);
 return null;
end $$;
drop trigger if exists sim_fixture_slots_trg on public.season_fixtures;
create trigger sim_fixture_slots_trg after insert or update of round_no,home_club,away_club,season_id,competition_id,stage
 on public.season_fixtures for each row execute function public.sim_fixture_slots_sync();

-- Berger: alterna a mesa fixa e inverte as demais mesas em mesas alternadas.
-- O returno começa pela segunda rodada da ida: impede uma sequência de três na virada.
create or replace function public.sim_round_robin(p_teams text[], p_double boolean default true)
returns table(round_no int,home text,away text) language plpgsql as $$
declare n int:=cardinality(p_teams); arr text[]:=p_teams; r int; i int; h text; a text;
begin
 if n is null or n<2 or n%2<>0 or n<>(select count(distinct x) from unnest(p_teams) x) then
  raise exception 'Liga requer lista par, sem clubes repetidos ou nulos';
 end if;
 for r in 1..n-1 loop
  for i in 1..n/2 loop
   h:=arr[i]; a:=arr[n-i+1];
   if (i=1 and r%2=0) or (i>1 and i%2=0) then h:=arr[n-i+1]; a:=arr[i]; end if;
   round_no:=r;home:=h;away:=a;return next;
   if p_double then
    round_no:=n-1+case when n=2 then 1 else ((r-2+n-1)%(n-1))+1 end;
    home:=a;away:=h;return next;
   end if;
  end loop;
  arr:=array[arr[1],arr[n]]||arr[2:n-1];
 end loop;
end $$;

-- Custo de sequências acima de dois jogos no mesmo mando. Usado também para
-- comparar a reparação com o calendário anterior, sem aceitar piora global.
create or replace function public.sim_calendar_cost(p_season uuid,p_comp text,p_stage text,p_rounds int[] default null,p_fixed int default 0)
returns bigint language sql stable set search_path=public as $$
 with games as (
  select x.club,x.venue,case when f.round_no<=p_fixed or p_rounds is null then f.round_no
      else p_fixed+array_position(p_rounds,f.round_no) end as r
  from public.season_fixtures f cross join lateral(values(f.home_club,'h'),(f.away_club,'a')) x(club,venue)
  where f.season_id=p_season and f.competition_id=p_comp and f.stage=p_stage
 ), islands as (
  select *,row_number() over(partition by club order by r)-row_number() over(partition by club,venue order by r) as island from games
 ), runs as(select club,venue,island,count(*) as n from islands group by club,venue,island)
 select coalesce(sum(greatest(n-2,0)*greatest(n-2,0)),0)::bigint from runs
$$;

create table if not exists public.season_schedule_changes (
 fixture_id bigint primary key references public.season_fixtures(id),
 season_id uuid not null references public.career_seasons(id), previous_round int not null,new_round int not null,
 changed_at timestamptz not null default now()
);
alter table public.season_schedule_changes enable row level security;
revoke all on public.season_schedule_changes from public,anon,authenticated;

-- Reordena somente RODADAS INTEIRAMENTE futuras. Uma rodada com partida disputada
-- ou com estado de partida já criado fixa todo o prefixo. IDs, adversários, mando e
-- resultados são preservados; não é possível desfazer uma sequência já disputada.
create or replace function public.sim_rebalance_pending(p_season uuid,p_comp text,p_stage text default 'league')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 fixed int; round_slots int[]; remaining int[]; chosen int[]:='{}'; best_order int[]; candidate int; best int; score bigint; best_score bigint;
 old_cost bigint; new_cost bigint; r record; state jsonb:='{}'; club text; venue text; previous text; run int; cost bigint; changed int:=0;
begin
 perform 1 from public.careers where id=(select career_id from public.career_seasons where id=p_season) for update;
 perform 1 from public.career_seasons where id=p_season and status='active' for update;
 if not found then return jsonb_build_object('changed',0); end if;
 if coalesce(public.sim_phase(p_comp,p_stage)->>'type','')<>'league' then raise exception 'Reparação disponível apenas para ligas'; end if;
 select coalesce(max(f.round_no),0) into fixed from public.season_fixtures f
 where f.season_id=p_season and f.competition_id=p_comp and f.stage=p_stage
 and (f.status='played' or exists(select 1 from public.mgr_matches m where m.fixture_id=f.id));
 select array_agg(distinct round_no order by round_no) into remaining from public.season_fixtures
 where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed;
 if cardinality(remaining) is null then return jsonb_build_object('changed',0); end if;
 -- Só permuta números de rodada existentes: não cria rodadas extras.
 round_slots:=remaining;best_order:=remaining; old_cost:=public.sim_calendar_cost(p_season,p_comp,p_stage); new_cost:=old_cost;
 if old_cost=0 then return jsonb_build_object('changed',0,'before',0,'after',0);end if;
 -- Busca local: trocas de rodadas reduzem estritamente o custo; termina em ótimo local.
 -- Não há sorteio global nem acesso a dados de outras temporadas/carreiras.
 for pass in 1..10 loop
  best_score:=new_cost;
  for i in 1..cardinality(remaining)-1 loop
   for j in i+1..cardinality(remaining) loop
    chosen:=best_order;candidate:=chosen[i];chosen[i]:=chosen[j];chosen[j]:=candidate;
    score:=public.sim_calendar_cost(p_season,p_comp,p_stage,chosen,fixed);
    if score<best_score then best_score:=score;remaining:=chosen; end if;
   end loop;
  end loop;
  exit when best_score>=new_cost;
  best_order:=remaining;new_cost:=best_score;
  exit when new_cost=0;
 end loop;
 if new_cost>=old_cost then return jsonb_build_object('changed',0,'before',old_cost,'after',old_cost); end if;
 -- Chave diferida protege os clubes durante a troca atômica de rodadas.
 insert into public.season_schedule_changes(fixture_id,season_id,previous_round,new_round)
 select id,season_id,round_no,round_slots[array_position(best_order,round_no)]
 from public.season_fixtures where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed
 and round_no<>round_slots[array_position(best_order,round_no)]
 on conflict(fixture_id) do update set new_round=excluded.new_round,changed_at=now();
 update public.season_fixtures set round_no=round_slots[array_position(best_order,round_no)]
 where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed
 and round_no<>round_slots[array_position(best_order,round_no)];
 get diagnostics changed=row_count;
 return jsonb_build_object('changed',changed,'before',old_cost,'after',new_cost,'fixed_through',fixed);
end $$;

-- Funções internas: não ficam disponíveis a usuários, mesmo por RPC manual.
revoke all on function public.sim_fixture_integrity(),public.sim_fixture_slots_sync(),
 public.sim_calendar_cost(uuid,text,text,int[],int),public.sim_rebalance_pending(uuid,text,text) from public,anon,authenticated;


-- FILE: 16_match_simulation.sql
-- EVOLUÇÃO 16: motor versionado, identidade tática e disciplina contextual.
-- Partidas já iniciadas continuam no motor v1; novas partidas usam v2.
alter table public.sim_player_attrs add column if not exists aggression smallint not null default 50 check(aggression between 1 and 99);
alter table public.sim_player_attrs add column if not exists discipline smallint not null default 60 check(discipline between 1 and 99);
alter table public.mgr_ai_clubs add column if not exists style text;

-- Estimativas de gameplay configuráveis, não estatísticas oficiais dos atletas.
create or replace function public.mgr_card_chances(p_aggression numeric,p_discipline numeric,p_tack numeric,p_cond numeric,
 p_fouls int,p_booked boolean,p_tackles text,p_ref numeric,p_context numeric default 1)
returns jsonb language sql immutable as $$
 select jsonb_build_object(
 'yellow',least(0.42,greatest(0.06,0.16 * (0.65+p_aggression/100) * (1.30-p_discipline/200)
       * (1.25-p_tack/200) * (1+greatest(0,55-p_cond)/180) * (1+least(p_fouls,5)*0.04)
       * case p_tackles when 'aggressive' then 1.35 when 'cautious' then 0.70 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context * case when p_booked then 0.35 else 1 end)),
 'red',least(0.009,greatest(0.0003,0.0012 * (0.50+p_aggression/100) * (1.30-p_discipline/200)
       * case p_tackles when 'aggressive' then 2.0 when 'cautious' then 0.5 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context)))
$$;

-- O encaixe do elenco decide a formação; pequena preferência própria desempata
-- opções próximas. Não altera a força dos jogadores para favorecer o usuário.
create or replace function public.mgr_ai_formation(p_career uuid,p_club text)
returns text language plpgsql security definer set search_path=public as $$
declare form text; best text; score numeric; best_score numeric:=-1; lineup jsonb;
begin
 select formation into best from public.mgr_ai_clubs where career_id=p_career and club_id=p_club;
 if best is not null then return best; end if;
 for form in select id from public.sim_formations order by id loop
  lineup:=public.mgr_auto_lineup(p_career,p_club,form,null,0);
  score:=public.mgr_lineup_score(lineup,form) * (0.985 + (('x'||substr(md5(p_career::text||p_club||form),1,7))::bit(28)::int % 300)/10000.0);
  if score>best_score then best_score:=score;best:=form;end if;
 end loop;
 best:=coalesce(best,'4-3-3');
 insert into public.mgr_ai_clubs(career_id,club_id,formation) values(p_career,p_club,best) on conflict do nothing;
 return (select formation from public.mgr_ai_clubs where career_id=p_career and club_id=p_club);
end $$;

create or replace function public.mgr_ai_plan(p_career uuid,p_club text,p_diff numeric,p_home boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_style text; t jsonb; passing numeric; speed numeric; stamina numeric; heading numeric; choice int;
begin
 perform public.mgr_ai_formation(p_career,p_club);
 select c.style into v_style from public.mgr_ai_clubs c where career_id=p_career and club_id=p_club;
 if v_style is null then
  select avg(a.passing+a.vision)/2,avg(a.pace),avg(a.stamina),avg(a.heading)
    into passing,speed,stamina,heading from public.mgr_players m join public.sim_player_attrs a on a.player_id=m.player_id
    join public.sim_players p on p.id=m.player_id
    where m.career_id=p_career and m.club_id=p_club and p.position<>'GOL';
  choice:=('x'||substr(md5(p_career::text||p_club),1,7))::bit(28)::int % 5;
  v_style:=case when choice=0 and passing>=58 then 'possession' when choice=1 and stamina>=60 then 'press'
              when choice=2 and speed>=55 then 'counter' when choice=3 and heading>=55 then 'wide' else 'balanced' end;
  update public.mgr_ai_clubs set style=v_style where career_id=p_career and club_id=p_club;
 end if;
 t:=public.mgr_ai_tactics(p_diff,p_home);
 t:=t || case v_style when 'possession' then '{"build":"short","tempo":"slow","width":"center"}'::jsonb
    when 'press' then '{"pressing":"high","line":"high","tempo":"fast"}'::jsonb
    when 'counter' then '{"pressing":"low","line":"low","build":"direct","tempo":"fast"}'::jsonb
    when 'wide' then '{"width":"wide","build":"mixed","tempo":"normal"}'::jsonb else '{}'::jsonb end;
 if p_diff < -12 then t:=t||'{"mentality":-1,"line":"low"}'; end if;
 return public.mgr_tactics_clean(t);
end $$;

-- Interações dependem dos atributos do elenco, não apenas de escolher uma opção.
create or replace function public.mgr_tactical_effect(p_t jsonb,p_opp jsonb,p_skill numeric,p_pace numeric,p_stamina numeric,p_head numeric)
returns jsonb language plpgsql immutable as $$
declare ctl numeric:=1; freq numeric:=1; quality numeric:=0;
begin
 if p_t->>'build'='short' then
  ctl:=ctl+greatest(-0.10,least(0.06,(p_skill-60)/250));
  if p_opp->>'pressing'='high' then ctl:=ctl+(p_skill-65)/400; quality:=quality+(p_skill-65)/700; end if;
 elsif p_t->>'build'='direct' and p_opp->>'line'='high' then
  freq:=freq+greatest(-0.04,least(0.10,(p_pace-55)/250));quality:=quality+greatest(-0.03,least(0.06,(p_pace-60)/500));
 end if;
 if p_t->>'build'='direct' and p_opp->>'pressing'='high' then freq:=freq*1.12;quality:=quality+0.025;end if;
 if p_t->>'width'='wide' then quality:=quality+greatest(-0.05,least(0.05,(p_head-60)/400)); end if;
 if p_t->>'pressing'='high' then ctl:=ctl+greatest(-0.06,least(0.04,(p_stamina-65)/350)); end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',quality);
end $$;

create or replace function public.mgr_tactics_clean(p_t jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'mentality', greatest(-2, least(2, coalesce((p_t ->> 'mentality')::int, 0))),
    'pressing',  case when p_t ->> 'pressing' in ('low', 'medium', 'high') then p_t ->> 'pressing' else 'medium' end,
    'line',      case when p_t ->> 'line' in ('low', 'medium', 'high') then p_t ->> 'line' else 'medium' end,
    'tempo',     case when p_t ->> 'tempo' in ('slow', 'normal', 'fast') then p_t ->> 'tempo' else 'normal' end,
    'build',     case when p_t ->> 'build' in ('short', 'mixed', 'direct') then p_t ->> 'build' else 'mixed' end,
    'width',     case when p_t ->> 'width' in ('center', 'mixed', 'wide') then p_t ->> 'width' else 'mixed' end,
    'tackles', case when p_t ->> 'tackles' in ('cautious','normal','aggressive') then p_t ->> 'tackles' else 'normal' end,
    'manage',    case when p_t ->> 'manage' in ('keep', 'normal', 'push') then p_t ->> 'manage' else 'normal' end)
$$;
create or replace function public.mgr_match_create(p_fixture bigint, p_career uuid, p_user_side char, p_user_lineup jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_f     public.season_fixtures;
  v_s     public.career_seasons;
  v_rules jsonb;
  v_lh    jsonb;
  v_la    jsonb;
  v_sh    numeric;
  v_sa    numeric;
  v_th    jsonb;
  v_ta    jsonb;
  v_neut  boolean;
  v_dec   boolean;
  v_agg_h int := 0;
  v_agg_a int := 0;
  v_first public.season_fixtures;
  v_ph    jsonb;
  v_bench int;
begin
  perform 1 from public.careers where id=p_career for update;
  select * into v_f from public.season_fixtures where id=p_fixture for update;
  if not found then raise exception 'Partida inexistente'; end if;
  if not exists(select 1 from public.career_seasons where id=v_f.season_id and career_id=p_career) then raise exception 'Partida de outra carreira'; end if;
  if exists (select 1 from public.mgr_matches where fixture_id = p_fixture) then return; end if;
  if v_f.status <> 'pending' then raise exception 'Partida já disputada'; end if;
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select rules into v_rules from public.sim_competitions where id = v_f.competition_id;
  v_ph := public.sim_phase(v_f.competition_id, v_f.stage);
  v_bench := coalesce((v_rules ->> 'bench')::int, 12);
  if v_ph is not null then
    -- configuração da fase (evolução 03): mando neutro, jogo que decide o confronto, prorrogação e critério de empate
    v_neut := coalesce((v_ph ->> 'neutral')::boolean, false);
    v_dec  := v_ph ->> 'type' = 'knockout' and (coalesce((v_ph ->> 'legs')::int, 1) = 1 or v_f.leg = 2);
  else
    v_neut := (v_f.stage = 'final');
    v_dec  := v_f.stage in ('r16', 'qf', 'sf', 'final') and (v_f.stage = 'final' or v_f.leg = 2);
  end if;
  if v_dec and coalesce(v_f.leg, 1) = 2 then
    select * into v_first from public.season_fixtures
     where season_id = v_f.season_id and competition_id = v_f.competition_id and stage = v_f.stage and tie_no = v_f.tie_no and leg = 1;
    -- placar da ida do ponto de vista dos lados deste jogo
    v_agg_h := case when v_first.home_club = v_f.home_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
    v_agg_a := case when v_first.home_club = v_f.away_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
  end if;

  insert into public.mgr_matches (fixture_id, career_id, season_id, user_side, minute, state)
  values (p_fixture, p_career, v_f.season_id, p_user_side, 0, jsonb_build_object(
    'engine_version', 2, 'referee', round((0.80+random()*0.40)::numeric,3), 'seq', 0, 'score', jsonb_build_array(0, 0), 'poss', jsonb_build_array(0, 0),
    'corners', jsonb_build_array(0, 0), 'offsides', jsonb_build_array(0, 0),
    'subs', jsonb_build_object('h', jsonb_build_object('used', 0, 'windows', 0), 'a', jsonb_build_object('used', 0, 'windows', 0)),
    'max_subs', coalesce((v_rules ->> 'max_subs')::int, 5), 'max_windows', coalesce((v_rules ->> 'sub_windows')::int, 3),
    'neutral', v_neut, 'decisive', v_dec, 'agg', jsonb_build_array(v_agg_h, v_agg_a),
    'extra_time_rule', (v_dec and case when v_ph is not null then coalesce((v_ph ->> 'extra_time')::boolean, false)
                                       else v_f.stage = 'final' and coalesce((v_rules ->> 'final_extra_time')::boolean, false) end),
    'tie_rule', coalesce(v_ph ->> 'tie', 'penalties'),
    'et', false, 'comp', v_f.competition_id, 'stage', v_f.stage, 'day', v_s.day_no,
    'form', jsonb_build_array(round((0.90 + random() * 0.20)::numeric, 3), round((0.90 + random() * 0.20)::numeric, 3))));

  v_lh := case when p_user_side = 'h' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.home_club, public.mgr_ai_formation(p_career, v_f.home_club), v_f.competition_id, v_s.day_no, v_bench) end;
  v_la := case when p_user_side = 'a' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.away_club, public.mgr_ai_formation(p_career, v_f.away_club), v_f.competition_id, v_s.day_no, v_bench) end;
  perform public.mgr_build_side(p_fixture, 'h', p_career, v_f.home_club, v_lh);
  perform public.mgr_build_side(p_fixture, 'a', p_career, v_f.away_club, v_la);

  v_sh := public.mgr_side_strength(p_fixture, 'h');
  v_sa := public.mgr_side_strength(p_fixture, 'a');
  v_th := case when p_user_side = 'h' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_plan(p_career,v_f.home_club,v_sh-v_sa,not v_neut) end;
  v_ta := case when p_user_side = 'a' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_plan(p_career,v_f.away_club,v_sa-v_sh,false) end;

  update public.mgr_matches
     set state = state || jsonb_build_object(
           'tactics', jsonb_build_object('h', v_th, 'a', v_ta),
           'base_mentality', jsonb_build_array((v_th ->> 'mentality')::int, (v_ta ->> 'mentality')::int),
           'formation', jsonb_build_array(v_lh ->> 'formation', v_la ->> 'formation'),
           'strength', jsonb_build_array(round(v_sh, 1), round(v_sa, 1)))
   where fixture_id = p_fixture;
end;
$$;
-- Preserva também o comportamento da IA das partidas já abertas.
do $$ begin
 if to_regprocedure('public.mgr_ai_manage_v1(bigint,character,integer)') is null then
  alter function public.mgr_ai_manage(bigint,char,int) rename to mgr_ai_manage_v1;
 end if;
end $$;
create or replace function public.mgr_ai_manage_v2(p_fixture bigint, p_side char, p_minute int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_m     public.mgr_matches;
  v_my    int;
  v_opp   int;
  v_base  int;
  v_ment  int;
  r       record;
  v_in    text;
  v_n     int := 0;
  v_first boolean := true;
  v_max   int := case when p_minute >= 75 then 3 else 2 end;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_my  := (v_m.state -> 'score' ->> (case when p_side = 'h' then 0 else 1 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 0 else 1 end))::int;
  v_opp := (v_m.state -> 'score' ->> (case when p_side = 'h' then 1 else 0 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 1 else 0 end))::int;
  v_base := (v_m.state -> 'base_mentality' ->> (case when p_side = 'h' then 0 else 1 end))::int;

  -- postura
  v_ment := v_base;
  if v_my < v_opp and p_minute >= 60 then v_ment := least(2, v_base + case when v_opp - v_my >= 2 or p_minute >= 75 then 2 else 1 end);
  elsif v_my > v_opp and p_minute >= 75 then v_ment := greatest(-2, v_base - 1);
  end if;
  if v_ment <> coalesce((v_m.state -> 'tactics' -> p_side ->> 'mentality')::int, 0) then
    update public.mgr_matches set state = jsonb_set(state, array['tactics', p_side, 'mentality'], to_jsonb(v_ment)) where fixture_id = p_fixture;
  end if;

  -- Ajusta mais que a postura: pressão/ritmo conforme placar, tempo e cansaço.
  if p_minute>=60 then
   update public.mgr_matches set state=jsonb_set(state,array['tactics',p_side],
     (state->'tactics'->p_side) || case when v_my<v_opp then
       jsonb_build_object('tempo','fast','pressing',case when (select avg(cond) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on')>60 then 'high' else 'medium' end,'manage','push')
      when v_my>v_opp and p_minute>=75 then '{"tempo":"slow","pressing":"low","manage":"keep"}'::jsonb else '{}'::jsonb end
     || case when (select count(*) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on' and yellow>0)>=3
         then '{"tackles":"cautious"}'::jsonb else '{}'::jsonb end)
    where fixture_id=p_fixture;
  end if;

  -- substituições (lesionados primeiro, depois os mais cansados / pendurados)
  for r in
    select mp.player_id, mp.pos, mp.status
      from public.mgr_match_players mp
     where mp.fixture_id = p_fixture and mp.side = p_side
       and ((mp.status = 'injured_off' and mp.slot is not null)
            or (mp.status = 'on' and mp.pos <> 'GOL' and p_minute >= 45
                and (mp.cond < 66 or (mp.yellow > 0 and mp.pos in ('ZAG', 'LD', 'LE', 'VOL') and p_minute >= 55)
                     or (p_minute >= 70 and mp.cond < 74 and v_my <> v_opp))))
     order by (mp.status = 'injured_off') desc, mp.cond
  loop
    exit when v_n >= v_max and r.status <> 'injured_off';
    v_in := public.mgr_best_bench(p_fixture, p_side,
              case when v_my < v_opp and p_minute >= 70 and r.pos in ('VOL', 'ZAG') and v_ment >= 1 then 'ATA' else r.pos end);
    exit when v_in is null;
    exit when public.mgr_do_sub(p_fixture, p_side, r.player_id, v_in, p_minute, v_first) is not null;
    v_first := false;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
create or replace function public.mgr_ai_manage(p_fixture bigint,p_side char,p_minute int)
returns int language plpgsql security definer set search_path=public as $$
begin
 if coalesce((select (state->>'engine_version')::int from public.mgr_matches where fixture_id=p_fixture),1)=1 then
  return public.mgr_ai_manage_v1(p_fixture,p_side,p_minute);
 end if;
 return public.mgr_ai_manage_v2(p_fixture,p_side,p_minute);
end $$;

do $$ begin
 if to_regprocedure('public.mgr_engine_run_v1(bigint,integer,character)') is null then
  alter function public.mgr_engine_run(bigint,int,char) rename to mgr_engine_run_v1;
 end if;
end $$;

create or replace function public.mgr_engine_run_v2(p_fixture bigint, p_to int, p_interactive char)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_m      public.mgr_matches;
  v_p      public.mgr_ep[];
  v_n      int;
  v_min    int;
  v_end    int;
  v_stop   text := 'segment';
  i        int;
  j        int;
  s        int;
  d        int;
  v_e      float8;
  v_att    float8[];
  v_def    float8[];
  v_ctl    float8[];
  v_gkr    float8[];
  v_gki    int[];
  v_defav  float8[];
  v_paceav float8[];
  v_non    int[];
  v_tac    jsonb;
  v_ment   int[];
  v_amult  float8[];
  v_dmult  float8[];
  v_freq   float8[];
  v_qual   float8[];
  v_drainm float8[];
  v_foulm  float8[];
  v_offm   float8[];
  v_hdr    float8[];
  v_sc     int[];
  v_agg    int[];
  v_poss   int[];
  v_corn   int[];
  v_offs   int[];
  v_ph     float8;
  v_r      float8;
  v_pa     float8;
  v_q      float8;
  v_w      float8[];
  v_k      int;
  v_a      int;
  v_gkidx  int;
  v_head   boolean;
  v_reload boolean;
  v_neut   boolean;
  v_et     boolean;
  v_side   char;
  v_oside  char;
  v_dsec   char;
  v_inj_stop boolean;
  v_lead   int;
  v_detail text;
  v_form   float8[];
  v_tpress text[];
  v_tline  text[];
  v_ttempo text[];
  v_tbuild text[];
  v_tmanage text[];
  v_tment  int[];
  v_ctlm   float8[];
  v_dws    float8[];
  v_dirty  boolean := true;
  v_profiles jsonb;
  v_card jsonb;
  v_ref float8;
  v_tackles text[];
  v_effect jsonb;
  v_skill record;
  v_yprob float8;
  v_rprob float8;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture for update;
  if v_m.status <> 'live' then return 'ft'; end if;
  select jsonb_object_agg(a.player_id,jsonb_build_array(a.aggression,a.discipline)) into v_profiles
   from public.mgr_match_players mp join public.sim_player_attrs a on a.player_id=mp.player_id where mp.fixture_id=p_fixture;
  v_ref:=coalesce((v_m.state->>'referee')::float8,1);
  v_form := array[coalesce((v_m.state -> 'form' ->> 0)::numeric, 1), coalesce((v_m.state -> 'form' ->> 1)::numeric, 1)];
  v_min := v_m.minute;
  v_et  := coalesce((v_m.state ->> 'et')::boolean, false);
  v_end := least(p_to, case when v_et then 120 else 90 end);
  v_neut := coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_poss := array[(v_m.state -> 'poss' ->> 0)::int, (v_m.state -> 'poss' ->> 1)::int];
  v_corn := array[(v_m.state -> 'corners' ->> 0)::int, (v_m.state -> 'corners' ->> 1)::int];
  v_offs := array[(v_m.state -> 'offsides' ->> 0)::int, (v_m.state -> 'offsides' ->> 1)::int];
  v_sc   := array[(v_m.state -> 'score' ->> 0)::int, (v_m.state -> 'score' ->> 1)::int];
  v_agg  := array[(v_m.state -> 'agg' ->> 0)::int, (v_m.state -> 'agg' ->> 1)::int];
  v_reload := true;

  while v_min < v_end loop
    v_min := v_min + 1;

    -- a IA (e o auxiliar, no modo automático) mexe nos intervalos e marcos do jogo
    if v_min in (46, 61, 71, 81, 91, 106) then
      if v_p is not null then   -- grava antes: a IA decide olhando a condição e o placar atuais
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
        update public.mgr_matches
           set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
         where fixture_id = p_fixture;
        v_p := null;
      end if;
      if p_interactive is distinct from 'h' then perform public.mgr_ai_manage(p_fixture, 'h', v_min - 1); end if;
      if p_interactive is distinct from 'a' then perform public.mgr_ai_manage(p_fixture, 'a', v_min - 1); end if;
      v_reload := true;
    end if;

    if v_reload then
      if v_p is not null then
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
      end if;
      select * into v_m from public.mgr_matches where fixture_id = p_fixture;
      select array_agg(row(mp.player_id, case when mp.side = 'h' then 1 else 2 end, mp.slot, mp.pos,
                           sp.w_att::float8, sp.w_def::float8, sp.w_ctl::float8, sp.drain::float8,
                           mp.c_att::float8, mp.c_cre::float8, mp.c_def::float8, mp.c_ctl::float8, mp.c_gk::float8, mp.c_fin::float8,
                           mp.c_head::float8, mp.c_pace::float8, mp.c_stam::float8, mp.c_tack::float8, mp.c_str::float8,
                           mp.fit::float8, mp.cond::float8, mp.rhythm::float8, mp.goals, mp.assists, mp.shots, mp.sot, mp.saves, mp.fouls, mp.yellow, mp.red,
                           false, true, mp.minutes)::public.mgr_ep order by mp.side, mp.slot)
        into v_p
        from public.mgr_match_players mp join public.sim_positions sp on sp.code = mp.pos
       where mp.fixture_id = p_fixture and mp.status = 'on';
      v_n := coalesce(array_length(v_p, 1), 0);
      v_tac := v_m.state -> 'tactics';
      v_reload := false;
      v_dirty := true;
      -- parâmetros táticos fixos até a próxima mudança
      v_tackles:=array[coalesce(v_tac->'h'->>'tackles','normal'),coalesce(v_tac->'a'->>'tackles','normal')];
      v_tpress := array[v_tac -> 'h' ->> 'pressing', v_tac -> 'a' ->> 'pressing'];
      v_tline  := array[v_tac -> 'h' ->> 'line', v_tac -> 'a' ->> 'line'];
      v_ttempo := array[v_tac -> 'h' ->> 'tempo', v_tac -> 'a' ->> 'tempo'];
      v_tbuild := array[v_tac -> 'h' ->> 'build', v_tac -> 'a' ->> 'build'];
      v_tmanage := array[v_tac -> 'h' ->> 'manage', v_tac -> 'a' ->> 'manage'];
      v_tment  := array[coalesce((v_tac -> 'h' ->> 'mentality')::int, 0), coalesce((v_tac -> 'a' ->> 'mentality')::int, 0)];
      v_freq := array[1, 1]; v_qual := array[0, 0]; v_drainm := array[1, 1]; v_foulm := array[1, 1]; v_offm := array[1, 1];
      v_hdr := array[0.2, 0.2]; v_ctlm := array[1, 1];
      for s in 1 .. 2 loop
        d := 3 - s;
        if v_tpress[s] = 'high' then v_freq[s] := v_freq[s] * 1.06; v_drainm[s] := 1.30; v_foulm[s] := 1.25; v_ctlm[d] := v_ctlm[d] * 0.93;
        elsif v_tpress[s] = 'low' then v_drainm[s] := 0.85; v_foulm[s] := 0.85; v_ctlm[d] := v_ctlm[d] * 1.04; end if;
        if v_ttempo[s] = 'fast' then v_freq[s] := v_freq[s] * 1.10; v_drainm[s] := v_drainm[s] * 1.18; v_ctlm[s] := v_ctlm[s] * 0.97;
        elsif v_ttempo[s] = 'slow' then v_freq[s] := v_freq[s] * 0.90; v_drainm[s] := v_drainm[s] * 0.90; v_ctlm[s] := v_ctlm[s] * 1.04; end if;
        if v_tbuild[s] = 'short' then v_freq[s] := v_freq[s] * 0.95; v_qual[s] := v_qual[s] + 0.04; v_ctlm[s] := v_ctlm[s] * 1.05;
        elsif v_tbuild[s] = 'direct' then v_freq[s] := v_freq[s] * 1.08; v_qual[s] := v_qual[s] - 0.03; v_offm[s] := 1.25; v_ctlm[s] := v_ctlm[s] * 0.94; end if;
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'width' when 'wide' then 0.30 when 'center' then 0.10 else 0.20 end;
        if v_hdr[s] = 0.10 then v_qual[s] := v_qual[s] + 0.02; end if;
        -- linha defensiva do ADVERSÁRIO muda a frequência de ataque e os impedimentos
        if v_tline[d] = 'high' then v_freq[s] := v_freq[s] * 0.95; v_offm[s] := v_offm[s] * 1.7;
        elsif v_tline[d] = 'low' then v_freq[s] := v_freq[s] * 1.06; v_offm[s] := v_offm[s] * 0.6; end if;
      end loop;
      for s in 1..2 loop
        select avg(c_cre) as skill,avg(c_pace) as pace,avg(c_stam * cond/100) as stamina,avg(c_head) as heading into v_skill
        from public.mgr_match_players where fixture_id=p_fixture and side=case when s=1 then 'h' else 'a' end and status='on' and pos<>'GOL';
        v_effect:=public.mgr_tactical_effect(v_tac->(case when s=1 then 'h' else 'a' end),v_tac->(case when s=1 then 'a' else 'h' end),
                  v_skill.skill,v_skill.pace,v_skill.stamina,v_skill.heading);
        v_ctlm[s]:=v_ctlm[s]*(v_effect->>'control')::float8;
        v_freq[s]:=v_freq[s]*(v_effect->>'frequency')::float8;
        v_qual[s]:=v_qual[s]+(v_effect->>'quality')::float8;
        v_foulm[s]:=v_foulm[s]*case v_tackles[s] when 'aggressive' then 1.22 when 'cautious' then 0.78 else 1 end;
      end loop;
      if not v_neut then v_ctlm[1] := v_ctlm[1] * 1.05; end if;
    end if;

    -- ---- força dos times (recalculada a cada 3 minutos ou quando alguém sai/entra) ----
    if v_dirty or v_min % 3 = 1 then
      v_dirty := false;
      v_att := array[0, 0]; v_def := array[0, 0]; v_ctl := array[0, 0]; v_gkr := array[30, 30]; v_gki := array[0, 0];
      v_defav := array[0, 0]; v_paceav := array[0, 0]; v_non := array[0, 0]; v_dws := array[0, 0];
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond) * (case when v_p[i].cond < 50 then 0.88 + 0.0024 * v_p[i].cond else 1 end)
               * (0.94 + 0.0006 * v_p[i].rhy);
        v_att[s] := v_att[s] + v_p[i].aw * (0.62 * v_p[i].att + 0.38 * v_p[i].cre) * v_e;
        v_def[s] := v_def[s] + v_p[i].dw * v_p[i].def * v_e;
        v_ctl[s] := v_ctl[s] + v_p[i].cw * v_p[i].ctl * v_e;
        v_non[s] := v_non[s] + 1;
        if v_p[i].pos = 'GOL' then v_gkr[s] := v_p[i].gk * v_e; v_gki[s] := i;
        else
          v_defav[s] := v_defav[s] + v_p[i].dw * v_p[i].def * v_e;
          v_paceav[s] := v_paceav[s] + v_p[i].dw * v_p[i].pace * v_e;
          v_dws[s] := v_dws[s] + v_p[i].dw;
        end if;
      end loop;
      for s in 1 .. 2 loop
        v_defav[s] := case when v_dws[s] > 0 then v_defav[s] / v_dws[s] else 40 end;
        v_paceav[s] := case when v_dws[s] > 0 then v_paceav[s] / v_dws[s] else 50 end;
      end loop;
    end if;

    -- ---- postura (muda com o placar conforme a "gestão do jogo") ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_ment[s] := v_tment[s];
      v_lead := (v_sc[s] + v_agg[s]) - (v_sc[d] + v_agg[d]);
      if v_tmanage[s] = 'keep' and v_lead > 0 and v_min >= 70 then v_ment[s] := greatest(-2, v_ment[s] - 1); end if;
      if v_tmanage[s] = 'push' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if;
      v_amult[s] := (array[0.80, 0.90, 1.00, 1.10, 1.20])[v_ment[s] + 3];
      v_dmult[s] := (array[1.15, 1.07, 1.00, 0.94, 0.86])[v_ment[s] + 3] * case when v_tpress[s] = 'low' then 1.03 else 1 end;
    end loop;

    -- ---- posse ----
    v_r := v_ctl[1] * v_ctlm[1];
    v_q := v_ctl[2] * v_ctlm[2];
    v_ph := greatest(0.25, least(0.75, 0.5 + 1.15 * (v_r / greatest(v_r + v_q, 1) - 0.5)));
    s := case when random() < v_ph then 1 else 2 end;
    d := 3 - s;
    v_side := case when s = 1 then 'h' else 'a' end;
    v_oside := case when d = 1 then 'h' else 'a' end;
    v_poss[s] := v_poss[s] + 1;

    -- ---- jogada de ataque? ----
    v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case when v_neut then 1 when s = 1 then 1.16 else 0.96 end), 1)
                          / greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.50)
                  * v_freq[s];
    v_pa := greatest(0.05, least(0.55, v_pa));

    if random() < v_pa then
      v_r := random();
      if v_r < 0.07 * v_offm[s] then
        -- impedimento
        v_offs[s] := v_offs[s] + 1;
        if p_interactive is not null then
          v_w := '{}';
          for i in 1 .. v_n loop v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s then v_p[i].aw * v_p[i].pace else 0 end; end loop;
          v_k := public.mgr_pick(v_w);
          if v_k > 0 then perform public.mgr_event(p_fixture, v_min, v_side, 'offside', v_p[v_k].pid); end if;
        end if;
      elsif v_r < 0.07 + 0.10 then
        -- falta do defensor na jogada (pode virar pênalti ou cartão)
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = d and v_p[i].pos <> 'GOL' then v_p[i].dw * (1 + (100 - v_p[i].tack) / 100) else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].fouls := v_p[v_k].fouls + 1;
          v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
            v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[d],v_ref::numeric,1.20);
          v_r:=random();
          if v_r<(v_card->>'red')::float8 then
            v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
            perform public.mgr_event(p_fixture,v_min,v_oside,'red',v_p[v_k].pid,null,'Entrada temerária');
            update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
            if p_interactive=v_oside then v_stop:='red';end if;
          elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
            if v_p[v_k].yel>=1 then
              v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
              perform public.mgr_event(p_fixture,v_min,v_oside,'second_yellow',v_p[v_k].pid);
              update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
              if p_interactive=v_oside then v_stop:='red';end if;
            else
              v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_oside,'yellow',v_p[v_k].pid);
            end if;
          end if;
          if random() < 0.11 then                                         -- pênalti
            v_a := 0; v_e := -1;
            for i in 1 .. v_n loop
              if v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and v_p[i].fin > v_e then v_e := v_p[i].fin; v_a := i; end if;
            end loop;
            if v_a > 0 then
              v_p[v_a].shots := v_p[v_a].shots + 1;
              v_gkidx := v_gki[d];
              if random() < greatest(0.55, least(0.88, 0.70 + 0.004 * (v_p[v_a].fin - v_gkr[d]))) then
                v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_a].goals := v_p[v_a].goals + 1; v_sc[s] := v_sc[s] + 1;
                perform public.mgr_event(p_fixture, v_min, v_side, 'pen_goal', v_p[v_a].pid);
              else
                if random() < 0.6 and v_gkidx > 0 then
                  v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1;
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, v_p[v_gkidx].pid, 'defendido');
                else
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, null, 'para fora');
                end if;
              end if;
            end if;
          end if;
        end if;
      elsif v_r < 0.17 + 0.12 then
        if random() < 0.45 then v_corn[s] := v_corn[s] + 1; end if;  -- cruzamento cortado / jogada desarmada
      else
        -- ---- finalização ----
        v_head := random() < v_hdr[s];
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
                   case when v_head then (v_p[i].aw + 0.25) * power(v_p[i].head / 60, 3)
                        else power(v_p[i].aw + 0.05, 1.6) * power(v_p[i].fin / 60, 2) * (0.70 + 0.003 * v_p[i].cond) end
                 else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          v_q := 0.30 + 0.0025 * ((case when v_head then v_p[v_k].head else v_p[v_k].att end) - v_defav[d])
                 + case when s = 1 and not v_neut then 0.02 else 0 end
                 + v_qual[s] + random() * 0.35
                 + case v_tline[d] when 'high' then 0.003 * (v_p[v_k].pace - v_paceav[d]) when 'low' then -0.04 else 0 end
                 - case when v_head then 0.08 else 0 end;
          v_q := greatest(0.05, least(0.95, v_q * (0.85 + 0.15*v_p[v_k].fit)));
          v_gkidx := v_gki[d];
          v_r := random();
          if v_r < 0.20 then
            -- bloqueada
            if random() < 0.60 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, 'bloqueado'); end if;
          elsif random() < greatest(0.10, least(0.75, 0.26 + 0.32 * v_q + 0.0020 * (v_p[v_k].fin - 65))) then
            v_p[v_k].sot := v_p[v_k].sot + 1;
            if random() < greatest(0.05, least(0.70, 0.11 + 0.36 * v_q + 0.0015 * (v_p[v_k].fin - v_gkr[d]))) then
              -- GOL
              v_p[v_k].goals := v_p[v_k].goals + 1;
              v_sc[s] := v_sc[s] + 1;
              v_a := 0;
              if random() < 0.78 then
                v_w := '{}';
                for i in 1 .. v_n loop
                  v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and i <> v_k and v_p[i].pos <> 'GOL'
                                     then (v_p[i].aw + 0.6 * v_p[i].cw) * power(v_p[i].cre / 60, 2) else 0 end;
                end loop;
                v_a := public.mgr_pick(v_w);
                if v_a > 0 then v_p[v_a].assists := v_p[v_a].assists + 1; end if;
              end if;
              perform public.mgr_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid,
                                       case when v_a > 0 then v_p[v_a].pid end, case when v_head then 'de cabeça' end);
            else
              if v_gkidx > 0 then v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1; end if;
              if random() < 0.40 then v_corn[s] := v_corn[s] + 1; end if;
              if p_interactive is not null or v_q > 0.62 then
                perform public.mgr_event(p_fixture, v_min, v_side, 'save', v_p[v_k].pid,
                                         case when v_gkidx > 0 then v_p[v_gkidx].pid end, case when v_q > 0.62 then 'grande chance' end);
              end if;
            end if;
          else
            if random() < 0.18 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then
              perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_q > 0.62 then 'grande chance' end);
            end if;
          end if;
        end if;
      end if;
    end if;

    -- ---- faltas no meio-campo e cartões (os dois times) ----
    for s in 1 .. 2 loop
      continue when random() >= 0.125 * v_foulm[s] * (case when v_min > 75 then 1.15 else 1 end);
      v_side := case when s = 1 then 'h' else 'a' end;
      v_w := '{}';
      for i in 1 .. v_n loop
        v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL'
                           then (v_p[i].dw + 0.3) * (1 + (100 - v_p[i].tack) / 100) * case when v_p[i].yel > 0 then 0.45 else 1 end else 0 end;
      end loop;
      v_k := public.mgr_pick(v_w);
      continue when v_k = 0;
      v_p[v_k].fouls := v_p[v_k].fouls + 1;
      v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
        v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[s],v_ref::numeric,case when v_min>75 and abs(v_sc[1]-v_sc[2])<=1 then 1.10 else 1.0 end);
      v_r:=random();
      if v_r<(v_card->>'red')::float8 then
        v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
        perform public.mgr_event(p_fixture,v_min,v_side,'red',v_p[v_k].pid,null,'Entrada temerária');
        update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
        if p_interactive=v_side then v_stop:='red';end if;
      elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
        if v_p[v_k].yel>=1 then
          v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
          perform public.mgr_event(p_fixture,v_min,v_side,'second_yellow',v_p[v_k].pid);
          update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
          if p_interactive=v_side then v_stop:='red';end if;
        else
          v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_side,'yellow',v_p[v_k].pid);
        end if;
      end if;
    end loop;

    -- ---- desgaste, lesões e minutos jogados ----
    v_inj_stop := false;
    if v_min % 3 = 0 then
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_side := case when s = 1 then 'h' else 'a' end;
        v_p[i].cond := greatest(0, v_p[i].cond - 3 * 0.21 * v_p[i].drain * (1.32 - v_p[i].stam / 100 * 0.62) * v_drainm[s]
                                   * case when v_et then 1.15 else 1 end);
        if random() < 3 * 0.00005 * (1 + greatest(0, 70 - v_p[i].cond) / 25) * (case when v_tpress[s] = 'high' then 1.15 else 1 end) then
          v_p[i].inj := true; v_p[i].on_field := false; v_dirty := true;
          perform public.mgr_event(p_fixture, v_min, v_side, 'injury', v_p[i].pid);
          update public.mgr_match_players set status = 'injured_off', injured = true, left_min = v_min where fixture_id = p_fixture and player_id = v_p[i].pid;
          if p_interactive = v_side then v_inj_stop := true;
          else
            -- a IA troca na hora (se ainda tiver substituição)
            v_detail := public.mgr_do_sub(p_fixture, v_side, v_p[i].pid, public.mgr_best_bench(p_fixture, v_side, v_p[i].pos), v_min, true);
            v_reload := true;
          end if;
        end if;
      end loop;
    end if;
    if v_inj_stop then v_stop := 'injury'; end if;

    if v_reload then  -- grava o estado antes de recarregar a lista de quem está em campo
      update public.mgr_matches
         set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
       where fixture_id = p_fixture;
    end if;

    exit when v_stop in ('red', 'injury');
    if v_min = 45 and not v_et then v_stop := 'ht'; exit; end if;
    if v_min = 105 and v_et then v_stop := 'et_ht'; exit; end if;
  end loop;

  -- grava tudo
  if v_p is not null then
    update public.mgr_match_players m
       set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
           fouls = x.fouls, yellow = x.yel, red = x.red,
           minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
      from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
  end if;
  update public.mgr_matches
     set minute = v_min, updated_at = now(),
         state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
   where fixture_id = p_fixture;

  if v_min >= (case when v_et then 120 else 90 end) then v_stop := 'ft'; end if;
  if v_stop = 'segment' and v_min = 45 then v_stop := 'ht'; end if;
  return v_stop;
end;
$$;
create or replace function public.mgr_engine_run(p_fixture bigint,p_to int,p_interactive char)
returns text language plpgsql security definer set search_path=public as $$
begin
 if coalesce((select (state->>'engine_version')::int from public.mgr_matches where fixture_id=p_fixture),1)=1 then
  return public.mgr_engine_run_v1(p_fixture,p_to,p_interactive);
 end if;
 return public.mgr_engine_run_v2(p_fixture,p_to,p_interactive);
end $$;

revoke all on function public.mgr_card_chances(numeric,numeric,numeric,numeric,int,boolean,text,numeric,numeric),
 public.mgr_ai_plan(uuid,text,numeric,boolean),public.mgr_tactical_effect(jsonb,jsonb,numeric,numeric,numeric,numeric),
 public.mgr_ai_manage_v1(bigint,char,int),public.mgr_ai_manage_v2(bigint,char,int),public.mgr_ai_manage(bigint,char,int),
 public.mgr_engine_run_v1(bigint,int,char),public.mgr_engine_run_v2(bigint,int,char),public.mgr_engine_run(bigint,int,char)
 from public,anon,authenticated;


-- FILE: 17_season_draws.sql
-- EVOLUÇÃO 17: tabelas finais e sorteios individuais com classificação esportiva.

create table if not exists public.season_final_tables (
 season_id uuid not null references public.career_seasons(id) on delete cascade,
 competition_id text not null references public.sim_competitions(id),
 standings jsonb not null check(jsonb_typeof(standings)='array'),
 recorded_at timestamptz not null default now(), primary key(season_id,competition_id)
);
alter table public.season_final_tables enable row level security;
revoke all on public.season_final_tables from public,anon,authenticated;
grant select on public.season_final_tables to authenticated;
drop policy if exists own_final_tables on public.season_final_tables;
create policy own_final_tables on public.season_final_tables for select to authenticated using
 (exists(select 1 from public.career_seasons s join public.careers c on c.id=s.career_id where s.id=season_id and c.user_id=auth.uid()));

-- Mantém as vagas do formato já modelado: 6 brasileiras / 5 inglesas.
-- Não inventa fases preliminares ou ligas que o jogo ainda não simula.
update public.sim_competitions set rules=jsonb_set(rules,'{qualification,slots}',to_jsonb(
 (select count(*)::int from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
  where cc.competition_id=sim_competitions.id and cl.region=sim_competitions.region)))
 where kind='continental' and rules ? 'qualification' and not rules->'qualification' ? 'slots';

create or replace function public.sim_record_final_tables(p_season uuid)
returns void language plpgsql security definer set search_path=public as $$
declare c record; data jsonb;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 if not found then raise exception 'Temporada inexistente'; end if;
 if exists(select 1 from public.season_fixtures where season_id=p_season and status<>'played') then raise exception 'Temporada ainda tem jogos pendentes'; end if;
 for c in select sc.competition_id from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
    where sc.season_id=p_season and co.kind='league' loop
  select jsonb_agg(to_jsonb(t) order by t.pos) into data from public.sim_standings(p_season,c.competition_id,null) t;
  if data is null then raise exception 'Liga sem classificação final: %',c.competition_id; end if;
  insert into public.season_final_tables values(p_season,c.competition_id,data,now()) on conflict do nothing;
 end loop;
end $$;


-- A Copa do Brasil é modelada a partir das oitavas (16 vagas). Na continuidade
-- as vagas vêm da liga anterior; fases estaduais/preliminares não são simuladas.
update public.sim_competitions set rules=jsonb_set(jsonb_set(rules,'{qualification}',jsonb_build_object(
 'from','brasileirao','region','BRA','slots',(select count(*) from public.sim_competition_clubs where competition_id='copa_brasil'))),
 '{phases,0,pairing,mode}','"draw"'::jsonb) where id='copa_brasil';
update public.sim_competitions set rules=jsonb_set(rules,'{phases,0,pairing,first_season}','"reference"'::jsonb) where id='copa_brasil';

-- Única leitura de vagas esportivas para copas nacionais e continentais.
create or replace function public.sim_qualification_list(p_season uuid,p_comp text)
returns text[] language plpgsql security definer set search_path=public as $$
declare s public.career_seasons;co public.sim_competitions;previous uuid;source text;slots int;clubs text[];
begin
 select * into s from public.career_seasons where id=p_season;
 select * into co from public.sim_competitions where id=p_comp;
 source:=co.rules#>>'{qualification,from}';slots:=(co.rules#>>'{qualification,slots}')::int;
 if source is null or slots is null or slots<1 then raise exception 'Critério de classificação ausente em %',p_comp;end if;
 select old.id into previous from public.career_seasons old where old.career_id=s.career_id and old.region=s.region and old.season_no<s.season_no
  and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;
 if previous is null then
  select array_agg(cc.club_id order by cc.club_id) into clubs from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
   where cc.competition_id=p_comp and (co.kind<>'continental' or cl.region=s.region);
 else
  perform public.sim_record_final_tables(previous);
  select array_agg(t->>'club_id' order by(t->>'pos')::int) into clubs from public.season_final_tables ft
   cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=previous and ft.competition_id=source and(t->>'pos')::int<=slots;
 end if;
 if coalesce(cardinality(clubs),0)<>slots then raise exception 'Sem classificação suficiente para % (% vagas)',p_comp,slots;end if;
 return clubs;
end $$;

-- Uma tabela final é um retrato histórico, não é recalculada quando o regulamento muda.
create or replace function public.sim_keep_final_table()
returns trigger language plpgsql as $$ begin raise exception 'Classificação final é imutável'; end $$;
drop trigger if exists sim_keep_final_table_trg on public.season_final_tables;
create trigger sim_keep_final_table_trg before update on public.season_final_tables for each row execute function public.sim_keep_final_table();

create or replace function public.sim_season_transition(p_season uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_s      public.career_seasons;
  v_prev   jsonb;
  r        record;
  c        record;
  v_upper  text[];
  v_lower  text[];
  v_down   text[];
  v_up     text[];
  v_po     text[];
  v_n      int;
  v_res    jsonb := jsonb_build_object('leagues', '{}'::jsonb, 'promoted', '{}'::jsonb, 'relegated', '{}'::jsonb, 'qualified', '{}'::jsonb);
  v_q      text[];
  v_from   text;
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  perform public.sim_record_final_tables(p_season);
  select result into v_prev from public.season_transitions where from_season = p_season;
  if found then return v_prev; end if;                         -- já aplicado: não roda de novo
  if exists (select 1 from public.season_fixtures where season_id = p_season and status = 'pending') then
    raise exception 'A temporada ainda tem jogos pendentes.';
  end if;

  -- ligas que não mudam (sem regra): ficam como estão
  for c in select sp.competition_id as comp, array_agg(sp.club_id order by sp.club_id) as clubs
             from public.season_participants sp join public.sim_competitions sc on sc.id = sp.competition_id
            where sp.season_id = p_season and sc.kind = 'league' group by sp.competition_id loop
    v_res := jsonb_set(v_res, array['leagues', c.comp], to_jsonb(c.clubs));
  end loop;

  for r in select * from public.sim_promotion_rules_for(v_s.region, v_s.year) loop
    -- só aplica se as DUAS divisões foram disputadas nesta temporada (temporadas antigas não tinham Série B)
    continue when not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.upper_comp)
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.lower_comp);
    select array_agg(club_id order by club_id) into v_upper from public.season_participants where season_id = p_season and competition_id = r.upper_comp;
    select array_agg(club_id order by club_id) into v_lower from public.season_participants where season_id = p_season and competition_id = r.lower_comp;
    select count(*) into v_n from public.sim_standings(p_season, r.upper_comp, null);
    select array_agg(t.club_id order by t.pos) into v_down from public.sim_standings(p_season, r.upper_comp, null) t
     where t.pos > v_n - r.relegated;
    select array_agg(t.club_id order by t.pos) into v_up from public.sim_standings(p_season, r.lower_comp, null) t
     where t.pos <= r.promoted_direct;
    v_po := '{}';
    if r.promoted_playoff_phase is not null then
      select array_agg(f.tie_winner order by f.tie_no) into v_po from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = r.lower_comp and f.stage = r.promoted_playoff_phase and f.tie_winner is not null;
      v_up := coalesce(v_up, '{}') || coalesce(v_po, '{}');
    end if;
    v_down := coalesce(v_down, '{}');
    v_up := coalesce(v_up, '{}');
    if cardinality(v_up) <> cardinality(v_down) then
      raise exception 'Acesso/rebaixamento desequilibrado em % / %: sobem %, caem %', r.upper_comp, r.lower_comp, cardinality(v_up), cardinality(v_down);
    end if;
    if exists (select 1 from unnest(v_up) u where u = any (v_down)) then raise exception 'Clube sobe e cai ao mesmo tempo'; end if;
    v_res := jsonb_set(v_res, array['leagues', r.upper_comp],
               to_jsonb(array(select x from unnest(v_upper) x where not x = any (v_down) union select unnest(v_up) order by 1)));
    v_res := jsonb_set(v_res, array['leagues', r.lower_comp],
               to_jsonb(array(select x from unnest(v_lower) x where not x = any (v_up) union select unnest(v_down) order by 1)));
    v_res := jsonb_set(v_res, array['promoted', r.upper_comp], to_jsonb(v_up));
    v_res := jsonb_set(v_res, array['relegated', r.lower_comp], to_jsonb(v_down));
  end loop;

  -- classificação continental: as vagas do país vão para os mais bem colocados da liga
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'continental' loop
    v_from := c.rules #>> '{qualification,from}';
    continue when v_from is null
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = v_from);
    v_n:=(c.rules#>>'{qualification,slots}')::int;
    if v_n is null or v_n<1 then raise exception 'Vagas continentais não configuradas: %',c.id;end if;
    select array_agg(t->>'club_id' order by (t->>'pos')::int) into v_q from public.season_final_tables ft cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=p_season and ft.competition_id=v_from and (t->>'pos')::int<=v_n;
    if cardinality(v_q)<>v_n then raise exception 'Classificação incompleta para %',c.id;end if;
    v_res := jsonb_set(v_res, array['qualified', c.id], to_jsonb(coalesce(v_q, '{}')));
  end loop;

  insert into public.season_transitions (career_id, region, from_season, year, result)
  values (v_s.career_id, v_s.region, p_season, v_s.year, v_res)
  on conflict (from_season) do nothing;
  return (select result from public.season_transitions where from_season = p_season);
end;
$$;
create or replace function public.sim_participants_build(p_season uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_s     public.career_seasons;
  v_t     public.season_transitions;
  c       record;
  v_list  text[];
  v_q     text[];
  v_slots record;
  v_i     int;
  v_n     int := 0;
  v_entry jsonb;
  v_lg    record;
  v_previous uuid;
  v_from text;
  v_count int;
begin
  select * into v_s from public.career_seasons where id = p_season;
  if exists (select 1 from public.season_participants where season_id = p_season) then
    return 0;                                            -- já montado (idempotente)
  end if;
  select t.* into v_t from public.season_transitions t
    join public.career_seasons fs on fs.id = t.from_season
   where t.career_id = v_s.career_id and fs.career_id=v_s.career_id and t.region = v_s.region and fs.status in ('finished','archived') and fs.season_no < v_s.season_no
   order by fs.season_no desc limit 1;

  select old.id into v_previous from public.career_seasons old where old.career_id=v_s.career_id and old.region=v_s.region
    and old.season_no<v_s.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;

  -- 2a) LIGAS
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'league' order by sort_order loop
    v_list := null;
    if v_t.id is not null and v_t.result -> 'leagues' ? c.id then
      select array_agg(x) into v_list from jsonb_array_elements_text(v_t.result -> 'leagues' -> c.id) x;
    end if;
    if v_list is null then
      select array_agg(club_id order by club_id) into v_list from public.sim_competition_clubs where competition_id = c.id;
    end if;
    insert into public.season_participants (season_id, competition_id, club_id, division_key, origin)
    select p_season, c.id, x,
           v_s.region || ':league',
           case when v_t.id is null then 'reference'
                when coalesce(v_t.result -> 'promoted' -> c.id, '[]'::jsonb) ? x then 'promoted'
                when coalesce(v_t.result -> 'relegated' -> c.id, '[]'::jsonb) ? x then 'relegated'
                else 'stayed' end
      from unnest(v_list) x;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- 2b) COPAS NACIONAIS: com "entry" (copas inglesas) = todos os clubes das ligas da temporada, entrando na fase da sua divisão;
  --     com qualification = mérito na liga anterior; primeira edição pode conservar a chave de referência
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'cup' order by sort_order loop
    v_entry := c.rules -> 'entry';
    if c.rules ? 'qualification' and v_previous is null and c.rules#>>'{phases,0,pairing,first_season}'='reference' then
      insert into public.season_participants(season_id,competition_id,club_id,group_label,seed,entry_phase,origin)
       select p_season,c.id,cc.club_id,cc.group_label,cc.seed,cc.entry_phase,'reference' from public.sim_competition_clubs cc where cc.competition_id=c.id;
    elsif c.rules ? 'qualification' then
      v_list:=public.sim_qualification_list(p_season,c.id);
      insert into public.season_participants(season_id,competition_id,club_id,origin)
       select p_season,c.id,x,'league' from unnest(v_list) x;
    elsif v_entry is not null then
      for v_lg in select key as comp, value #>> '{}' as phase from jsonb_each(v_entry) loop
        insert into public.season_participants (season_id, competition_id, club_id, entry_phase, origin)
        select p_season, c.id, sp.club_id, v_lg.phase, 'league'
          from public.season_participants sp
         where sp.season_id = p_season and sp.competition_id = v_lg.comp
        on conflict do nothing;
      end loop;
    else
      insert into public.season_participants (season_id, competition_id, club_id, group_label, seed, entry_phase, origin)
      select p_season, c.id, cc.club_id, cc.group_label, cc.seed, cc.entry_phase, 'reference'
        from public.sim_competition_clubs cc where cc.competition_id = c.id
      on conflict do nothing;
    end if;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- As vagas nacionais são preenchidas pela tabela FINAL da própria carreira.
  select old.id into v_previous from public.career_seasons old where old.career_id=v_s.career_id and old.region=v_s.region
    and old.season_no<v_s.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;
  for c in select * from public.sim_competitions where region=v_s.region and active and kind='continental' loop
    v_from:=c.rules#>>'{qualification,from}';
    v_count:=(c.rules#>>'{qualification,slots}')::int;
    if v_count is null or v_count<1 then raise exception 'Vagas não configuradas: %',c.id;end if;
    v_q:=public.sim_qualification_list(p_season,c.id);
    if cardinality(v_q)<>v_count then raise exception 'Lista regional incoerente em %',c.id;end if;
    insert into public.season_participants(season_id,competition_id,club_id,origin)
      select p_season,c.id,x,case when v_previous is null then 'reference' else 'qualified' end from unnest(v_q) x;
    insert into public.season_participants(season_id,competition_id,club_id,origin)
      select p_season,c.id,cc.club_id,'reference' from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
      where cc.competition_id=c.id and cl.region is distinct from v_s.region;
    if (select count(*) from public.season_participants where season_id=p_season and competition_id=c.id)
       <> (select count(*) from public.sim_competition_clubs where competition_id=c.id) then
      raise exception 'Quantidade de participantes incoerente em %',c.id;
    end if;
    perform public.sim_continental_draw(p_season,c.id);
  end loop;

  select count(*) into v_n from public.season_participants where season_id = p_season;
  return v_n;
end;
$$;
create or replace function public.sim_create_season(p_career uuid, p_region text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_club text;
  v_no   int;
  v_id   uuid;
  c      record;
  v_ph   jsonb;
begin
  perform 1 from public.careers where id=p_career for update;
  if not found then raise exception 'Carreira inexistente';end if;
  if exists(select 1 from public.career_seasons where career_id=p_career and status='active') then raise exception 'Carreira já tem temporada ativa';end if;
  select club_id into v_club from public.careers where id = p_career;
  if v_club is null then raise exception 'Escolha um clube antes de iniciar a temporada'; end if;
  if not exists (select 1 from public.sim_competitions where region = p_region and active) then
    raise exception 'Região sem competições: %', p_region;
  end if;

  select coalesce(max(season_no), 0) + 1 into v_no from public.career_seasons where career_id = p_career;
  insert into public.career_seasons (career_id, season_no, year, club_id, region)
  values (p_career, v_no, 2025 + v_no, v_club, p_region) returning id into v_id;

  perform public.sim_participants_build(v_id);

  for c in select * from public.sim_competitions where region = p_region and active order by sort_order loop
    v_ph := public.sim_phase_at(c.id, 1);
    if v_ph is null then raise exception 'Competição sem fases: %', c.id; end if;
    insert into public.season_competitions (season_id, competition_id, stage) values (v_id, c.id, v_ph ->> 'id');
    perform public.sim_phase_create(v_id, c.id, v_ph ->> 'id', null);
  end loop;

  insert into public.career_stats (career_id) values (p_career) on conflict do nothing;
  return v_id;
end;
$$;
create or replace function public.sim_phase_create(p_season uuid, p_comp text, p_phase_id text, p_winners text[])
returns int language plpgsql security definer set search_path = public as $$
declare
  v_ph    jsonb := public.sim_phase(p_comp, p_phase_id);
  v_type  text;
  v_legs  int;
  v_teams text[];
  v_g     record;
  r       record;
  v_n     int := 0;
begin
  perform 1 from public.career_seasons where id=p_season for update;
  if not found then raise exception 'Temporada inexistente';end if;
  if v_ph is null then raise exception 'Fase % não existe em %', p_phase_id, p_comp; end if;
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and stage = p_phase_id) then
    return 0;                                                    -- já criada (idempotente)
  end if;
  v_type := v_ph ->> 'type';
  v_legs := coalesce((v_ph ->> 'legs')::int, 1);

  if v_type = 'league' then
    select array_agg(club_id order by random()) into v_teams
      from public.season_participants where season_id = p_season and competition_id = p_comp
       and (entry_phase is null or entry_phase = p_phase_id);
    if coalesce(array_length(v_teams, 1), 0) < 2 or array_length(v_teams, 1) % 2 = 1 then
      raise exception 'Liga % precisa de número par de clubes (tem %)', p_comp, coalesce(array_length(v_teams, 1), 0);
    end if;
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, home_club, away_club)
    select p_season, p_comp, p_phase_id, rr.round_no, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
    get diagnostics v_n = row_count;

  elsif v_type = 'groups' then
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      select array_agg(club_id order by random()) into v_teams
        from public.season_participants where season_id = p_season and competition_id = p_comp and group_label = v_g.group_label;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, group_label, home_club, away_club)
      select p_season, p_comp, p_phase_id, rr.round_no, v_g.group_label, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
      v_n := v_n + array_length(v_teams, 1) * (array_length(v_teams, 1) - 1) / (case when v_legs = 2 then 1 else 2 end);
    end loop;

  elsif v_type = 'swiss' then
    v_n := public.sim_swiss_create(p_season, p_comp, v_ph);

  elsif v_type = 'knockout' then
    for r in select * from public.sim_phase_pairs(p_season, p_comp, v_ph, p_winners) loop
      if r.o_home is null or r.o_away is null then raise exception 'Confronto incompleto em % / %', p_comp, p_phase_id; end if;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
      values (p_season, p_comp, p_phase_id, 1, r.o_tie, 1, r.o_home, r.o_away);
      v_n := v_n + 1;
      if v_legs = 2 then
        insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
        values (p_season, p_comp, p_phase_id, 2, r.o_tie, 2, r.o_away, r.o_home);
        v_n := v_n + 1;
      end if;
    end loop;
    if v_n = 0 then raise exception 'Fase eliminatória sem confrontos: % / %', p_comp, p_phase_id; end if;
  else
    raise exception 'Tipo de fase desconhecido: %', v_type;
  end if;
  return v_n;
end;
$$;

create or replace function public.sim_continental_draw(p_season uuid,p_comp text)
returns void language plpgsql security definer set search_path=public as $$
declare
 n int; pot_size int; previous uuid; ids text[]; assigned text[]; groups int[]; available int[]; team text;
 cty jsonb; country text; ok boolean; g int; attempt int; pot int;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 if exists(select 1 from public.season_fixtures where season_id=p_season and competition_id=p_comp) then
  raise exception 'Não é permitido refazer sorteio com calendário criado';
 end if;
 select count(*) into n from public.season_participants where season_id=p_season and competition_id=p_comp;
 if n not in(32,36) then raise exception 'Formato continental sem sorteio configurado: % clubes',n; end if;
 pot_size:=n/4;
 select old.id into previous from public.career_seasons old join public.career_seasons cur on cur.id=p_season
 where old.career_id=cur.career_id and old.region=cur.region and old.season_no<cur.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending')))
 order by old.season_no desc limit 1;
 -- UCL usa os potes de coeficiente cadastrados para ligas não simuladas.
 -- As vagas da região são ocupadas por mérito (ordem final da liga), nunca
 -- pelos nomes originais. Conserva a distribuição de associações dos potes;
 -- ordenar só por força podia colocar cinco ingleses em um pote de nove,
 -- tornando matematicamente impossível evitar confrontos nacionais.
 if n=36 then
  update public.season_participants sp set seed=cc.seed,group_label=null
   from public.sim_competition_clubs cc,public.sim_clubs cl,public.career_seasons cs
   where sp.season_id=p_season and sp.competition_id=p_comp and cc.competition_id=p_comp and cc.club_id=sp.club_id
     and cl.id=sp.club_id and cs.id=p_season and cl.region is distinct from cs.region;
  with places as (
   select cc.seed,row_number() over(order by cc.seed,cc.club_id) as rn
   from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id join public.career_seasons cs on cs.id=p_season
   where cc.competition_id=p_comp and cl.region=cs.region
  ), qualifiers as (
   select sp.club_id,row_number() over(order by coalesce((select (t->>'pos')::int from public.season_final_tables ft
      cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=previous
       and ft.competition_id=(select rules#>>'{qualification,from}' from public.sim_competitions where id=p_comp)
       and t->>'club_id'=sp.club_id),999),cl.strength desc,sp.club_id) as rn
   from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id join public.career_seasons cs on cs.id=p_season
   where sp.season_id=p_season and sp.competition_id=p_comp and cl.region=cs.region
  ) update public.season_participants sp set seed=places.seed,group_label=null
    from qualifiers join places using(rn) where sp.season_id=p_season and sp.competition_id=p_comp and sp.club_id=qualifiers.club_id;
  return;
 end if;
 -- Cabeças de chave: campeão continental anterior; depois força de referência +
 -- mérito recente na continental da MESMA carreira. Coeficiente é estimativa de gameplay.
 with ranked as (
  select sp.club_id,row_number() over(order by
   case when exists(select 1 from public.season_competitions sc where sc.season_id=previous and sc.competition_id=p_comp and sc.champion_club=sp.club_id) then 1 else 0 end desc,
   cl.strength+least(6,coalesce((select sum(case when (f.home_club=sp.club_id and f.home_goals>f.away_goals)
      or(f.away_club=sp.club_id and f.away_goals>f.home_goals) then 3 when f.home_goals=f.away_goals then 1 else 0 end)*0.15
      from public.season_fixtures f where f.season_id=previous and f.competition_id=p_comp and f.status='played'
       and sp.club_id in(f.home_club,f.away_club)),0)) desc,sp.club_id) as rank
   from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
   where sp.season_id=p_season and sp.competition_id=p_comp
 ) update public.season_participants sp set seed=1+(ranked.rank-1)/pot_size,group_label=null
 from ranked where sp.season_id=p_season and sp.competition_id=p_comp and sp.club_id=ranked.club_id;
 if n=36 then return; end if;
 select jsonb_object_agg(sp.club_id,cl.country) into cty from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
 where sp.season_id=p_season and sp.competition_id=p_comp;
 -- Um clube de cada pote por grupo; nenhuma associação repetida no grupo.
 for attempt in 1..500 loop
  assigned:=array_fill(null::text,array[32]);ok:=true;
  for pot in 1..4 loop
   select array_agg(club_id order by random()) into ids from public.season_participants
    where season_id=p_season and competition_id=p_comp and seed=pot;
   available:=array[1,2,3,4,5,6,7,8];
   foreach team in array ids loop
    select x into g from unnest(available) x where not exists(
      select 1 from generate_series(0,pot-2) k where cty->>assigned[k*8+x]=cty->>team)
     order by random() limit 1;
    if g is null then ok:=false;exit;end if;
    assigned[(pot-1)*8+g]:=team;available:=array_remove(available,g);
   end loop;
   exit when not ok;
  end loop;
  exit when ok;
 end loop;
 if not ok then raise exception 'Não foi possível sortear grupos respeitando as associações'; end if;
 for pot in 1..4 loop
  for g in 1..8 loop
   update public.season_participants set group_label=chr(64+g)
    where season_id=p_season and competition_id=p_comp and club_id=assigned[(pot-1)*8+g];
  end loop;
 end loop;
end $$;

create or replace function public.sim_swiss_cost(p_slots text[],p_tpl jsonb,p_cty jsonb)
returns bigint language sql immutable as $$
 with edges as (
  select (m->>1)::int+1 as a,(m->>2)::int+1 as b from jsonb_array_elements(p_tpl) m
 ), sides as(select a,b from edges union all select b,a from edges),
 countries as(select a,p_cty->>p_slots[b] as country,count(*) as n from sides group by 1,2)
 select (select count(*)*1000 from edges where p_cty->>p_slots[a]=p_cty->>p_slots[b])
       +coalesce((select sum(greatest(n-2,0))*100 from countries),0)
$$;

-- Busca por restrições sobre ASSOCIAÇÕES, não permutações de clubes equivalentes.
-- MRV + verificação antecipada: sem compatriotas; até dois rivais de cada país.
create or replace function public.sim_swiss_search(p_adj int[],p_left int[],p_assignment int[],p_neighbors int[],p_countries int,p_steps int default 0)
returns jsonb language plpgsql volatile set search_path=public as $$
declare
 slot int; country int; k int; neighbor int; pot int; domain int[]; best_domain int[]; best_slot int:=0;
 best_n int:=100;best_degree int:=-1;degree int;allowed boolean;a int[];remaining int[];neighbors int[];result jsonb;
begin
 p_steps:=p_steps+1;
 if p_steps>30000 then return jsonb_build_object('assignment',null,'steps',p_steps);end if;
 for slot in 1..36 loop
  continue when p_assignment[slot]<>0;
  pot:=(slot-1)/9;domain:='{}';degree:=0;
  for k in 1..8 loop
   if p_assignment[p_adj[(slot-1)*8+k]]<>0 then degree:=degree+1;end if;
  end loop;
  for country in 1..p_countries loop
   continue when p_left[pot*p_countries+country]=0 or p_neighbors[(slot-1)*p_countries+country]>0;
   allowed:=true;
   for k in 1..8 loop
    neighbor:=p_adj[(slot-1)*8+k];
    if p_neighbors[(neighbor-1)*p_countries+country]>=2 then allowed:=false;exit;end if;
   end loop;
   if allowed then domain:=array_append(domain,country);end if;
  end loop;
  if cardinality(domain)=0 then return jsonb_build_object('assignment',null,'steps',p_steps);end if;
  if cardinality(domain)<best_n or (cardinality(domain)=best_n and degree>best_degree) then
   best_slot:=slot;best_domain:=domain;best_n:=cardinality(domain);best_degree:=degree;
  end if;
 end loop;
 if best_slot=0 then return jsonb_build_object('assignment',to_jsonb(p_assignment),'steps',p_steps);end if;
 pot:=(best_slot-1)/9;
 select array_agg(x order by p_left[pot*p_countries+x] desc,random()) into best_domain from unnest(best_domain) x;
 foreach country in array best_domain loop
  a:=p_assignment;remaining:=p_left;neighbors:=p_neighbors;
  a[best_slot]:=country;remaining[pot*p_countries+country]:=remaining[pot*p_countries+country]-1;
  for k in 1..8 loop
   neighbor:=p_adj[(best_slot-1)*8+k];
   neighbors[(neighbor-1)*p_countries+country]:=neighbors[(neighbor-1)*p_countries+country]+1;
  end loop;
  result:=public.sim_swiss_search(p_adj,remaining,a,neighbors,p_countries,p_steps);
  p_steps:=(result->>'steps')::int;
  if jsonb_typeof(result->'assignment')='array' then return result;end if;
  exit when p_steps>30000;
 end loop;
 return jsonb_build_object('assignment',null,'steps',p_steps);
end $$;

create or replace function public.sim_swiss_create(p_season uuid,p_comp text,p_phase jsonb)
returns int language plpgsql security definer set search_path=public as $$
declare
 templates jsonb;tpl jsonb;cty jsonb;countries text[];slots text[];ids text[];adj int[];degree int[];remaining int[];colors int[];
 result jsonb;signature jsonb;certificate jsonb;pot int;c int;k int;a int;b int;v_count int;try int;m jsonb;n int:=0;nc int;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 select rules->'swiss_templates' into templates from public.sim_competitions where id=p_comp;
 if coalesce(jsonb_array_length(templates),0)=0 then raise exception 'Sem modelos de calendário suíço';end if;
 if (select count(*) from public.season_participants where season_id=p_season and competition_id=p_comp)<>36 then raise exception 'Fase suíça exige 36 clubes';end if;
 select array_agg(distinct cl.country order by cl.country),jsonb_object_agg(sp.club_id,cl.country) into countries,cty
  from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id where sp.season_id=p_season and sp.competition_id=p_comp;
 nc:=cardinality(countries);remaining:=array_fill(0,array[4*nc]);
 for pot in 0..3 loop
  if (select count(*) from public.season_participants where season_id=p_season and competition_id=p_comp and seed=pot+1)<>9 then raise exception 'Pote inválido';end if;
  for c in 1..nc loop
   select count(*) into v_count from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
    where sp.season_id=p_season and sp.competition_id=p_comp and sp.seed=pot+1 and cl.country=countries[c];
   remaining[pot*nc+c]:=v_count;
  end loop;
 end loop;
 -- Primeiro utiliza uma solução previamente certificada para o perfil de países.
 -- O certificado contém somente associações por vaga, nunca clubes classificados.
 -- Os nomes são sorteados individualmente abaixo, preservando o histórico da carreira.
 with counts as(select sp.seed,cl.country,count(*) as n from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
   where sp.season_id=p_season and sp.competition_id=p_comp group by 1,2),
 pots as(select seed,jsonb_object_agg(counts.country,counts.n) as association_counts from counts group by seed)
 select jsonb_agg(pots.association_counts order by seed) into signature from pots;
 select cert into certificate from public.sim_competitions co cross join lateral jsonb_array_elements(co.rules->'swiss_certificates') cert
 where co.id=p_comp and cert->'signature'=signature order by random() limit 1;
 if certificate is not null then
  tpl:=templates->(certificate->>'template')::int;
  select array_agg(array_position(countries,x) order by o) into colors
   from jsonb_array_elements_text(certificate->'assignment') with ordinality t(x,o);
 end if;
 -- Configurações novas sem certificado ainda passam pela busca de restrições.
 -- Cada modelo é tentado uma vez, em ordem sorteada; nenhuma solução inválida é aceita.
 for try in select i from generate_series(0,jsonb_array_length(templates)-1) i order by random() loop
  exit when colors is not null;
  tpl:=templates->try;adj:=array_fill(0,array[36*8]);degree:=array_fill(0,array[36]);
  for m in select * from jsonb_array_elements(tpl) loop
   a:=(m->>1)::int+1;b:=(m->>2)::int+1;
   degree[a]:=degree[a]+1;degree[b]:=degree[b]+1;
   if a=b or a not between 1 and 36 or b not between 1 and 36 or degree[a]>8 or degree[b]>8 then raise exception 'Modelo suíço inválido';end if;
   adj[(a-1)*8+degree[a]]:=b;adj[(b-1)*8+degree[b]]:=a;
  end loop;
  if exists(select 1 from unnest(degree) x where x<>8) then raise exception 'Modelo suíço incompleto';end if;
  result:=public.sim_swiss_search(adj,remaining,array_fill(0,array[36]),array_fill(0,array[36*nc]),nc);
  if jsonb_typeof(result->'assignment')='array' then
   select array_agg(x::int order by o) into colors from jsonb_array_elements_text(result->'assignment') with ordinality t(x,o);
   exit;
  end if;
 end loop;
 if colors is null then raise exception 'Não há sorteio válido para os potes configurados. Nenhuma temporada parcial foi gravada.';end if;
 slots:=array_fill(null::text,array[36]);
 for pot in 0..3 loop
  for c in 1..nc loop
   select array_agg(sp.club_id order by random()) into ids from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
    where sp.season_id=p_season and sp.competition_id=p_comp and sp.seed=pot+1 and cl.country=countries[c];
   k:=0;
   for a in pot*9+1..pot*9+9 loop
    if colors[a]=c then k:=k+1;slots[a]:=ids[k];end if;
   end loop;
  end loop;
 end loop;
 if public.sim_swiss_cost(slots,tpl,cty)<>0 then raise exception 'Sorteio violou as regras de associação';end if;
 for m in select * from jsonb_array_elements(tpl) loop
  insert into public.season_fixtures(season_id,competition_id,stage,round_no,home_club,away_club)
   values(p_season,p_comp,p_phase->>'id',(m->>0)::int,slots[(m->>1)::int+1],slots[(m->>2)::int+1]);
  n:=n+1;
 end loop;
 return n;
end $$;


create or replace function public.sim_phase_pairs(p_season uuid, p_comp text, p_phase jsonb, p_winners text[])
returns table (o_tie int, o_home text, o_away text)
language plpgsql security definer set search_path = public as $$
declare
  v_mode  text := coalesce(p_phase #>> '{pairing,mode}', 'draw');
  v_legs  int  := coalesce((p_phase ->> 'legs')::int, 1);
  v_from  text := p_phase #>> '{pairing,from}';
  v_seedf text := p_phase #>> '{pairing,seed_from}';
  v_ent   text[];
  v_pos   jsonb;
  v_i     int;
  v_a     text;
  v_b     text;
  v_hi    text;
  v_lo    text;
  pr      jsonb;
  v_wc text[]; v_wg text[]; v_rc text[]; v_rg text[];
  v_perm int[];
  v_ok   boolean;
  v_try  int;
  v_g    record;
  v_s1   text[];
  v_s2   text[];
  v_w    text[];
  v_tie  int := 0;
  v_grp  int;
  v_seedpairs int[][] := array[[1,2],[7,8],[3,4],[5,6]];
begin
  -- quem entra nesta fase: vencedores da fase anterior + clubes que entram aqui (copas inglesas)
  v_ent := coalesce(p_winners, '{}') || coalesce((select array_agg(club_id order by club_id) from public.season_participants
            where season_id = p_season and competition_id = p_comp
              and (entry_phase = p_phase ->> 'id' or (entry_phase is null and (p_phase ->> 'idx')::int = 1))), '{}');

  if p_phase#>>'{pairing,first_season}'='reference' and exists(select 1 from public.season_participants where season_id=p_season and competition_id=p_comp and origin='reference' and group_label is not null) then
    v_mode:='fixed';
  end if;

  -- posição na fase de liga (quando a chave depende dela)
  if coalesce(v_from, v_seedf) is not null then
    select jsonb_object_agg(t.club_id, t.pos) into v_pos from public.sim_standings(p_season, p_comp, null) t;
  end if;

  if v_mode = 'fixed' then
    -- Copa do Brasil: confrontos de referência (T1..T8), seed 1 manda o 1º jogo
    for v_g in
      select sp.group_label, max(sp.club_id) filter (where sp.seed = 1) as c1, max(sp.club_id) filter (where sp.seed = 2) as c2
        from public.season_participants sp
       where sp.season_id = p_season and sp.competition_id = p_comp and sp.group_label is not null
       group by sp.group_label order by sp.group_label
    loop
      o_tie := coalesce(nullif(regexp_replace(v_g.group_label, '\D', '', 'g'), '')::int, v_tie + 1);
      v_tie := o_tie;
      o_home := v_g.c1; o_away := v_g.c2; return next;
    end loop;

  elsif v_mode = 'draw' then
    select array_agg(x order by random()) into v_ent from unnest(v_ent) x;
    for v_i in 1 .. coalesce(array_length(v_ent, 1), 0) / 2 loop
      o_tie := v_i; o_home := v_ent[2 * v_i - 1]; o_away := v_ent[2 * v_i]; return next;
    end loop;

  elsif v_mode = 'lib_r16' then
    -- 1º de cada grupo x 2º de OUTRO grupo; o 1º decide em casa
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      v_wc := coalesce(v_wc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 1);
      v_rc := coalesce(v_rc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 2);
      v_wg := coalesce(v_wg, '{}') || v_g.group_label;
      v_rg := coalesce(v_rg, '{}') || v_g.group_label;
    end loop;
    for v_try in 1 .. 300 loop
      select array_agg(i order by random()) into v_perm from generate_series(1, array_length(v_rc, 1)) as i;
      v_ok := true;
      for v_i in 1 .. array_length(v_wc, 1) loop
        if v_rg[v_perm[v_i]] = v_wg[v_i] then v_ok := false; exit; end if;
      end loop;
      exit when v_ok;
    end loop;
    if not v_ok then raise exception 'Sorteio de oitavas sem combinação válida';end if;
    for v_i in 1 .. array_length(v_wc, 1) loop
      o_tie := v_i; o_home := v_rc[v_perm[v_i]]; o_away := v_wc[v_i]; return next;
    end loop;

  elsif v_mode = 'positions' then
    -- pares de posições da liga (ex.: Série B [[3,6],[4,5]]); o melhor colocado decide em casa
    v_i := 0;
    for pr in select * from jsonb_array_elements(p_phase #> '{pairing,pairs}') loop
      v_i := v_i + 1;
      select club_id into v_hi from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 0)::int;
      select club_id into v_lo from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 1)::int;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'champ_sf' then
    -- playoff da Championship: 3º x vencedor de pior campanha; 4º x o outro (melhor colocado decide em casa)
    select club_id into v_a from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,0}')::int;
    select club_id into v_b from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,1}')::int;
    select array_agg(x order by (v_pos ->> x)::int desc) into v_w from unnest(p_winners) x;   -- pior campanha primeiro
    o_tie := 1; o_home := v_w[1]; o_away := v_a; return next;
    o_tie := 2; o_home := v_w[2]; o_away := v_b; return next;

  elsif v_mode = 'bracket' then
    -- chave fixa: vencedor do confronto k x vencedor do k+1; com seed_from, o melhor colocado decide em casa
    for v_i in 1 .. coalesce(array_length(p_winners, 1), 0) / 2 loop
      v_a := p_winners[2 * v_i - 1]; v_b := p_winners[2 * v_i];
      if v_seedf is not null and (v_pos ->> v_a)::int < (v_pos ->> v_b)::int then
        v_hi := v_a; v_lo := v_b;
      elsif v_seedf is not null then
        v_hi := v_b; v_lo := v_a;
      elsif random() < 0.5 then v_hi := v_a; v_lo := v_b;
      else v_hi := v_b; v_lo := v_a; end if;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'ucl_po' then
    -- (9º/10º x 23º/24º), (11º/12º x 21º/22º), (13º/14º x 19º/20º), (15º/16º x 17º/18º); cabeça de chave decide em casa
    for v_grp in 0 .. 3 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (9 + 2 * v_grp, 10 + 2 * v_grp);
      select array_agg(club_id order by random()) into v_s2 from public.sim_standings(p_season, p_comp, null)
       where pos in (23 - 2 * v_grp, 24 - 2 * v_grp);
      for v_i in 1 .. 2 loop
        v_tie := v_tie + 1;
        o_tie := v_tie; o_home := v_s2[v_i]; o_away := v_s1[v_i]; return next;
      end loop;
    end loop;

  elsif v_mode = 'ucl_r16' then
    -- vencedores do playoff chegam na ordem dos confrontos: 1-2 (9º/10º), 3-4 (11º/12º), 5-6 (13º/14º), 7-8 (15º/16º)
    -- 1º/2º x vencedores 7-8 · 7º/8º x vencedores 1-2 · 3º/4º x vencedores 5-6 · 5º/6º x vencedores 3-4
    -- ordem dos confrontos = chave: [1/2, 7/8, 3/4, 5/6] de um lado e os outros do outro (1º e 2º em lados opostos)
    for v_grp in 1 .. 4 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (v_seedpairs[v_grp][1], v_seedpairs[v_grp][2]);
      v_wc := coalesce(v_wc, '{}') || v_s1;
    end loop;
    -- v_wc = [s(1/2)a, s(1/2)b, s(7/8)a, s(7/8)b, s(3/4)a, s(3/4)b, s(5/6)a, s(5/6)b]
    v_rc := array[p_winners[7], p_winners[8], p_winners[1], p_winners[2], p_winners[5], p_winners[6], p_winners[3], p_winners[4]];
    if random() < 0.5 then v_rc := array[v_rc[2], v_rc[1], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[4], v_rc[3], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[6], v_rc[5], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[8], v_rc[7]]; end if;
    -- lado A: confrontos 1-4 ; lado B: 5-8
    o_tie := 1; o_home := v_rc[1]; o_away := v_wc[1]; return next;
    o_tie := 2; o_home := v_rc[3]; o_away := v_wc[3]; return next;
    o_tie := 3; o_home := v_rc[5]; o_away := v_wc[5]; return next;
    o_tie := 4; o_home := v_rc[7]; o_away := v_wc[7]; return next;
    o_tie := 5; o_home := v_rc[2]; o_away := v_wc[2]; return next;
    o_tie := 6; o_home := v_rc[4]; o_away := v_wc[4]; return next;
    o_tie := 7; o_home := v_rc[6]; o_away := v_wc[6]; return next;
    o_tie := 8; o_home := v_rc[8]; o_away := v_wc[8]; return next;

  else
    raise exception 'Chaveamento desconhecido: %', v_mode;
  end if;
end;
$$;

create or replace function public.sim_resolve_ties(p_season uuid, p_comp text, p_stage text)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  v_ph      jsonb := public.sim_phase(p_comp, p_stage);
  v_rule    text  := coalesce(public.sim_phase(p_comp, p_stage) ->> 'tie', 'penalties');
  v_t       record;
  v_c1      text;
  v_c2      text;
  v_g1      int;
  v_g2      int;
  v_last    bigint;
  v_lasthome text;
  v_lastwin text;
  v_w       text;
  v_wp      int;
  v_lp      int;
  v_out     text[] := '{}';
begin
  if exists(select 1 from public.season_fixtures where season_id=p_season and competition_id=p_comp and stage=p_stage and status<>'played') then raise exception 'Confronto ainda não terminou';end if;
  for v_t in
    select distinct tie_no from public.season_fixtures
    where season_id = p_season and competition_id = p_comp and stage = p_stage order by tie_no
  loop
    select home_club, away_club into v_c1, v_c2 from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no and leg = 1;
    select id, home_club, tie_winner into v_last, v_lasthome, v_lastwin from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no
     order by leg desc limit 1;

    if v_lastwin is not null then
      v_w := v_lastwin;
    else
      select coalesce(sum(case when home_club = v_c1 then home_goals else away_goals end), 0),
             coalesce(sum(case when home_club = v_c2 then home_goals else away_goals end), 0)
        into v_g1, v_g2
        from public.season_fixtures
       where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no;
      if v_g1 > v_g2 then v_w := v_c1;
      elsif v_g2 > v_g1 then v_w := v_c2;
      elsif v_rule = 'higher_seed' then
        v_w := v_lasthome;
      else
        v_w  := public.sim_pens_winner(v_c1, v_c2);
        v_wp := 3 + floor(random() * 3)::int;
        v_lp := greatest(0, v_wp - 1 - floor(random() * 2)::int);
        update public.season_fixtures
           set home_pens = case when v_lasthome = v_w then v_wp else v_lp end,
               away_pens = case when v_lasthome = v_w then v_lp else v_wp end
         where id = v_last;
      end if;
      update public.season_fixtures set tie_winner = v_w where id = v_last;
    end if;
    v_out := v_out || v_w;
  end loop;
  return v_out;
end;
$$;

-- Segurança explícita em todas as novas funções internas.
revoke all on function public.sim_continental_draw(uuid,text),public.sim_swiss_cost(text[],jsonb,jsonb),
 public.sim_swiss_search(int[],int[],int[],int[],int,int),public.sim_qualification_list(uuid,text),public.sim_record_final_tables(uuid),public.sim_keep_final_table(),public.sim_swiss_create(uuid,text,jsonb),
 public.sim_participants_build(uuid),public.sim_create_season(uuid,text),public.sim_phase_create(uuid,text,text,text[]),
 public.sim_phase_pairs(uuid,text,jsonb,text[]),public.sim_season_transition(uuid),public.sim_resolve_ties(uuid,text,text)
 from public,anon,authenticated;


-- FILE: 18_swiss_certificates.sql
-- GERADO por scripts/certify-swiss-draws.py; sem nomes de usuários ou clubes classificados.
update public.sim_competitions set rules=jsonb_set(rules,'{swiss_certificates}',$cert$[{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["FRA","ESP","ENG","WAL","GER","WAL","ESP","ESP","ITA","POR","NED","GER","ENG","ITA","WAL","BEL","POR","ESP","UKR","GER","ITA","ESP","NOR","FRA","NED","TUR","TUR","ITA","AUT","GRE","SVK","CZE","GER","FRA","NOR","AZE"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","GER","ITA","WAL","WAL","ESP","ESP","FRA","GER","WAL","ITA","POR","NED","BEL","POR","ENG","ESP","GER","UKR","TUR","ESP","ITA","NED","TUR","NOR","FRA","NOR","ITA","AUT","GRE","FRA","CZE","AZE","SVK","GER"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["GER","ESP","ITA","FRA","WAL","ENG","ESP","ESP","WAL","GER","POR","NED","ENG","WAL","BEL","POR","ITA","ESP","UKR","ITA","TUR","ESP","NED","TUR","NOR","FRA","GER","NOR","FRA","SVK","GER","AZE","CZE","GRE","ITA","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["WAL","GER","ESP","WAL","FRA","ENG","ESP","ESP","ITA","NED","ESP","POR","BEL","GER","WAL","POR","ENG","ITA","GER","UKR","TUR","NOR","FRA","ESP","TUR","NED","ITA","ITA","FRA","GRE","SVK","CZE","GER","NOR","AUT","AZE"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ITA","ENG","ESP","WAL","GER","WAL","ESP","FRA","WAL","POR","ENG","POR","ITA","NED","BEL","GER","ESP","UKR","ESP","ITA","TUR","TUR","NOR","FRA","NED","GER","FRA","SVK","GRE","CZE","ITA","GER","AZE","NOR","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["WAL","ESP","ESP","GER","ITA","ENG","ESP","WAL","FRA","ENG","WAL","ESP","NED","GER","POR","BEL","POR","ITA","UKR","TUR","ESP","GER","ITA","NOR","FRA","TUR","NED","FRA","AUT","GRE","SVK","CZE","GER","ITA","NOR","AZE"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","ITA","ESP","ESP","FRA","ESP","GER","WAL","WAL","ENG","WAL","NED","BEL","ITA","POR","GER","ESP","POR","UKR","TUR","NOR","ITA","FRA","ESP","NED","TUR","GER","AZE","NOR","FRA","AUT","SVK","CZE","ITA","GRE","GER"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","ENG","ESP","ESP","ITA","ESP","GER","WAL","FRA","POR","GER","ENG","ITA","NED","WAL","BEL","ESP","POR","TUR","TUR","GER","UKR","ITA","ESP","NOR","FRA","NED","AZE","NOR","ITA","AUT","GRE","SVK","CZE","GER","FRA"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","GER","ESP","ESP","ITA","ESP","FRA","WAL","ENG","POR","POR","ENG","ITA","NED","WAL","BEL","ESP","GER","ITA","TUR","UKR","GER","TUR","ESP","NOR","FRA","NED","AZE","NOR","AUT","GRE","ITA","SVK","CZE","FRA","GER"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["WAL","ENG","GER","ESP","FRA","ESP","ITA","WAL","ESP","ITA","GER","NED","WAL","ENG","ESP","BEL","POR","POR","TUR","ITA","ESP","TUR","GER","UKR","NOR","FRA","NED","ITA","SVK","FRA","CZE","GER","AUT","AZE","NOR","GRE"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ESP","ITA","GER","WAL","ESP","WAL","FRA","ESP","ENG","GER","POR","ENG","WAL","ESP","NED","BEL","ITA","POR","UKR","ESP","GER","NOR","ITA","TUR","NED","TUR","FRA","GER","ITA","SVK","CZE","NOR","GRE","AUT","AZE","FRA"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["WAL","ITA","GER","ESP","WAL","ESP","ENG","FRA","ESP","ENG","NED","BEL","WAL","ITA","ESP","GER","POR","POR","UKR","GER","ESP","NOR","TUR","ITA","TUR","NED","FRA","AZE","ITA","CZE","FRA","GER","GRE","AUT","NOR","SVK"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["GER","ESP","ENG","FRA","WAL","ITA","ESP","ESP","WAL","GER","POR","ENG","ENG","NED","ITA","BEL","POR","ESP","TUR","TUR","ITA","ESP","FRA","UKR","NOR","NED","GER","AZE","GER","GRE","CZE","SVK","FRA","ITA","NOR","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","WAL","FRA","GER","ITA","ESP","ESP","WAL","ENG","ITA","GER","POR","POR","BEL","NED","ENG","ESP","UKR","GER","TUR","ESP","TUR","NOR","FRA","NED","ITA","ITA","AUT","AZE","GRE","NOR","SVK","GER","CZE","FRA"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","FRA","WAL","WAL","ITA","ESP","ESP","GER","BEL","ITA","POR","POR","ENG","ENG","NED","GER","ESP","UKR","NOR","FRA","ESP","NED","TUR","GER","TUR","ITA","ITA","FRA","GRE","CZE","SVK","AUT","NOR","GER","AZE"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ITA","ENG","WAL","ESP","WAL","GER","ESP","ENG","ITA","NED","BEL","POR","GER","POR","ENG","UKR","ITA","NED","GER","FRA","TUR","NOR","ESP","TUR","GER","SVK","AZE","CZE","ITA","FRA","NOR","GRE","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ITA","FRA","ESP","ENG","WAL","GER","ESP","WAL","POR","BEL","GER","ENG","POR","NED","ITA","ENG","ESP","UKR","ESP","NOR","TUR","GER","TUR","FRA","NED","ITA","ITA","GRE","GER","SVK","CZE","FRA","AZE","NOR","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","WAL","ENG","ESP","WAL","ITA","GER","ITA","ENG","ESP","GER","NED","BEL","POR","POR","ENG","UKR","TUR","ESP","NOR","NED","ITA","FRA","GER","TUR","FRA","GRE","GER","SVK","CZE","ITA","NOR","AZE","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","ITA","ESP","ESP","WAL","ESP","WAL","FRA","GER","BEL","ENG","NED","POR","POR","ENG","GER","ESP","ITA","UKR","TUR","ITA","NOR","GER","ESP","FRA","NED","TUR","AZE","NOR","FRA","AUT","GRE","SVK","GER","CZE","ITA"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","WAL","ESP","ESP","ESP","ITA","ENG","WAL","GER","ENG","BEL","ESP","NED","POR","ITA","POR","ENG","GER","UKR","GER","TUR","TUR","ESP","FRA","NOR","ITA","NED","AZE","NOR","FRA","ITA","AUT","GRE","SVK","CZE","GER"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","GER","ESP","ENG","ESP","WAL","ITA","ESP","FRA","BEL","ENG","POR","ESP","ENG","GER","ITA","NED","POR","TUR","NED","GER","FRA","ESP","NOR","UKR","TUR","ITA","AZE","NOR","AUT","FRA","GRE","SVK","CZE","ITA","GER"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["GER","ESP","ITA","ESP","ESP","FRA","WAL","WAL","ENG","ENG","BEL","POR","POR","ESP","ITA","NED","ENG","GER","UKR","NOR","FRA","GER","ITA","ESP","TUR","NED","TUR","NOR","FRA","CZE","SVK","GRE","GER","ITA","AZE","AUT"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ESP","ENG","ITA","WAL","ESP","GER","WAL","ESP","FRA","ITA","GER","BEL","POR","ESP","ENG","NED","ENG","POR","UKR","ESP","ITA","TUR","TUR","NOR","FRA","GER","NED","ITA","AUT","GRE","SVK","GER","CZE","NOR","AZE","FRA"]},{"signature":[{"ENG":1,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":2},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ESP","GER","ESP","ESP","ITA","WAL","WAL","ENG","NED","GER","BEL","POR","ITA","ESP","ENG","POR","ENG","NOR","TUR","FRA","UKR","NED","GER","TUR","ITA","ESP","NOR","GRE","AUT","FRA","ITA","CZE","GER","AZE","SVK"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","ENG","FRA","GER","WAL","ESP","ESP","ITA","NED","WAL","GER","ENG","POR","BEL","ITA","POR","ESP","UKR","NOR","TUR","ESP","TUR","ITA","GER","NED","FRA","FRA","GRE","SVK","CZE","ITA","GER","AUT","NOR","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","ENG","ITA","WAL","GER","ESP","ESP","FRA","ENG","GER","ITA","NED","POR","WAL","BEL","POR","ESP","TUR","TUR","UKR","ESP","ITA","FRA","NOR","NED","GER","GER","ITA","AUT","GRE","CZE","NOR","SVK","FRA","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","FRA","ITA","ENG","ENG","ESP","ESP","GER","GER","NED","ITA","ENG","WAL","BEL","POR","POR","ESP","ITA","UKR","GER","ESP","NOR","TUR","TUR","FRA","NED","ITA","GER","AUT","GRE","FRA","SVK","CZE","NOR","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ENG","ESP","ESP","GER","ENG","ESP","ITA","FRA","WAL","NED","ITA","ESP","ENG","WAL","BEL","POR","POR","GER","UKR","NOR","ESP","NED","ITA","GER","TUR","TUR","FRA","ITA","GRE","GER","SVK","CZE","FRA","NOR","AZE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","WAL","ENG","ESP","GER","FRA","ENG","ESP","ITA","GER","ENG","WAL","NED","ITA","BEL","POR","POR","ESP","NOR","ESP","TUR","ITA","FRA","UKR","TUR","NED","GER","ITA","AUT","GRE","SVK","CZE","GER","FRA","AZE","NOR"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["WAL","ESP","ESP","FRA","GER","ESP","ENG","ENG","ITA","GER","NED","ESP","WAL","ENG","BEL","ITA","POR","POR","UKR","TUR","ESP","ITA","NOR","NED","FRA","GER","TUR","ITA","AUT","GRE","SVK","CZE","GER","FRA","NOR","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","WAL","ESP","GER","ESP","ENG","FRA","ESP","ITA","POR","WAL","ENG","ESP","GER","NED","ITA","BEL","POR","ITA","UKR","TUR","NOR","ESP","GER","NED","TUR","FRA","AZE","NOR","FRA","AUT","SVK","CZE","ITA","GRE","GER"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","GER","ESP","ESP","ITA","ESP","ENG","WAL","FRA","ENG","GER","POR","ITA","WAL","BEL","NED","ESP","POR","TUR","TUR","GER","UKR","ITA","ESP","NOR","FRA","NED","AZE","NOR","ITA","AUT","GRE","SVK","CZE","GER","FRA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","ENG","ESP","GER","ESP","WAL","ITA","ESP","ENG","ITA","ENG","POR","ESP","GER","POR","BEL","NED","WAL","FRA","TUR","NOR","UKR","ESP","GER","ITA","NED","TUR","AZE","NOR","AUT","FRA","ITA","SVK","CZE","GRE","GER"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["GER","FRA","ENG","ESP","ITA","ESP","WAL","ENG","ESP","WAL","NED","ITA","ENG","POR","ESP","BEL","POR","GER","TUR","ITA","ESP","GER","NED","TUR","NOR","FRA","UKR","ITA","GRE","SVK","CZE","FRA","GER","NOR","AZE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ESP","WAL","ITA","ENG","ESP","ENG","GER","ESP","FRA","NED","POR","BEL","ENG","ESP","POR","GER","WAL","ITA","UKR","ESP","TUR","TUR","NOR","ITA","NED","FRA","GER","NOR","GER","SVK","CZE","AZE","AUT","ITA","GRE","FRA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ENG","ESP","GER","ESP","ESP","WAL","ITA","ENG","FRA","GER","WAL","BEL","ENG","ESP","NED","ITA","POR","POR","TUR","GER","NED","TUR","FRA","ESP","NOR","UKR","ITA","GER","ITA","CZE","FRA","AZE","GRE","NOR","AUT","SVK"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","GER","FRA","ENG","ITA","ESP","ESP","ENG","ENG","ITA","BEL","POR","ENG","POR","NED","GER","ESP","TUR","GER","TUR","ESP","NOR","FRA","ITA","UKR","NED","FRA","AUT","GRE","SVK","CZE","AZE","NOR","GER","ITA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","ENG","ITA","WAL","FRA","ESP","ESP","GER","BEL","NED","ITA","POR","ENG","GER","POR","ENG","ESP","ITA","UKR","NOR","ESP","NED","GER","TUR","FRA","TUR","ITA","FRA","GER","SVK","AUT","NOR","CZE","GRE","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["GER","ESP","FRA","WAL","ENG","ITA","ESP","ESP","ENG","ENG","POR","NED","BEL","ENG","POR","GER","ITA","ESP","NOR","UKR","FRA","ESP","TUR","GER","ITA","NED","TUR","NOR","FRA","SVK","ITA","AZE","CZE","GER","GRE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ENG","GER","WAL","ESP","ENG","ITA","BEL","NED","ESP","ITA","POR","POR","ENG","ENG","GER","GER","TUR","ESP","UKR","NOR","NED","ITA","FRA","TUR","FRA","CZE","ITA","GER","AZE","NOR","AUT","SVK","GRE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ENG","FRA","ESP","WAL","GER","ENG","ESP","ITA","ENG","POR","GER","NED","ENG","BEL","ITA","POR","ESP","UKR","ESP","GER","TUR","NOR","FRA","ITA","TUR","NED","ITA","SVK","CZE","GER","GRE","AUT","FRA","NOR","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ENG","FRA","ESP","WAL","GER","ENG","ESP","ESP","ITA","GER","ESP","POR","NED","ITA","BEL","POR","ENG","ENG","UKR","TUR","FRA","ITA","NOR","ESP","TUR","GER","NED","ITA","FRA","CZE","GER","AUT","AZE","GRE","NOR","SVK"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","WAL","ESP","GER","ESP","ENG","ITA","ESP","ENG","ITA","NED","POR","ESP","GER","BEL","ENG","ENG","POR","FRA","TUR","UKR","NOR","ESP","TUR","ITA","GER","NED","NOR","FRA","GRE","GER","AUT","CZE","SVK","ITA","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","WAL","ESP","ESP","ESP","ITA","ENG","GER","ENG","ENG","POR","ESP","NED","POR","GER","ITA","ENG","BEL","UKR","GER","ITA","TUR","ESP","NOR","TUR","FRA","NED","ITA","GRE","GER","CZE","SVK","FRA","AZE","AUT","NOR"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","WAL","ESP","ESP","ITA","ESP","GER","ENG","ENG","ITA","POR","POR","NED","ENG","GER","ENG","ESP","BEL","UKR","TUR","GER","NOR","FRA","ESP","NED","TUR","ITA","NOR","GRE","GER","FRA","SVK","ITA","CZE","AUT","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["WAL","ESP","GER","ESP","ESP","FRA","ENG","ENG","ITA","NED","ENG","ENG","BEL","POR","ESP","GER","ITA","POR","NOR","GER","TUR","UKR","NED","ITA","FRA","TUR","ESP","NOR","ITA","CZE","SVK","GRE","FRA","GER","AZE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ENG","GER","ESP","FRA","ENG","ESP","ESP","ITA","WAL","ESP","ENG","NED","POR","BEL","GER","ITA","ENG","POR","UKR","TUR","ESP","ITA","GER","NOR","FRA","TUR","NED","FRA","ITA","AUT","SVK","GRE","CZE","GER","AZE","NOR"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["WAL","ESP","GER","ESP","ESP","ENG","ENG","ITA","FRA","ENG","GER","NED","ITA","ENG","ESP","BEL","POR","POR","ITA","NOR","GER","NED","TUR","FRA","UKR","TUR","ESP","ITA","AUT","GRE","SVK","GER","CZE","FRA","AZE","NOR"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["GER","ESP","ENG","FRA","ENG","ITA","ESP","ESP","WAL","GER","POR","WAL","WAL","NED","ITA","BEL","POR","ESP","TUR","TUR","ITA","ESP","FRA","UKR","NOR","NED","GER","AZE","GER","GRE","CZE","SVK","FRA","ITA","NOR","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","ENG","FRA","GER","ITA","ESP","ESP","ENG","WAL","ITA","GER","POR","POR","BEL","NED","WAL","ESP","UKR","GER","TUR","ESP","TUR","NOR","FRA","NED","ITA","ITA","AUT","NOR","GRE","SVK","AZE","GER","CZE","FRA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","FRA","ENG","ENG","ITA","ESP","ESP","GER","BEL","ITA","POR","POR","WAL","WAL","NED","GER","ESP","UKR","NOR","FRA","ESP","NED","TUR","GER","TUR","ITA","ITA","FRA","GRE","CZE","SVK","AUT","AZE","GER","NOR"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ITA","ENG","ENG","ESP","WAL","GER","ESP","WAL","ITA","NED","BEL","POR","GER","POR","WAL","UKR","ITA","NED","GER","FRA","TUR","NOR","ESP","TUR","GER","SVK","AZE","CZE","ITA","FRA","NOR","GRE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ESP","ENG","ESP","FRA","WAL","ENG","GER","ITA","BEL","NED","POR","POR","ESP","GER","ITA","WAL","WAL","UKR","ESP","TUR","GER","ITA","TUR","NOR","NED","FRA","NOR","GER","ITA","SVK","CZE","FRA","AZE","AUT","GRE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ENG","WAL","ESP","ENG","ITA","GER","ITA","WAL","ESP","GER","NED","BEL","POR","POR","WAL","UKR","TUR","ESP","NOR","NED","ITA","FRA","GER","TUR","FRA","GRE","GER","SVK","CZE","ITA","NOR","AZE","AUT"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","ITA","ESP","ESP","ENG","ESP","ENG","FRA","GER","BEL","WAL","NED","POR","POR","WAL","GER","ESP","ITA","UKR","TUR","ITA","NOR","GER","ESP","FRA","NED","TUR","AZE","NOR","FRA","AUT","GRE","SVK","GER","CZE","ITA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","ENG","ESP","ESP","ESP","ITA","WAL","ENG","GER","WAL","BEL","ESP","NED","POR","ITA","POR","WAL","GER","UKR","GER","TUR","TUR","ESP","FRA","NOR","ITA","NED","AZE","NOR","FRA","ITA","AUT","GRE","SVK","CZE","GER"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","GER","ESP","WAL","ESP","ENG","ITA","ESP","FRA","BEL","WAL","POR","ESP","WAL","GER","ITA","NED","POR","TUR","NED","GER","FRA","ESP","NOR","UKR","TUR","ITA","AZE","NOR","AUT","FRA","GRE","SVK","CZE","ITA","GER"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ENG","ESP","WAL","ESP","ESP","FRA","GER","ENG","ITA","POR","GER","NED","BEL","POR","ESP","WAL","ITA","WAL","TUR","UKR","GER","TUR","NED","ITA","NOR","FRA","ESP","NOR","ITA","AUT","SVK","GRE","CZE","FRA","GER","AZE"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ESP","WAL","ITA","ENG","ESP","GER","ENG","ESP","FRA","ITA","GER","BEL","POR","ESP","WAL","NED","WAL","POR","UKR","ESP","ITA","TUR","TUR","NOR","FRA","GER","NED","ITA","AUT","GRE","SVK","GER","CZE","NOR","AZE","FRA"]},{"signature":[{"ENG":2,"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ESP","GER","ESP","ESP","ITA","ENG","ENG","WAL","NED","GER","BEL","POR","ITA","ESP","WAL","POR","WAL","NOR","TUR","FRA","UKR","NED","GER","TUR","ITA","ESP","NOR","GRE","AUT","FRA","ITA","CZE","GER","AZE","SVK"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["GER","ESP","FRA","ENG","ENG","ITA","ESP","ESP","ENG","GER","WAL","ENG","NED","BEL","POR","POR","ITA","ESP","NOR","FRA","TUR","ESP","TUR","NED","UKR","ITA","GER","ITA","GER","SVK","CZE","AZE","GRE","NOR","FRA","AUT"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["FRA","ESP","ENG","GER","ENG","ENG","ESP","ESP","ITA","NED","ENG","POR","BEL","ITA","WAL","GER","POR","ESP","NED","NOR","ITA","ESP","TUR","GER","TUR","FRA","UKR","GER","AUT","GRE","NOR","AZE","FRA","CZE","SVK","ITA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ITA","ESP","FRA","ENG","ENG","GER","ESP","ESP","ENG","NED","WAL","ENG","ITA","POR","BEL","GER","POR","ESP","UKR","TUR","FRA","ESP","NOR","TUR","ITA","GER","NED","GER","FRA","SVK","AUT","AZE","GRE","CZE","ITA","NOR"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ENG","GER","ESP","ENG","ENG","FRA","ESP","ESP","ITA","NED","ESP","WAL","BEL","GER","ENG","POR","POR","ITA","UKR","NOR","TUR","FRA","NED","ESP","TUR","ITA","GER","ITA","AUT","GRE","SVK","CZE","GER","AZE","NOR","FRA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ENG","ITA","ESP","ENG","GER","ENG","ESP","FRA","ENG","ITA","GER","POR","NED","WAL","BEL","POR","ESP","UKR","ESP","GER","TUR","NOR","NED","TUR","ITA","FRA","ITA","GER","SVK","CZE","AZE","NOR","GRE","FRA","AUT"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ENG","ENG","ESP","GER","FRA","ENG","ESP","ITA","ENG","WAL","NED","ITA","BEL","POR","GER","POR","ESP","UKR","ESP","NOR","FRA","GER","TUR","ITA","NED","TUR","GER","SVK","ITA","CZE","NOR","AUT","FRA","GRE","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","ITA","ESP","ESP","ENG","ESP","ENG","ENG","GER","NED","ITA","BEL","POR","GER","ENG","WAL","ESP","POR","TUR","NED","TUR","FRA","ITA","ESP","GER","NOR","UKR","FRA","ITA","GER","GRE","SVK","AUT","CZE","NOR","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","ITA","ESP","FRA","ESP","GER","ENG","ESP","ENG","ENG","POR","WAL","ESP","ITA","GER","BEL","POR","NED","TUR","UKR","TUR","NOR","ESP","ITA","NED","GER","FRA","NOR","ITA","GRE","GER","SVK","CZE","AUT","AZE","FRA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","ENG","ESP","ESP","ESP","ITA","GER","ENG","ENG","POR","ENG","ESP","ITA","GER","NED","WAL","BEL","POR","TUR","NOR","UKR","FRA","ESP","GER","ITA","NED","TUR","NOR","GRE","GER","SVK","ITA","FRA","CZE","AUT","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ITA","FRA","ENG","ESP","ENG","ESP","GER","ENG","ESP","NED","ITA","GER","ENG","POR","ESP","BEL","POR","WAL","FRA","UKR","ESP","GER","ITA","TUR","NOR","TUR","NED","NOR","SVK","FRA","CZE","GRE","ITA","GER","AZE","AUT"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["GER","ENG","ITA","ESP","ENG","ESP","ENG","FRA","ESP","BEL","ITA","ENG","GER","WAL","ESP","NED","POR","POR","GER","TUR","ESP","FRA","ITA","UKR","NOR","TUR","NED","NOR","GRE","AZE","CZE","AUT","SVK","ITA","FRA","GER"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":1},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["ESP","ITA","ENG","ESP","ESP","FRA","GER","ENG","ENG","POR","ESP","NED","BEL","POR","ENG","GER","WAL","ITA","UKR","GER","NOR","ITA","ESP","TUR","FRA","NED","TUR","NOR","GRE","FRA","SVK","GER","CZE","ITA","AZE","AUT"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ESP","GER","ESP","ENG","ENG","ITA","FRA","ENG","ENG","POR","BEL","ENG","ESP","NED","GER","POR","ITA","UKR","ESP","FRA","TUR","GER","ITA","TUR","NOR","NED","NOR","AZE","GER","CZE","ITA","AUT","SVK","FRA","GRE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ESP","ITA","ESP","ENG","ENG","GER","FRA","ENG","ENG","POR","GER","ENG","ESP","ITA","NED","BEL","POR","TUR","ESP","ITA","TUR","GER","FRA","UKR","NOR","NED","NOR","CZE","GER","ITA","FRA","AZE","SVK","GRE","AUT"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ITA","ENG","ENG","ESP","GER","ENG","ENG","NED","ESP","ENG","GER","BEL","POR","POR","ITA","GER","ITA","ESP","UKR","NOR","TUR","FRA","NED","TUR","ITA","AUT","GRE","SVK","CZE","GER","AZE","NOR","FRA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["GER","ENG","ESP","ESP","ENG","ESP","FRA","ENG","ITA","BEL","ITA","GER","NED","POR","ENG","POR","ESP","ENG","GER","TUR","ITA","NED","NOR","ESP","FRA","TUR","UKR","AZE","AUT","GRE","NOR","ITA","CZE","GER","SVK","FRA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["GER","ENG","ESP","ESP","ENG","ESP","ITA","ENG","FRA","BEL","ITA","NED","GER","POR","ENG","POR","ESP","ENG","GER","NOR","TUR","TUR","UKR","ESP","FRA","ITA","NED","NOR","GRE","FRA","GER","SVK","CZE","ITA","AUT","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["FRA","ENG","ESP","ESP","ENG","ESP","GER","ENG","ITA","ITA","POR","NED","GER","POR","ENG","BEL","ESP","ENG","UKR","NOR","TUR","NED","FRA","ESP","ITA","TUR","GER","NOR","FRA","ITA","SVK","AUT","CZE","AZE","GRE","GER"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","GER","ESP","ENG","ESP","ENG","ENG","ESP","ITA","ENG","POR","GER","ESP","ENG","NED","BEL","POR","ITA","TUR","UKR","NOR","NED","GER","ESP","FRA","ITA","TUR","GER","CZE","FRA","AZE","NOR","SVK","AUT","ITA","GRE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ITA","ENG","ESP","GER","ESP","ENG","ENG","ESP","NED","ENG","BEL","POR","GER","ESP","ENG","POR","ITA","ITA","GER","ESP","UKR","FRA","NOR","TUR","TUR","NED","ITA","CZE","FRA","GRE","GER","AUT","AZE","SVK","NOR"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","GER","ESP","ENG","ESP","ENG","ENG","ESP","ITA","ENG","BEL","ITA","ESP","ENG","NED","POR","GER","POR","GER","TUR","NOR","UKR","FRA","ESP","TUR","ITA","NED","NOR","AZE","CZE","SVK","GER","AUT","FRA","GRE","ITA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","ENG","ITA","GER","FRA","ESP","ESP","ENG","NED","BEL","POR","WAL","GER","WAL","ITA","POR","ESP","UKR","NOR","FRA","ESP","TUR","ITA","TUR","NED","GER","ITA","AUT","GRE","GER","SVK","FRA","CZE","AZE","NOR"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ENG","ESP","FRA","ENG","ITA","ENG","ESP","ESP","GER","POR","NED","POR","WAL","ITA","WAL","BEL","GER","ESP","UKR","GER","NED","ESP","TUR","FRA","NOR","TUR","ITA","NOR","AUT","FRA","ITA","GER","SVK","GRE","CZE","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ITA","ESP","ENG","GER","ENG","ENG","ESP","ESP","FRA","NED","GER","BEL","WAL","POR","ITA","WAL","POR","ESP","UKR","GER","TUR","ESP","FRA","TUR","NOR","ITA","NED","NOR","FRA","AUT","GRE","GER","SVK","CZE","ITA","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","GER","ENG","ESP","ITA","ENG","FRA","ESP","ENG","GER","BEL","NED","WAL","WAL","ITA","POR","POR","ESP","ITA","ESP","TUR","TUR","UKR","FRA","NED","GER","NOR","NOR","ITA","AUT","GRE","SVK","GER","CZE","FRA","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","ENG","GER","ITA","ESP","ENG","ENG","ESP","WAL","ITA","BEL","NED","POR","WAL","POR","GER","TUR","UKR","GER","TUR","ITA","NOR","FRA","ESP","NED","FRA","GRE","SVK","GER","CZE","ITA","AUT","NOR","AZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ESP","GER","ESP","ENG","ENG","ITA","FRA","ENG","NED","POR","WAL","BEL","ESP","GER","WAL","POR","ITA","UKR","ESP","GER","NOR","NED","FRA","TUR","TUR","ITA","ITA","GRE","SVK","GER","CZE","FRA","AZE","AUT","NOR"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","ENG","ESP","GER","ESP","ENG","FRA","ESP","ITA","NED","WAL","POR","ESP","GER","WAL","ITA","BEL","POR","ITA","UKR","TUR","TUR","ESP","GER","NOR","FRA","NED","AZE","NOR","CZE","AUT","GRE","SVK","ITA","FRA","GER"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","FRA","ESP","GER","ESP","ITA","ENG","ESP","ENG","BEL","POR","WAL","ESP","WAL","POR","GER","ITA","NED","TUR","TUR","UKR","FRA","ESP","GER","NOR","NED","ITA","AZE","NOR","ITA","AUT","GRE","FRA","SVK","CZE","GER"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["ENG","ITA","ESP","ESP","ESP","ENG","GER","FRA","ENG","POR","NED","ESP","WAL","WAL","GER","POR","BEL","ITA","UKR","TUR","ITA","GER","ESP","NOR","FRA","TUR","NED","AZE","NOR","AUT","GRE","GER","SVK","FRA","CZE","ITA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["GER","FRA","ENG","ESP","ENG","ESP","ITA","ENG","ESP","BEL","WAL","ITA","GER","NED","ESP","POR","WAL","POR","ITA","UKR","ESP","FRA","TUR","NOR","TUR","GER","NED","AZE","NOR","AUT","SVK","GRE","CZE","FRA","GER","ITA"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ESP","ITA","ESP","ESP","ENG","GER","ENG","ENG","BEL","WAL","NED","POR","ESP","ITA","GER","WAL","POR","NED","NOR","TUR","TUR","ITA","ESP","FRA","UKR","GER","AZE","NOR","FRA","AUT","GRE","SVK","ITA","GER","CZE"]},{"signature":[{"ENG":3,"ESP":3,"FRA":1,"GER":1,"ITA":1},{"BEL":1,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2,"WAL":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ITA","ESP","ENG","GER","ENG","ESP","ESP","ENG","POR","NED","POR","BEL","WAL","GER","ESP","ITA","WAL","ITA","ESP","NED","NOR","FRA","TUR","TUR","UKR","GER","AZE","NOR","ITA","AUT","GRE","GER","FRA","SVK","CZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","WAL","ITA","GER","FRA","ESP","ESP","WAL","NED","BEL","POR","ENG","GER","ENG","ITA","POR","ESP","UKR","NOR","FRA","ESP","TUR","ITA","TUR","NED","GER","ITA","AUT","GRE","GER","SVK","FRA","CZE","AZE","NOR"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["WAL","ESP","FRA","WAL","ITA","WAL","ESP","ESP","GER","POR","NED","POR","ENG","ITA","ENG","BEL","GER","ESP","UKR","GER","NED","ESP","TUR","FRA","NOR","TUR","ITA","NOR","AUT","FRA","ITA","GER","SVK","GRE","CZE","AZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":0,"assignment":["ITA","ESP","WAL","GER","WAL","WAL","ESP","ESP","FRA","NED","GER","BEL","ENG","POR","ITA","ENG","POR","ESP","UKR","GER","TUR","ESP","FRA","TUR","NOR","ITA","NED","NOR","FRA","AUT","GRE","GER","SVK","CZE","ITA","AZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","GER","WAL","ESP","ITA","WAL","FRA","ESP","WAL","GER","BEL","NED","ENG","ENG","ITA","POR","POR","ESP","ITA","ESP","TUR","TUR","UKR","FRA","NED","GER","NOR","NOR","ITA","AUT","GRE","SVK","GER","CZE","FRA","AZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["FRA","ESP","ESP","WAL","GER","ITA","ESP","WAL","WAL","ESP","ENG","ITA","BEL","NED","POR","ENG","POR","GER","TUR","UKR","GER","TUR","ITA","NOR","FRA","ESP","NED","FRA","GRE","SVK","GER","CZE","ITA","AUT","NOR","AZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":1,"assignment":["ESP","ESP","GER","ESP","WAL","WAL","ITA","FRA","WAL","NED","POR","ENG","BEL","ESP","GER","ENG","POR","ITA","UKR","ESP","GER","NOR","NED","FRA","TUR","TUR","ITA","ITA","GRE","SVK","GER","CZE","FRA","AZE","AUT","NOR"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","WAL","ESP","GER","ESP","WAL","FRA","ESP","ITA","NED","ENG","POR","ESP","GER","ENG","ITA","BEL","POR","ITA","UKR","TUR","TUR","ESP","GER","NOR","FRA","NED","AZE","NOR","CZE","AUT","GRE","SVK","ITA","FRA","GER"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","FRA","ESP","GER","ESP","ITA","WAL","ESP","WAL","BEL","POR","ENG","ESP","ENG","POR","GER","ITA","NED","TUR","TUR","UKR","FRA","ESP","GER","NOR","NED","ITA","AZE","NOR","ITA","AUT","GRE","FRA","SVK","CZE","GER"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":2,"assignment":["WAL","ITA","ESP","ESP","ESP","WAL","GER","FRA","WAL","POR","NED","ESP","ENG","ENG","GER","POR","BEL","ITA","UKR","TUR","ITA","GER","ESP","NOR","FRA","TUR","NED","AZE","NOR","AUT","GRE","GER","SVK","FRA","CZE","ITA"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["GER","FRA","WAL","ESP","WAL","ESP","ITA","WAL","ESP","BEL","ENG","ITA","GER","NED","ESP","POR","ENG","POR","ITA","UKR","ESP","FRA","TUR","NOR","TUR","GER","NED","AZE","NOR","AUT","SVK","GRE","CZE","FRA","GER","ITA"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ESP","ITA","ESP","ESP","WAL","GER","WAL","WAL","BEL","ENG","NED","POR","ESP","ITA","GER","ENG","POR","NED","NOR","TUR","TUR","ITA","ESP","FRA","UKR","GER","AZE","NOR","FRA","AUT","GRE","SVK","ITA","GER","CZE"]},{"signature":[{"ESP":3,"FRA":1,"GER":1,"ITA":1,"WAL":3},{"BEL":1,"ENG":2,"ESP":1,"GER":1,"ITA":1,"NED":1,"POR":2},{"ESP":1,"FRA":1,"GER":1,"ITA":1,"NED":1,"NOR":1,"TUR":2,"UKR":1},{"AUT":1,"AZE":1,"CZE":1,"FRA":1,"GER":1,"GRE":1,"ITA":1,"NOR":1,"SVK":1}],"template":3,"assignment":["FRA","ITA","ESP","WAL","GER","WAL","ESP","ESP","WAL","POR","NED","POR","BEL","ENG","GER","ESP","ITA","ENG","ITA","ESP","NED","NOR","FRA","TUR","TUR","UKR","GER","AZE","NOR","ITA","AUT","GRE","GER","FRA","SVK","CZE"]}]$cert$::jsonb) where id='ucl';


-- FILE: 19_opponent_analysis.sql
-- EVOLUÇÃO 18: análise do rival sem expor dados de outras carreiras.
create or replace function public.mgr_opponent_report(p_fixture bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 car public.careers;coach public.mgr_coach;f public.season_fixtures;s public.career_seasons;m public.mgr_matches;
 opp text;form text;lineup jsonb;tactics jsonb;strength numeric;mine numeric;side text;is_home boolean;
begin
 car:=public.mgr_lock();
 select * into coach from public.mgr_coach where career_id=car.id;
 select fx.* into f from public.season_fixtures fx join public.career_seasons cs on cs.id=fx.season_id
  where fx.id=p_fixture and cs.career_id=car.id;
 if not found or coach.club_id is null or coach.club_id not in(f.home_club,f.away_club) then raise exception 'Partida não encontrada nesta carreira';end if;
 select * into s from public.career_seasons where id=f.season_id;
 opp:=case when f.home_club=coach.club_id then f.away_club else f.home_club end;
 side:=case when f.home_club=opp then 'h' else 'a' end;
 select * into m from public.mgr_matches where fixture_id=f.id and career_id=car.id;
 if found then
  form:=m.state->'formation'->>(case when side='h' then 0 else 1 end);
  tactics:=m.state->'tactics'->side;
  strength:=public.mgr_side_strength(f.id,side::char);
 else
  form:=public.mgr_ai_formation(car.id,opp);
  lineup:=public.mgr_auto_lineup(car.id,opp,form,f.competition_id,s.day_no);
  strength:=public.mgr_lineup_score(lineup,form)/11;
  mine:=coalesce((select public.mgr_lineup_score(jsonb_build_object('slots',l.slots),l.formation)/11 from public.mgr_lineups l where l.career_id=car.id and l.club_id=coach.club_id),(select cl.strength from public.sim_clubs cl where cl.id=coach.club_id),60);
  is_home:=f.home_club=opp and not coalesce((public.sim_phase(f.competition_id,f.stage)->>'neutral')::boolean,false);
  tactics:=public.mgr_ai_plan(car.id,opp,strength-mine,is_home);
 end if;
 return jsonb_build_object('fixture_id',f.id,'club_id',opp,'formation',form,'tactics',tactics,
   'style',(select c.style from public.mgr_ai_clubs c where c.career_id=car.id and c.club_id=opp),
   'live',m.status='live','strength',round(strength,1));
end $$;
revoke all on function public.mgr_opponent_report(bigint) from public,anon;
grant execute on function public.mgr_opponent_report(bigint) to authenticated;
create or replace function public.mgr_history()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_car public.careers;
  v_c   public.mgr_coach;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  return jsonb_build_object(
    'coach', jsonb_build_object('reputation', round(v_c.reputation, 1), 'matches', v_c.matches, 'wins', v_c.wins, 'draws', v_c.draws,
      'losses', v_c.losses, 'gf', v_c.gf, 'ga', v_c.ga, 'titles', v_c.titles, 'fired_count', v_c.fired_count, 'seasons', v_c.seasons,
      'status', v_c.status, 'club_id', v_c.club_id),
    'spells', (select coalesce(jsonb_agg(jsonb_build_object('id', sp.id, 'club_id', sp.club_id, 'current', sp.id = v_c.spell_id,
        'started_year', sp.started_year, 'started_day', sp.started_day, 'started_season', sp.started_season,
        'ended_year', sp.ended_year, 'ended_day', sp.ended_day, 'end_reason', sp.end_reason,
        'matches', sp.matches, 'wins', sp.wins, 'draws', sp.draws, 'losses', sp.losses, 'gf', sp.gf, 'ga', sp.ga, 'titles', sp.titles)
        order by sp.created_at desc), '[]'::jsonb) from public.mgr_spells sp where sp.career_id = v_car.id),
    'seasons', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'year', s.year, 'region', s.region, 'season_no', s.season_no, 'status', s.status,
        'club_id', s.club_id, 'matches', s.matches, 'wins', s.wins, 'draws', s.draws, 'losses', s.losses,
        'xp_earned', s.xp_earned, 'coins_earned', s.coins_earned, 'summary', s.summary,
        'final_tables', (select coalesce(jsonb_object_agg(ft.competition_id,ft.standings),'{}'::jsonb) from public.season_final_tables ft where ft.season_id=s.id),
        'clubs', (select coalesce(jsonb_agg(distinct f.coach_club), '[]'::jsonb) from public.season_fixtures f where f.season_id = s.id and f.player_match),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object('label', o.label, 'status', o.status, 'club_id', o.club_id) order by o.priority desc), '[]'::jsonb)
                         from public.mgr_objectives o where o.season_id = s.id))
        order by s.season_no desc), '[]'::jsonb)
        from public.career_seasons s where s.career_id = v_car.id and s.mode = 'coach'));
end;
$$;
create or replace function public.mgr_match_payload(p_fixture bigint, p_after_seq int)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'engine_version',coalesce((m.state->>'engine_version')::int,1),'referee',m.state->'referee',
    'fixture_id', m.fixture_id, 'status', m.status, 'minute', m.minute, 'user_side', m.user_side,
    'score', m.state -> 'score', 'agg', m.state -> 'agg', 'decisive', m.state -> 'decisive', 'et', m.state -> 'et',
    'extra_time_rule', m.state -> 'extra_time_rule', 'pens', m.state -> 'pens',
    'competition', f.competition_id, 'stage', f.stage, 'round', f.round_no, 'leg', f.leg, 'group', f.group_label,
    'home', f.home_club, 'away', f.away_club, 'neutral', m.state -> 'neutral',
    'tactics', m.state -> 'tactics', 'formation', m.state -> 'formation',
    'subs', m.state -> 'subs', 'max_subs', m.state -> 'max_subs', 'max_windows', m.state -> 'max_windows',
    'events', (select coalesce(jsonb_agg(jsonb_build_object('seq', e.seq, 'minute', e.minute, 'side', e.side, 'kind', e.kind,
                 'player', e.player_id, 'player_name', p1.short_name, 'player2', e.player2_id, 'player2_name', p2.short_name, 'detail', e.detail)
                 order by e.seq), '[]'::jsonb)
                 from public.mgr_match_events e
                 left join public.sim_players p1 on p1.id = e.player_id left join public.sim_players p2 on p2.id = e.player2_id
                where e.fixture_id = m.fixture_id and e.seq > coalesce(p_after_seq, 0)),
    'stats', jsonb_build_object(
       'poss', jsonb_build_array(round(100.0 * (m.state -> 'poss' ->> 0)::int / greatest((m.state -> 'poss' ->> 0)::int + (m.state -> 'poss' ->> 1)::int, 1)),
                                 100 - round(100.0 * (m.state -> 'poss' ->> 0)::int / greatest((m.state -> 'poss' ->> 0)::int + (m.state -> 'poss' ->> 1)::int, 1))),
       'shots', jsonb_build_array((select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(shots), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'sot', jsonb_build_array((select coalesce(sum(sot), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                (select coalesce(sum(sot), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'fouls', jsonb_build_array((select coalesce(sum(fouls), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(fouls), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'yellows', jsonb_build_array((select coalesce(sum(yellow), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                    (select coalesce(sum(yellow), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'reds', jsonb_build_array((select coalesce(sum(red), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                 (select coalesce(sum(red), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'saves', jsonb_build_array((select coalesce(sum(saves), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'h'),
                                  (select coalesce(sum(saves), 0) from public.mgr_match_players where fixture_id = m.fixture_id and side = 'a')),
       'corners', m.state -> 'corners', 'offsides', m.state -> 'offsides'),
    'players', (select coalesce(jsonb_agg(jsonb_build_object('id', mp.player_id, 'name', p.short_name, 'number', p.shirt_number, 'side', mp.side,
                 'slot', mp.slot, 'pos', mp.pos, 'natural', p.position, 'status', mp.status, 'starter', mp.starter, 'fit', mp.fit,
                 'cond', round(mp.cond), 'rating', mp.rating, 'goals', mp.goals, 'assists', mp.assists, 'yellow', mp.yellow, 'red', mp.red,
                 'injured', mp.injured, 'minutes', mp.minutes,
                 'overall', round((select r.eff from public.sim_player_pos_ratings r where r.player_id = mp.player_id and r.pos = coalesce(mp.pos, p.position))))
                 order by mp.side, (mp.status = 'on') desc, mp.slot, p.shirt_number), '[]'::jsonb)
                 from public.mgr_match_players mp join public.sim_players p on p.id = mp.player_id where mp.fixture_id = m.fixture_id),
    'summary', m.summary)
  from public.mgr_matches m join public.season_fixtures f on f.id = m.fixture_id
  where m.fixture_id = p_fixture
$$;
-- A interface só libera os controles novos depois que o backend correspondente existe.
do $$ begin
 if to_regprocedure('public.mgr_hub_before_seasons_v2()') is null then
  alter function public.mgr_hub() rename to mgr_hub_before_seasons_v2;
 end if;
end $$;
create or replace function public.mgr_hub()
returns jsonb language sql security definer set search_path=public as $$
 select public.mgr_hub_before_seasons_v2() || jsonb_build_object('simulation_version',2)
$$;
revoke all on function public.mgr_hub_before_seasons_v2(),public.mgr_hub() from public,anon,authenticated;
grant execute on function public.mgr_hub() to authenticated;
notify pgrst,'reload schema';


-- FILE: 20_pending_calendar_repair.sql
-- Reparação de dados DEPOIS das migrações 15..19 e do backup.
-- A migração não reinicia nem apaga temporadas. Se houver inconsistência,
-- toda a transação falha; não tenta adivinhar resultados.
set local lock_timeout='5s';
set local statement_timeout='10min';
do $$
declare r record;v jsonb;before_hash text;after_hash text;
begin
 select md5(coalesce(string_agg(md5(to_jsonb(f)::text),'' order by f.id),'')) into before_hash from public.season_fixtures f where status='played';
 for r in select id from public.career_seasons where status in('finished','archived')
  and not exists(select 1 from public.season_fixtures f where f.season_id=career_seasons.id and f.status<>'played') loop
  perform public.sim_record_final_tables(r.id);
 end loop;
 for r in select distinct f.season_id,f.competition_id,f.stage from public.season_fixtures f
  join public.career_seasons s on s.id=f.season_id join public.sim_competitions c on c.id=f.competition_id
  where s.status='active' and s.mode='coach' and c.kind='league' and f.status='pending'
    and public.sim_phase(f.competition_id,f.stage)->>'type'='league'
  order by f.season_id,f.competition_id,f.stage loop
  v:=public.sim_rebalance_pending(r.season_id,r.competition_id,r.stage);
  raise notice 'Calendário % / %: %',r.season_id,r.competition_id,v;
 end loop;
 select md5(coalesce(string_agg(md5(to_jsonb(f)::text),'' order by f.id),'')) into after_hash from public.season_fixtures f where status='played';
 if before_hash<>after_hash then raise exception 'Partidas disputadas foram alteradas; abortando reparação';end if;
end $$;
set constraints all immediate;


set constraints all immediate;
notify pgrst,'reload schema';
commit;
