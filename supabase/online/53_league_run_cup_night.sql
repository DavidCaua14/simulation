-- MODO ONLINE — Fase 49: quatro jogos de liga por dia para todos e copa como quinto jogo, à noite.
--
-- Na fase 48 as séries dividiam os mesmos 40 turnos de liga: C e D (menos rodadas) ficavam com turnos vazios, e os
-- turnos de copa tiravam um turno de liga de todo mundo. Agora:
--  • LIGA: cada série joga as rodadas em sequência, sem buraco: 08:00, 11:30, 15:00 e 18:40, todo dia.
--    Slot de liga = rodada − 1 + deslocamento da série (on_seasons.cal->>'A'… ; 0 nas temporadas novas).
--    Turno do slot s: dia = início + s/4, horário = (08:00, 11:30, 15:00, 18:40)[s % 4].
--  • COPA: um jogo por dia às 20:30, para quem está nela (o quinto do dia). Slot da copa = 100 + fase;
--    dia = fase − 1 + cal->>'K'. Duas partidas por vez, como as séries: as fases de 30 e 32 jogos acabam ~23:57.
--  • A fila de cada turno segue a ordem do último jogo de cada clube antes dele (quem jogou cedo joga cedo).
--  • Temporada 9 (em andamento): os jogos a partir de 24/11 mudam para esse formato (cal: A, B e D +7, C +8, copa +2;
--    min_slot 12). Os de hoje (23/11) ficam como estão. A 2ª fase da copa é em 24/11 às 20:30 e a final em 03/12.
--  A Série D continua com uma folga por rodada em cada grupo (15 clubes), e quem sai na primeira fase de C e D
--  termina a temporada antes.

alter table public.on_seasons add column if not exists cal jsonb not null default '{}'::jsonb;

-- Slot de cada rodada (layout 2): liga em sequência por série; copa em 100 + fase.
create or replace function public.on_round_slot(p_season smallint,p_div text,p_round int) returns int
language sql stable security definer set search_path=public as $$
 select case when coalesce(s.layout,2)=2 then
   case when p_div='K' then 100+p_round else p_round-1+coalesce((s.cal->>p_div)::int,0) end
  else (with cup as(select array[3,8,13,18,22,27,31,36,40,45,49] s),
   lg as(select array(select g from generate_series(0,50) g,cup where g<>all(cup.s) order by g) s)
   select case when p_div='K' then (select s[p_round] from cup)
    else (select s[1+case p_div when 'C' then round((p_round-1)*39.0/30) when 'D' then round((p_round-1)*39.0/35) else p_round-1 end] from lg) end)
  end
 from (select 1) one left join public.on_seasons s on s.id=p_season
$$;

-- Início do turno de um slot.
create or replace function public.on_turn_start(p_season smallint,p_slot int) returns timestamptz
language sql stable security definer set search_path=public as $$
 select coalesce((select t.at from public.on_turns t where t.season_id=p_season and t.slot=p_slot),
  (select case
    when s.layout=2 and p_slot>=100 then ((s.starts_on+(p_slot-101+coalesce((s.cal->>'K')::int,0)))+time '20:30')::timestamp at time zone s.tz
    when s.layout=2 then ((s.starts_on+(p_slot/4))+(public.on_turn_times())[1+p_slot%4])::timestamp at time zone s.tz
    else ((s.starts_on+(p_slot/2))+case when p_slot%2=0 then time '08:00' else time '14:00' end)::timestamp at time zone s.tz end
   from public.on_seasons s where s.id=p_season))
$$;

-- Fila de um campeonato num turno: duas vagas, 13 min por jogo; ordem pelo último jogo de cada clube antes do turno.
create or replace function public.on_plan_group(p_season smallint,p_slot int,p_grp text,p_partner boolean default true) returns void
language plpgsql security definer set search_path=public as $$
declare r record;l1 timestamptz;l2 timestamptz;t timestamptz;gap interval:=interval '13 minutes';
 v_floor timestamptz:=date_trunc('minute',now())+interval '1 minute';v_start timestamptz:=public.on_turn_start(p_season,p_slot);
begin
 if p_slot<coalesce((select (cal->>'min_slot')::int from public.on_seasons where id=p_season),0) and p_slot<100 then return; end if;
 l1:=greatest(v_start,v_floor);l2:=l1;
 for r in select f.kickoff from public.on_fixtures f where f.season_id=p_season and f.slot=p_slot and f.status='live'
   and case when p_grp='K' then f.comp='C' else f.comp='L' and f.div=p_grp end order by f.kickoff loop
  t:=greatest(date_trunc('minute',r.kickoff)+gap,v_floor);
  if l1<=l2 then l1:=greatest(l1,t); else l2:=greatest(l2,t); end if;
 end loop;
 for r in select f.id,f.kickoff from public.on_fixtures f
   left join lateral(select max(g.kickoff) t from public.on_fixtures g where p_partner and g.season_id=f.season_id
     and g.kickoff<v_start and g.id<>f.id and (g.home in(f.home,f.away) or g.away in(f.home,f.away))) pt on true
  where f.season_id=p_season and f.slot=p_slot and f.status='sched'
   and case when p_grp='K' then f.comp='C' else f.comp='L' and f.div=p_grp end
  order by case when p_partner then pt.t end nulls first,case when p_partner then null else f.kickoff end,
   public.sim_hash01(p_season||':'||p_slot||':'||f.id),f.id loop
  if l1<=l2 then t:=l1;l1:=l1+gap; else t:=l2;l2:=l2+gap; end if;
  if r.kickoff is distinct from t then update public.on_fixtures set kickoff=t where id=r.id and status='sched'; end if;
 end loop;
end $$;

-- Fim de partida: a fila do campeonato anda (só no calendário novo).
create or replace function public.on_chain_hook(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f record;
begin
 select x.season_id,x.slot,x.comp,x.div,s.layout into f from public.on_fixtures x join public.on_seasons s on s.id=x.season_id where x.id=p_fixture;
 if f.slot is null or f.layout<>2 then return; end if;
 perform public.on_plan_group(f.season_id,f.slot,case when f.comp='C' then 'K' else f.div end,false);
end $$;

-- Temporada 9: do dia 24/11 em diante, liga em sequência por série e copa às 20:30.
do $$
declare s record;v_cal jsonb:='{"A":7,"B":7,"C":8,"D":7,"K":2,"min_slot":12}';r record;
begin
 select * into s from public.on_seasons where status='live' and series and layout=1 order by id desc limit 1;
 if s.id is null then return; end if;
 if s.id<>9 or exists(select 1 from public.on_fixtures where season_id=s.id and slot>=6 and status<>'sched') then
  raise exception 'temporada % não está no estado esperado',s.id;
 end if;
 update public.on_seasons set layout=2,cal=v_cal where id=s.id;
 delete from public.on_turns where season_id=s.id;
 update public.on_fixtures f set slot=public.on_round_slot(s.id,case when f.comp='C' then 'K' else f.div end,f.round)
  where f.season_id=s.id and f.slot>=6;
 for r in select x.slot,x.g from (select distinct slot,case when comp='C' then 'K' else div end g from public.on_fixtures
   where season_id=s.id and slot>=12) x order by public.on_turn_start(s.id,x.slot),x.g loop
  perform public.on_plan_group(s.id,r.slot,r.g,true);
 end loop;
end $$;

revoke all on function public.on_round_slot(smallint,text,int),public.on_turn_start(smallint,int),
 public.on_plan_group(smallint,int,text,boolean),public.on_chain_hook(bigint) from public,anon,authenticated;
