-- MODO ONLINE — Fase 48: quatro turnos por dia e jogos em sequência dentro de cada campeonato.
--
-- 1. QUATRO TURNOS: 08:00, 11:30, 15:00 e 18:40 (nada entre 17:30 e 18:40, nada de madrugada). Antes eram dois
--    turnos (manhã e tarde) e a temporada levava ~26 dias; agora leva ~13.
--      • Temporadas novas (layout 2): turno = slot % 4, dia = início + slot / 4. As duas primeiras fases da copa
--        (30 e 32 jogos) caem no turno da noite (slots 3 e 7), as únicas que não cabem antes das 17:30.
--      • Temporada em andamento (layout 1): a partir de 24/11 cada slot ganha dia e turno em on_turns (a 2ª fase da
--        copa vai para a noite; o resto segue em sequência). Os jogos até o slot 5 (hoje) não mudam.
-- 2. JOGOS EM SEQUÊNCIA: dentro de um turno, cada campeonato (cada série, ou a copa) joga no máximo duas partidas ao
--    mesmo tempo, todas da mesma rodada. Quando uma termina, a próxima começa no minuto seguinte (on_chain_hook,
--    no fim de cada partida). Uma partida dura 12 min, então a fila anda a cada 13 min: Série D (15 jogos) em
--    1h44, Série A (10 jogos) em 1h05. Pênaltis atrasam só a fila daquele campeonato.
--    A ordem da fila segue o turno anterior (quem jogou cedo joga cedo): o descanso fica perto de 3h30 para todos.
-- 3. RECUPERAÇÃO: +10 de condição por hora (antes +6), mais 1,5 por nível do departamento médico, para o descanso
--    entre turnos render o mesmo que antes.

-- as temporadas que já existem ficam no calendário antigo (layout 1); as novas nascem com quatro turnos (layout 2)
alter table public.on_seasons add column if not exists layout smallint not null default 1;
alter table public.on_seasons alter column layout set default 2;

-- Dia e hora de início de cada turno, quando não sai da regra do layout (temporada que mudou no meio).
create table if not exists public.on_turns(
 season_id smallint not null references public.on_seasons(id) on delete cascade,
 slot int not null,
 at timestamptz not null,
 primary key(season_id,slot)
);
alter table public.on_turns enable row level security;

create or replace function public.on_turn_times() returns time[] language sql immutable as $$
 select array[time '08:00',time '11:30',time '15:00',time '18:40']
$$;

-- Início do turno de um slot.
create or replace function public.on_turn_start(p_season smallint,p_slot int) returns timestamptz
language sql stable security definer set search_path=public as $$
 select coalesce((select t.at from public.on_turns t where t.season_id=p_season and t.slot=p_slot),
  (select case when s.layout=2
     then ((s.starts_on+(p_slot/4))+(public.on_turn_times())[1+p_slot%4])::timestamp at time zone s.tz
     else ((s.starts_on+(p_slot/2))+case when p_slot%2=0 then time '08:00' else time '14:00' end)::timestamp at time zone s.tz end
   from public.on_seasons s where s.id=p_season))
$$;

-- Slot de cada rodada. Layout 1: o de antes. Layout 2: copa nos slots 3, 7 (noite), 13, 18, 22, 27, 31, 36, 40, 45, 49.
create or replace function public.on_round_slot(p_season smallint,p_div text,p_round int) returns int
language sql stable security definer set search_path=public as $$
 with cup as(select case when coalesce((select layout from public.on_seasons where id=p_season),2)=2
   then array[3,7,13,18,22,27,31,36,40,45,49] else array[3,8,13,18,22,27,31,36,40,45,49] end s),
 lg as(select array(select g from generate_series(0,50) g,cup where g<>all(cup.s) order by g) s)
 select case when p_div='K' then (select s[p_round] from cup)
  else (select s[1+case p_div when 'C' then round((p_round-1)*39.0/30) when 'D' then round((p_round-1)*39.0/35) else p_round-1 end] from lg) end
$$;

-- Fila de um campeonato num turno (p_grp: 'A','B','C','D' ou 'K' para a copa). Duas vagas; cada jogo ocupa a vaga
-- por 13 min (12 de jogo + 1 de folga). Jogo ao vivo segura a vaga até acabar. Só mexe em jogo marcado ('sched').
-- p_partner: ordem pelo turno anterior (quem jogou cedo joga cedo); sem ele, mantém a ordem atual da fila.
create or replace function public.on_plan_group(p_season smallint,p_slot int,p_grp text,p_partner boolean default true) returns void
language plpgsql security definer set search_path=public as $$
declare r record;l1 timestamptz;l2 timestamptz;t timestamptz;gap interval:=interval '13 minutes';
 v_floor timestamptz:=date_trunc('minute',now())+interval '1 minute';
