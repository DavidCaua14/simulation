-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 37 (mercado, economia e notícias). Transação com ROLLBACK.
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;pid text;n public.cw_negotiations;r1 jsonb;r2 jsonb;cash0 bigint;cash1 bigint;i int;d date;
 v70 bigint;v80 bigint;v90 bigint;fx bigint;other text;cnt int;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 update public.cw_world set needs_sync=false where career_id=car;

 -- 1) renovar duas vezes antes de enviar a proposta reabre a mesma renovação
 select ct.player_id into pid from public.cw_contracts ct where ct.career_id=car and ct.club_id=own and ct.status='active'
  and not exists(select 1 from public.cw_negotiations z where z.career_id=car and z.player_id=ct.player_id) order by ct.player_id limit 1;
 r1:=public.career_contract_renew(pid,gen_random_uuid());
 r2:=public.career_contract_renew(pid,gen_random_uuid());
 if r1->>'id' is distinct from r2->>'id' then raise exception 'Renovação duplicada: % / %',r1,r2;end if;
 raise notice 'PASS renovar de novo reabre a renovação aberta (sem erro de chave duplicada)';

 -- 2) venda para clube da IA conclui e o valor entra no caixa
 select today into d from public.cw_world where career_id=car;
 update public.cw_world set today=make_date(extract(year from d)::int+1,1,10) where career_id=car;
 select ct.player_id into pid from public.cw_contracts ct where ct.career_id=car and ct.club_id=own and ct.status='active'
  and not exists(select 1 from public.cw_negotiations z where z.career_id=car and z.player_id=ct.player_id) order by ct.monthly_salary desc limit 1 offset 2;
 perform public.career_player_list(pid,true);
 for i in 1..40 loop perform public.cw_v32_tick(car);exit when exists(select 1 from public.cw_negotiations where career_id=car and player_id=pid and seller_club=own and status='seller_review');end loop;
 select * into n from public.cw_negotiations where career_id=car and player_id=pid and seller_club=own and status='seller_review';
 if n.id is null then raise exception 'Atleta listado não recebeu proposta';end if;
 -- força o atleta a pedir salário maior: o comprador da IA precisa aceitar sozinho
 update public.cw_negotiations set monthly_salary=ceil(monthly_salary*.85),decision_roll=.5 where id=n.id;
 select cash into cash0 from public.cw_clubs where career_id=car and club_id=own;
 perform public.career_transfer_respond(n.id,'accept',null,gen_random_uuid());
 for i in 1..12 loop
  update public.cw_world set today=today+1,needs_sync=false where career_id=car;
  perform public.cw_market_tick(car);
  exit when (select status from public.cw_negotiations where id=n.id) in('completed','rejected','cancelled','failed_funds','expired');
 end loop;
 select * into n from public.cw_negotiations where id=n.id;
 select cash into cash1 from public.cw_clubs where career_id=car and club_id=own;
 if n.status<>'completed' then raise exception 'Venda não concluída: % (%)',n.status,n.response;end if;
 if cash1-cash0<ceil(n.fee::numeric/n.installments) then raise exception 'Valor da venda não entrou no caixa: +% de %',cash1-cash0,n.fee;end if;
 raise notice 'PASS venda para a IA com pedido salarial conclui e credita % no caixa',cash1-cash0;

 -- 3) receita de jogo: bilheteria do mandante e prêmio do vencedor
 select f.id,f.home_club into fx,other from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id
  where fd.career_id=car and f.status='pending' and own not in(f.home_club,f.away_club) order by fd.due_on limit 1;
 select cash into cash0 from public.cw_clubs where career_id=car and club_id=other;
 update public.season_fixtures set home_goals=2,away_goals=0,status='played',played_at=now() where id=fx;
 select cash into cash1 from public.cw_clubs where career_id=car and club_id=other;
 if cash1-cash0<=0 or not exists(select 1 from public.cw_finance where career_id=car and club_id=other and kind='matchday' and reference='match:'||fx)
  or not exists(select 1 from public.cw_finance where career_id=car and club_id=other and kind='match_prize' and reference='match:'||fx) then
  raise exception 'Mandante vencedor sem bilheteria/prêmio';
 end if;
 raise notice 'PASS mandante recebe bilheteria e prêmio por vitória (+%)',cash1-cash0;

 -- 4) notícias: só do seu clube
 update public.mgr_coach set status='employed',club_id=own where career_id=car; -- os dias simulados acima podem ter trocado o treinador de clube
 perform public.cw_news_add(car,'t37:other','transfer','Outro clube contrata','x',40,other,null,null,'{}');
 perform public.cw_news_add(car,'t37:mine','transfer','Seu clube contrata','x',40,own,null,null,'{}');
 if exists(select 1 from public.cw_news where career_id=car and event_key='t37:other') or not exists(select 1 from public.cw_news where career_id=car and event_key='t37:mine') then
  raise exception 'Filtro de notícias incorreto';
 end if;
 raise notice 'PASS notícias de outros clubes não são criadas; as do seu clube sim';

 -- 5) valor de mercado: curva crescente e realista
 select public.cw_player_value(car,p.id) into v70 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position join public.cw_players cp on cp.career_id=car and cp.player_id=p.id where round(r.rating)=70 and cp.age_at_start between 24 and 27 and cp.potential<=r.rating+3 limit 1;
 select public.cw_player_value(car,p.id) into v80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position join public.cw_players cp on cp.career_id=car and cp.player_id=p.id where round(r.rating)=80 and cp.age_at_start between 24 and 27 and cp.potential<=r.rating+3 limit 1;
 select public.cw_player_value(car,p.id) into v90 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position join public.cw_players cp on cp.career_id=car and cp.player_id=p.id where round(r.rating)>=88 and cp.age_at_start between 24 and 27 limit 1;
 if not(v70<v80 and v80<coalesce(v90,v80+1) and v80 between 25000 and 70000 and v70<15000) then raise exception 'Curva de valor inesperada: 70=% 80=% 90=%',v70,v80,v90;end if;
 raise notice 'PASS valor de mercado: 70≈% · 80≈% · 90≈%',v70,v80,v90;

 -- 6) busca no mercado não trava a carreira e filtra pelo valor guardado
 if jsonb_array_length(public.career_player_search('','','','',20000,0,''))=0 then raise exception 'Busca vazia';end if;
 if exists(select 1 from jsonb_array_elements(public.career_player_search('','','','',20000,0,'')) e
   where (select market_value from public.cw_players where career_id=car and player_id=e->>'id')>20000) then raise exception 'Filtro de valor máximo ignorado';end if;
 raise notice 'PASS busca no mercado só leitura, com filtro de valor';
end $test$;
rollback;
