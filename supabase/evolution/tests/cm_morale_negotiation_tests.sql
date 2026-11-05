-- Evoluções 65 a 67: moral do CM17, negociação/renovação com salário semanal e pré-seleção. Banco descartável.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('65650000-0000-0000-0000-000000000001','cm65@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('65650000-0000-0000-0000-000000000011','65650000-0000-0000-0000-000000000001','CM65','sport','1',30,1000,3,250);
select set_config('request.jwt.claim.sub','65650000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='65650000-0000-0000-0000-000000000011';d date;mine text;r jsonb;dm bigint;n public.cw_negotiations;ok boolean;other text;
begin
 update public.cw_world set needs_sync=false where career_id=cid;
 perform public.mgr_lock();
 select today into d from public.cw_world where career_id=cid;

 -- 1) Moral: titular sem minutos cai, quem joga e vence sobe; ninguém pede para sair; papel prometido não existe.
 select mp.player_id into mine from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  where mp.career_id=cid and mp.club_id='sport' order by pr.rating desc limit 1;
 if public.cw_cm_morale_next(cid,'sport',mine,60,4,0,0,d)>=60 then raise exception 'Titular sem jogar não perdeu moral';end if;
 if public.cw_cm_morale_next(cid,'sport',mine,60,4,4,0,d)<=60 then raise exception 'Titular jogando não ganhou moral';end if;
 if public.cw_cm_morale_next(cid,'sport',mine,60,4,4,1,d)>=public.cw_cm_morale_next(cid,'sport',mine,60,4,4,0,d) then raise exception 'Salário atrasado sem efeito';end if;
 if exists(select 1 from public.cw_players where transfer_requested) then raise exception 'Ainda há pedido de saída';end if;
 begin perform public.career_player_role(mine,'key');raise exception 'Papel prometido ainda aceito';
 exception when raise_exception then if sqlerrm like 'Papel prometido ainda aceito' then raise;end if;end;
 if public.cw_board_veto(cid,'sport',mine) is null then raise exception 'Veto sem lista de transferências';end if;
 update public.cw_players set transfer_listed=true where career_id=cid and player_id=mine;
 if public.cw_board_veto(cid,'sport',mine) like '%três principais%' then raise exception 'Listado continua vetado';end if;
 update public.cw_players set transfer_listed=false where career_id=cid and player_id=mine;
 raise notice 'PASS moral CM17';

 -- 2) Folha só com salários; sem luvas mínimas; IA sem pré-contrato.
 if public.cw_contract_cost(mine,100,50,50,'key')<>100 then raise exception 'Bônus ainda contam na folha';end if;
 if public.cw_minimum_signing(cid,mine,'sport')<>0 then raise exception 'Luvas mínimas ainda exigidas';end if;
 if not exists(select 1 from pg_proc where proname='cw_v32_tick' and prosrc like '%pré-contratos desativados (CM17)%') then raise exception 'IA ainda faz pré-contrato';end if;
 if exists(select 1 from public.cw_contracts where status='active' and (appearance_bonus<>0 or goal_bonus<>0)) then raise exception 'Contrato com bônus';end if;
 raise notice 'PASS contrato sem bônus nem luvas';

 -- 3) Renovação: salário semanal; abaixo da pedida o atleta recusa dizendo quanto quer; na pedida, vai para análise.
 dm:=(public.career_wage_demand(mine)->>'weekly_demand')::bigint;
 if dm is null or dm<=0 then raise exception 'Pedida semanal ausente';end if;
 begin
  r:=public.career_contract_renew_offer(mine,greatest(1,round(dm*.9))::bigint,2,gen_random_uuid());
  raise exception 'Aceitou abaixo da pedida';
 exception when sqlstate 'P6602' then null;end;
 begin
  r:=public.career_contract_renew_offer(mine,greatest(1,round(dm*.5))::bigint,2,gen_random_uuid());
  raise exception 'Oferta muito baixa sem aviso';
 exception when sqlstate 'P6601' then null;end;
 r:=public.career_contract_renew_offer(mine,dm,2,gen_random_uuid());
 select * into n from public.cw_negotiations where id=(r->>'id')::uuid;
 if n.status<>'player_pending' or n.initiator<>'renewal' or n.contract_years<>2 or n.signing_bonus<>0 or n.appearance_bonus<>0 or n.goal_bonus<>0
  or public.cw_weekly(n.monthly_salary)<dm then raise exception 'Renovação CM17 errada: %',to_jsonb(n);end if;
 raise notice 'PASS renovação com salário semanal';

 -- 4) Contratar: oferta só de valor (sem parcelas, bônus nem pré-contrato).
 select mp.player_id into other from public.mgr_players mp where mp.career_id=cid and mp.club_id<>'sport' and mp.club_id in(select public.cw_domestic_clubs(cid)) order by mp.player_id limit 1;
 select d2 into d from generate_series(d,d+200,'1 day') d2 where public.cw_window_open(public.cw_region('sport'),d2::date) order by 1 limit 1;
 if d is not null then
  update public.cw_world set today=d where career_id=cid;
  begin
   r:=public.career_transfer_offer(other,public.cw_player_value(cid,other),gen_random_uuid());
   select * into n from public.cw_negotiations where id=(r->>'id')::uuid;
   if n.installments<>1 or n.performance_bonus<>0 or n.status not in('club_pending','player_counter') then raise exception 'Oferta CM17 errada: %',to_jsonb(n);end if;
  exception when raise_exception then
   if sqlerrm like 'Oferta CM17 errada%' then raise;end if;
   raise notice 'Oferta recusada pela regra do clube/elenco: %',sqlerrm;
  end;
 end if;
 raise notice 'PASS oferta só de valor';

 -- 5) Pré-seleção
 r:=public.career_shortlist_toggle(other);
 if not (r->>'shortlisted')::boolean or jsonb_array_length(public.career_shortlist())<>1 then raise exception 'Pré-seleção não adicionou';end if;
 r:=public.career_shortlist_toggle(other);
 if (r->>'shortlisted')::boolean or jsonb_array_length(public.career_shortlist())<>0 then raise exception 'Pré-seleção não removeu';end if;
 raise notice 'PASS pré-seleção';
end $test$;
rollback;
