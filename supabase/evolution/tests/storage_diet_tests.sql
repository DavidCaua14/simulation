-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 38 (banco enxuto). Transação com ROLLBACK.
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;m date;cash_before jsonb;cash_after jsonb;ai_rows int;own_rows int;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 select date_trunc('month',today)::date into m from public.cw_world where career_id=car;
 delete from public.cw_settled_months where career_id=car and month=m;
 perform public.cw_settle_month(car,m);
 select jsonb_object_agg(club_id,cash) into cash_before from public.cw_clubs where career_id=car;
 perform public.cw_settle_month(car,m);
 perform public.cw_compact_month(car,m);
 select jsonb_object_agg(club_id,cash) into cash_after from public.cw_clubs where career_id=car;
 if cash_before<>cash_after then raise exception 'Mês pago duas vezes';end if;
 raise notice 'PASS mês fechado não é pago de novo e compactar não mexe no caixa';
 select count(*) into ai_rows from public.cw_finance where career_id=car and kind='wages' and club_id<>own and reference like '%:'||to_char(m,'YYYY-MM');
 select count(*) into own_rows from public.cw_finance where career_id=car and kind='wages' and club_id=own and reference like '%:'||to_char(m,'YYYY-MM');
 if ai_rows>(select count(*) from public.cw_clubs where career_id=car) then raise exception 'Salários da IA não foram agrupados: % linhas',ai_rows;end if;
 if own_rows<10 then raise exception 'Extrato do seu clube perdeu o detalhe por atleta: %',own_rows;end if;
 if exists(select 1 from public.cw_finance where career_id=car and kind='wages' and club_id<>own and reference='club:'||to_char(m,'YYYY-MM') and amount>=0) then raise exception 'Folha agrupada com valor inválido';end if;
 raise notice 'PASS salários da IA em uma linha por clube (% linhas); seu clube detalhado (% atletas)',ai_rows,own_rows;
end $test$;
rollback;
