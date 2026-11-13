-- MODO ONLINE — Fase 25: abrir a escalação pela preparação já conta como revisada.
-- Antes a tarefa "Escalação" só ficava verde depois de salvar uma mudança no time. Como no relatório do adversário,
-- abrir a escalação a partir da preparação marca a tarefa; salvar continua marcando também.
create or replace function public.on_lineup_review() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);f public.on_fixtures;
begin
 f:=public.on_next_fixture(c.id);
 if f.id is null then return null;end if;
 perform public.on_prep_mark(c.id,'lineup');
 select * into c from public.on_clubs where id=c.id;
 return public.on_prep_json(c,f);
end $$;
revoke all on function public.on_lineup_review() from public,anon;
grant execute on function public.on_lineup_review() to authenticated;