begin
 l1:=greatest(public.on_turn_start(p_season,p_slot),v_floor);l2:=l1;
 for r in select f.kickoff from public.on_fixtures f where f.season_id=p_season and f.slot=p_slot and f.status='live'
   and case when p_grp='K' then f.comp='C' else f.comp='L' and f.div=p_grp end order by f.kickoff loop
  t:=greatest(date_trunc('minute',r.kickoff)+gap,v_floor);
  if l1<=l2 then l1:=greatest(l1,t); else l2:=greatest(l2,t); end if;
 end loop;
 for r in select f.id,f.kickoff from public.on_fixtures f
   left join lateral(select max(g.kickoff) t from public.on_fixtures g where p_partner and g.season_id=f.season_id and g.slot=p_slot-1
     and (g.home in(f.home,f.away) or g.away in(f.home,f.away))) pt on true
  where f.season_id=p_season and f.slot=p_slot and f.status='sched'
   and case when p_grp='K' then f.comp='C' else f.comp='L' and f.div=p_grp end
  order by case when p_partner then pt.t end nulls first,case when p_partner then null else f.kickoff end,
   public.sim_hash01(p_season||':'||p_slot||':'||f.id),f.id loop
  if l1<=l2 then t:=l1;l1:=l1+gap; else t:=l2;l2:=l2+gap; end if;
  if r.kickoff is distinct from t then update public.on_fixtures set kickoff=t where id=r.id and status='sched'; end if;
 end loop;
end $$;

-- Turno inteiro (todas as séries e a copa).
create or replace function public.on_plan_slot(p_season smallint,p_slot int) returns void
language plpgsql security definer set search_path=public as $$
declare x text;
begin
 foreach x in array array['A','B','C','D','K'] loop perform public.on_plan_group(p_season,p_slot,x,true);end loop;
end $$;

-- Fim de partida: a fila do campeonato anda (o próximo jogo começa no minuto seguinte).
create or replace function public.on_chain_hook(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f record;
begin
 select x.season_id,x.slot,x.comp,x.div,s.layout into f from public.on_fixtures x join public.on_seasons s on s.id=x.season_id where x.id=p_fixture;
 if f.slot is null then return; end if;
 -- calendário antigo (dois turnos): só nos slots que já ganharam turno novo
 if f.layout=1 and not exists(select 1 from public.on_turns t where t.season_id=f.season_id and t.slot=f.slot) then return; end if;
 perform public.on_plan_group(f.season_id,f.slot,case when f.comp='C' then 'K' else f.div end,false);
end $$;

-- Jogo novo (tabela, mata-mata, copa): entra no slot da rodada e a fila daquele campeonato é refeita.
create or replace function public.on_fx_add(p_season smallint,p_comp text,p_div text,p_round int,p_home int,p_away int,
 p_tphase int,p_grp int,p_tie int,p_legs int,p_stage text,p_adv int) returns void
language plpgsql security definer set search_path=public as $$
declare v_slot int;i int;v_g text:=case when p_comp='C' then 'K' else p_div end;
begin
 for i in 1..p_legs loop
  v_slot:=public.on_round_slot(p_season,v_g,p_round+i-1);
  insert into public.on_fixtures(season_id,comp,div,round,stage,home,away,kickoff,tphase,grp,tie,leg,adv,slot)
  values(p_season,p_comp,case when p_comp='L' then p_div end,p_round+i-1,p_stage,
   case when i=1 then p_home else p_away end,case when i=1 then p_away else p_home end,
   greatest(public.on_turn_start(p_season,v_slot),now()+interval '1 minute'),p_tphase,nullif(p_grp,0),p_tie,case when p_legs=2 then i end,p_adv,v_slot);
  perform public.on_plan_group(p_season,v_slot,v_g,true);
 end loop;
end $$;

-- Recuperação física por hora.
create or replace function public.on_recovery_rate(p_level int) returns numeric
language sql immutable as $$ select 10+1.5*coalesce(p_level,0) $$;

-- Gancho de fim de partida.
update public.on_config set finish_hooks=array_append(finish_hooks,'on_chain_hook') where not ('on_chain_hook'=any(finish_hooks));

-- Temporada em andamento: do slot 6 em diante (24/11), quatro turnos por dia. A 2ª fase da copa (slot 8, 32 jogos)
-- vai para a noite do primeiro dia; os demais slots seguem em sequência a partir do dia seguinte.
do $$
declare s record;v_slot int;v_day date;v_t int;v_first int:=6;v_from date:='2026-11-24';
begin
 select * into s from public.on_seasons where status='live' and series and layout=1 order by id desc limit 1;
 if s.id is null or exists(select 1 from public.on_turns where season_id=s.id) then return; end if;
 if exists(select 1 from public.on_fixtures where season_id=s.id and slot>=v_first and status<>'sched') then
  raise exception 'temporada % já tem jogo começado a partir do slot %',s.id,v_first;
 end if;
 v_day:=v_from;v_t:=0;
 for v_slot in v_first..50 loop
  if v_slot=8 then v_t:=3; end if;  -- copa grande: noite
  insert into public.on_turns(season_id,slot,at)
  values(s.id,v_slot,((v_day+0)+(public.on_turn_times())[1+v_t])::timestamp at time zone s.tz);
  v_t:=v_t+1;
  if v_t=4 then v_t:=0;v_day:=v_day+1; end if;
 end loop;
 for v_slot in v_first..50 loop perform public.on_plan_slot(s.id,v_slot); end loop;
end $$;

revoke all on function public.on_turn_times(),public.on_turn_start(smallint,int),public.on_round_slot(smallint,text,int),
 public.on_plan_group(smallint,int,text,boolean),public.on_plan_slot(smallint,int),public.on_chain_hook(bigint),
 public.on_fx_add(smallint,text,text,int,int,int,int,int,int,int,text,int),public.on_recovery_rate(int) from public,anon,authenticated;
