-- DIAGNÓSTICO: "Não foi possível carregar sua carreira". Só LEITURA: não altera nada.
-- Cole o arquivo inteiro no SQL Editor e clique em Run. O resultado é uma tabela (verificação | resultado).
with
act as (
 select count(*) filter (where state='active') ativas,
        count(*) filter (where state='active' and now()-query_start>interval '5 seconds') lentas,
        count(*) filter (where wait_event_type='Lock') bloqueadas,
        count(*) total
 from pg_stat_activity where datname=current_database()
),
slow as (
 select string_agg(format('%ss: %s', round(extract(epoch from now()-query_start)), left(regexp_replace(query,'\s+',' ','g'),90)),' || ' order by query_start) q
 from (select * from pg_stat_activity where datname=current_database() and state='active' and now()-query_start>interval '5 seconds' and pid<>pg_backend_pid() order by query_start limit 5) s
),
dup as (select count(*) n from (select user_id from public.careers where status='active' group by user_id having count(*)>1) d),
adm as (
 select coalesce(string_agg(format('carreira %s status=%s clube=%s nível=%s', c.id, c.status, coalesce(c.club_id,'—'), c.level),' | '),'nenhuma carreira') r
 from auth.users u left join public.careers c on c.user_id=u.id where lower(u.email)='contatodavidcaua@gmail.com'
),
pol as (select coalesce(string_agg(format('%s (%s)', policyname, cmd),', '),'nenhuma') r from pg_policies where schemaname='public' and tablename='careers'),
gr as (select coalesce(string_agg(distinct privilege_type,', '),'nenhum') r from information_schema.role_table_grants where table_schema='public' and table_name='careers' and grantee='authenticated')
select 'Conexões ao banco (ativas / total)' verificacao, (select ativas||' / '||total from act) resultado
union all select 'Consultas rodando há mais de 5 s', (select lentas::text from act)
union all select 'Consultas esperando bloqueio', (select bloqueadas::text from act)
union all select 'Exemplos de consultas lentas', coalesce((select q from slow),'nenhuma')
union all select 'Usuários com mais de uma carreira ativa', (select n::text from dup)
union all select 'Sua conta (contatodavidcaua@gmail.com)', (select r from adm)
union all select 'RLS ligado em careers', (select relrowsecurity::text from pg_class where oid='public.careers'::regclass)
union all select 'Regras (policies) de careers', (select r from pol)
union all select 'Permissões do papel authenticated em careers', (select r from gr)
union all select 'Carreiras ativas / total', (select count(*) filter (where status='active')||' / '||count(*) from public.careers)
union all select 'Presente da atualização (recebidos / elegíveis)', case when to_regclass('public.release_gifts') is null then 'script de presentes não instalado'
  else (select count(*) filter (where claimed_at is not null)||' / '||count(*) from public.release_gifts) end;
