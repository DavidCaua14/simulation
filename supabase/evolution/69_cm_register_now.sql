-- Evolução 69 — contratações como no Championship Manager 17.
--  * Não existe limite de contratações por janela (o limite de 6 sai da proposta e do registro).
--  * Negócio fechado entra no elenco na hora. A janela só limita quando se pode NEGOCIAR uma contratação;
--    acordos já fechados não ficam mais "aguardando a próxima janela".
--  * A verba de transferências paga a taxa; os salários não saem dela (regra da evolução 62), então o registro
--    deixa de exigir dois meses de folha em caixa.
--  * Acordos que estavam aguardando a janela (inclusive pré-contratos antigos) são registrados agora, no elenco
--    do clube comprador.
begin;

-- substituição de texto com verificação: cada trecho precisa existir exatamente uma vez
create or replace function pg_temp.patch(p_fn regprocedure,p_marker text,p_pairs text[])
returns void language plpgsql as $$
declare src text;i int;n int;begin
 select pg_get_functiondef(p_fn) into src;
 if src like '%'||p_marker||'%' then return;end if;
 for i in 1..array_length(p_pairs,1)/2 loop
  n:=(length(src)-length(replace(src,p_pairs[2*i-1],'')))/length(p_pairs[2*i-1]);
  if n<>1 then raise exception '% diferente do esperado (trecho %: % ocorrências)',p_fn,i,n;end if;
  src:=replace(src,p_pairs[2*i-1],p_pairs[2*i]);
 end loop;
 src:=replace(src,'AS $function$','AS $function$'||E'\n-- '||p_marker);
 execute src;
end $$;

-- 1) proposta: sem limite de 6 contratações por janela
select pg_temp.patch('public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid)','cm69: sem limite por janela',array[
 'and public.cw_registered_in_window(car.id,own,d)>=6 then','and false then']);

-- 2) registro: sem espera pela janela, sem limite de 6
select pg_temp.patch('public.cw_register_transfer(uuid)','cm69: registro imediato',array[
 'if n.initiator<>''renewal'' and not public.cw_window_open(region,d) then','if false then',
 'if not legacy and n.buyer_club=own and public.cw_registered_in_window(n.career_id,own,d)>=6 then','if false then']);
select pg_temp.patch('public.cw_register_transfer_before_v32(uuid)','cm69: registro imediato',array[
 'and n.initiator<>''renewal'' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then return false;end if;','and false then return false;end if;',
 '-(select reserve_salary_months from public.cw_rules)*(','-0*(']);

-- 3) acordo aprovado (mercado e confirmação) registra no mesmo dia
select pg_temp.patch('public.cw_market_tick_before_v37(uuid)','cm69: registro imediato',array[
 'case when n.seller_club is not null and n.initiator<>''renewal'' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end','d']);
select pg_temp.patch('public.career_transfer_confirm(uuid,boolean,uuid)','cm69: registro imediato',array[
 E'case when n.seller_club is not null and n.initiator<>''renewal'' and not public.cw_window_open(public.cw_region(n.buyer_club),d)\n    then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end','d']);

-- 4) acordos que aguardavam a janela entram no elenco agora
do $$ declare r record;begin
 for r in select n.id from public.cw_negotiations n join public.cw_world w on w.career_id=n.career_id
  where n.status in('agreed','precontract') order by n.created_on,n.id loop
  -- acordo já aprovado pelas duas partes: registra sem reavaliar salário pedido ou projeto
  insert into public.cw_market_legacy_agreements(negotiation_id,career_id) select n.id,n.career_id from public.cw_negotiations n where n.id=r.id on conflict do nothing;
  update public.cw_negotiations x set register_on=(select today from public.cw_world where career_id=x.career_id),
   response='Acordo fechado: o atleta foi registrado no elenco.' where x.id=r.id;
  perform public.cw_register_transfer(r.id);
 end loop;
end $$;

notify pgrst,'reload schema';
commit;
