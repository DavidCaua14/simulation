-- MODO ONLINE — Fase 52: recuperação física dobrada só até o fim da temporada 9 (calendário acelerado até 29/11).
-- Enquanto a temporada 9 estiver em andamento: +20 de condição por hora (+1,5 por nível do departamento médico).
-- Na temporada seguinte volta sozinho para +10 por hora.
create or replace function public.on_recovery_rate(p_level int) returns numeric
language sql stable security definer set search_path=public as $$
 select case when exists(select 1 from public.on_seasons where id=9 and status='live') then 20 else 10 end+1.5*coalesce(p_level,0)
$$;
revoke all on function public.on_recovery_rate(int) from public,anon,authenticated;
