-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 44 (ranking geral dos treinadores). Transação com ROLLBACK.
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
declare car uuid:='31313131-0000-0000-0000-000000000011';r jsonb;p0 int;p1 int;e jsonb;prev bigint:=null;
begin
 r:=public.ranking_overall(50);
 if jsonb_array_length(r->'entries')=0 or r->'me' is null then raise exception 'Ranking vazio: %',r;end if;
 -- ordem decrescente de pontos e posições contínuas
 for e in select * from jsonb_array_elements(r->'entries') loop
  if prev is not null and (e->>'points')::bigint>prev then raise exception 'Fora de ordem';end if;
  prev:=(e->>'points')::bigint;
 end loop;
 if exists(select 1 from jsonb_array_elements(r->'entries') with ordinality x(item,i) where (item->>'position')::int<>i) then raise exception 'Posições com buraco';end if;
 if exists(select 1 from jsonb_array_elements(r->'entries') x where x ? 'email' or x ? 'career_id') then raise exception 'Ranking expõe dados privados';end if;
 raise notice 'PASS ranking em ordem, posições contínuas, sem dados privados (% treinadores)',r->>'total';
 -- desempenho no modo Temporadas sobe a posição
 p0:=(r->'me'->>'position')::int;
 update public.mgr_coach set titles=titles+5,wins=wins+40 where career_id=car;
 update public.careers set level=level+3 where id=car;
 r:=public.ranking_overall(50);p1:=(r->'me'->>'position')::int;
 if p1>=p0 and p0>1 then raise exception 'Títulos e vitórias não subiram a posição (% → %)',p0,p1;end if;
 if (r->'me'->>'points')::bigint<5*500+40*20 then raise exception 'Pontos não refletem títulos e vitórias';end if;
 raise notice 'PASS títulos, vitórias e nível sobem a posição (% → %)',p0,p1;
 -- demissões custam pontos
 p0:=(r->'me'->>'points')::int;
 update public.mgr_coach set fired_count=fired_count+1 where career_id=car;
 if (public.ranking_overall(5)->'me'->>'points')::int<>p0-150 then raise exception 'Demissão não penalizou';end if;
 raise notice 'PASS demissão tira 150 pontos';
end $test$;
rollback;
