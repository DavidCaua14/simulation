-- Executar somente quando a atualização estiver concluída.
begin;
do $$
begin
  if exists (
    select 1 from pg_roles r
    join pg_db_role_setting s on s.setrole = r.oid
    cross join lateral pg_options_to_table(s.setconfig)
    where r.rolname = 'authenticator' and option_name = 'pgrst.db_pre_request'
      and coalesce(option_value, '') not in ('', 'public.check_game_maintenance')
  ) then
    raise exception 'O hook da API mudou. Revise a configuração antes de remover a manutenção.';
  end if;
end;
$$;
alter role authenticator reset pgrst.db_pre_request;
notify pgrst, 'reload config';
commit;
-- A função fica inativa; nenhum dado de jogador é removido.
