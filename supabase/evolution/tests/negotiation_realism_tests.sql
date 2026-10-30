-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 40 (negociações realistas e idade nas cartas). Transação com ROLLBACK.
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;d date;top text;seller text;mid text;young text;old_p text;nid uuid;r public.cw_negotiations;b2 text;e jsonb;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 update public.cw_world set needs_sync=false where career_id=car;
 select today into d from public.cw_world where career_id=car;
 update public.cw_players set transfer_requested=false,morale=70 where career_id=car;
 update public.cw_contracts set expires_on=greatest(expires_on,d+700) where career_id=car and status='active';

 -- clube da Série A mais forte que não é o seu
 select c.id into seller from public.sim_clubs c where c.tier='serie_a' and c.id<>own order by c.strength desc limit 1;
 select x.player_id into top from(select mp.player_id from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=car and mp.club_id=seller order by pr.rating desc,mp.player_id limit 1) x;
 select x.player_id into mid from(select mp.player_id from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where mp.career_id=car and mp.club_id=seller order by pr.rating desc,mp.player_id offset 5 limit 1) x;

 -- 1) pilar do elenco: recusa mesmo com proposta muito acima do valor
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,valuation,decision_roll,agreed_owner_contract)
 select car,top,seller,own,'user','club_pending',public.cw_player_value(car,top)*5,100,3,d,d,d+7,public.cw_player_value(car,top),.5,ct.id from public.cw_contracts ct where ct.career_id=car and ct.player_id=top and ct.status='active' returning id into nid;
 perform public.cw_market_tick(car);
 select * into r from public.cw_negotiations where id=nid;
 if r.status<>'rejected' or r.response not like '%intocável%' then raise exception 'Pilar foi negociado: % %',r.status,r.response;end if;
 raise notice 'PASS pilar do elenco é intocável mesmo por 5× o valor';

 -- 2) titular: valor de mercado + um pouco não basta; o clube pede bem mais
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,valuation,decision_roll,agreed_owner_contract)
 select car,mid,seller,own,'user','club_pending',ceil(public.cw_player_value(car,mid)*1.1),100,3,d,d,d+7,public.cw_player_value(car,mid),.5,ct.id from public.cw_contracts ct where ct.career_id=car and ct.player_id=mid and ct.status='active' returning id into nid;
 perform public.cw_market_tick(car);
 select * into r from public.cw_negotiations where id=nid;
 if r.status<>'club_counter' or r.fee<r.valuation*1.6 then raise exception 'Titular negociado barato: % fee % valor %',r.status,r.fee,r.valuation;end if;
 raise notice 'PASS titular só sai por bem mais que o valor (pedida: % para valor %)',r.fee,r.valuation;

 -- 3) atleta da Série A não aceita ir para a Série B
 select c.id into b2 from public.sim_clubs c where c.tier='serie_b' order by c.strength desc limit 1;
 select x.player_id into young from(select mp.player_id from public.mgr_players mp join public.cw_players cp using(career_id,player_id)
  where mp.career_id=car and mp.club_id=seller and mp.player_id not in(top,mid) and cp.age_at_start<29 order by mp.player_id limit 1) x;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,valuation,decision_roll,agreed_owner_contract)
 select car,young,seller,b2,'ai','player_pending',100,ct.monthly_salary*2,3,d,d,d+7,1000,.5,ct.id from public.cw_contracts ct where ct.career_id=car and ct.player_id=young and ct.status='active' returning id into nid;
 perform public.cw_market_tick(car);
 select * into r from public.cw_negotiations where id=nid;
 if r.status<>'rejected' or r.response not like '%retrocesso%' then raise exception 'Atleta aceitou descer de divisão: % %',r.status,r.response;end if;
 raise notice 'PASS atleta da Série A recusa a Série B mesmo ganhando o dobro';

 -- 4) veterano (32+) aceita descer de divisão
 select x.player_id into old_p from(select mp.player_id from public.mgr_players mp join public.cw_players cp using(career_id,player_id)
  where mp.career_id=car and mp.club_id=seller and mp.player_id not in(top,mid,young) order by mp.player_id limit 1) x;
 update public.cw_players set age_at_start=34 where career_id=car and player_id=old_p;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,valuation,decision_roll,agreed_owner_contract)
 select car,old_p,seller,b2,'ai','player_pending',100,ct.monthly_salary*2,1,d,d,d+7,1000,.5,ct.id from public.cw_contracts ct where ct.career_id=car and ct.player_id=old_p and ct.status='active' returning id into nid;
 perform public.cw_market_tick(car);
 select * into r from public.cw_negotiations where id=nid;
 if r.response like '%retrocesso%' then raise exception 'Veterano recusou por retrocesso';end if;
 raise notice 'PASS veterano de 34 anos aceita descer de divisão (%)',r.status;

 -- 5) idade nas cartas de qualquer lista (inclusive partidas)
 e:=public.cw_patch_players(car,jsonb_build_array(jsonb_build_object('id',top)),false)->0;
 if e->>'age' is null then raise exception 'Carta sem idade';end if;
 raise notice 'PASS cartas trazem a idade (% anos)',e->>'age';
end $test$;
rollback;
