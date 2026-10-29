-- REMOVER A MANUTENÇÃO DO BANCO (libera a API para todos os jogadores).
-- Cole o arquivo inteiro no SQL Editor e clique em Run (sem selecionar trecho). É um comando só.
-- Não altera dados de jogadores: só desliga o bloqueio da API (pgrst.db_pre_request) instalado por
-- supabase/maintenance/01_enable.sql. A função check_game_maintenance fica no banco, inativa.
do $remove$
declare hook text;
begin
 select option_value into hook
 from pg_roles r
 join pg_db_role_setting s on s.setrole = r.oid
 cross join lateral pg_options_to_table(s.setconfig)
 where r.rolname = 'authenticator' and option_name = 'pgrst.db_pre_request'
 limit 1;
 if hook is null or hook = '' then
  perform pg_notify('pgrst', 'reload config');
  raise notice 'A manutenção do banco já estava desligada. Configuração da API recarregada.';
  return;
 end if;
 if hook <> 'public.check_game_maintenance' then
  raise exception 'O bloqueio da API é outro (%), não o da manutenção. Nada foi alterado.', hook;
 end if;
 alter role authenticator reset pgrst.db_pre_request;
 perform pg_notify('pgrst', 'reload config');
 raise notice 'Manutenção removida: a API está liberada para todos os jogadores. Dados preservados.';
end $remove$;
