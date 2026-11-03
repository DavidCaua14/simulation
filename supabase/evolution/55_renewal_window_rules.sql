-- New decisions only: existing careers, ownership, salaries and accepted terms are unchanged at installation.
begin;

create or replace function public.cw_project_reason(p_career uuid,p_player text,p_buyer text)
returns text language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare rating numeric;prestige numeric;current_club text;
begin
 select club_id into current_club from public.mgr_players where career_id=p_career and player_id=p_player;
 -- Owning a player does not guarantee that he will accept a new contract.
 select r.rating into rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=p_player;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=p_buyer),(select strength from public.sim_clubs where id=p_buyer)) into prestige;
 if rating is null or prestige is null then return 'Projeto esportivo indisponível para este atleta.';end if;
 -- Quality still matters for veterans and for players with an estimated age.
 if rating-prestige>(case when rating>=85 then 10 else 14 end) then
  return 'O atleta considera o nível esportivo do clube insuficiente e prefere uma equipe compatível com sua qualidade.';
 end if;
 if rating>=85 and public.cw_club_level(p_buyer)>1 then return 'Um atleta de elite não aceita este projeto em uma divisão inferior.';end if;
 return null;
end $$;

-- A renewal requires a current, unexpired contract AND current ownership by the same club.
create or replace function public.cw_valid_renewal(p_career uuid,p_player text,p_club text,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.mgr_players mp join public.cw_contracts ct
  on ct.career_id=mp.career_id and ct.player_id=mp.player_id and ct.club_id=mp.club_id
  where mp.career_id=p_career and mp.player_id=p_player and mp.club_id=p_club
   and ct.status='active' and ct.starts_on<=p_date and ct.expires_on>=p_date)
$$;

create or replace function public.career_transfer_bid(p_player text,p_fee bigint,p_installments int,p_bonus bigint,p_precontract boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;d date;b record;receipt jsonb;owner text;
begin
 car:=public.mgr_lock();receipt:=public.econ_request_get(car.id,p_request,'transfer_bid');if receipt is not null then return receipt;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select today into d from public.cw_world where career_id=car.id;
 if own is null then raise exception 'Assuma um clube para negociar';end if;
 if not public.cw_window_open(public.cw_region(own),d) then raise exception 'Janela de transferências fechada. Novas contratações, inclusive atletas livres e pré-contratos, só podem ser negociadas na janela aberta. Você pode renovar atletas do seu elenco.';end if;
 if not coalesce(p_precontract,false) and public.cw_window_open(public.cw_region(own),d)
  and public.cw_registered_in_window(car.id,own,d)>=6 then
  select * into b from public.cw_transfer_window(public.cw_region(own),d);
  raise exception 'Limite de 6 contratações registradas nesta janela atingido. Próxima janela: %.',to_char(public.cw_next_window(public.cw_region(own),b.ends_on+1),'DD/MM/YYYY');
 end if;
 -- A search never mutates the save. Materialize only the target club when an actual bid is made.
 owner:=public.cw_effective_player_club(car.id,p_player);
 if not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player) and owner is not null then perform public.cw_materialize_club(car.id,owner);end if;
 perform public.cw_recover_ai_free_players(car.id,p_player);
 return public.career_transfer_bid_before_v39(p_player,p_fee,p_installments,p_bonus,p_precontract,p_request);
end $$;

