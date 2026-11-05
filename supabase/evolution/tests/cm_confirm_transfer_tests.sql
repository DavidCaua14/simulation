-- Evolução 68: o atleta aceita e o treinador confirma (ou desiste) antes do registro. Banco descartável.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('68680000-0000-0000-0000-000000000001','cm68@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('68680000-0000-0000-0000-000000000011','68680000-0000-0000-0000-000000000001','CM68','sport','1',30,1000,3,250);
select set_config('request.jwt.claim.sub','68680000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='68680000-0000-0000-0000-000000000011';d date;mine text;r jsonb;dm bigint;nid uuid;st text;
begin
 update public.cw_world set needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=50000000,wage_budget=50000000 where career_id=cid and club_id='sport';
 perform public.mgr_lock();
 select today into d from public.cw_world where career_id=cid;
 select mp.player_id into mine from public.mgr_players mp where mp.career_id=cid and mp.club_id='sport' order by mp.player_id limit 1;
 dm:=(public.career_wage_demand(mine)->>'weekly_demand')::bigint;
 -- renovação generosa: o atleta aceita na resposta do mercado e fica aguardando confirmação
 r:=public.career_contract_renew_offer(mine,dm*3,3,gen_random_uuid());nid:=(r->>'id')::uuid;
 update public.cw_negotiations set reply_on=d where id=nid;
 perform public.cw_market_tick(cid);
 select status into st from public.cw_negotiations where id=nid;
 if st<>'player_accepted' then raise exception 'Aceite não pediu confirmação: %',st;end if;
 if not exists(select 1 from public.mgr_messages where career_id=cid and body like 'Aceito sua oferta%') then raise exception 'Sem e-mail de aceite';end if;
 -- desistir libera a negociação
 r:=public.career_transfer_confirm(nid,false,gen_random_uuid());
 if (select status from public.cw_negotiations where id=nid)<>'cancelled' then raise exception 'Desistência não cancelou';end if;
 -- de novo, agora confirmando: vira acordo e é registrado
 r:=public.career_contract_renew_offer(mine,dm*3,3,gen_random_uuid());nid:=(r->>'id')::uuid;
 update public.cw_negotiations set reply_on=d where id=nid;
 perform public.cw_market_tick(cid);
 r:=public.career_transfer_confirm(nid,true,gen_random_uuid());
 select status into st from public.cw_negotiations where id=nid;
 if st not in('agreed','completed') then raise exception 'Confirmação não fechou: % %',st,r;end if;
 raise notice 'PASS confirmação final do negócio';
end $test$;
rollback;
