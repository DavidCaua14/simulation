-- MODO TEMPORADAS — nova era (2026-11-13). Só regras; o reinício dos mundos fica em supabase/maintenance/reset/2026-11-nova-era.sql.
--
--  1. Sem aposentadoria e sem envelhecimento: a idade do atleta fica a do início do mundo.
--  2. Sem insatisfação de elenco/atleta: moral neutra, sem pedidos de saída, sem cobrança da diretoria por vestiário.
--  3. Premiação por competição em moedas, na proporção do futebol real (1 moeda ≈ R$ 10 mil), e moedas por vitória.
--  4. Sala de troféus permanente (career_trophies): as taças sobrevivem ao reinício do mundo.
--  5. Partida que "ficava em andamento": o último passo da partida ganha mais tempo para concluir.
--  6. Dificuldade: a IA aproveita menos a diferença de elenco a favor do técnico.
-- Tudo pode ser reaplicado.

-- Troca de texto conferida em uma função (mesma ideia de on_patch, que pode não existir em bancos sem o modo online).
create or replace function public.sim_patch(p_fn regprocedure,p_from text,p_to text) returns void
language plpgsql set search_path=public as $$
declare v text:=pg_get_functiondef(p_fn);c int;
begin
 if strpos(v,p_to)>0 then return;end if;
 c:=(length(v)-length(replace(v,p_from,'')))/length(p_from);
 if c<>1 then raise exception '%: "%" aparece % vez(es), esperado 1',p_fn,p_from,c;end if;
 execute replace(v,p_from,p_to);
end $$;
revoke all on function public.sim_patch(regprocedure,text,text) from public,anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Idade congelada e fim da aposentadoria
-- ─────────────────────────────────────────────────────────────────────────────
update public.cw_dev_rules set retirement_enabled=false;

do $$
declare r record;v text;re text:='floor\(\(\s*w\.today\s*-\s*w\.started_on\s*\)\s*/\s*365\.25\)';
 vw text:='floor((((w.today - w.started_on))::numeric / 365.25))';
begin
 -- toda função que somava os anos passados à idade inicial passa a somar zero
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.prosrc ~ re loop
  execute regexp_replace(pg_get_functiondef(r.oid),re,'0','g');
 end loop;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.prosrc like '%started_on%365.25%' and p.proname not like '%\_before\_%') then
  raise exception 'Ainda há função somando anos à idade';
 end if;
 -- a visão dos atletas calculava o valor de mercado com a idade corrente
 v:=pg_get_viewdef('public.cw_players'::regclass);
 if strpos(v,vw)>0 then
  execute 'create or replace view public.cw_players as '||replace(v,vw,'(0)::numeric');
 elsif strpos(v,'365.25')>0 then
  raise exception 'Visão cw_players: expressão de idade não reconhecida';
 end if;
end $$;

-- sem envelhecer não há queda por idade: veterano mantém o nível; jovem continua evoluindo até o potencial
select public.sim_patch('public.cw_dev_grow(uuid,date)',
 'when p.age<=30 then 0 when p.age<=32 then -.10 when p.age<=34 then -.22 else -.38 end;',
 'when p.age<=30 then 0 when p.age<=32 then -.10 when p.age<=34 then -.22 else -.38 end;'||chr(10)||'  base:=greatest(base,0); -- idade congelada');

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Sem insatisfação
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.cw_morale_factor(p_morale numeric) returns numeric
language sql immutable set search_path=public,pg_temp as $$ select 1::numeric $$;
create or replace function public.cw_coach_morale_factor(p_morale numeric) returns numeric
language sql immutable set search_path=public,pg_temp as $$ select 1::numeric $$;
create or replace function public.cw_cm_morale_next(p_career uuid,p_club text,p_player text,p_morale numeric,p_games integer,p_apps integer,p_arrears numeric,p_day date)
returns numeric language sql stable security definer set search_path=public as $$ select 70::numeric $$;
create or replace function public.cw_cm_morale_next_ai(p_career uuid,p_club text,p_player text,p_morale numeric,p_games integer,p_apps integer,p_arrears numeric,p_day date)
returns numeric language sql stable security definer set search_path=public as $$ select 70::numeric $$;
create or replace function public.cw_unrest_tick(p_career uuid) returns void
language sql security definer set search_path=public as $$ select $$;
create or replace function public.mgr_squad_morale_hit(p_career uuid,p_club text,p_amount numeric) returns void
language sql security definer set search_path=public as $$ select $$;
create or replace function public.mgr_match_morale(p_fixture bigint,p_car jsonb) returns jsonb
language sql security definer set search_path=public as $$ select p_car $$;
-- o app ainda lê este resumo: sempre neutro (fator 1, ninguém insatisfeito)
create or replace function public.cw_squad_unrest(p_career uuid,p_club text) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('harmony',80,'avg',70,'total',0,'satisfied',0,'neutral',0,'unhappy',0,'angry',0,'rebels',0,
  'penalty',0,'bonus',0,'factor',1,'disabled',true)
