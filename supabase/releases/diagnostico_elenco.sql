-- DIAGNÓSTICO (somente leitura): não grava nada. Cole no SQL Editor e execute.
-- Mostra o que já está instalado, quanto existe de dados de usuários e se a manutenção está ativa.
select 'carreira completa (24–30)' as item, (to_regclass('public.cw_world') is not null and to_regprocedure('public.career_world_advance(integer,uuid)') is not null)::text as resultado
union all select 'evolução 31 (avanço rápido)', (position('1200 milliseconds' in coalesce((select prosrc from pg_proc where oid=to_regprocedure('public.career_world_advance(integer,uuid)')),''))>0)::text
union all select 'evolução 32 (elenco/satisfação)', (to_regprocedure('public.mgr_squad_before_v32(text)') is not null)::text
union all select 'manutenção da API (db_pre_request)', coalesce((select string_agg(option_value,', ') from pg_roles r join pg_db_role_setting s on s.setrole=r.oid cross join lateral pg_options_to_table(s.setconfig) where r.rolname='authenticator' and option_name='pgrst.db_pre_request'),'desligada')
union all select 'carreiras ativas', (select count(*)::text from public.careers where status='active')
union all select 'carreiras no mundo paralelo', (select count(*)::text from public.cw_world)
union all select 'partidas ao vivo agora', (select count(*)::text from public.mgr_matches where status='live')
union all select 'contratos ativos', (select count(*)::text from public.cw_contracts where status='active')
union all select 'atletas com satisfação registrada', (select count(*)::text from public.cw_players)
union all select 'tempo limite das requisições (authenticated)', coalesce((select string_agg(option_value,', ') from pg_roles r join pg_db_role_setting s on s.setrole=r.oid cross join lateral pg_options_to_table(s.setconfig) where r.rolname='authenticated' and option_name='statement_timeout'),'padrão');
