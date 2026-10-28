-- Teste transacional: não altera usuários ou dados do jogo.
-- Execute depois de 01_enable.sql. Erro de asserção indica falha.
begin;
do $$
declare
  claims jsonb;
  blocked boolean;
begin
  foreach claims in array array[
    '{"role":"authenticated","email":"outro@example.com"}'::jsonb,
    '{"role":"authenticated","email":""}'::jsonb,
    '{"role":"anon"}'::jsonb
  ] loop
    perform set_config('request.jwt.claims', claims::text, true);
    blocked := false;
    begin
      perform public.check_game_maintenance();
    exception when sqlstate 'PT503' then
      blocked := true;
    end;
    if not blocked then raise exception 'Falha: usuário comum não foi bloqueado'; end if;
  end loop;
  perform set_config('request.jwt.claims', '{"role":"authenticated","email":"contatodavidcaua@gmail.com"}', true);
  perform public.check_game_maintenance();
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.check_game_maintenance();
  raise notice 'PASS: usuários comuns bloqueados; administrador e serviço preservados';
end;
$$;
rollback;