CREATE OR REPLACE FUNCTION public.career_player_offer(p_id uuid, p_salary bigint, p_years integer, p_signing bigint, p_role text, p_appearance bigint, p_goal bigint, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;n public.cw_negotiations;own text;prev jsonb;d date;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_offer');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into n from public.cw_negotiations where id=p_id and career_id=car.id and buyer_club=own for update;
 if not found or n.status<>'player_counter' or n.expires_on<d then raise exception 'Etapa de contrato indisponível';end if;
 if n.initiator='renewal' then
  if not public.cw_valid_renewal(car.id,n.player_id,own,d) then raise exception 'Só é possível renovar um contrato vigente de um atleta que ainda pertence ao seu clube.';end if;
 elsif not public.cw_window_open(public.cw_region(own),d) then raise exception 'Janela de transferências fechada. Apenas renovações do seu elenco estão disponíveis.';end if;
 if p_salary is null or p_salary not between 1 and 10000000 or p_years is null or (p_years<1 or p_years>(select max_contract_years from public.cw_rules)) or p_signing is null or p_signing not between 0 and 10000000 or p_role not in('key','starter','rotation','prospect') or p_appearance is null or p_appearance not between 0 and 1000000 or p_goal is null or p_goal not between 0 and 1000000 then raise exception 'Contrato inválido';end if;
 if public.cw_project_reason(car.id,n.player_id,own) is not null then raise exception '%',public.cw_project_reason(car.id,n.player_id,own);end if;
 if p_salary<public.cw_salary_demand(car.id,n.player_id,own) then raise exception 'Salário mensal insuficiente. O atleta exige pelo menos %.',public.cw_money_label(public.cw_salary_demand(car.id,n.player_id,own));end if;
 if n.seller_club is null and n.initiator<>'renewal' and p_signing<public.cw_minimum_signing(car.id,n.player_id,own) then raise exception 'Atleta livre exige ao menos % de luvas.',public.cw_money_label(public.cw_minimum_signing(car.id,n.player_id,own));end if;
 update public.cw_negotiations set monthly_salary=p_salary,contract_years=p_years,signing_bonus=p_signing,role=p_role,appearance_bonus=p_appearance,goal_bonus=p_goal,status='player_pending',reply_on=d+2,expires_on=public.cw_deadline(d) where id=n.id;
 perform public.cw_reserve_offer(n.id);perform public.cw_neg_history(n.id,'user','Condições contratuais apresentadas ao atleta.');
 return public.econ_request_save(car.id,p_request,'player_offer',jsonb_build_object('ok',true));
end $function$;

CREATE OR REPLACE FUNCTION public.cw_market_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;cp public.cw_players;rk int;minfee numeric;
 sb public.sim_clubs;bb public.sim_clubs;age int;rating numeric;wants_out boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- Every new decision uses the same salary floor, including renewals and free agents.
 for n in select * from public.cw_negotiations where career_id=p_career and status='player_pending' and reply_on<=d and expires_on>=d order by created_on,id for update loop
  if n.initiator='renewal' and not public.cw_valid_renewal(p_career,n.player_id,n.buyer_club,d) then
   perform public.cw_neg_close(n.id,'rejected','O atleta já não possui vínculo vigente com o clube.');continue;
  end if;
  if public.cw_project_reason(p_career,n.player_id,n.buyer_club) is not null then
   perform public.cw_neg_close(n.id,'rejected',public.cw_project_reason(p_career,n.player_id,n.buyer_club));continue;
  end if;
  if n.monthly_salary<public.cw_salary_demand(p_career,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(p_career,n.player_id,n.buyer_club)) then
   if n.round_no>=3 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou as condições salariais e as luvas.');
   else
    update public.cw_negotiations set status='player_counter',monthly_salary=greatest(monthly_salary,public.cw_salary_demand(p_career,n.player_id,n.buyer_club)),
     signing_bonus=greatest(signing_bonus,case when seller_club is null and initiator<>'renewal' then public.cw_minimum_signing(p_career,n.player_id,n.buyer_club) else 0 end),
     round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta exige salário e luvas compatíveis com sua qualidade e com o projeto esportivo.' where id=n.id;
    perform public.cw_neg_history(n.id,'player','Exigência salarial e de luvas atualizada.');
   end if;
  end if;
 end loop;
 -- Comprador da IA aceita o pedido salarial do atleta (evolução 37).
 update public.cw_negotiations set status='player_pending',reply_on=d,response='O clube comprador aceitou as condições pedidas pelo atleta.'
  where career_id=p_career and status='player_counter' and initiator<>'renewal' and buyer_club is distinct from own and expires_on>=d;

 for n in select * from public.cw_negotiations where career_id=p_career and status in('club_pending','player_pending') and reply_on<=d and expires_on>=d
   and initiator<>'renewal' order by created_on,id for update loop
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into cp from public.cw_players where career_id=p_career and player_id=n.player_id;
  select * into bb from public.sim_clubs where id=n.buyer_club;
  select * into sb from public.sim_clubs where id=n.seller_club;
  select r.rating into rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=n.player_id;
  age:=cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)::int;
  wants_out:=coalesce(cp.transfer_requested,false) or coalesce(cp.morale,60)<30;

  -- Clube vendedor da IA: pilares e titulares não saem por qualquer valor.
  if n.status='club_pending' and n.seller_club is not null and n.seller_club is distinct from own
     and not wants_out and coalesce(ct.expires_on,d+999)>=d+180 and n.register_on is null then
   rk:=public.cw_squad_rank(p_career,n.seller_club,n.player_id);
   if rk<=3 and not(bb.strength>sb.strength+5 and n.fee>=n.valuation*3 and n.decision_roll>.7) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' considera '||public.mgr_player_name(n.player_id)||' intocável: é um dos pilares do elenco.');
   elsif rk between 4 and 7 or (rk between 8 and 11 and n.initiator<>'ai') then
    if n.decision_roll<.2 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' não quer perder um titular agora.');
    else
     -- Titulares principais (4º–7º) custam 1,6–2× o valor; os demais titulares (8º–11º), 1,25–1,5×. Comprador menor paga 20% a mais.
     minfee:=n.valuation*case when rk<=7 then 1.6+n.decision_roll*.4 else 1.25+n.decision_roll*.25 end*case when bb.strength<sb.strength then 1.2 else 1 end;
     if n.fee<minfee then
      if n.initiator='ai' and n.decision_roll>.3 and public.cw_available_budget(p_career,n.buyer_club)>=minfee then
       -- Comprador da IA com caixa topa pagar o preço de um titular.
       update public.cw_negotiations set fee=ceil(minfee) where id=n.id;
       perform public.cw_neg_history(n.id,'buyer','Comprador aceitou pagar o preço pedido por um titular.');
      elsif n.round_no>=2 or n.initiator='ai' then
       perform public.cw_neg_close(n.id,'rejected','O clube só libera um titular por um valor bem acima do mercado.');
      else
       update public.cw_negotiations set status='club_counter',fee=ceil(minfee),round_no=round_no+1,expires_on=public.cw_deadline(d),
        response='Titular do elenco: o clube só negocia por '||public.cw_money_label(ceil(minfee))||'.' where id=n.id;
       perform public.cw_neg_history(n.id,'seller','Contraproposta por um titular.');
      end if;
     end if;
    end if;
   end if;

  -- Atleta: carreira em primeiro lugar (não desce de divisão nem vai para clube bem menor sem motivo).
  elsif n.status='player_pending' and bb.id is not null then
   if sb.id is null then
    if rating>=bb.strength+12 and age<31 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' prefere esperar uma proposta de um clube do seu nível.');
    end if;
   elsif public.cw_club_level(n.buyer_club)>public.cw_club_level(n.seller_club)
      and not(age>=32 or (wants_out and n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.3)) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' não aceita deixar a primeira divisão por um clube de divisão inferior: seria um retrocesso na carreira.');
   elsif public.cw_club_level(n.buyer_club)=public.cw_club_level(n.seller_club) and bb.strength<sb.strength-8
      and not(age>=31 or wants_out or n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.5) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' considera '||public.mgr_club_name(n.buyer_club)||' pequeno para o momento da carreira.');
   end if;
  end if;
 end loop;
 perform public.cw_market_tick_before_v37(p_career);
