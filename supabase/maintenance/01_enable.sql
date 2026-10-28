-- Execute no SQL Editor como postgres. Não modifica dados dos jogadores.
-- Bloqueia a Data API (REST/RPC), inclusive para clientes antigos.
-- Não interrompe jobs, Edge Functions com service_role ou requisições já em execução.
begin;

-- Nunca substituir silenciosamente um hook de segurança existente.
do $$
declare
  existing text;
begin
  select option_value into existing
  from pg_roles r
  join pg_db_role_setting s on s.setrole = r.oid
  cross join lateral pg_options_to_table(s.setconfig)
  where r.rolname = 'authenticator'
    and option_name = 'pgrst.db_pre_request'
    and coalesce(option_value, '') not in ('', 'public.check_game_maintenance')
  limit 1;
  if existing is not null then
    raise exception 'Já existe um db_pre_request (%). Integre a manutenção ao hook existente antes de prosseguir.', existing;
  end if;
end;
$$;

create or replace function public.check_game_maintenance()
returns void
language plpgsql
set search_path = ''
as $$
begin
  -- JWT verificado pelo gateway; não usa user_metadata editável pelo usuário.
  if coalesce(auth.jwt() ->> 'role', '') = 'service_role'
     or (coalesce(auth.jwt() ->> 'role', '') = 'authenticated'
         and lower(coalesce(auth.jwt() ->> 'email', '')) = 'contatodavidcaua@gmail.com') then
    return;
  end if;
  raise sqlstate 'PT503'
    using message = 'Jogo em manutenção. Seu progresso está preservado. Atualize a página para ver o aviso.';
end;
$$;

-- Só altera o hook da API, não as permissões/RLS/tabelas existentes.
alter role authenticator set pgrst.db_pre_request = 'public.check_game_maintenance';
notify pgrst, 'reload config';
commit;
