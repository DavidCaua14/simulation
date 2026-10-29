-- Testes da evolução 33 (caixa de mensagens). Roda numa transação e desfaz tudo (ROLLBACK).
-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção:
-- ele usa carreiras fictícias de teste. Em produção, use supabase/releases/diagnostico_elenco.sql.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado. Em produção, rode supabase/releases/diagnostico_elenco.sql.';
 end if;
end $guard$;
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;pid text;other text;d date;nid uuid;n int;h jsonb;before int;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 update public.cw_world set needs_sync=false where career_id=car;
 select today into d from public.cw_world where career_id=car;
 update public.cw_world set today=make_date(extract(year from d)::int,1,10) where career_id=car;
 select count(*) into before from public.mgr_messages where career_id=car;

 -- 1) proposta recebida por atleta à venda → mensagem em Mercado com atalho
 select mp.player_id into pid from public.mgr_players mp where mp.career_id=car and mp.club_id=own order by mp.player_id limit 1;
 perform public.career_player_list(pid,true);
 for n in 1..40 loop perform public.cw_v32_tick(car);exit when exists(select 1 from public.cw_negotiations where career_id=car and player_id=pid and status='seller_review');end loop;
 select id into nid from public.cw_negotiations where career_id=car and player_id=pid and status='seller_review';
 if not exists(select 1 from public.mgr_messages where career_id=car and negotiation_id=nid and category='market' and action='open_negotiations' and title like '%faz proposta por%') then raise exception 'Proposta recebida sem mensagem';end if;
 raise notice 'PASS proposta recebida chega na caixa (Mercado)';

 -- 2) resposta do atleta à venda aceita → mensagem de conclusão ou recusa
 perform public.career_transfer_respond(nid,'accept',null,gen_random_uuid());
 update public.cw_negotiations set reply_on=(select today from public.cw_world where career_id=car) where id=nid;
 perform public.cw_market_tick(car);
 if (select status from public.cw_negotiations where id=nid) not in('completed','rejected','expired','cancelled','failed_funds') then
  update public.cw_world set today=(select expires_on+1 from public.cw_negotiations where id=nid) where career_id=car;
  perform public.cw_market_tick(car);
 end if;
 if (select count(*) from public.mgr_messages where career_id=car and negotiation_id=nid)<2 then raise exception 'Resposta da negociação sem mensagem: %',(select status from public.cw_negotiations where id=nid);end if;
 raise notice 'PASS resposta da negociação chega na caixa (%)',(select title from public.mgr_messages where career_id=car and negotiation_id=nid order by id desc limit 1);

 -- 3) proposta do treinador: resposta do clube vendedor vira mensagem
 select mp.player_id,mp.club_id into pid,other from public.mgr_players mp where mp.career_id=car and mp.club_id is not null and mp.club_id<>own
  and public.cw_region(mp.club_id)=public.cw_region(own) order by mp.player_id limit 1;
 update public.cw_clubs set cash=cash+50000000 where career_id=car and club_id=own;
 nid:=(public.career_transfer_bid(pid,10,1,0,false,gen_random_uuid())->>'id')::uuid;
 update public.cw_negotiations set reply_on=(select today from public.cw_world where career_id=car) where id=nid;
 perform public.cw_market_tick(car);
 if not exists(select 1 from public.mgr_messages where career_id=car and negotiation_id=nid and category='market') then raise exception 'Resposta do clube sem mensagem: %',(select status from public.cw_negotiations where id=nid);end if;
 raise notice 'PASS resposta do clube à sua proposta (%)',(select title from public.mgr_messages where career_id=car and negotiation_id=nid order by id desc limit 1);

 -- 4) insatisfação / pedido de saída → mensagem em Elenco
 perform public.cw_news_add(car,'morale-test:'||pid,'squad','Atleta pede para sair','Teste',90,own,pid);
 if not exists(select 1 from public.mgr_messages where career_id=car and category='squad' and action='open_player' and title='Atleta pede para sair') then raise exception 'Insatisfação sem mensagem';end if;
 -- notícia de outro clube não entra
 perform public.cw_news_add(car,'other-test','squad','De outro clube','Teste',90,other,pid);
 if exists(select 1 from public.mgr_messages where career_id=car and title='De outro clube') then raise exception 'Mensagem de outro clube vazou';end if;
 raise notice 'PASS satisfação do seu elenco na caixa (Elenco), sem notícias de outros clubes';

 -- 5) hub devolve categorias e não lidas por categoria
 h:=public.mgr_hub();
 if not (h ? 'unread_by_category') or exists(select 1 from jsonb_array_elements(h->'messages') e where not(e ? 'category')) then raise exception 'Hub sem categorias';end if;
 raise notice 'PASS hub com % mensagens novas e não lidas por categoria %',(select count(*) from public.mgr_messages where career_id=car)-before,h->'unread_by_category';
end $test$;
rollback;
