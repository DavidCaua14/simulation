-- MODO ONLINE — Fase 17: recuperação por hora com departamento médico, obras rápidas e bilheteria maior.
-- As rodadas saem a cada 7 horas, então nada no clube pode depender de "um dia".
--  • Condição física: +6 por hora, mais +1,5 por hora a cada nível do departamento médico (antes o médico dava
--    +5 por nível uma vez por dia). Nível 0 recupera 42 pontos entre duas rodadas; nível 3, 73; nível 5, 94.
--  • Lesão: 1 ou 2 dias; com departamento médico nível 3 ou mais, sempre 1 dia.
--  • Obras: 1 hora por nível (1 h até 5 h) em vez de 12 horas por nível.
--  • Bilheteria por jogo em casa: $ 15 mil + $ 10 mil por nível do estádio (antes 8 mil + 3 mil).
create or replace function public.on_build_time(p_level integer,p_sandbox boolean) returns interval
language sql immutable as $$ select case when p_sandbox then (p_level+1)*interval '5 minutes' else (p_level+1)*interval '1 hour' end $$;

-- bilheteria de um jogo em casa conforme o nível do estádio
create or replace function public.on_gate_value(p_level int) returns bigint
language sql immutable as $$ select (15000+10000*coalesce(p_level,0))::bigint $$;
-- recuperação de condição por hora conforme o nível do departamento médico
create or replace function public.on_recovery_rate(p_level int) returns numeric
language sql immutable as $$ select 6+1.5*coalesce(p_level,0) $$;
revoke all on function public.on_gate_value(int),public.on_recovery_rate(int) from public,anon,authenticated;

do $$ begin
 perform public.on_patch('public.on_gate_income(bigint)',
  'select (8000+3000*coalesce((lv->>''stadium'')::int,0))*case','select public.on_gate_value((lv->>''stadium'')::int)*case');
 -- o bônus diário do médico sai (a recuperação por hora já leva o nível em conta)
 perform public.on_patch('public.on_club_tick(timestamp with time zone,boolean)',
  '  if (r.lv->>''medical'')::int>0 then','  if false and (r.lv->>''medical'')::int>0 then -- substituído pela recuperação por hora');
 perform public.on_patch('public.on_tick(timestamp with time zone)',
  '   update public.on_players p set cond=least(100,p.cond+5)',
  '   update public.on_players p set cond=least(100,round(p.cond+public.on_recovery_rate((k.lv->>''medical'')::int)))');
 perform public.on_patch('public.on_match_finish(bigint)',
  '::date+1+floor(random()*2)::int else p.inj_until end',
  '::date+1+case when coalesce((select (k.lv->>''medical'')::int from public.on_clubs k where k.id=mp.club_id),0)>=3 then 0 else floor(random()*2)::int end else p.inj_until end');
end $$;
-- obras já em andamento passam a valer pelo prazo novo
update public.on_clubs k set build_until=least(k.build_until,now()+public.on_build_time(coalesce((k.lv->>k.build_kind)::int,0),false))
where k.build_kind is not null and k.build_until is not null;
