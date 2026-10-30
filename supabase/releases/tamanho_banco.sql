-- TAMANHO DO BANCO (só leitura). Mostra o total e as 15 maiores tabelas.
select 'TOTAL DO BANCO' as tabela, pg_size_pretty(pg_database_size(current_database())) as tamanho, null::bigint as linhas
union all
select * from (
 select s.schemaname||'.'||s.relname, pg_size_pretty(pg_total_relation_size(s.relid)), s.n_live_tup
 from pg_stat_user_tables s order by pg_total_relation_size(s.relid) desc limit 15) t;