$$;
-- a diretoria não demite nem cobra por vestiário
create or replace function public.mgr_squad_check(p_fixture bigint,p_club text,p_car jsonb) returns jsonb
language sql security definer set search_path=public as $$ select p_car $$;

delete from public.cw_player_unrest;
update public.cw_player_rows set morale=70,morale_trend=0,transfer_requested=false where morale<>70 or transfer_requested or morale_trend<>0;
update public.mgr_coach set squad_warned=0 where squad_warned<>0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Premiação em moedas (1 moeda ≈ R$ 10 mil)
-- ─────────────────────────────────────────────────────────────────────────────
-- league: moedas por posição final (1º, 2º, ...); stages: moedas acumuladas até a fase em que o clube parou
-- (group, r16, qf, sf, runner_up, champion); win/draw: moedas por jogo.
create table if not exists public.sim_prizes(
 competition_id text primary key references public.sim_competitions(id) on delete cascade,
 league int[] not null default '{}',
 stages jsonb not null default '{}',
 win int not null default 0,
 draw int not null default 0,
 source text);
alter table public.sim_prizes enable row level security;
revoke all on public.sim_prizes from anon,authenticated;

insert into public.sim_prizes(competition_id,league,stages,win,draw,source)
select v.id,v.league,v.stages,v.win,v.draw,v.source from(values
 -- Brasileirão 2024: R$ 48,1 mi ao campeão até R$ 16,3 mi ao 16º; rebaixados não recebem
 ('brasileirao',array[4810,4570,4330,4090,3850,3610,3370,3130,2890,2640,2160,2020,1880,1730,1680,1630,0,0,0,0],'{}'::jsonb,30,10,'CBF 2024, por posição'),
 ('serie_b',array[350,200,150,150,60,60,40,40,40,40,20,20,20,20,20,20,0,0,0,0],'{}'::jsonb,12,4,'CBF 2024: campeão e acesso'),
 -- Copa do Brasil 2024 (a partir das oitavas): 3,46 + 4,72 + 9,45 mi; vice 31,5 mi; campeão 73,5 mi
 ('copa_brasil','{}'::int[],'{"group":0,"r16":346,"qf":819,"sf":1764,"runner_up":4914,"champion":9114}'::jsonb,40,0,'CBF 2024, cotas acumuladas'),
 -- Libertadores 2024: grupos US$ 3 mi, oitavas 1,25, quartas 1,7, semi 2,3, vice 7, campeão 23; US$ 330 mil por vitória
 ('libertadores','{}'::int[],'{"group":1620,"r16":2295,"qf":3215,"sf":4455,"runner_up":8235,"champion":16875}'::jsonb,180,0,'Conmebol 2024, cotas acumuladas'),
 ('ucl','{}'::int[],'{"group":3000,"r16":5000,"qf":8000,"sf":12000,"runner_up":17000,"champion":24000}'::jsonb,250,80,'UEFA 2024/25, cotas acumuladas (reduzidas)'),
 ('eng_premier',array(select 9000-350*(i-1) from generate_series(1,20) i),'{}'::jsonb,45,15,'Mérito por posição (reduzido)'),
 ('esp_laliga',array(select 7000-300*(i-1) from generate_series(1,20) i),'{}'::jsonb,40,12,'Mérito por posição (reduzido)'),
 ('ita_seriea',array(select 7000-300*(i-1) from generate_series(1,20) i),'{}'::jsonb,40,12,'Mérito por posição (reduzido)'),
 ('ger_bundesliga',array(select 7000-340*(i-1) from generate_series(1,18) i),'{}'::jsonb,40,12,'Mérito por posição (reduzido)'),
 ('fra_ligue1',array(select 5000-240*(i-1) from generate_series(1,18) i),'{}'::jsonb,35,10,'Mérito por posição (reduzido)'),
 ('por_primeira',array(select 2200-110*(i-1) from generate_series(1,18) i),'{}'::jsonb,25,8,'Mérito por posição (reduzido)'),
 ('arg_primera',array(select greatest(0,800-45*(i-1)) from generate_series(1,20) i),'{}'::jsonb,18,6,'Estimativa'),
 ('fa_cup','{}'::int[],'{"group":0,"r16":60,"qf":200,"sf":500,"runner_up":1000,"champion":2000}'::jsonb,30,0,'FA 2024/25, cotas acumuladas')
) v(id,league,stages,win,draw,source)
where exists(select 1 from public.sim_competitions c where c.id=v.id)
on conflict(competition_id) do update set league=excluded.league,stages=excluded.stages,win=excluded.win,draw=excluded.draw,source=excluded.source;
-- demais ligas e copas do catálogo: escala menor, pela categoria
insert into public.sim_prizes(competition_id,league,stages,win,draw,source)
select c.id,
 case when c.kind='league' then array(select greatest(0,400-25*(i-1)) from generate_series(1,20) i) else '{}'::int[] end,
 case when c.kind='league' then '{}'::jsonb
  when c.region='ENG' then '{"group":0,"r16":40,"qf":120,"sf":300,"runner_up":600,"champion":1200}'::jsonb
  else '{"group":0,"r16":20,"qf":60,"sf":150,"runner_up":300,"champion":600}'::jsonb end,
 case when c.kind='league' then 15 else 20 end,case when c.kind='league' then 5 else 0 end,'Estimativa'
