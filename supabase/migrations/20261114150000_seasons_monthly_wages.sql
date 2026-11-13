-- MODO TEMPORADAS — salário sempre por mês.
-- O clube trabalha com folha e teto mensais, mas a negociação com o atleta era feita em valor semanal. Agora a
-- negociação usa o mesmo valor mensal: cw_weekly e cw_monthly viram identidade (os nomes ficam por compatibilidade com
-- as funções que os chamam) e os textos passam a dizer "por mês". Nenhum contrato muda de valor.
create or replace function public.cw_weekly(p_monthly numeric) returns bigint
language sql immutable as $$ select greatest(1,round(coalesce(p_monthly,0)))::bigint $$;
create or replace function public.cw_monthly(p_weekly numeric) returns bigint
language sql immutable as $$ select greatest(1,round(coalesce(p_weekly,0)))::bigint $$;
do $$
declare r record;
begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in('career_contract_offer','cw_neg_inbox_trg') and p.prosrc like '%por semana%' loop
  execute replace(replace(pg_get_functiondef(r.oid),'por semana','por mês'),'valor semanal pedido','valor pedido');
 end loop;
end $$;