end $function$;

create or replace function public.cw_register_transfer(p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n public.cw_negotiations;own text;d date;region text;b record;next_date date;legacy boolean;result boolean;reason text;
begin
 select career_id into n.career_id from public.cw_negotiations where id=p_id;
 if n.career_id is null then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into own from public.mgr_coach where career_id=n.career_id and status='employed';
 region:=public.cw_region(n.buyer_club);
 if n.initiator='renewal' and not public.cw_valid_renewal(n.career_id,n.player_id,n.buyer_club,d) then
  perform public.cw_neg_close(n.id,'rejected','A renovação exige atleta e contrato vigentes do próprio clube.');return false;
 end if;
 -- Registration always waits for the buyer's window, including free agents, AI and old pre-contracts.
 -- Defer before reassessing the deal: approved agreements do not expire merely because the window closed.
 if n.initiator<>'renewal' and not public.cw_window_open(region,d) then
  next_date:=public.cw_next_window(region,d);
  update public.cw_negotiations set register_on=next_date,response='Acordo preservado. O registro aguarda a próxima janela disponível: '||to_char(next_date,'DD/MM/YYYY')||'.' where id=n.id;
  update public.cw_commitments set due_on=next_date where negotiation_id=n.id and kind='offer' and status='reserved';
  return false;
 end if;
 legacy:=exists(select 1 from public.cw_market_legacy_agreements where negotiation_id=n.id);
 if not legacy then
  reason:=public.cw_project_reason(n.career_id,n.player_id,n.buyer_club);
  if reason is not null then perform public.cw_neg_close(n.id,'rejected',reason);return false;end if;
  if n.monthly_salary<public.cw_salary_demand(n.career_id,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(n.career_id,n.player_id,n.buyer_club)) then
   perform public.cw_neg_close(n.id,'rejected','Os termos não atendem ao salário e às luvas exigidos pelo atleta.');return false;
  end if;
  if not public.cw_can_afford_contract(n.id) then
   perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar taxa, luvas, dívidas e seis meses do acréscimo da folha.');return false;
  end if;
 end if;
 if n.initiator<>'renewal' then
  if not legacy and n.buyer_club=own and public.cw_registered_in_window(n.career_id,own,d)>=6 then
   select * into b from public.cw_transfer_window(region,d);
   next_date:=public.cw_next_window(region,b.ends_on+1);
  end if;
  if next_date is not null then
   update public.cw_negotiations set register_on=next_date,response='Acordo preservado. O registro aguarda a próxima janela disponível: '||to_char(next_date,'DD/MM/YYYY')||'.' where id=n.id and register_on is distinct from next_date;
   update public.cw_commitments set due_on=next_date where negotiation_id=n.id and kind='offer' and status='reserved';
   return false;
  end if;
 end if;
 result:=public.cw_register_transfer_before_v39(p_id);
 if result and n.initiator<>'renewal' and n.buyer_club=own then
  insert into public.cw_transfer_registrations(career_id,negotiation_id,player_id,buyer_club,registered_on)
   values(n.career_id,n.id,n.player_id,n.buyer_club,d) on conflict do nothing;
 end if;
 return result;
end $$;

create or replace function public.career_contract_renew(p_player text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;cid uuid;own text;car public.careers;d date;reason text;prev jsonb;
begin
 car:=public.mgr_lock();cid:=car.id;
 prev:=public.econ_request_get(cid,p_request,'contract_renew');if prev is not null then return prev||jsonb_build_object('salary_demand',public.cw_salary_demand(cid,p_player,car.club_id));end if;
 select club_id into own from public.mgr_coach where career_id=cid and status='employed';
 select today into d from public.cw_world where career_id=cid;
 if not public.cw_valid_renewal(cid,p_player,own,d) then raise exception 'Só é possível renovar um contrato vigente de um atleta que ainda pertence ao seu clube.';end if;
 reason:=public.cw_project_reason(cid,p_player,own);
 if reason is not null then raise exception 'O atleta recusou a renovação: % O contrato atual continua válido até o vencimento.',reason;end if;
 r:=public.career_contract_renew_before_v54(p_player,p_request);
 return r||jsonb_build_object('salary_demand',public.cw_salary_demand(cid,p_player,own));
end $$;

create or replace function public.career_transfer_respond(p_id uuid,p_action text,p_fee bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;n public.cw_negotiations;own text;d date;prev jsonb;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'transfer_respond');if prev is not null then return prev;end if;
 select * into n from public.cw_negotiations where id=p_id and career_id=car.id for update;if not found then raise exception 'Negociação inexistente';end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 if own is null or (own is distinct from n.buyer_club and own is distinct from n.seller_club) or n.expires_on<d then raise exception 'Você não pode responder esta negociação';end if;
 if p_action in('accept','counter') and own=n.buyer_club and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(own),d) then raise exception 'Janela de transferências fechada. Apenas renovações do seu elenco estão disponíveis.';end if;
 if p_action='reject' and n.status in('seller_review','club_pending','club_counter','player_counter','player_pending') then perform public.cw_neg_close(n.id,'rejected','Proposta recusada pelo treinador.');
 elsif n.status='seller_review' and own=n.seller_club then
  if p_action='counter' then
   if n.round_no>=3 or p_fee is null or p_fee not between 0 and 100000000 then raise exception 'Contraproposta inválida';end if;
   if p_fee>n.valuation*1.8 or p_fee>public.cw_available_budget(car.id,n.buyer_club)+n.fee then perform public.cw_neg_close(n.id,'rejected','O comprador não aceita esse valor.');
   else update public.cw_negotiations set fee=p_fee,status='player_pending',reply_on=d+2,round_no=round_no+1,expires_on=public.cw_deadline(d) where id=n.id;perform public.cw_reserve_offer(n.id);end if;
  elsif p_action='accept' then update public.cw_negotiations set status='player_pending',reply_on=d+2,expires_on=public.cw_deadline(d) where id=n.id;
  else raise exception 'Resposta inválida';end if;
 elsif n.status='club_counter' and own=n.buyer_club and p_action='accept' then
  perform public.cw_reserve_offer(n.id);update public.cw_negotiations set status='player_counter',expires_on=public.cw_deadline(d),response='Clube aprovou. Negocie o contrato do atleta.' where id=n.id;
 elsif n.status='club_counter' and own=n.buyer_club and p_action='counter' then
  if n.round_no>=3 or p_fee is null or p_fee not between 0 and 100000000 then raise exception 'Contraproposta inválida';end if;
  update public.cw_negotiations set status='club_pending',fee=p_fee,round_no=round_no+1,reply_on=d+2,expires_on=public.cw_deadline(d) where id=n.id;perform public.cw_reserve_offer(n.id);
 else raise exception 'Aguarde a etapa atual da negociação';end if;
 perform public.cw_neg_history(n.id,'user','Resposta: '||p_action);
 return public.econ_request_save(car.id,p_request,'transfer_respond',jsonb_build_object('ok',true));
end $$;

revoke all on function public.cw_valid_renewal(uuid,text,text,date),public.cw_project_reason(uuid,text,text),public.cw_market_tick(uuid),public.cw_register_transfer(uuid) from public,anon,authenticated;
revoke all on function public.career_contract_renew(text,uuid),public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid),public.career_player_offer(uuid,bigint,integer,bigint,text,bigint,bigint,uuid),public.career_transfer_respond(uuid,text,bigint,uuid) from public,anon;
grant execute on function public.career_contract_renew(text,uuid),public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid),public.career_player_offer(uuid,bigint,integer,bigint,text,bigint,bigint,uuid),public.career_transfer_respond(uuid,text,bigint,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