from public.sim_competitions c
on conflict(competition_id) do nothing;

-- moedas da campanha: liga pela posição final; copa pela fase alcançada
create or replace function public.sim_prize_coins(p_comp text,p_code text,p_pos int) returns int
language sql stable security definer set search_path=public as $$
 select coalesce((select case when p_code in('p1','p2_4','p5_8','pother') then coalesce(z.league[p_pos],0)
  else coalesce((z.stages->>p_code)::int,0) end from public.sim_prizes z where z.competition_id=p_comp),0)
$$;
-- moedas do jogo: vitória (nos pênaltis também) ou empate
create or replace function public.sim_match_coins(p_comp text,p_won boolean,p_draw boolean) returns int
language sql stable security definer set search_path=public as $$
 select coalesce((select case when p_won then z.win when p_draw then z.draw else 0 end from public.sim_prizes z where z.competition_id=p_comp),0)
$$;
revoke all on function public.sim_prize_coins(text,text,int),public.sim_match_coins(text,boolean,boolean) from public,anon,authenticated;

select public.sim_patch('public.sim_finish_competition(uuid,text)',
 '      if v_xp > 0 or v_coins > 0 then',
 '      v_coins := public.sim_prize_coins(p_comp, v_code, v_pos); -- tabela sim_prizes'||chr(10)||'      if v_xp > 0 or v_coins > 0 then');
select public.sim_patch('public.base_award_match(bigint)',
 'values(f.id,s.id,s.career_id,0,won::int,',
 'values(f.id,s.id,s.career_id,public.sim_match_coins(f.competition_id,won,mine=opp and not won),won::int,');
-- o título já é pago pela tabela da competição: o prêmio fixo de fim de temporada sai
update public.cw_season_reward_rules set title_coins=0;

-- tabela de premiações para o app (as competições da temporada do técnico primeiro)
create or replace function public.sim_prize_table() returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'kind',c.kind,'region',c.region,'division',c.division,
  'league',to_jsonb(z.league),'stages',z.stages,'win',z.win,'draw',z.draw)
  order by (c.id in('brasileirao','copa_brasil','libertadores','serie_b')) desc,c.region,c.kind='league' desc,coalesce(z.league[1],(z.stages->>'champion')::int) desc),'[]'::jsonb)
 from public.sim_prizes z join public.sim_competitions c on c.id=z.competition_id
$$;
revoke all on function public.sim_prize_table() from public,anon;
grant execute on function public.sim_prize_table() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Sala de troféus permanente
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.career_trophies(
 id bigserial primary key,
 career_id uuid not null references public.careers(id) on delete cascade,
 competition text not null,
 year int not null,
 club_id text,
 era text not null default '2026-11',
 unique(career_id,competition,year,club_id,era));
alter table public.career_trophies enable row level security;
revoke all on public.career_trophies from anon,authenticated;

-- taças do técnico: as arquivadas (eras anteriores) e as da passagem atual
create or replace function public.career_titles(p_career uuid) returns table(competition text,year int,club_id text)
language sql stable security definer set search_path=public as $$
 select t.competition,t.year,t.club_id from public.career_trophies t where t.career_id=p_career
 union all
 select x->>'competition',(x->>'year')::int,sp.club_id from public.mgr_spells sp
  cross join lateral jsonb_array_elements(coalesce(sp.titles,'[]'::jsonb)) x where sp.career_id=p_career
$$;
revoke all on function public.career_titles(uuid) from public,anon,authenticated;

select public.sim_patch('public.profile_build(uuid,boolean)',
 '           from public.mgr_spells sp cross join lateral jsonb_array_elements(coalesce(sp.titles, ''[]''::jsonb)) t
          where sp.career_id = p_career) end,',
 '           from (select jsonb_build_object(''competition'', ct.competition, ''year'', ct.year) t, ct.club_id from public.career_titles(p_career) ct) sp) end,');
select public.sim_patch('public.badge_metric(uuid,text,numeric)',
 'select coalesce(sum(jsonb_array_length(coalesce(titles, ''[]''::jsonb))), 0) into v from public.mgr_spells where career_id = p_career;',
 'select count(*) into v from public.career_titles(p_career);');

-- histórico do técnico: as taças (arquivadas + atuais) para a sala de troféus do modo
select public.sim_patch('public.mgr_history()',
 '    ''spells'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', sp.id,',
 '    ''trophies'', (select coalesce(jsonb_agg(jsonb_build_object(''competition'', ct.competition, ''year'', ct.year, ''club_id'', ct.club_id) order by ct.year desc), ''[]''::jsonb) from public.career_titles(v_car.id) ct),'||chr(10)||
 '    ''spells'', (select coalesce(jsonb_agg(jsonb_build_object(''id'', sp.id,');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Mais tempo para os passos pesados (o PostgREST aplica o limite da função antes de chamá-la)
-- ─────────────────────────────────────────────────────────────────────────────
-- O apito final simula o resto da rodada, avança o calendário e pode fechar a temporada. Com o limite de 8 s do
-- papel authenticated o passo era desfeito inteiro e a partida continuava "em andamento".
alter function public.mgr_match_step(bigint,integer,integer,jsonb,boolean,integer) set statement_timeout='30s';
alter function public.mgr_match_start() set statement_timeout='20s';
alter function public.career_world_advance(integer,uuid) set statement_timeout='20s';
alter function public.career_world_prepare(integer,uuid,bigint) set statement_timeout='20s';
alter function public.mgr_advance(boolean) set statement_timeout='20s';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Dificuldade: a vantagem de elenco do técnico rende menos contra a IA
-- ─────────────────────────────────────────────────────────────────────────────
update public.career_difficulty_levels set ai_gap_keep=.60,ai_base_boost=.02,ai_match_mult=1.12 where id='easy';
update public.career_difficulty_levels set ai_gap_keep=.38,ai_base_boost=.07,ai_match_mult=1.32 where id='normal';
update public.career_difficulty_levels set ai_gap_keep=.28,ai_base_boost=.10,ai_match_mult=1.42 where id='hard';
