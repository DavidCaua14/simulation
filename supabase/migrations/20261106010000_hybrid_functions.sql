-- Fase 2 (banco híbrido): funções ajustadas para as views mgr_players, cw_players e cw_contracts.
-- Gerado a partir das definições em produção; cada bloco substitui a função inteira.

-- cw_finance_tick(uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;coach public.mgr_coach;ct public.cw_contracts;
begin
 perform public.cw_prepare_club_economy(p_career);
 perform public.cw_ai_contracts_tick(p_career);
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 select * into coach from public.mgr_coach where career_id=p_career;
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today
  and(not public.cw_runtime_enabled(p_career) or club_id=coach.club_id or club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id and n.status='precontract')) loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

-- career_transfer_bid_before_v32(text,bigint,integer,bigint,boolean,uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.career_transfer_bid_before_v32(p_player text, p_fee bigint, p_installments integer, p_bonus bigint, p_precontract boolean, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;owner text;ct public.cw_contracts;d date;id uuid;prev jsonb;value bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'transfer_bid');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 if own is null then raise exception 'Assuma um clube para negociar';end if;
 select club_id into owner from public.mgr_players where career_id=car.id and player_id=p_player;
 if not found or owner=own then raise exception 'Atleta indisponível para compra';end if;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and status='active';
 if p_precontract and (ct.id is null or ct.expires_on>d+180) then raise exception 'Pré-contrato disponível apenas nos seis meses finais do vínculo';end if;
 if not p_precontract and owner is not null and not public.cw_window_open(public.cw_region(own),d) then raise exception 'Janela de transferências fechada';end if;
 if p_fee is null or p_fee not between 0 and 100000000 or p_installments is null or p_installments not between 1 and 24 or p_bonus is null or p_bonus not between 0 and 10000000 then raise exception 'Condições financeiras inválidas';end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=p_player and buyer_club=own and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract')) then raise exception 'Já existe uma negociação em andamento por este atleta';end if;
 value:=public.cw_player_value(car.id,p_player);
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,installments,performance_bonus,created_on,reply_on,expires_on,register_on,valuation,agreed_owner_contract)
 values(car.id,p_player,owner,own,'user',case when owner is null or p_precontract then 'player_counter' else 'club_pending' end,
 case when p_precontract or owner is null then 0 else p_fee end,p_installments,p_bonus,d,d+2,public.cw_deadline(d),case when p_precontract then ct.expires_on+1 else null end,value,ct.id) returning id into id;
 perform public.cw_reserve_offer(id);perform public.cw_neg_history(id,'user','Proposta inicial registrada.');
 return public.econ_request_save(car.id,p_request,'transfer_bid',jsonb_build_object('id',id));
end $function$;

-- cw_register_transfer_before_v32(uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.cw_register_transfer_before_v32(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare n public.cw_negotiations;ct public.cw_contracts;d date;owner text;upfront bigint;part bigint;i int;own text;new_contract uuid;ref text;other record;
begin
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into owner from public.mgr_players where career_id=n.career_id and player_id=n.player_id;
 select * into ct from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and status='active';
 if (n.status<>'precontract' and ((n.initiator<>'renewal' and owner is distinct from n.seller_club) or ct.id is distinct from n.agreed_owner_contract)) or
    (n.status='precontract' and ct.id is not null and ct.id is distinct from n.agreed_owner_contract) then
  perform public.cw_neg_close(n.id,'cancelled','O vínculo do atleta mudou durante a negociação.');return false;
 end if;
 if n.status<>'precontract' and owner is not null and false then return false;end if;
 upfront:=ceil(n.fee::numeric/n.installments)::bigint;
 if (select cash-public.cw_reserved(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0)-0*(public.cw_payroll(n.career_id,n.buyer_club)+public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)-coalesce(case when ct.club_id=n.buyer_club then public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role) else 0 end,0)) from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club)<n.fee+n.signing_bonus+n.performance_bonus then
  perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar o custo e a nova folha.');return false;
 end if;
 if ct.id is not null then update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;end if;
 update public.cw_commitments set status='released' where negotiation_id=n.id and status='reserved';
 if upfront>0 then
  perform public.cw_cash(n.career_id,n.buyer_club,-upfront,'transfer',n.id||':0','Entrada da contratação');
  if n.seller_club is not null then perform public.cw_cash(n.career_id,n.seller_club,upfront,'player_sale',n.id||':0','Receita de venda de atleta');end if;
 end if;
 if n.signing_bonus>0 then perform public.cw_cash(n.career_id,n.buyer_club,-n.signing_bonus,'player_signing',n.id::text,'Luvas do atleta');end if;
 for i in 1..n.installments-1 loop
  part:=least(upfront,n.fee-upfront*i);
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'installment',greatest(0,part),(d+make_interval(months=>i))::date,n.id||':installment:'||i);
 end loop;
 if n.performance_bonus>0 then
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'performance',n.performance_bonus,d+365,n.id||':performance');
 end if;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role)
 values(n.career_id,n.player_id,n.buyer_club,d,(d+make_interval(years=>n.contract_years))::date,n.monthly_salary,n.signing_bonus,n.appearance_bonus,n.goal_bonus,n.role) returning id into new_contract;
 update public.mgr_players set club_id=n.buyer_club where career_id=n.career_id and player_id=n.player_id;
 -- Materialize only missing personal state for this registered player; never reset existing ability/history.
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select n.career_id,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
  least(99,round(r.rating)+case when coalesce(p.age,26)<23 then 12 else 3 end)
 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where p.id=n.player_id on conflict(career_id,player_id) do nothing;
 update public.cw_players set morale=75,promised_role=n.role,transfer_requested=false,last_warning_on=null where career_id=n.career_id and player_id=n.player_id;
 perform public.cw_prune_lineups(n.career_id,n.player_id);
 if not exists(select 1 from public.mgr_players where career_id=n.career_id and player_id=n.player_id and club_id=n.buyer_club)
  or not exists(select 1 from public.cw_players where career_id=n.career_id and player_id=n.player_id) then
  raise exception 'Não foi possível concluir o vínculo do atleta com o elenco. A operação foi revertida.';
 end if;
 update public.cw_negotiations set status='completed',response='Contrato registrado. O atleta integra o novo elenco.',register_on=d where id=n.id;
 if n.initiator<>'renewal' then
 insert into public.mgr_transfers(career_id,season_id,player_id,from_club,to_club,kind,fee,day_no)
 select n.career_id,w.primary_season,n.player_id,n.seller_club,n.buyer_club,'transfer',n.fee::int,w.elapsed_days from public.cw_world w where w.career_id=n.career_id;
 end if;
 for other in select id from public.cw_negotiations where career_id=n.career_id and player_id=n.player_id and id<>n.id and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') loop
  perform public.cw_neg_close(other.id,'cancelled','O atleta assinou outro contrato.');
 end loop;
 select club_id into own from public.mgr_coach where career_id=n.career_id;
 perform public.cw_news_add(n.career_id,'transfer:'||n.id,'transfer',public.mgr_player_name(n.player_id)||case when n.initiator='renewal' then ' renova com ' else ' assina com ' end||public.mgr_club_name(n.buyer_club),
  coalesce(public.mgr_club_name(n.seller_club),'Livre no mercado')||' → '||public.mgr_club_name(n.buyer_club)||'. Valor: '||public.cw_money_label(n.fee)||'. Contrato de '||n.contract_years||' anos.',
  case when own in(n.seller_club,n.buyer_club) then case when n.valuation>=150000 then 98 else 85 end else 45 end,n.buyer_club,n.player_id,null,
  jsonb_build_object('negotiation_id',n.id,'fee',n.fee,'from_club',n.seller_club,'to_club',n.buyer_club,'overall',(select round(rating) from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and sp.position=pr.pos where sp.id=n.player_id),'position',(select position from public.sim_players where id=n.player_id),'big_signing',n.valuation>=150000 and own=n.buyer_club and n.initiator<>'renewal'));
 perform public.cw_neg_history(n.id,'system','Registro concluído com pagamentos e vínculo únicos.');return true;
end $function$;

-- cw_ai_contracts_tick(uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.cw_ai_contracts_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare ct public.cw_contracts;d date;own text;wage bigint;payroll bigint;revenue bigint;cash bigint;inactive boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_recover_ai_free_players(p_career);
 for ct in select x.* from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and x.expires_on<=d+45
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
  order by x.club_id,x.player_id loop
  inactive:=public.cw_runtime_enabled(p_career) and ct.club_id not in(select public.cw_domestic_clubs(p_career));
  if inactive then
   -- Dormant leagues retain their clubs; no salary, cash, results or market simulation is advanced there.
   if ct.expires_on<d then update public.cw_contracts set expires_on=ct.expires_on+make_interval(years=>greatest(2,ceil((d-ct.expires_on)/365.0)::int+2)) where id=ct.id;end if;
   continue;
  end if;
  wage:=greatest(ct.monthly_salary,public.cw_salary_floor(ct.player_id));
  select c.monthly_revenue,c.cash-c.debt-public.cw_reserved(p_career,ct.club_id) into revenue,cash from public.cw_clubs c where c.career_id=p_career and c.club_id=ct.club_id and c.financial_risk<75;
  payroll:=public.cw_payroll(p_career,ct.club_id);
  if revenue is not null and cash>=2*payroll+6*greatest(0,wage-ct.monthly_salary)
   and payroll-ct.monthly_salary+wage<=revenue
   and((select r.rating>=80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=ct.player_id)
    or coalesce((select morale from public.cw_players where career_id=p_career and player_id=ct.player_id),65)>=35) then
   update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
    values(p_career,ct.player_id,ct.club_id,d,d+730,wage,ct.appearance_bonus,ct.goal_bonus,ct.role);
  end if;
 end loop;
end $function$;

-- career_player_release_before_v58(text,uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.career_player_release_before_v58(p_player text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;ct public.cw_contracts;d date;prev jsonb;months int;cost bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_release');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and club_id=own and status='active';
 if not found then raise exception 'Atleta fora do seu elenco';end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=p_player and status in('agreed','precontract')) then raise exception 'O atleta já tem uma transferência acertada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 months:=greatest(1,least(6,ceil((ct.expires_on-d)/30.0)::int));cost:=ct.monthly_salary*months+ct.arrears;
 perform public.cw_cash(car.id,own,-cost,'player_release',ct.id::text,'Rescisão de contrato de '||public.mgr_player_name(p_player));
 update public.cw_contracts set status='ended',ended_on=d,arrears=0 where id=ct.id;
 update public.mgr_players set club_id=null where career_id=car.id and player_id=p_player;
 perform public.cw_prune_lineups(car.id,p_player);
 update public.cw_negotiations set status='cancelled',response='O atleta deixou o clube.' where career_id=car.id and player_id=p_player and status in('seller_review','club_pending','club_counter','player_pending','player_counter');
 perform public.cw_news_add(car.id,'release:'||p_player||':'||d,'contract',public.mgr_player_name(p_player)||' tem contrato rescindido',
  'O atleta deixa '||public.mgr_club_name(own)||' e está livre no mercado. Custo da rescisão: '||public.cw_money_label(cost)||'.',85,own,p_player);
 return public.econ_request_save(car.id,p_request,'player_release',jsonb_build_object('ok',true,'cost',cost));
end $function$;

-- cw_loan_start(uuid): sem FOR UPDATE sobre view híbrida
CREATE OR REPLACE FUNCTION public.cw_loan_start(p_loan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare l public.cw_loans;ct public.cw_contracts;today date;nid uuid;
begin
 select * into l from public.cw_loans where id=p_loan for update;
 if l.status<>'offered' then raise exception 'Empréstimo indisponível';end if;
 select w.today into today from public.cw_world w where w.career_id=l.career_id;
 select * into ct from public.cw_contracts where career_id=l.career_id and player_id=l.player_id and club_id=l.parent_club and status='active';
 if not found then raise exception 'O atleta não tem contrato com o clube de origem';end if;
 if exists(select 1 from public.cw_negotiations where career_id=l.career_id and player_id=l.player_id and status in('agreed','precontract')) then
  raise exception 'O atleta já tem uma transferência acertada';
 end if;
 if l.fee>0 then
  perform public.cw_cash(l.career_id,l.borrower_club,-l.fee,'loan_fee',l.id::text,'Taxa de empréstimo de '||public.mgr_player_name(l.player_id));
  perform public.cw_cash(l.career_id,l.parent_club,l.fee,'loan_fee',l.id::text,'Taxa de empréstimo de '||public.mgr_player_name(l.player_id));
 end if;
 update public.cw_contracts set status='ended',ended_on=today where id=ct.id;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 values(l.career_id,l.player_id,l.borrower_club,today,least(l.ends_on,ct.expires_on),greatest(1,round(ct.monthly_salary*l.wage_share)),l.role) returning id into nid;
 update public.mgr_players set club_id=l.borrower_club where career_id=l.career_id and player_id=l.player_id;
 perform public.cw_prune_lineups(l.career_id,l.player_id);
 update public.cw_players set loan_listed=false,transfer_listed=false where career_id=l.career_id and player_id=l.player_id;
 update public.cw_loans set status='active',starts_on=today,ends_on=(select expires_on from public.cw_contracts where id=nid),borrower_contract=nid,
  parent_contract=jsonb_build_object('id',ct.id,'monthly_salary',ct.monthly_salary,'expires_on',ct.expires_on,'role',ct.role,
   'appearance_bonus',ct.appearance_bonus,'goal_bonus',ct.goal_bonus)
 where id=l.id;
 update public.cw_negotiations set status='cancelled',response='O atleta foi emprestado.' where career_id=l.career_id and player_id=l.player_id
  and status in('seller_review','club_pending','club_counter','player_pending','player_counter');
 perform public.cw_news_add(l.career_id,'loan:'||l.id,'transfer',public.mgr_player_name(l.player_id)||' é emprestado a '||public.mgr_club_name(l.borrower_club),
  'O atleta deixa '||public.mgr_club_name(l.parent_club)||' por empréstimo até '||to_char((select expires_on from public.cw_contracts where id=nid),'DD/MM/YYYY')||'.',55,l.borrower_club,l.player_id);
end $function$;

-- career_free_agent_offer
CREATE OR REPLACE FUNCTION public.career_free_agent_offer(p_player text, p_salary bigint, p_years integer, p_signing bigint, p_role text, p_appearance bigint, p_goal bigint, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;prev jsonb;r jsonb;oid uuid;d date;expired record;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'free_agent_offer');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select today into d from public.cw_world where career_id=car.id;
 if own is null then raise exception 'Assuma um clube para negociar';end if;
 if not exists(select 1 from public.sim_players where id=p_player and active) then raise exception 'Atleta indisponível';end if;
 if public.cw_effective_player_club(car.id,p_player) is not null or exists(select 1 from public.cw_contracts where career_id=car.id and player_id=p_player and status='active') then
  raise exception 'O atleta possui vínculo com um clube. Negocie a transferência com o proprietário.';
 end if;
 insert into public.mgr_players(career_id,player_id,club_id,rhythm) select car.id,p_player,null,70
  where not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player);
 perform public.cw_initialize_finances(car.id);perform public.cw_prepare_club_economy(car.id,own);
 for expired in select id from public.cw_negotiations where career_id=car.id and player_id=p_player and buyer_club=own
  and status in('player_counter','player_pending') and expires_on<d for update loop
  perform public.cw_neg_close(expired.id,'expired','Prazo da negociação encerrado.');
 end loop;
 select id into oid from public.cw_negotiations where career_id=car.id and player_id=p_player and buyer_club=own
  and seller_club is null and initiator='user' and status='player_counter' and expires_on>=d for update;
 if oid is null then
  r:=public.career_transfer_bid(p_player,0,1,0,false,md5(p_request::text||':free-bid')::uuid);oid:=(r->>'id')::uuid;
 end if;
 perform public.career_player_offer(oid,p_salary,p_years,p_signing,p_role,p_appearance,p_goal,md5(p_request::text||':free-contract')::uuid);
 update public.cw_negotiations set response='Proposta contratual apresentada diretamente ao atleta livre. Aguarde a decisão do jogador.' where id=oid;
 return public.econ_request_save(car.id,p_request,'free_agent_offer',jsonb_build_object('ok',true,'id',oid,'direct',true));
end $function$;

-- cw_register_transfer_before_v32
CREATE OR REPLACE FUNCTION public.cw_register_transfer_before_v32(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare n public.cw_negotiations;ct public.cw_contracts;d date;owner text;upfront bigint;part bigint;i int;own text;new_contract uuid;ref text;other record;
begin
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into owner from public.mgr_players where career_id=n.career_id and player_id=n.player_id;
 select * into ct from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and status='active';
 if (n.status<>'precontract' and ((n.initiator<>'renewal' and owner is distinct from n.seller_club) or ct.id is distinct from n.agreed_owner_contract)) or
    (n.status='precontract' and ct.id is not null and ct.id is distinct from n.agreed_owner_contract) then
  perform public.cw_neg_close(n.id,'cancelled','O vínculo do atleta mudou durante a negociação.');return false;
 end if;
 if n.status<>'precontract' and owner is not null and false then return false;end if;
 upfront:=ceil(n.fee::numeric/n.installments)::bigint;
 if (select cash-public.cw_reserved(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0)-0*(public.cw_payroll(n.career_id,n.buyer_club)+public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)-coalesce(case when ct.club_id=n.buyer_club then public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role) else 0 end,0)) from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club)<n.fee+n.signing_bonus+n.performance_bonus then
  perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar o custo e a nova folha.');return false;
 end if;
 if ct.id is not null then update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;end if;
 update public.cw_commitments set status='released' where negotiation_id=n.id and status='reserved';
 if upfront>0 then
  perform public.cw_cash(n.career_id,n.buyer_club,-upfront,'transfer',n.id||':0','Entrada da contratação');
  if n.seller_club is not null then perform public.cw_cash(n.career_id,n.seller_club,upfront,'player_sale',n.id||':0','Receita de venda de atleta');end if;
 end if;
 if n.signing_bonus>0 then perform public.cw_cash(n.career_id,n.buyer_club,-n.signing_bonus,'player_signing',n.id::text,'Luvas do atleta');end if;
 for i in 1..n.installments-1 loop
  part:=least(upfront,n.fee-upfront*i);
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'installment',greatest(0,part),(d+make_interval(months=>i))::date,n.id||':installment:'||i);
 end loop;
 if n.performance_bonus>0 then
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'performance',n.performance_bonus,d+365,n.id||':performance');
 end if;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role)
 values(n.career_id,n.player_id,n.buyer_club,d,(d+make_interval(years=>n.contract_years))::date,n.monthly_salary,n.signing_bonus,n.appearance_bonus,n.goal_bonus,n.role) returning id into new_contract;
 update public.mgr_players set club_id=n.buyer_club where career_id=n.career_id and player_id=n.player_id;
 -- Materialize only missing personal state for this registered player; never reset existing ability/history.
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select n.career_id,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
  least(99,round(r.rating)+case when coalesce(p.age,26)<23 then 12 else 3 end)
 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where p.id=n.player_id and not exists(select 1 from public.cw_players x where x.career_id=n.career_id and x.player_id=p.id);
 update public.cw_players set morale=75,promised_role=n.role,transfer_requested=false,last_warning_on=null where career_id=n.career_id and player_id=n.player_id;
 perform public.cw_prune_lineups(n.career_id,n.player_id);
 if not exists(select 1 from public.mgr_players where career_id=n.career_id and player_id=n.player_id and club_id=n.buyer_club)
  or not exists(select 1 from public.cw_players where career_id=n.career_id and player_id=n.player_id) then
  raise exception 'Não foi possível concluir o vínculo do atleta com o elenco. A operação foi revertida.';
 end if;
 update public.cw_negotiations set status='completed',response='Contrato registrado. O atleta integra o novo elenco.',register_on=d where id=n.id;
 if n.initiator<>'renewal' then
 insert into public.mgr_transfers(career_id,season_id,player_id,from_club,to_club,kind,fee,day_no)
 select n.career_id,w.primary_season,n.player_id,n.seller_club,n.buyer_club,'transfer',n.fee::int,w.elapsed_days from public.cw_world w where w.career_id=n.career_id;
 end if;
 for other in select id from public.cw_negotiations where career_id=n.career_id and player_id=n.player_id and id<>n.id and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') loop
  perform public.cw_neg_close(other.id,'cancelled','O atleta assinou outro contrato.');
 end loop;
 select club_id into own from public.mgr_coach where career_id=n.career_id;
 perform public.cw_news_add(n.career_id,'transfer:'||n.id,'transfer',public.mgr_player_name(n.player_id)||case when n.initiator='renewal' then ' renova com ' else ' assina com ' end||public.mgr_club_name(n.buyer_club),
  coalesce(public.mgr_club_name(n.seller_club),'Livre no mercado')||' → '||public.mgr_club_name(n.buyer_club)||'. Valor: '||public.cw_money_label(n.fee)||'. Contrato de '||n.contract_years||' anos.',
  case when own in(n.seller_club,n.buyer_club) then case when n.valuation>=150000 then 98 else 85 end else 45 end,n.buyer_club,n.player_id,null,
  jsonb_build_object('negotiation_id',n.id,'fee',n.fee,'from_club',n.seller_club,'to_club',n.buyer_club,'overall',(select round(rating) from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and sp.position=pr.pos where sp.id=n.player_id),'position',(select position from public.sim_players where id=n.player_id),'big_signing',n.valuation>=150000 and own=n.buyer_club and n.initiator<>'renewal'));
 perform public.cw_neg_history(n.id,'system','Registro concluído com pagamentos e vínculo únicos.');return true;
end $function$;

-- mgr_init_world
CREATE OR REPLACE FUNCTION public.mgr_init_world(p_career uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
if public.cw_is_hybrid(p_career) then
 -- Híbrido: o mundo registra só os clubes; os atletas vêm do catálogo (view mgr_players).
 insert into public.cw_world_clubs(career_id,club_id)
 select distinct p_career,p.club_id from public.sim_players p where p.career_id is null and p.active and p.club_id is not null and (p.club_id=(select club_id from public.mgr_coach where career_id=p_career) or exists(select 1 from public.career_seasons s join public.sim_clubs c on c.id=p.club_id and c.region=s.region where s.career_id=p_career and s.mode='coach' and s.status='active'))
 on conflict do nothing;
 get diagnostics v_n = row_count;
 return v_n;
end if;
insert into public.mgr_player_rows (career_id, player_id, club_id, rhythm)
select p_career, p.id, p.club_id, case when p.is_youth then 50 else 70 end
from public.sim_players p where p.active and p.club_id is not null and (p.club_id=(select club_id from public.mgr_coach where career_id=p_career) or exists(select 1 from public.career_seasons s join public.sim_clubs c on c.id=p.club_id and c.region=s.region where s.career_id=p_career and s.mode='coach' and s.status='active'))
on conflict (career_id, player_id) do nothing;
get diagnostics v_n = row_count;
return v_n;
end;
$function$;

-- mgr_sync_base_cards_before_world
CREATE OR REPLACE FUNCTION public.mgr_sync_base_cards_before_world(p_career uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare target text;r record;original text;changed int:=0;
begin
 perform 1 from public.careers where id=p_career for update;
 select club_id into target from public.mgr_coach where career_id=p_career and status='employed';
 if target is null then return 0;end if;
 for r in select m.card_id,m.player_id from public.user_cards u join public.base_card_players m on m.card_id=u.card_id
   where u.career_id=p_career and u.qty>0 order by m.player_id loop
  insert into public.mgr_players(career_id,player_id,club_id,rhythm)
   select p_career,p.id,p.club_id,case when p.is_youth then 50 else 70 end from public.sim_players p where p.id=r.player_id
   and not exists(select 1 from public.mgr_players x where x.career_id=p_career and x.player_id=p.id);
  select club_id into original from public.mgr_players where career_id=p_career and player_id=r.player_id;
  insert into public.base_card_roster(career_id,player_id,card_id,original_club_id,last_club_id)
   values(p_career,r.player_id,r.card_id,original,target) on conflict(career_id,player_id) do update set last_club_id=excluded.last_club_id;
  if original is distinct from target then
   -- Preserve saved tactics; only remove this transferred athlete from old club selections.
   update public.mgr_lineups l set
    slots=coalesce((select jsonb_object_agg(k,v) from jsonb_each(l.slots) e(k,v) where v<>to_jsonb(r.player_id)),'{}'),
    bench=array_remove(l.bench,r.player_id)
    where l.career_id=p_career and l.club_id<>target and
     (exists(select 1 from jsonb_each_text(l.slots) where value=r.player_id)
       or r.player_id=any(l.bench));
   update public.mgr_players set club_id=target where career_id=p_career and player_id=r.player_id;
   changed:=changed+1;
  end if;
 end loop;
 return changed;
end $function$;

-- cw_initialize_finances
CREATE OR REPLACE FUNCTION public.cw_initialize_finances(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 public.cw_commercial_income(c.id),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.club_id=c.id) on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and not exists(select 1 from public.cw_players x where x.career_id=p_career and x.player_id=p.id);
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(public.cw_salary_floor(mp.player_id),round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' and not exists(select 1 from public.cw_runtime where career_id=p_career) loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

-- cw_materialize_club
CREATE OR REPLACE FUNCTION public.cw_materialize_club(p_career uuid, p_club text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if public.cw_is_hybrid(p_career) then
  -- Híbrido: o clube passa a existir no mundo; os atletas vêm do catálogo.
  insert into public.cw_world_clubs(career_id,club_id) select p_career,p_club where exists(select 1 from public.sim_clubs where id=p_club) on conflict do nothing;
  if found and exists(select 1 from public.cw_world where career_id=p_career) and not exists(select 1 from public.cw_clubs where career_id=p_career and club_id=p_club) then
   perform public.cw_initialize_finances(p_career);
  end if;
  return;
 end if;
 insert into public.mgr_player_rows(career_id,player_id,club_id,rhythm)
 select p_career,p.id,p.club_id,case when p.is_youth then 50 else 70 end from public.sim_players p
 where p.club_id=p_club and p.active and not exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.player_id=p.id)
 on conflict do nothing;
 if exists(select 1 from public.cw_world where career_id=p_career) and exists(select 1 from public.mgr_players p left join public.cw_players cp using(career_id,player_id) where p.career_id=p_career and p.club_id=p_club and cp.player_id is null) then
 perform public.cw_initialize_finances(p_career);end if;
end $function$;

-- cw_finance_tick(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;coach public.mgr_coach;ct public.cw_contracts;
begin
 perform public.cw_prepare_club_economy(p_career);
 perform public.cw_ai_contracts_tick(p_career);
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 select * into coach from public.mgr_coach where career_id=p_career;
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today
  and(not public.cw_runtime_enabled(p_career) or club_id=coach.club_id or club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id and n.status='precontract')) loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id and career_id=ct.career_id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

-- cw_ai_contracts_tick(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_ai_contracts_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare ct public.cw_contracts;d date;own text;wage bigint;payroll bigint;revenue bigint;cash bigint;inactive boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_recover_ai_free_players(p_career);
 for ct in select x.* from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and x.expires_on<=d+45
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
  order by x.club_id,x.player_id loop
  inactive:=public.cw_runtime_enabled(p_career) and ct.club_id not in(select public.cw_domestic_clubs(p_career));
  if inactive then
   -- Dormant leagues retain their clubs; no salary, cash, results or market simulation is advanced there.
   if ct.expires_on<d then update public.cw_contracts set expires_on=ct.expires_on+make_interval(years=>greatest(2,ceil((d-ct.expires_on)/365.0)::int+2)) where id=ct.id and career_id=ct.career_id;end if;
   continue;
  end if;
  wage:=greatest(ct.monthly_salary,public.cw_salary_floor(ct.player_id));
  select c.monthly_revenue,c.cash-c.debt-public.cw_reserved(p_career,ct.club_id) into revenue,cash from public.cw_clubs c where c.career_id=p_career and c.club_id=ct.club_id and c.financial_risk<75;
  payroll:=public.cw_payroll(p_career,ct.club_id);
  if revenue is not null and cash>=2*payroll+6*greatest(0,wage-ct.monthly_salary)
   and payroll-ct.monthly_salary+wage<=revenue
   and((select r.rating>=80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=ct.player_id)
    or coalesce((select morale from public.cw_players where career_id=p_career and player_id=ct.player_id),65)>=35) then
   update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id and career_id=ct.career_id;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
    values(p_career,ct.player_id,ct.club_id,d,d+730,wage,ct.appearance_bonus,ct.goal_bonus,ct.role);
  end if;
 end loop;
end $function$;

-- cw_loan_start(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_loan_start(p_loan uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare l public.cw_loans;ct public.cw_contracts;today date;nid uuid;
begin
 select * into l from public.cw_loans where id=p_loan for update;
 if l.status<>'offered' then raise exception 'Empréstimo indisponível';end if;
 select w.today into today from public.cw_world w where w.career_id=l.career_id;
 select * into ct from public.cw_contracts where career_id=l.career_id and player_id=l.player_id and club_id=l.parent_club and status='active';
 if not found then raise exception 'O atleta não tem contrato com o clube de origem';end if;
 if exists(select 1 from public.cw_negotiations where career_id=l.career_id and player_id=l.player_id and status in('agreed','precontract')) then
  raise exception 'O atleta já tem uma transferência acertada';
 end if;
 if l.fee>0 then
  perform public.cw_cash(l.career_id,l.borrower_club,-l.fee,'loan_fee',l.id::text,'Taxa de empréstimo de '||public.mgr_player_name(l.player_id));
  perform public.cw_cash(l.career_id,l.parent_club,l.fee,'loan_fee',l.id::text,'Taxa de empréstimo de '||public.mgr_player_name(l.player_id));
 end if;
 update public.cw_contracts set status='ended',ended_on=today where id=ct.id and career_id=ct.career_id;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 values(l.career_id,l.player_id,l.borrower_club,today,least(l.ends_on,ct.expires_on),greatest(1,round(ct.monthly_salary*l.wage_share)),l.role) returning id into nid;
 update public.mgr_players set club_id=l.borrower_club where career_id=l.career_id and player_id=l.player_id;
 perform public.cw_prune_lineups(l.career_id,l.player_id);
 update public.cw_players set loan_listed=false,transfer_listed=false where career_id=l.career_id and player_id=l.player_id;
 update public.cw_loans set status='active',starts_on=today,ends_on=(select expires_on from public.cw_contracts where id=nid and career_id=l.career_id),borrower_contract=nid,
  parent_contract=jsonb_build_object('id',ct.id,'monthly_salary',ct.monthly_salary,'expires_on',ct.expires_on,'role',ct.role,
   'appearance_bonus',ct.appearance_bonus,'goal_bonus',ct.goal_bonus)
 where id=l.id;
 update public.cw_negotiations set status='cancelled',response='O atleta foi emprestado.' where career_id=l.career_id and player_id=l.player_id
  and status in('seller_review','club_pending','club_counter','player_pending','player_counter');
 perform public.cw_news_add(l.career_id,'loan:'||l.id,'transfer',public.mgr_player_name(l.player_id)||' é emprestado a '||public.mgr_club_name(l.borrower_club),
  'O atleta deixa '||public.mgr_club_name(l.parent_club)||' por empréstimo até '||to_char((select expires_on from public.cw_contracts where id=nid and career_id=l.career_id),'DD/MM/YYYY')||'.',55,l.borrower_club,l.player_id);
end $function$;

-- cw_repay_arrears(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_repay_arrears(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare c public.cw_clubs;ct public.cw_contracts;st public.cw_coach_contracts;paid bigint;ref text;d date;
begin
 select today into d from public.cw_world where career_id=p_career;
 for c in select * from public.cw_clubs where career_id=p_career and debt>0 order by club_id loop
  for ct in select * from public.cw_contracts where career_id=p_career and club_id=c.club_id and arrears>0 order by starts_on,id loop
   ref:=ct.id||':'||d;
   if exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='arrears' and reference=ref) then continue;end if;
   select least(cash,ct.arrears) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
   if paid>0 then
    perform public.cw_cash(p_career,c.club_id,-paid,'arrears',ref,'Quitação de salários atrasados');
    update public.cw_contracts set arrears=arrears-paid where id=ct.id and career_id=ct.career_id;
    update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
   end if;
  end loop;
  for st in select * from public.cw_coach_contracts where career_id=p_career and club_id=c.club_id and arrears>0 order by starts_on,id loop
   ref:=st.id||':'||d;
   if exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='staff_arrears' and reference=ref) then continue;end if;
   select least(cash,st.arrears) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
   if paid>0 then
    perform public.cw_cash(p_career,c.club_id,-paid,'staff_arrears',ref,'Quitação do salário do treinador');
    perform public.econ_apply(p_career,'coins',paid::int,'coach_arrears',ref);
    update public.cw_coach_contracts set arrears=arrears-paid where id=st.id;
    update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
   end if;
  end loop;
  select least(debt,greatest(0,cash-public.cw_payroll(p_career,c.club_id))) into paid from public.cw_clubs where career_id=p_career and club_id=c.club_id;
  if paid>0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=c.club_id and kind='debt_repayment' and reference=d::text) then
   perform public.cw_cash(p_career,c.club_id,-paid,'debt_repayment',d::text,'Amortização da dívida do clube');
   update public.cw_clubs set debt=greatest(0,debt-paid) where career_id=p_career and club_id=c.club_id;
  end if;
 end loop;
end $function$;

-- cw_settle_month_before_v38(uuid,date): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_settle_month_before_v38(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_clubs.club_id)) order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue;
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Patrocínios, direitos de transmissão e receitas comerciais');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month and (not (select public.cw_runtime_enabled(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_contracts.club_id)) order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id and career_id=ct.career_id;
 end loop;

 if public.cw_runtime_enabled(p_career) then
 for club in select * from public.cw_clubs z where z.career_id=p_career and z.club_id in (select public.cw_domestic_clubs(p_career))
 and not exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=z.club_id) order by z.club_id loop
  with amounts as(
   select x.id,x.monthly_salary,x.arrears,
   round(x.monthly_salary*greatest(0,least(month_end,x.expires_on,coalesce(x.ended_on,x.expires_on))-greatest(p_month,x.starts_on)+1)::numeric/month_days)
   +coalesce((select count(*)*x.appearance_bonus+coalesce(sum(a.goals),0)*x.goal_bonus from public.cw_appearances a where a.career_id=p_career and a.player_id=x.player_id and a.club_id=x.club_id and a.minutes>0 and a.on_date between greatest(p_month,x.starts_on) and least(month_end,x.expires_on,coalesce(x.ended_on,x.expires_on))),0) amount
   from public.cw_contracts x where x.career_id=p_career and x.club_id=club.club_id and x.starts_on<=month_end and coalesce(x.ended_on,x.expires_on)>=p_month
  ),running as(select *,coalesce(sum(amount) over(order by id rows between unbounded preceding and 1 preceding),0) before_due from amounts),
  arrears as(update public.cw_contracts x set arrears=x.arrears+greatest(0,r.amount-greatest(0,club.cash-r.before_due)) from running r
   where x.id=r.id and r.amount>greatest(0,club.cash-r.before_due) returning x.id)
  select coalesce(sum(amount),0) into due from running;
  if due>0 then perform public.cw_cash(p_career,club.club_id,-due,'wages','club:'||to_char(p_month,'YYYY-MM'),'Folha salarial do mês',true,jsonb_build_object('compacted',true,'paid',least(club.cash,due),'owed',greatest(0,due-club.cash)));end if;
 end loop;
 end if;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=cw_clubs.club_id)) order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  -- Seu clube pode juntar até 10× o orçamento inicial para contratar; os da IA seguem com 3×.
  -- O caixa do seu clube é seu: nunca vira "patrimônio". Só os clubes da IA guardam o excedente acima de 3× o orçamento.
  surplus:=case when club.club_id=(select mc.club_id from public.mgr_coach mc where mc.career_id=p_career and mc.status='employed') then 0
   else greatest(0,club.cash-3*club.initial_budget) end;
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $function$;

-- cw_settle_month_before_v38_before_v45(uuid,date): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_settle_month_before_v38_before_v45(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue+apps*(300+club.prestige::int*12);
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Receitas comerciais, torcida e bilheteria');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id and career_id=ct.career_id;
 end loop;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  -- Seu clube pode juntar até 10× o orçamento inicial para contratar; os da IA seguem com 3×.
  -- O caixa do seu clube é seu: nunca vira "patrimônio". Só os clubes da IA guardam o excedente acima de 3× o orçamento.
  surplus:=case when club.club_id=(select mc.club_id from public.mgr_coach mc where mc.career_id=p_career and mc.status='employed') then 0
   else greatest(0,club.cash-3*club.initial_budget) end;
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $function$;

-- cw_register_transfer_before_v32(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_register_transfer_before_v32(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare n public.cw_negotiations;ct public.cw_contracts;d date;owner text;upfront bigint;part bigint;i int;own text;new_contract uuid;ref text;other record;
begin
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into owner from public.mgr_players where career_id=n.career_id and player_id=n.player_id;
 select * into ct from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and status='active';
 if (n.status<>'precontract' and ((n.initiator<>'renewal' and owner is distinct from n.seller_club) or ct.id is distinct from n.agreed_owner_contract)) or
    (n.status='precontract' and ct.id is not null and ct.id is distinct from n.agreed_owner_contract) then
  perform public.cw_neg_close(n.id,'cancelled','O vínculo do atleta mudou durante a negociação.');return false;
 end if;
 if n.status<>'precontract' and owner is not null and false then return false;end if;
 upfront:=ceil(n.fee::numeric/n.installments)::bigint;
 if (select cash-public.cw_reserved(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0)-0*(public.cw_payroll(n.career_id,n.buyer_club)+public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)-coalesce(case when ct.club_id=n.buyer_club then public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role) else 0 end,0)) from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club)<n.fee+n.signing_bonus+n.performance_bonus then
  perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar o custo e a nova folha.');return false;
 end if;
 if ct.id is not null then update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id and career_id=ct.career_id;end if;
 update public.cw_commitments set status='released' where negotiation_id=n.id and status='reserved';
 if upfront>0 then
  perform public.cw_cash(n.career_id,n.buyer_club,-upfront,'transfer',n.id||':0','Entrada da contratação');
  if n.seller_club is not null then perform public.cw_cash(n.career_id,n.seller_club,upfront,'player_sale',n.id||':0','Receita de venda de atleta');end if;
 end if;
 if n.signing_bonus>0 then perform public.cw_cash(n.career_id,n.buyer_club,-n.signing_bonus,'player_signing',n.id::text,'Luvas do atleta');end if;
 for i in 1..n.installments-1 loop
  part:=least(upfront,n.fee-upfront*i);
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'installment',greatest(0,part),(d+make_interval(months=>i))::date,n.id||':installment:'||i);
 end loop;
 if n.performance_bonus>0 then
  insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
  values(n.career_id,n.buyer_club,n.id,'performance',n.performance_bonus,d+365,n.id||':performance');
 end if;
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role)
 values(n.career_id,n.player_id,n.buyer_club,d,(d+make_interval(years=>n.contract_years))::date,n.monthly_salary,n.signing_bonus,n.appearance_bonus,n.goal_bonus,n.role) returning id into new_contract;
 update public.mgr_players set club_id=n.buyer_club where career_id=n.career_id and player_id=n.player_id;
 -- Materialize only missing personal state for this registered player; never reset existing ability/history.
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select n.career_id,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
  least(99,round(r.rating)+case when coalesce(p.age,26)<23 then 12 else 3 end)
 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where p.id=n.player_id and not exists(select 1 from public.cw_players x where x.career_id=n.career_id and x.player_id=p.id);
 update public.cw_players set morale=75,promised_role=n.role,transfer_requested=false,last_warning_on=null where career_id=n.career_id and player_id=n.player_id;
 perform public.cw_prune_lineups(n.career_id,n.player_id);
 if not exists(select 1 from public.mgr_players where career_id=n.career_id and player_id=n.player_id and club_id=n.buyer_club)
  or not exists(select 1 from public.cw_players where career_id=n.career_id and player_id=n.player_id) then
  raise exception 'Não foi possível concluir o vínculo do atleta com o elenco. A operação foi revertida.';
 end if;
 update public.cw_negotiations set status='completed',response='Contrato registrado. O atleta integra o novo elenco.',register_on=d where id=n.id;
 if n.initiator<>'renewal' then
 insert into public.mgr_transfers(career_id,season_id,player_id,from_club,to_club,kind,fee,day_no)
 select n.career_id,w.primary_season,n.player_id,n.seller_club,n.buyer_club,'transfer',n.fee::int,w.elapsed_days from public.cw_world w where w.career_id=n.career_id;
 end if;
 for other in select id from public.cw_negotiations where career_id=n.career_id and player_id=n.player_id and id<>n.id and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') loop
  perform public.cw_neg_close(other.id,'cancelled','O atleta assinou outro contrato.');
 end loop;
 select club_id into own from public.mgr_coach where career_id=n.career_id;
 perform public.cw_news_add(n.career_id,'transfer:'||n.id,'transfer',public.mgr_player_name(n.player_id)||case when n.initiator='renewal' then ' renova com ' else ' assina com ' end||public.mgr_club_name(n.buyer_club),
  coalesce(public.mgr_club_name(n.seller_club),'Livre no mercado')||' → '||public.mgr_club_name(n.buyer_club)||'. Valor: '||public.cw_money_label(n.fee)||'. Contrato de '||n.contract_years||' anos.',
  case when own in(n.seller_club,n.buyer_club) then case when n.valuation>=150000 then 98 else 85 end else 45 end,n.buyer_club,n.player_id,null,
  jsonb_build_object('negotiation_id',n.id,'fee',n.fee,'from_club',n.seller_club,'to_club',n.buyer_club,'overall',(select round(rating) from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and sp.position=pr.pos where sp.id=n.player_id),'position',(select position from public.sim_players where id=n.player_id),'big_signing',n.valuation>=150000 and own=n.buyer_club and n.initiator<>'renewal'));
 perform public.cw_neg_history(n.id,'system','Registro concluído com pagamentos e vínculo únicos.');return true;
end $function$;

-- cw_dev_daily(uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.cw_dev_daily(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare today date;own text;l public.cw_loans;f record;p record;borrower text;ct uuid;sal bigint;
begin
 if not public.cw_dev_on() then return;end if;
 select w.today into today from public.cw_world w where w.career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- obras concluídas
 for f in select * from public.cw_facilities where career_id=p_career and building_until is not null and building_until<=today loop
  update public.cw_facilities set level=f.target_level,target_level=null,building_until=null,started_on=null where career_id=p_career and club_id=f.club_id and kind=f.kind;
  if f.club_id=own then
   perform public.cw_inbox_add(p_career,'facility:'||f.kind||':'||f.target_level,'board','club','Obra concluída',
    'A diretoria entregou a melhoria ('||f.kind||', nível '||f.target_level||'). Os efeitos já valem a partir de hoje.',own,null,null,null);
  end if;
 end loop;
 -- fim dos empréstimos
 for l in select * from public.cw_loans where career_id=p_career and status='active' and ends_on<=today for update loop
  update public.cw_contracts set status='ended',ended_on=today where id=l.borrower_contract and career_id=l.career_id and status='active';
  update public.cw_contracts set status='ended',ended_on=today where career_id=p_career and player_id=l.player_id and status='active';
  if exists(select 1 from public.cw_players where career_id=p_career and player_id=l.player_id and retired_on is not null) then
   update public.cw_loans set status='returned' where id=l.id;continue;
  end if;
  if (l.parent_contract->>'expires_on')::date>today then
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
   values(p_career,l.player_id,l.parent_club,today,(l.parent_contract->>'expires_on')::date,(l.parent_contract->>'monthly_salary')::bigint,
    coalesce((l.parent_contract->>'appearance_bonus')::bigint,0),coalesce((l.parent_contract->>'goal_bonus')::bigint,0),coalesce(l.parent_contract->>'role','rotation'));
   update public.mgr_players set club_id=l.parent_club where career_id=p_career and player_id=l.player_id;
  else
   update public.mgr_players set club_id=null where career_id=p_career and player_id=l.player_id;
  end if;
  perform public.cw_prune_lineups(p_career,l.player_id);
  update public.cw_loans set status='returned',response='Empréstimo encerrado.' where id=l.id;
  if own in(l.parent_club,l.borrower_club) then
   perform public.cw_inbox_add(p_career,'loan-end:'||l.id,'transfer','market','Fim de empréstimo: '||public.mgr_player_name(l.player_id),
    public.mgr_player_name(l.player_id)||' encerra o empréstimo em '||public.mgr_club_name(l.borrower_club)||' e volta para '||public.mgr_club_name(l.parent_club)||'.',
    own,l.player_id,null,'open_player');
  end if;
 end loop;
 update public.cw_loans set status='expired',response='A proposta expirou sem resposta.' where career_id=p_career and status='offered' and expires_on<today;
 -- propostas de empréstimo da IA para atletas listados pelo usuário (até 1 por atleta a cada janela de consulta)
 if own is not null and (select loans_enabled from public.cw_dev_rules) and public.cw_window_open(public.cw_region(own),today) then
  for p in select cp.player_id,public.cw_rating_now(p_career,cp.player_id) rt from public.cw_players cp join public.mgr_players mp on mp.career_id=cp.career_id and mp.player_id=cp.player_id
   where cp.career_id=p_career and cp.loan_listed and mp.club_id=own and cp.retired_on is null
    and not exists(select 1 from public.cw_loans x where x.career_id=p_career and x.player_id=cp.player_id and x.status in('offered','active')) loop
   continue when public.cw_random(p_career::text||':loanoffer:'||p.player_id||':'||today)>.18;
   select cc.club_id into borrower from public.cw_clubs cc
    where cc.career_id=p_career and cc.club_id<>own and cc.club_id in(select public.cw_domestic_clubs(p_career))
     and cc.prestige between p.rt-14 and p.rt+4 and public.cw_squad_count(p_career,cc.club_id)<public.cw_squad_limit()-1
    order by public.cw_random(p_career::text||':loanclub:'||p.player_id||':'||cc.club_id||':'||today) limit 1;
   continue when borrower is null;
   insert into public.cw_loans(career_id,player_id,parent_club,borrower_club,origin,status,wage_share,role,created_on,ends_on,expires_on,response)
   values(p_career,p.player_id,own,borrower,'ai_offer','offered',(array[.5,.75,1])[1+floor(public.cw_random(p_career::text||':share:'||p.player_id||today)*3)::int],
    case when p.rt>=(select prestige from public.cw_clubs where career_id=p_career and club_id=borrower)-3 then 'starter' else 'rotation' end,today,public.cw_season_end(public.cw_region(own),today),today+7,
    public.mgr_club_name(borrower)||' quer o atleta por empréstimo até o fim da temporada.')
   returning id into ct;
   perform public.cw_inbox_add(p_career,'loan-offer:'||ct,'transfer','market','Proposta de empréstimo por '||public.mgr_player_name(p.player_id),
    public.mgr_club_name(borrower)||' pede '||public.mgr_player_name(p.player_id)||' emprestado até o fim da temporada. Responda em Clube › Empréstimos.',own,p.player_id,null,'open_player');
  end loop;
 end if;
end $function$;

-- career_player_release_before_v58(text,uuid): busca de contrato por id limitada à carreira
CREATE OR REPLACE FUNCTION public.career_player_release_before_v58(p_player text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;ct public.cw_contracts;d date;prev jsonb;months int;cost bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_release');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and club_id=own and status='active';
 if not found then raise exception 'Atleta fora do seu elenco';end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=p_player and status in('agreed','precontract')) then raise exception 'O atleta já tem uma transferência acertada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 months:=greatest(1,least(6,ceil((ct.expires_on-d)/30.0)::int));cost:=ct.monthly_salary*months+ct.arrears;
 perform public.cw_cash(car.id,own,-cost,'player_release',ct.id::text,'Rescisão de contrato de '||public.mgr_player_name(p_player));
 update public.cw_contracts set status='ended',ended_on=d,arrears=0 where id=ct.id and career_id=ct.career_id;
 update public.mgr_players set club_id=null where career_id=car.id and player_id=p_player;
 perform public.cw_prune_lineups(car.id,p_player);
 update public.cw_negotiations set status='cancelled',response='O atleta deixou o clube.' where career_id=car.id and player_id=p_player and status in('seller_review','club_pending','club_counter','player_pending','player_counter');
 perform public.cw_news_add(car.id,'release:'||p_player||':'||d,'contract',public.mgr_player_name(p_player)||' tem contrato rescindido',
  'O atleta deixa '||public.mgr_club_name(own)||' e está livre no mercado. Custo da rescisão: '||public.cw_money_label(cost)||'.',85,own,p_player);
 return public.econ_request_save(car.id,p_request,'player_release',jsonb_build_object('ok',true,'cost',cost));
end $function$;

-- cw_ai_contracts_tick
CREATE OR REPLACE FUNCTION public.cw_ai_contracts_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare ct public.cw_contracts;d date;own text;wage bigint;payroll bigint;revenue bigint;cash bigint;inactive boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_recover_ai_free_players(p_career);
 for ct in select x.* from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.status='active' and not x.computed and x.club_id is distinct from own and x.expires_on<=d+45
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
  order by x.club_id,x.player_id loop
  inactive:=public.cw_runtime_enabled(p_career) and ct.club_id not in(select public.cw_domestic_clubs(p_career));
  if inactive then
   -- Dormant leagues retain their clubs; no salary, cash, results or market simulation is advanced there.
   if ct.expires_on<d then update public.cw_contracts set expires_on=ct.expires_on+make_interval(years=>greatest(2,ceil((d-ct.expires_on)/365.0)::int+2)) where id=ct.id and career_id=ct.career_id;end if;
   continue;
  end if;
  wage:=greatest(ct.monthly_salary,public.cw_salary_floor(ct.player_id));
  select c.monthly_revenue,c.cash-c.debt-public.cw_reserved(p_career,ct.club_id) into revenue,cash from public.cw_clubs c where c.career_id=p_career and c.club_id=ct.club_id and c.financial_risk<75;
  payroll:=public.cw_payroll(p_career,ct.club_id);
  if revenue is not null and cash>=2*payroll+6*greatest(0,wage-ct.monthly_salary)
   and payroll-ct.monthly_salary+wage<=revenue
   and((select r.rating>=80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=ct.player_id)
    or coalesce((select morale from public.cw_players where career_id=p_career and player_id=ct.player_id),65)>=35) then
   update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id and career_id=ct.career_id;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
    values(p_career,ct.player_id,ct.club_id,d,d+730,wage,ct.appearance_bonus,ct.goal_bonus,ct.role);
  end if;
 end loop;
end $function$;
-- Contratos do clube do técnico são sempre linhas reais: vencem e precisam ser renovados por ele.
create or replace function public.cw_materialize_own_contracts(p_career uuid) returns integer
language plpgsql security definer set search_path=public as $$
declare own text;n int;
begin
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is null or not public.cw_is_hybrid(p_career) then return 0;end if;
 insert into public.cw_contract_rows(id,career_id,player_id,club_id,starts_on,expires_on,ended_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role,status,arrears)
 select c.id,c.career_id,c.player_id,c.club_id,c.starts_on,c.expires_on,c.ended_on,c.monthly_salary,c.signing_bonus,c.appearance_bonus,c.goal_bonus,c.role,c.status,c.arrears
 from public.cw_contracts c where c.career_id=p_career and c.club_id=own and c.computed
 on conflict do nothing;
 get diagnostics n=row_count;
 return n;
end $$;
create or replace function public.cw_coach_club_trg() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.club_id is not null and (tg_op='INSERT' or new.club_id is distinct from old.club_id or new.status is distinct from old.status) then
  perform public.cw_materialize_own_contracts(new.career_id);
 end if;
 return null;
end $$;
drop trigger if exists cw_coach_club on public.mgr_coach;
create trigger cw_coach_club after insert or update of club_id,status on public.mgr_coach for each row execute function public.cw_coach_club_trg();

-- cw_initialize_finances
CREATE OR REPLACE FUNCTION public.cw_initialize_finances(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 public.cw_commercial_income(c.id),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.club_id=c.id) on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and not exists(select 1 from public.cw_players x where x.career_id=p_career and x.player_id=p.id);
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 perform public.cw_materialize_own_contracts(p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(public.cw_salary_floor(mp.player_id),round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' and not exists(select 1 from public.cw_runtime where career_id=p_career) loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

-- cw_recover_club
CREATE OR REPLACE FUNCTION public.cw_recover_club(p_career uuid, p_club text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare day int;start_day int;own text;
begin
 select w.elapsed_days,coalesce(r.last_recovery_day,w.elapsed_days) into day,start_day
 from public.cw_world w left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 if public.cw_is_hybrid(p_career) then
  select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
  if p_club is not distinct from own then
   -- Elenco do técnico: sempre com linha própria, para condição e ritmo evoluírem dia a dia.
   insert into public.mgr_player_rows(career_id,player_id,club_id,condition,rhythm)
   select mp.career_id,mp.player_id,mp.club_id,mp.condition,mp.rhythm from public.mgr_players mp where mp.career_id=p_career and mp.club_id=p_club
   on conflict do nothing;
   update public.mgr_player_rows p set
    condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
    rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no from public.mgr_player_rows r left join public.cw_player_clock pc using(career_id,player_id)
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
  else
   -- Clube da IA: quem tem linha volta ao padrão (condição 100, ritmo padrão) e, sem outra diferença, a linha sai.
   update public.mgr_player_rows p set
    condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
    rhythm=case when p.rhythm<c.base then least(c.base,p.rhythm+.4*greatest(0,day-coalesce(c.day_no,start_day)))
     else greatest(c.base,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))) end,
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no,case when sp.is_youth then 50 else 70 end base from public.mgr_player_rows r
    join public.sim_players sp on sp.id=r.player_id left join public.cw_player_clock pc using(career_id,player_id)
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
   delete from public.mgr_player_rows r using public.sim_players sp
   where r.career_id=p_career and r.club_id=p_club and not r.removed and sp.id=r.player_id and sp.career_id is null and sp.active
    and sp.club_id=r.club_id and r.condition=100 and r.rhythm=(case when sp.is_youth then 50 else 70 end)
    and r.injured_until is null and r.injury is null and r.susp='{}'::jsonb and r.yellows='{}'::jsonb
    and exists(select 1 from public.cw_world_clubs wc where wc.career_id=p_career and wc.club_id=r.club_id)
    and not exists(select 1 from public.cw_contract_rows ct where ct.career_id=p_career and ct.player_id=r.player_id and ct.club_id is distinct from r.club_id and ct.status='active');
   delete from public.cw_player_clock k where k.career_id=p_career
    and not exists(select 1 from public.mgr_player_rows r where r.career_id=p_career and r.player_id=k.player_id);
  end if;
  insert into public.cw_player_clock(career_id,player_id,day_no)
  select p_career,player_id,day from public.mgr_player_rows where career_id=p_career and club_id=p_club and not removed
  on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
  return;
 end if;
 update public.mgr_players p set
 condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
 rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
 injury=case when p.injured_until<=day then null else p.injury end,
 injured_until=case when p.injured_until<=day then null else p.injured_until end
 from (select mp.player_id,pc.day_no from public.mgr_players mp left join public.cw_player_clock pc using(career_id,player_id)
 where mp.career_id=p_career and mp.club_id=p_club)c
 where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
 insert into public.cw_player_clock(career_id,player_id,day_no)
 select p_career,player_id,day from public.mgr_players where career_id=p_career and club_id=p_club
 on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
end $function$;
-- Melhor XI disponível de um clube (goleiro + 10 de linha), lido do catálogo com as diferenças da carreira.
create or replace function public.cw_club_xi(p_career uuid,p_club text,p_comp text,p_day int)
returns table(player_id text,pos text,eff numeric)
language sql stable security definer set search_path=public as $$
 select x.player_id,x.pos,x.eff from(
  select mp.player_id,sp.position pos,r.eff+coalesce((d.pos->sp.position->>1)::numeric,0) eff,
   row_number() over(partition by sp.position='GOL' order by r.eff+coalesce((d.pos->sp.position->>1)::numeric,0) desc,mp.player_id) rn
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  left join public.cw_player_dev d on d.career_id=mp.career_id and d.player_id=mp.player_id
  where mp.career_id=p_career and mp.club_id=p_club and (mp.injured_until is null or mp.injured_until<=p_day)
   and coalesce((mp.susp->>p_comp)::int,0)=0)x
 where (x.pos='GOL' and x.rn=1) or (x.pos<>'GOL' and x.rn<=10)
$$;
create or replace function public.cw_club_strength(p_career uuid,p_club text,p_comp text,p_day int) returns numeric
language sql stable security definer set search_path=public as $$
 select coalesce(round(avg(eff),1),60) from public.cw_club_xi(p_career,p_club,p_comp,p_day)
$$;
-- Partida entre dois clubes da IA, só placar (carreira híbrida).
-- Grava: placar, pênaltis e classificado em season_fixtures; súmula curta (gols) em stats;
-- gols e assistências em mgr_player_stats; cartões do clube em season_card_totals.
-- Não cria mgr_matches, mgr_match_players, eventos nem atuações; atletas da IA não mudam de estado.
create or replace function public.cw_ai_shootout(p_seed text) returns integer[]
language plpgsql immutable as $$
declare h int:=0;a int:=0;i int:=1;
begin
 while i<=5 loop
  h:=h+(public.cw_random(p_seed||':pk:h:'||i)<.75)::int;
  a:=a+(public.cw_random(p_seed||':pk:a:'||i)<.75)::int;
  exit when h>a+(5-i) or a>h+(5-i);
  i:=i+1;
 end loop;
 i:=6;
 while h=a and i<=30 loop
  h:=h+(public.cw_random(p_seed||':pk:h:'||i)<.75)::int;
  a:=a+(public.cw_random(p_seed||':pk:a:'||i)<.75)::int;
  i:=i+1;
 end loop;
 if h=a then h:=h+1;end if;
 return array[h,a];
end $$;

create or replace function public.cw_sim_ai_fixture(p_fixture bigint,p_career uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f public.season_fixtures;s public.career_seasons;fst public.season_fixtures;rules jsonb;ph jsonb;seed text;
 neutral boolean;dec boolean;et_rule boolean;tie_rule text;agg_h int:=0;agg_a int:=0;sh numeric;sa numeric;
 h int;a int;et boolean:=false;dur int:=90;pens int[];winner text;possession int;
 side text;club text;n int;i int;xi text[];att text[];scorer text;helper text;minute int;
 goals jsonb:='[]';contrib jsonb:='{}';yel int[]:=array[0,0];red int[]:=array[0,0];k text;
begin
 select * into f from public.season_fixtures where id=p_fixture for update;
 if not found then raise exception 'Partida inexistente';end if;
 if f.status='played' then return;end if;
 select * into s from public.career_seasons where id=f.season_id and career_id=p_career;
 if not found then raise exception 'Partida fora da carreira';end if;
 select rules into rules from public.sim_competitions where id=f.competition_id;
 ph:=public.sim_phase(f.competition_id,f.stage);
 if ph is not null then
  neutral:=coalesce((ph->>'neutral')::boolean,false);
  dec:=ph->>'type'='knockout' and (coalesce((ph->>'legs')::int,1)=1 or f.leg=2);
 else
  neutral:=(f.stage='final');
  dec:=f.stage in('r16','qf','sf','final') and (f.stage='final' or f.leg=2);
 end if;
 if dec and coalesce(f.leg,1)=2 then
  select * into fst from public.season_fixtures where season_id=f.season_id and competition_id=f.competition_id and stage=f.stage and tie_no=f.tie_no and leg=1;
  agg_h:=case when fst.home_club=f.home_club then coalesce(fst.home_goals,0) else coalesce(fst.away_goals,0) end;
  agg_a:=case when fst.home_club=f.away_club then coalesce(fst.home_goals,0) else coalesce(fst.away_goals,0) end;
 end if;
 et_rule:=dec and case when ph is not null then coalesce((ph->>'extra_time')::boolean,false)
  else f.stage='final' and coalesce((rules->>'final_extra_time')::boolean,false) end;
 tie_rule:=coalesce(ph->>'tie','penalties');

 sh:=public.cw_club_strength(p_career,f.home_club,f.competition_id,s.day_no);
 sa:=public.cw_club_strength(p_career,f.away_club,f.competition_id,s.day_no);
 select r.seed::text||':'||p_fixture||':v2' into seed from public.cw_runtime r where r.career_id=p_career;
 possession:=greatest(30,least(70,round(50+(sh-sa)*.6+(public.cw_random(seed||':possession')-.5)*12)::int));
 h:=public.cw_poisson((case when neutral then 1.25 else 1.4 end)*exp(.022*(sh-sa)),seed||':home');
 a:=public.cw_poisson((case when neutral then 1.25 else 1.05 end)*exp(.022*(sa-sh)),seed||':away');
 if et_rule and h+agg_h=a+agg_a then
  et:=true;dur:=120;
  h:=h+public.cw_poisson(.42*exp(.022*(sh-sa)),seed||':extra-home');
  a:=a+public.cw_poisson(.35*exp(.022*(sa-sh)),seed||':extra-away');
 end if;
 if dec then
  if h+agg_h=a+agg_a and tie_rule='higher_seed' then winner:=f.home_club;
  elsif h+agg_h=a+agg_a then
   pens:=public.cw_ai_shootout(seed);
   winner:=case when pens[1]>pens[2] then f.home_club else f.away_club end;
  else winner:=case when h+agg_h>a+agg_a then f.home_club else f.away_club end;
  end if;
 end if;

 foreach side in array array['h','a'] loop
  club:=case when side='h' then f.home_club else f.away_club end;
  n:=case when side='h' then h else a end;
  select array_agg(x.player_id order by x.player_id),array_agg(x.player_id order by x.player_id) filter(where x.pos<>'GOL')
   into xi,att from public.cw_club_xi(p_career,club,f.competition_id,s.day_no) x;
  if att is null then continue;end if;
  for i in 1..n loop
   select p into scorer from unnest(att) p join public.sim_players sp on sp.id=p
    order by public.cw_random(seed||':goal:'||side||':'||i||':'||p)*case when sp.position in('ATA','PD','PE','MEI') then 3 else 1 end desc,p limit 1;
   helper:=null;
   if public.cw_random(seed||':assist-chance:'||side||':'||i)<.72 then
    select p into helper from unnest(att) p join public.sim_players sp on sp.id=p where p<>scorer
     order by public.cw_random(seed||':assist:'||side||':'||i||':'||p)*case when sp.position in('PD','PE','MEI','MC') then 2 else 1 end desc,p limit 1;
   end if;
   minute:=1+floor(public.cw_random(seed||':minute:'||side||':'||i)*(dur-1))::int;
   goals:=goals||jsonb_build_array(jsonb_build_array(minute,side,scorer,helper));
   contrib:=jsonb_set(contrib,array[scorer],coalesce(contrib->scorer,jsonb_build_object('c',club,'g',0,'a',0))||jsonb_build_object('g',coalesce((contrib->scorer->>'g')::int,0)+1));
   if helper is not null then
    contrib:=jsonb_set(contrib,array[helper],coalesce(contrib->helper,jsonb_build_object('c',club,'g',0,'a',0))||jsonb_build_object('a',coalesce((contrib->helper->>'a')::int,0)+1));
   end if;
  end loop;
  yel[case when side='h' then 1 else 2 end]:=1+floor(public.cw_random(seed||':cards:'||side)*3)::int;
  red[case when side='h' then 1 else 2 end]:=(public.cw_random(seed||':red-chance:'||side)<.015)::int;
 end loop;

 for k in select jsonb_object_keys(contrib) loop
  insert into public.mgr_player_stats as ps(season_id,player_id,competition_id,club_id,apps,starts,minutes,goals,assists,yellows,reds,rating_sum,motm)
  values(f.season_id,k,f.competition_id,contrib->k->>'c',1,1,dur,(contrib->k->>'g')::int,(contrib->k->>'a')::int,0,0,
   least(10,6.5+(contrib->k->>'g')::int+.5*(contrib->k->>'a')::int),0)
  on conflict(season_id,player_id,competition_id) do update set apps=ps.apps+1,starts=ps.starts+1,minutes=ps.minutes+excluded.minutes,
   goals=ps.goals+excluded.goals,assists=ps.assists+excluded.assists,rating_sum=ps.rating_sum+excluded.rating_sum,club_id=excluded.club_id;
 end loop;

 if f.stage in('league','group') then
  insert into public.season_card_totals as t(season_id,competition_id,group_label,club_id,yellows,reds)
  values(f.season_id,f.competition_id,coalesce(f.group_label,''),f.home_club,yel[1],red[1]),
        (f.season_id,f.competition_id,coalesce(f.group_label,''),f.away_club,yel[2],red[2])
  on conflict(season_id,competition_id,group_label,club_id) do update set yellows=t.yellows+excluded.yellows,reds=t.reds+excluded.reds;
 end if;

 update public.season_fixtures set home_goals=h,away_goals=a,status='played',played_at=now(),day_no=s.day_no,extra_time=et,
  home_pens=case when pens is not null then pens[1] end,away_pens=case when pens is not null then pens[2] end,
  tie_winner=coalesce(winner,tie_winner),player_match=false,coach_club=null,
  stats=jsonb_build_object('simulation','score','algorithm',2,'poss',jsonb_build_array(possession,100-possession),
   'yellows',to_jsonb(yel),'reds',to_jsonb(red),'goals',goals)
 where id=p_fixture;
end $$;

-- mgr_sim_fixture
CREATE OR REPLACE FUNCTION public.mgr_sim_fixture(p_fixture bigint, p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.season_fixtures;m public.mgr_matches;seed text;h int;a int;i int;v_side char;scorer text;helper text;yb int;extra_shots int;extra_sot int;extra_fouls int;possession int;
 sh numeric;sa numeric;neutral boolean;minute int;duration int:=90;et boolean:=false;
begin
 if not public.cw_runtime_enabled(p_career) then perform public.mgr_sim_fixture_before_v45(p_fixture,p_career);return;end if;
 -- Carreira híbrida: jogo da IA grava só o placar e os totais.
 if public.cw_is_hybrid(p_career) then perform public.cw_sim_ai_fixture(p_fixture,p_career);return;end if;
 select * into f from public.season_fixtures where id=p_fixture for update;
 if not found or not exists(select 1 from public.career_seasons where id=f.season_id and career_id=p_career) then raise exception 'Partida fora da carreira';end if;
 if f.status='played' then return;end if;
 if exists(select 1 from public.cw_world w join public.mgr_coach c using(career_id) where w.career_id=p_career and w.primary_season=f.season_id and c.status='employed' and c.club_id in(f.home_club,f.away_club)) then raise exception 'A partida do treinador exige intervenção';end if;
 if exists(select 1 from public.mgr_matches where fixture_id=p_fixture and user_side is not null) then raise exception 'Partida do usuário preservada';end if;
 perform public.mgr_match_create(p_fixture,p_career,null,null);
 select * into m from public.mgr_matches where fixture_id=p_fixture;
 select r.seed::text||':'||p_fixture||':v1' into seed from public.cw_runtime r where r.career_id=p_career;
 sh:=(m.state->'strength'->>0)::numeric;sa:=(m.state->'strength'->>1)::numeric;
 neutral:=coalesce((m.state->>'neutral')::boolean,false);
 possession:=greatest(30,least(70,round(50+(sh-sa)*.6+(public.cw_random(seed||':possession')-.5)*12)::int));
 h:=public.cw_poisson((case when neutral then 1.25 else 1.4 end)*exp(.022*(sh-sa)),seed||':home');
 a:=public.cw_poisson((case when neutral then 1.25 else 1.05 end)*exp(.022*(sa-sh)),seed||':away');
 et:=coalesce((m.state->>'extra_time_rule')::boolean,false) and h+coalesce((m.state->'agg'->>0)::int,0)=a+coalesce((m.state->'agg'->>1)::int,0);
 if et then
  duration:=120;
  h:=h+public.cw_poisson(.42*exp(.022*(sh-sa)),seed||':extra-home');
  a:=a+public.cw_poisson(.35*exp(.022*(sa-sh)),seed||':extra-away');
 end if;
 update public.mgr_matches set state=state||jsonb_build_object('summary_seed',seed,'et',et) where fixture_id=p_fixture;
 update public.mgr_match_players set minutes=case when status='on' then duration else 0 end,
 cond=case when status='on' then greatest(15,cond-.2*duration) else cond end where fixture_id=p_fixture;
 foreach v_side in array array['h'::char,'a'::char] loop
  for i in 1..case when v_side='h' then h else a end loop
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and mgr_match_players.side=v_side and status='on'
   order by public.cw_random(seed||':goal:'||v_side||':'||i||':'||player_id)*case when pos in('ATA','PD','PE','MEI') then 3 else 1 end desc,player_id limit 1;
   minute:=1+floor(public.cw_random(seed||':minute:'||v_side||':'||i)*89)::int;
   update public.mgr_match_players set goals=goals+1,shots=shots+1,sot=sot+1 where fixture_id=p_fixture and player_id=scorer;
   helper:=null;
   if public.cw_random(seed||':assist-chance:'||v_side||':'||i)<.72 then
    select player_id into helper from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on' and player_id<>scorer and pos<>'GOL'
    order by public.cw_random(seed||':assist:'||v_side||':'||i||':'||player_id)*case when pos in('PD','PE','MEI','MC') then 2 else 1 end desc,player_id limit 1;
    update public.mgr_match_players set assists=assists+1 where fixture_id=p_fixture and player_id=helper;
   end if;
   perform public.mgr_event(p_fixture,minute,v_side,'goal',scorer,helper,'Gol');
  end loop;
  yb:=1+floor(public.cw_random(seed||':cards:'||v_side)*3)::int;
  for i in 1..yb loop
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and mgr_match_players.side=v_side and status='on' and yellow=0
   order by public.cw_random(seed||':yellow:'||v_side||':'||i||':'||player_id),player_id limit 1;
   update public.mgr_match_players set yellow=1,fouls=fouls+1 where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,10+i*20,v_side,'yellow',scorer,null,'Cartão amarelo');
  end loop;
  extra_shots:=public.cw_poisson(9.0*duration/90,seed||':shots:'||v_side);
  extra_sot:=floor(extra_shots*(.25+.2*public.cw_random(seed||':sot:'||v_side)))::int;
  extra_fouls:=public.cw_poisson(10.0*duration/90,seed||':fouls:'||v_side);
  with ranked as(select player_id,row_number() over(order by case when pos in('ATA','PD','PE','MEI') then 0 else 1 end,player_id) rn,count(*) over() n
   from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on' and pos<>'GOL')
  update public.mgr_match_players mp set shots=shots+extra_shots/ranked.n+(ranked.rn<=extra_shots%ranked.n)::int,
   sot=sot+extra_sot/ranked.n+(ranked.rn<=extra_sot%ranked.n)::int,
   fouls=fouls+extra_fouls/ranked.n+(ranked.rn<=extra_fouls%ranked.n)::int
  from ranked where mp.fixture_id=p_fixture and mp.player_id=ranked.player_id;
  -- Sparse discipline/injury events, rather than minute-by-minute engine writes.
  if public.cw_random(seed||':red-chance:'||v_side)<.015 then
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on'
   order by public.cw_random(seed||':red:'||player_id),player_id limit 1;
   minute:=20+floor(public.cw_random(seed||':red-minute:'||v_side)*(duration-20))::int;
   update public.mgr_match_players set red=1,status='sent_off',left_min=minute,minutes=minute,slot=null where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,minute,v_side,'red',scorer,null,'Cartão vermelho');
  end if;
  if public.cw_random(seed||':injury-chance:'||v_side)<.05 then
   select player_id into scorer from public.mgr_match_players where fixture_id=p_fixture and side=v_side and status='on'
   order by public.cw_random(seed||':injury:'||player_id),player_id limit 1;
   minute:=20+floor(public.cw_random(seed||':injury-minute:'||v_side)*(duration-20))::int;
   update public.mgr_match_players set injured=true,status='injured_off',left_min=minute,minutes=minute,slot=null where fixture_id=p_fixture and player_id=scorer;
   perform public.mgr_event(p_fixture,minute,v_side,'injury',scorer);
  end if;
 end loop;
 update public.mgr_match_players g set saves=(select greatest(0,coalesce(sum(sot-goals),0)) from public.mgr_match_players p where p.fixture_id=p_fixture and p.side<>g.side)
 where g.fixture_id=p_fixture and g.pos='GOL' and g.starter;
 update public.mgr_matches set minute=duration,state=state||jsonb_build_object('score',jsonb_build_array(h,a),'poss',jsonb_build_array(possession,100-possession),'corners',jsonb_build_array(public.cw_poisson(4.5,seed||':corners:h'),public.cw_poisson(4,seed||':corners:a')),'offsides',jsonb_build_array(public.cw_poisson(1.5,seed||':offside:h'),public.cw_poisson(1.5,seed||':offside:a'))) where fixture_id=p_fixture;
 -- Existing finalization owns ties, penalties, discipline, totals, bonuses and appearances.
 perform public.mgr_match_finish(p_fixture);
 update public.season_fixtures set stats=stats||jsonb_build_object('simulation','summary','algorithm',1) where id=p_fixture;
 delete from public.mgr_matches where fixture_id=p_fixture and user_side is null and status='finished';
end $function$;

-- cw_sim_ai_fixture
CREATE OR REPLACE FUNCTION public.cw_sim_ai_fixture(p_fixture bigint, p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare f public.season_fixtures;s public.career_seasons;fst public.season_fixtures;rules jsonb;ph jsonb;seed text;
 neutral boolean;dec boolean;et_rule boolean;tie_rule text;agg_h int:=0;agg_a int:=0;sh numeric;sa numeric;
 h int;a int;et boolean:=false;dur int:=90;pens int[];winner text;possession int;
 side text;club text;n int;i int;xi text[];att text[];scorer text;helper text;minute int;
 goals jsonb:='[]';contrib jsonb:='{}';yel int[]:=array[0,0];red int[]:=array[0,0];k text;
begin
 select * into f from public.season_fixtures where id=p_fixture for update;
 if not found then raise exception 'Partida inexistente';end if;
 if f.status='played' then return;end if;
 select * into s from public.career_seasons where id=f.season_id and career_id=p_career;
 if not found then raise exception 'Partida fora da carreira';end if;
 if exists(select 1 from public.cw_world w join public.mgr_coach c using(career_id) where w.career_id=p_career and w.primary_season=f.season_id and c.status='employed' and c.club_id in(f.home_club,f.away_club)) then raise exception 'A partida do treinador exige intervenção';end if;
 if exists(select 1 from public.mgr_matches where fixture_id=p_fixture and user_side is not null) then raise exception 'Partida do usuário preservada';end if;
 select rules into rules from public.sim_competitions where id=f.competition_id;
 ph:=public.sim_phase(f.competition_id,f.stage);
 if ph is not null then
  neutral:=coalesce((ph->>'neutral')::boolean,false);
  dec:=ph->>'type'='knockout' and (coalesce((ph->>'legs')::int,1)=1 or f.leg=2);
 else
  neutral:=(f.stage='final');
  dec:=f.stage in('r16','qf','sf','final') and (f.stage='final' or f.leg=2);
 end if;
 if dec and coalesce(f.leg,1)=2 then
  select * into fst from public.season_fixtures where season_id=f.season_id and competition_id=f.competition_id and stage=f.stage and tie_no=f.tie_no and leg=1;
  agg_h:=case when fst.home_club=f.home_club then coalesce(fst.home_goals,0) else coalesce(fst.away_goals,0) end;
  agg_a:=case when fst.home_club=f.away_club then coalesce(fst.home_goals,0) else coalesce(fst.away_goals,0) end;
 end if;
 et_rule:=dec and case when ph is not null then coalesce((ph->>'extra_time')::boolean,false)
  else f.stage='final' and coalesce((rules->>'final_extra_time')::boolean,false) end;
 tie_rule:=coalesce(ph->>'tie','penalties');

 sh:=public.cw_club_strength(p_career,f.home_club,f.competition_id,s.day_no);
 sa:=public.cw_club_strength(p_career,f.away_club,f.competition_id,s.day_no);
 select r.seed::text||':'||p_fixture||':v2' into seed from public.cw_runtime r where r.career_id=p_career;
 possession:=greatest(30,least(70,round(50+(sh-sa)*.6+(public.cw_random(seed||':possession')-.5)*12)::int));
 h:=public.cw_poisson((case when neutral then 1.25 else 1.4 end)*exp(.022*(sh-sa)),seed||':home');
 a:=public.cw_poisson((case when neutral then 1.25 else 1.05 end)*exp(.022*(sa-sh)),seed||':away');
 if et_rule and h+agg_h=a+agg_a then
  et:=true;dur:=120;
  h:=h+public.cw_poisson(.42*exp(.022*(sh-sa)),seed||':extra-home');
  a:=a+public.cw_poisson(.35*exp(.022*(sa-sh)),seed||':extra-away');
 end if;
 if dec then
  if h+agg_h=a+agg_a and tie_rule='higher_seed' then winner:=f.home_club;
  elsif h+agg_h=a+agg_a then
   pens:=public.cw_ai_shootout(seed);
   winner:=case when pens[1]>pens[2] then f.home_club else f.away_club end;
  else winner:=case when h+agg_h>a+agg_a then f.home_club else f.away_club end;
  end if;
 end if;

 foreach side in array array['h','a'] loop
  club:=case when side='h' then f.home_club else f.away_club end;
  n:=case when side='h' then h else a end;
  select array_agg(x.player_id order by x.player_id),array_agg(x.player_id order by x.player_id) filter(where x.pos<>'GOL')
   into xi,att from public.cw_club_xi(p_career,club,f.competition_id,s.day_no) x;
  if att is null then continue;end if;
  for i in 1..n loop
   select p into scorer from unnest(att) p join public.sim_players sp on sp.id=p
    order by public.cw_random(seed||':goal:'||side||':'||i||':'||p)*case when sp.position in('ATA','PD','PE','MEI') then 3 else 1 end desc,p limit 1;
   helper:=null;
   if public.cw_random(seed||':assist-chance:'||side||':'||i)<.72 then
    select p into helper from unnest(att) p join public.sim_players sp on sp.id=p where p<>scorer
     order by public.cw_random(seed||':assist:'||side||':'||i||':'||p)*case when sp.position in('PD','PE','MEI','MC') then 2 else 1 end desc,p limit 1;
   end if;
   minute:=1+floor(public.cw_random(seed||':minute:'||side||':'||i)*(dur-1))::int;
   goals:=goals||jsonb_build_array(jsonb_build_array(minute,side,scorer,helper));
   contrib:=jsonb_set(contrib,array[scorer],coalesce(contrib->scorer,jsonb_build_object('c',club,'g',0,'a',0))||jsonb_build_object('g',coalesce((contrib->scorer->>'g')::int,0)+1));
   if helper is not null then
    contrib:=jsonb_set(contrib,array[helper],coalesce(contrib->helper,jsonb_build_object('c',club,'g',0,'a',0))||jsonb_build_object('a',coalesce((contrib->helper->>'a')::int,0)+1));
   end if;
  end loop;
  yel[case when side='h' then 1 else 2 end]:=1+floor(public.cw_random(seed||':cards:'||side)*3)::int;
  red[case when side='h' then 1 else 2 end]:=(public.cw_random(seed||':red-chance:'||side)<.015)::int;
 end loop;

 for k in select jsonb_object_keys(contrib) loop
  insert into public.mgr_player_stats as ps(season_id,player_id,competition_id,club_id,apps,starts,minutes,goals,assists,yellows,reds,rating_sum,motm)
  values(f.season_id,k,f.competition_id,contrib->k->>'c',1,1,dur,(contrib->k->>'g')::int,(contrib->k->>'a')::int,0,0,
   least(10,6.5+(contrib->k->>'g')::int+.5*(contrib->k->>'a')::int),0)
  on conflict(season_id,player_id,competition_id) do update set apps=ps.apps+1,starts=ps.starts+1,minutes=ps.minutes+excluded.minutes,
   goals=ps.goals+excluded.goals,assists=ps.assists+excluded.assists,rating_sum=ps.rating_sum+excluded.rating_sum,club_id=excluded.club_id;
 end loop;

 if f.stage in('league','group') then
  insert into public.season_card_totals as t(season_id,competition_id,group_label,club_id,yellows,reds)
  values(f.season_id,f.competition_id,coalesce(f.group_label,''),f.home_club,yel[1],red[1]),
        (f.season_id,f.competition_id,coalesce(f.group_label,''),f.away_club,yel[2],red[2])
  on conflict(season_id,competition_id,group_label,club_id) do update set yellows=t.yellows+excluded.yellows,reds=t.reds+excluded.reds;
 end if;

 update public.season_fixtures set home_goals=h,away_goals=a,status='played',played_at=now(),day_no=s.day_no,extra_time=et,
  home_pens=case when pens is not null then pens[1] end,away_pens=case when pens is not null then pens[2] end,
  tie_winner=coalesce(winner,tie_winner),player_match=false,coach_club=null,
  stats=jsonb_build_object('simulation','score','algorithm',2,'poss',jsonb_build_array(possession,100-possession),
   'yellows',to_jsonb(yel),'reds',to_jsonb(red),'goals',goals)
 where id=p_fixture;
end $function$;

-- cw_market_tick_before_v37
CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or player_id in(select player_id from public.mgr_players where career_id=p_career and club_id in (select public.cw_domestic_clubs(p_career))));end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 for id in select x.id from public.cw_negotiations x where x.career_id=p_career and x.status='player_accepted' and x.expires_on<d loop
  perform public.cw_neg_close(id,'expired','O prazo para confirmar terminou e o atleta seguiu outro caminho.');
 end loop;
 for n in select * from public.cw_negotiations where career_id=p_career and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') order by created_on,id for update loop
  if n.status in('agreed','precontract') then perform public.cw_register_transfer(n.id);continue;end if;
  if n.expires_on<d then perform public.cw_neg_close(n.id,'expired','Prazo da proposta encerrado.');continue;end if;
  if n.reply_on>d or n.status in('seller_review','club_counter','player_counter') then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into buyer from public.cw_clubs where career_id=p_career and club_id=n.buyer_club;
  select * into seller from public.cw_clubs where career_id=p_career and club_id=n.seller_club;
  if n.status='club_pending' then
   select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=n.seller_club;
   threshold:=n.valuation*(case when seller.financial_risk>=50 then .85 else 1.05 end)+n.valuation*case when ct.role='key' then .35 else .05 end;
   threshold:=threshold*(.9+n.decision_roll*.3)*case when ct.expires_on<d+180 then .65 else 1 end;
   if exists(select 1 from public.cw_rivalries rv where rv.club_a=least(n.buyer_club,n.seller_club) and rv.club_b=greatest(n.buyer_club,n.seller_club)) then threshold:=threshold*1.12;end if;
   threshold:=threshold*(1+least(.20,.04*(select count(*) from public.cw_negotiations z where z.career_id=p_career and z.player_id=n.player_id and z.id<>n.id and z.status in('club_pending','player_pending','seller_review'))));
   if n.seller_club is null or n.register_on>coalesce(ct.expires_on,d+999) then threshold:=0;end if;
   if (cnt<=18 and threshold>0) or n.decision_roll<.04 then
    perform public.cw_neg_close(n.id,'rejected','O clube considera o atleta indispensável ou não tem reposição.');
   elsif n.fee+n.performance_bonus*.5<threshold then
    if n.round_no>=2 or n.fee<threshold*.55 then perform public.cw_neg_close(n.id,'rejected','Os valores não atendem à avaliação do clube.');
    else
     update public.cw_negotiations set status='club_counter',fee=ceil(threshold),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O clube pede uma revisão do valor.' where id=n.id;
     if n.initiator='ai' then perform public.cw_neg_close(n.id,'rejected','O comprador desistiu da contraproposta.');else perform public.cw_neg_history(n.id,'seller','Contraproposta do clube vendedor.');end if;
    end if;
   else
    update public.cw_negotiations set status='player_counter',response='Clube de acordo. Apresente salário, duração, luvas e papel ao atleta.',expires_on=public.cw_deadline(d) where id=n.id;
    if n.initiator='ai' then
     update public.cw_negotiations set status='player_pending',monthly_salary=public.cw_salary_demand(p_career,n.player_id,n.buyer_club),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
    end if;
    perform public.cw_neg_history(n.id,'seller','Condições entre clubes aprovadas.');
   end if;
  elsif n.status='player_pending' then
   interest:=coalesce(public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role),greatest(40,n.valuation*.0065))*case when buyer.prestige>=coalesce(seller.prestige,0)+5 then 1.02 else 1.12 end;
   interest:=interest*(1+greatest(0,coalesce(seller.prestige,0)-buyer.prestige)*.015);
   interest:=interest*case when (select morale from public.cw_players where career_id=p_career and player_id=n.player_id)<35 and n.initiator='renewal' then 1.35 else 1 end;
   interest:=interest*case when n.role='prospect' and coalesce(ct.role,'rotation') in('key','starter') then 1.35 else 1 end;
   if n.decision_roll<.06 and buyer.prestige<coalesce(seller.prestige,0) then
    perform public.cw_neg_close(n.id,'rejected','O atleta recusou o projeto esportivo, independentemente da remuneração.');continue;
   end if;
   if (public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)+n.signing_bonus/greatest(12*n.contract_years,1))<interest then
    if n.round_no>=3 or n.monthly_salary<interest*.65 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou salário, papel ou projeto esportivo.');
    else update public.cw_negotiations set status='player_counter',monthly_salary=ceil(interest),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta pede melhores condições salariais.' where id=n.id;perform public.cw_neg_history(n.id,'player','Contraproposta salarial do atleta.');end if;
   elsif exists(select 1 from public.cw_negotiations where career_id=p_career and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
    perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
   else
    if n.buyer_club=own and n.initiator in('user','renewal') then
     update public.cw_negotiations set status='player_accepted',expires_on=public.cw_deadline(d),
      response=format('Aceito sua oferta de %s por semana por %s ano(s). Se estiver de acordo, confirme e meu agente cuida da papelada.',public.cw_money_label(public.cw_weekly(n.monthly_salary)),n.contract_years) where id=n.id;
     perform public.cw_neg_history(n.id,'player','O atleta aceitou; aguardando a confirmação do treinador.');
     continue;
    end if;
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,d) where id=n.id;
     perform public.cw_neg_history(n.id,'player','Condições do atleta aprovadas.');perform public.cw_register_transfer(n.id);
    exception when raise_exception then perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);end;
   end if;
  end if;
 end loop;
 -- Scheduled transfer liabilities are paid once; performance clauses require ten actual appearances.
 for r in select cm.*,n.player_id,n.seller_club,n.register_on from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
  where cm.career_id=p_career and cm.status='reserved' and n.status='completed' and cm.kind in('installment','performance') order by cm.due_on,cm.id loop
  if r.kind='performance' then
   select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=r.player_id and mp.club_id=r.club_id and mp.minutes>0 and mp.on_date>=r.register_on;
   if apps<10 and d<r.due_on then continue;end if;
   if apps<10 then update public.cw_commitments set status='released' where id=r.id;continue;end if;
  elsif r.due_on>d then continue;end if;
  perform public.cw_cash(p_career,r.club_id,-r.amount,'transfer_clause',r.id::text,'Parcela ou bônus da contratação',true);
  if r.seller_club is not null then perform public.cw_cash(p_career,r.seller_club,r.amount,'player_sale_clause',r.id::text,'Recebimento de parcela ou bônus');end if;
  update public.cw_commitments set status='paid' where id=r.id;
 end loop;
 -- Moral (CM17) em lote: mesma regra de cw_cm_morale_next, calculada uma vez por clube em vez de por atleta.
 update public.cw_players xcp set last_morale_on=d
  from public.mgr_players xmp, public.cw_contracts xct
  where xcp.career_id=p_career and xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
   and xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active' and d-xct.starts_on<28
   and (xmp.club_id=own or (not public.cw_is_hybrid(p_career) and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)))))
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7);
 with m_elig as materialized(
  select distinct on (xcp.player_id) xcp.player_id m_player,xcp.morale m_morale,xmp.club_id m_club,xct.arrears m_arrears
  from public.cw_players xcp join public.mgr_players xmp on xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
  join public.cw_contracts xct on xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active'
  where xcp.career_id=p_career and (xmp.club_id=own or (not public.cw_is_hybrid(p_career) and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)))))
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7) and d-xct.starts_on>=28
  order by xcp.player_id),
 m_clubs as materialized(select distinct m_club from m_elig),
 m_res as(
  select xfd.club_id m_club,count(*) m_games,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals>xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals>xf.home_goals))) m_w,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals<xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals<xf.home_goals))) m_l
  from public.cw_club_dates xfd join public.season_fixtures xf on xf.id=xfd.fixture_id
  where xfd.career_id=p_career and xfd.club_id in(select m_club from m_clubs) and xf.status='played' and xfd.due_on between d-28 and d
  group by xfd.club_id),
 m_ap as(
  select xa.player_id m_player,xa.club_id m_club,count(*) m_apps from public.cw_appearances xa
  where xa.career_id=p_career and xa.player_id in(select m_player from m_elig) and xa.minutes>=30 and xa.on_date between d-28 and d
  group by 1,2),
 m_rk as(
  select xmp.player_id m_player,rank() over(partition by xmp.club_id order by xpr.rating+coalesce(xdv.d_rating,0) desc,xmp.player_id) m_rank
  from public.mgr_players xmp join public.sim_players xsp on xsp.id=xmp.player_id
  join public.sim_player_pos_ratings xpr on xpr.player_id=xsp.id and xpr.pos=xsp.position
  left join public.cw_player_dev xdv on xdv.career_id=xmp.career_id and xdv.player_id=xmp.player_id
  where xmp.career_id=p_career and xmp.club_id in(select m_club from m_clubs)),
 m_base as(
  select e.m_player,e.m_morale,e.m_arrears,coalesce(rs.m_games,0) m_games,coalesce(ap.m_apps,0) m_apps,coalesce(rs.m_w,0) m_w,coalesce(rs.m_l,0) m_l,
   case when coalesce(rk.m_rank,30)<=11 then .60 when coalesce(rk.m_rank,30)<=16 then .30 else .10 end m_exp
  from m_elig e left join m_res rs on rs.m_club=e.m_club left join m_ap ap on ap.m_player=e.m_player and ap.m_club=e.m_club
  left join m_rk rk on rk.m_player=e.m_player),
 m_calc as(
  select b.m_player,b.m_morale,
   greatest(0,least(100,b.m_morale
    +case when b.m_games>=3 then greatest(case when b.m_apps::numeric/b.m_games>=b.m_exp then 1 else -6 end,
          greatest(-6,least(6,round(10*(b.m_apps::numeric/b.m_games-b.m_exp)))))
     else case when b.m_morale<60 then 1 when b.m_morale>70 then -1 else 0 end end
    +greatest(-4,least(4,2*b.m_w-2*b.m_l))
    -case when coalesce(b.m_arrears,0)>0 then 8 else 0 end)) m_new
  from m_base b)
 update public.cw_players xcp set morale=mc.m_new,morale_trend=sign(mc.m_new-mc.m_morale)::smallint,last_morale_on=d,transfer_requested=false,last_warning_on=null
  from m_calc mc where xcp.career_id=p_career and xcp.player_id=mc.m_player;
 -- Alvos realistas (evolução 40): pilares (3 melhores de cada clube) não são alvo, e atletas com menos de 32 anos
 -- não são procurados por clubes de divisão inferior à deles. Calculado uma vez por dia.
 create temp table if not exists _cw_pillars(player_id text primary key) on commit drop;
 create temp table if not exists _cw_levels(club_id text primary key,lvl int not null) on commit drop;
 truncate _cw_pillars;truncate _cw_levels;
 insert into _cw_pillars select x.player_id from(select mp.player_id,row_number() over(partition by mp.club_id order by r.rating desc,mp.player_id) rk
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is not null) x where x.rk<=3 on conflict do nothing;
 insert into _cw_levels select c.id,public.cw_club_level(c.id) from public.sim_clubs c on conflict do nothing;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career))) order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>public.cw_tick_probability((select ai_bid_chance from public.cw_rules))*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id is null or mp.club_id in (select public.cw_domestic_clubs(p_career)))
    and (mp.club_id is null or public.cw_window_open(public.cw_region(c.club_id),d))
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
    and (mp.club_id is null or not exists(select 1 from _cw_pillars pl where pl.player_id=sp.id))
    and (mp.club_id is null or cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)>=32
     or (select lvl from _cw_levels where club_id=c.club_id)<=(select lvl from _cw_levels where club_id=mp.club_id))
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    public.cw_salary_demand(p_career,p.id,c.club_id),3,greatest(ceil(value*.02),case when p.club_id is null then public.cw_minimum_signing(p_career,p.id,c.club_id) else 0 end),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- Contract continuity and rational renewals run before expiry in cw_finance_tick.
end $function$;
create or replace function public.career_reset_world(p_career uuid) returns jsonb
language plpgsql security definer set search_path=public as $f$
-- Apaga o mundo da carreira (elencos, temporadas, finanças, partidas). Mantém perfil, ranks, apostas,
-- carteira e o registro do técnico (mgr_coach, cw_coach). Gerado por FKs: filhos antes dos pais.
declare n_seasons int;
begin
 perform 1 from public.careers where id=p_career for update;
 create temp table _rs on commit drop as select id from public.career_seasons where career_id=p_career;
 create temp table _rf on commit drop as select f.id from public.season_fixtures f join _rs s on s.id=f.season_id;
 select count(*) into n_seasons from _rs;
 update public.mgr_coach set spell_id=null where career_id=p_career;
 delete from public.base_match_rewards where career_id=p_career;
 delete from public.mgr_transfers where career_id=p_career;
 delete from public.season_competitions where season_id in(select id from _rs);
 delete from public.mgr_matches where career_id=p_career;
 delete from public.mgr_match_players where fixture_id in(select id from _rf);
 delete from public.mgr_match_events where fixture_id in(select id from _rf);
 delete from public.season_fixture_slots where season_id in(select id from _rs);
 delete from public.season_schedule_changes where season_id in(select id from _rs);
 delete from public.cw_club_dates where career_id=p_career;
 delete from public.cw_fixture_dates where career_id=p_career;
 delete from public.cw_appearances where career_id=p_career;
 delete from public.season_fixtures where season_id in(select id from _rs);
 delete from public.season_offers where career_id=p_career;
 delete from public.mgr_objectives where career_id=p_career;
 delete from public.mgr_player_stats where season_id in(select id from _rs);
 delete from public.mgr_messages where career_id=p_career;
 delete from public.season_participants where season_id in(select id from _rs);
 delete from public.season_transitions where career_id=p_career;
 delete from public.season_card_totals where season_id in(select id from _rs);
 delete from public.season_final_tables where season_id in(select id from _rs);
 delete from public.cw_world where career_id=p_career;
 delete from public.cw_stats_opening where career_id=p_career;
 delete from public.cw_seasons where career_id=p_career;
 delete from public.cw_news where career_id=p_career;
 delete from public.career_seasons where career_id=p_career;
 delete from public.cw_ai_days where career_id=p_career;
 delete from public.cw_ai_roster_recoveries where career_id=p_career;
 delete from public.cw_attention_acks where career_id=p_career;
 delete from public.cw_board_contributions where career_id=p_career;
 delete from public.cw_budget_years where career_id=p_career;
 delete from public.cw_economy_rollouts where career_id=p_career;
 delete from public.cw_training where career_id=p_career;
 delete from public.cw_familiarity where career_id=p_career;
 delete from public.cw_set_pieces where career_id=p_career;
 delete from public.cw_staff where career_id=p_career;
 delete from public.cw_facilities where career_id=p_career;
 delete from public.cw_finance where career_id=p_career;
 delete from public.cw_contract_rows where career_id=p_career;
 delete from public.cw_market_legacy_agreements where career_id=p_career;
 delete from public.cw_offer_history where career_id=p_career;
 delete from public.cw_commitments where career_id=p_career;
 delete from public.cw_negotiations where career_id=p_career;
 delete from public.cw_coach_contracts where career_id=p_career;
 delete from public.cw_clubs where career_id=p_career;
 delete from public.cw_dev_errors where career_id=p_career;
 delete from public.cw_dev_months where career_id=p_career;
 delete from public.cw_dev_years where career_id=p_career;
 delete from public.cw_funding_dismissals where career_id=p_career;
 delete from public.cw_loans where career_id=p_career;
 delete from public.cw_match_boosts where career_id=p_career;
 delete from public.cw_operations where career_id=p_career;
 delete from public.cw_player_clock where career_id=p_career;
 delete from public.cw_player_dev where career_id=p_career;
 delete from public.cw_player_rows where career_id=p_career;
 delete from public.cw_runtime where career_id=p_career;
 delete from public.cw_runtime_metrics where career_id=p_career;
 delete from public.cw_scouting where career_id=p_career;
 delete from public.cw_settled_months where career_id=p_career;
 delete from public.cw_shortlist where career_id=p_career;
 delete from public.cw_transfer_registrations where career_id=p_career;
 delete from public.cw_world_clubs where career_id=p_career;
 delete from public.econ_requests where career_id=p_career;
 delete from public.mgr_ai_clubs where career_id=p_career;
 delete from public.mgr_lineups where career_id=p_career;
 delete from public.mgr_player_rows where career_id=p_career;
 delete from public.mgr_spells where career_id=p_career;
 delete from public.sim_players sp where sp.career_id=p_career;
 -- Técnico recomeça: mantém reputação; zera contadores, confiança e vínculo.
 update public.mgr_coach set status='unemployed',club_id=null,spell_id=null,board_confidence=60,fan_mood=60,unemployed_day=null,unemployed_season_no=null,
  matches=0,wins=0,draws=0,losses=0,gf=0,ga=0,titles=0,fired_count=0,seasons=0,warned=0,fan_warned=0,started_at=now() where career_id=p_career;
 -- Credibilidade fica; contrato do técnico recomeça com o novo clube.
 update public.cw_coach k set monthly_salary=round(70+coalesce(m.reputation,25)*3)::bigint,contract_until=null,promised_budget=0,last_pay_on=null,
  last_finance_warning=null,financial_dismissals=0 from public.mgr_coach m where k.career_id=p_career and m.career_id=k.career_id;
 update public.careers set club_id=null where id=p_career;
 drop table _rs;drop table _rf;
 return jsonb_build_object('seasons',n_seasons,'tables',66);
end $f$;
-- Começa a carreira de técnico num clube (mundo híbrido), depois de career_reset_world.
create or replace function public.career_begin_coach(p_career uuid,p_club text) returns uuid
language plpgsql security definer set search_path=public as $f$
declare sid uuid;
begin
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.career_seasons where career_id=p_career) then raise exception 'Carreira já tem mundo; reinicie antes';end if;
 if not exists(select 1 from public.sim_clubs where id=p_club) then raise exception 'Clube inexistente';end if;
 update public.careers set club_id=p_club where id=p_career;
 insert into public.mgr_coach(career_id,status,club_id) values(p_career,'employed',p_club)
 on conflict(career_id) do update set status='employed',club_id=excluded.club_id,unemployed_day=null,unemployed_season_no=null;
 perform public.mgr_init_world(p_career);
 sid:=public.mgr_new_season(p_career);
 perform public.mgr_start_spell(p_career,p_club);
 perform public.mgr_msg(p_career,sid,0,'board','Bem-vindo, professor!',
  format('A diretoria %s confia no seu trabalho. Monte o time, defina a tática e confira os objetivos da temporada.',public.mgr_club_do(p_club)),p_club);
 return sid;
end $f$;

-- cw_ensure
CREATE OR REPLACE FUNCTION public.cw_ensure(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare s public.career_seasons;starts date;current_day date;v_region text;sid uuid;
begin
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.cw_world where career_id=p_career) then return;end if;
 select * into s from public.career_seasons where career_id=p_career and mode='coach' order by season_no desc limit 1;
 if not found then raise exception 'Carreira de treinador não inicializada';end if;
 starts:=public.cw_start(s.region,s.year);
 current_day:=case when s.status='finished' then(starts+interval '1 year - 1 day')::date else least((starts+interval '1 year - 1 day')::date,starts+s.day_no*3) end;
 -- Legacy careers advanced regions sequentially. Do not move the global date behind an already completed regional year.
 select greatest(current_day,coalesce(max((public.cw_start(cs.region,cs.year)+interval '1 year - 1 day')::date),current_day)) into current_day
 from public.career_seasons cs where cs.career_id=p_career and cs.mode='coach' and (cs.status='finished' or(cs.status='archived' and not exists(select 1 from public.season_fixtures fx where fx.season_id=cs.id and fx.status='pending')));
 insert into public.cw_world(career_id,today,started_on,elapsed_days,primary_season) values(p_career,current_day,current_day,s.day_no,s.id) on conflict do nothing;
 -- Carreira híbrida: o runtime nasce antes das finanças, para os atletas virem do catálogo sem cópia.
 if public.cw_is_hybrid(p_career) then perform public.cw_runtime_ensure(p_career);end if;
 insert into public.cw_coach(career_id,monthly_salary,contract_until) select p_career,round(70+reputation*3)::bigint,(current_day+interval '2years')::date from public.mgr_coach where career_id=p_career
 on conflict(career_id) do update set contract_until=excluded.contract_until,monthly_salary=excluded.monthly_salary where cw_coach.contract_until is null;
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on) values(p_career,s.region,s.year,s.id,starts,(starts+interval '1 year - 1 day')::date) on conflict do nothing;
 update public.career_seasons set was_coached=true where id=s.id;
 perform public.mgr_init_world(p_career);
 perform public.cw_initialize_finances(p_career);
 perform public.cw_schedule(s.id);
 update public.season_offers set expires_on=current_day+greatest(1,coalesce(expires_day-s.day_no,7)),
 salary=coalesce(salary,150),contract_years=coalesce(contract_years,2),budget_guarantee=coalesce(budget_guarantee,0)
 where career_id=p_career and status='pending' and kind='coach' and expires_on is null;
 perform public.cw_news_add(p_career,'world:created','world','O mundo do futebol está em movimento',
 'Brasil e Europa agora seguem calendários próprios na sua carreira. Contratos, finanças e notícias evoluem com os dias.',65,s.club_id);

end $function$;

-- cw_recover_club
CREATE OR REPLACE FUNCTION public.cw_recover_club(p_career uuid, p_club text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare day int;start_day int;own text;
begin
 select w.elapsed_days,coalesce(r.last_recovery_day,w.elapsed_days) into day,start_day
 from public.cw_world w left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 if public.cw_is_hybrid(p_career) then
  select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
  if p_club is not distinct from own then
   -- Elenco do técnico: sempre com linha própria, para condição e ritmo evoluírem dia a dia.
   insert into public.mgr_player_rows(career_id,player_id,club_id,condition,rhythm)
   select mp.career_id,mp.player_id,mp.club_id,mp.condition,mp.rhythm from public.mgr_players mp where mp.career_id=p_career and mp.club_id=p_club
   on conflict do nothing;
   update public.mgr_player_rows p set
    condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
    rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no from public.mgr_player_rows r left join public.cw_player_clock pc using(career_id,player_id)
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
  else
   -- Clube da IA: quem tem linha volta ao padrão (condição 100, ritmo padrão) e, sem outra diferença, a linha sai.
   update public.mgr_player_rows p set
    condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
    rhythm=case when p.rhythm<c.base then least(c.base,p.rhythm+.4*greatest(0,day-coalesce(c.day_no,start_day)))
     else greatest(c.base,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))) end,
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no,case when sp.is_youth then 50 else 70 end base from public.mgr_player_rows r
    join public.sim_players sp on sp.id=r.player_id left join public.cw_player_clock pc on pc.career_id=r.career_id and pc.player_id=r.player_id
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
   delete from public.mgr_player_rows r using public.sim_players sp
   where r.career_id=p_career and r.club_id=p_club and not r.removed and sp.id=r.player_id and sp.career_id is null and sp.active
    and sp.club_id=r.club_id and r.condition=100 and r.rhythm=(case when sp.is_youth then 50 else 70 end)
    and r.injured_until is null and r.injury is null and r.susp='{}'::jsonb and r.yellows='{}'::jsonb
    and exists(select 1 from public.cw_world_clubs wc where wc.career_id=p_career and wc.club_id=r.club_id)
    and not exists(select 1 from public.cw_contract_rows ct where ct.career_id=p_career and ct.player_id=r.player_id and ct.club_id is distinct from r.club_id and ct.status='active');
   delete from public.cw_player_clock k where k.career_id=p_career
    and not exists(select 1 from public.mgr_player_rows r where r.career_id=p_career and r.player_id=k.player_id);
  end if;
  insert into public.cw_player_clock(career_id,player_id,day_no)
  select p_career,player_id,day from public.mgr_player_rows where career_id=p_career and club_id=p_club and not removed
  on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
  return;
 end if;
 update public.mgr_players p set
 condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
 rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
 injury=case when p.injured_until<=day then null else p.injury end,
 injured_until=case when p.injured_until<=day then null else p.injured_until end
 from (select mp.player_id,pc.day_no from public.mgr_players mp left join public.cw_player_clock pc using(career_id,player_id)
 where mp.career_id=p_career and mp.club_id=p_club)c
 where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
 insert into public.cw_player_clock(career_id,player_id,day_no)
 select p_career,player_id,day from public.mgr_players where career_id=p_career and club_id=p_club
 on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
end $function$;

-- cw_market_tick_before_v37
CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career
  -- Híbrido: valor padrão já é calculado na view; reavalia só quem tem linha própria.
  and (not public.cw_is_hybrid(p_career) or player_id in(select r.player_id from public.cw_player_rows r where r.career_id=p_career))
  and (not (select public.cw_runtime_enabled(p_career)) or player_id in(select player_id from public.mgr_players where career_id=p_career and club_id in (select public.cw_domestic_clubs(p_career))));end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 for id in select x.id from public.cw_negotiations x where x.career_id=p_career and x.status='player_accepted' and x.expires_on<d loop
  perform public.cw_neg_close(id,'expired','O prazo para confirmar terminou e o atleta seguiu outro caminho.');
 end loop;
 for n in select * from public.cw_negotiations where career_id=p_career and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') order by created_on,id for update loop
  if n.status in('agreed','precontract') then perform public.cw_register_transfer(n.id);continue;end if;
  if n.expires_on<d then perform public.cw_neg_close(n.id,'expired','Prazo da proposta encerrado.');continue;end if;
  if n.reply_on>d or n.status in('seller_review','club_counter','player_counter') then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into buyer from public.cw_clubs where career_id=p_career and club_id=n.buyer_club;
  select * into seller from public.cw_clubs where career_id=p_career and club_id=n.seller_club;
  if n.status='club_pending' then
   select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=n.seller_club;
   threshold:=n.valuation*(case when seller.financial_risk>=50 then .85 else 1.05 end)+n.valuation*case when ct.role='key' then .35 else .05 end;
   threshold:=threshold*(.9+n.decision_roll*.3)*case when ct.expires_on<d+180 then .65 else 1 end;
   if exists(select 1 from public.cw_rivalries rv where rv.club_a=least(n.buyer_club,n.seller_club) and rv.club_b=greatest(n.buyer_club,n.seller_club)) then threshold:=threshold*1.12;end if;
   threshold:=threshold*(1+least(.20,.04*(select count(*) from public.cw_negotiations z where z.career_id=p_career and z.player_id=n.player_id and z.id<>n.id and z.status in('club_pending','player_pending','seller_review'))));
   if n.seller_club is null or n.register_on>coalesce(ct.expires_on,d+999) then threshold:=0;end if;
   if (cnt<=18 and threshold>0) or n.decision_roll<.04 then
    perform public.cw_neg_close(n.id,'rejected','O clube considera o atleta indispensável ou não tem reposição.');
   elsif n.fee+n.performance_bonus*.5<threshold then
    if n.round_no>=2 or n.fee<threshold*.55 then perform public.cw_neg_close(n.id,'rejected','Os valores não atendem à avaliação do clube.');
    else
     update public.cw_negotiations set status='club_counter',fee=ceil(threshold),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O clube pede uma revisão do valor.' where id=n.id;
     if n.initiator='ai' then perform public.cw_neg_close(n.id,'rejected','O comprador desistiu da contraproposta.');else perform public.cw_neg_history(n.id,'seller','Contraproposta do clube vendedor.');end if;
    end if;
   else
    update public.cw_negotiations set status='player_counter',response='Clube de acordo. Apresente salário, duração, luvas e papel ao atleta.',expires_on=public.cw_deadline(d) where id=n.id;
    if n.initiator='ai' then
     update public.cw_negotiations set status='player_pending',monthly_salary=public.cw_salary_demand(p_career,n.player_id,n.buyer_club),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
    end if;
    perform public.cw_neg_history(n.id,'seller','Condições entre clubes aprovadas.');
   end if;
  elsif n.status='player_pending' then
   interest:=coalesce(public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role),greatest(40,n.valuation*.0065))*case when buyer.prestige>=coalesce(seller.prestige,0)+5 then 1.02 else 1.12 end;
   interest:=interest*(1+greatest(0,coalesce(seller.prestige,0)-buyer.prestige)*.015);
   interest:=interest*case when (select morale from public.cw_players where career_id=p_career and player_id=n.player_id)<35 and n.initiator='renewal' then 1.35 else 1 end;
   interest:=interest*case when n.role='prospect' and coalesce(ct.role,'rotation') in('key','starter') then 1.35 else 1 end;
   if n.decision_roll<.06 and buyer.prestige<coalesce(seller.prestige,0) then
    perform public.cw_neg_close(n.id,'rejected','O atleta recusou o projeto esportivo, independentemente da remuneração.');continue;
   end if;
   if (public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)+n.signing_bonus/greatest(12*n.contract_years,1))<interest then
    if n.round_no>=3 or n.monthly_salary<interest*.65 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou salário, papel ou projeto esportivo.');
    else update public.cw_negotiations set status='player_counter',monthly_salary=ceil(interest),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta pede melhores condições salariais.' where id=n.id;perform public.cw_neg_history(n.id,'player','Contraproposta salarial do atleta.');end if;
   elsif exists(select 1 from public.cw_negotiations where career_id=p_career and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
    perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
   else
    if n.buyer_club=own and n.initiator in('user','renewal') then
     update public.cw_negotiations set status='player_accepted',expires_on=public.cw_deadline(d),
      response=format('Aceito sua oferta de %s por semana por %s ano(s). Se estiver de acordo, confirme e meu agente cuida da papelada.',public.cw_money_label(public.cw_weekly(n.monthly_salary)),n.contract_years) where id=n.id;
     perform public.cw_neg_history(n.id,'player','O atleta aceitou; aguardando a confirmação do treinador.');
     continue;
    end if;
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,d) where id=n.id;
     perform public.cw_neg_history(n.id,'player','Condições do atleta aprovadas.');perform public.cw_register_transfer(n.id);
    exception when raise_exception then perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);end;
   end if;
  end if;
 end loop;
 -- Scheduled transfer liabilities are paid once; performance clauses require ten actual appearances.
 for r in select cm.*,n.player_id,n.seller_club,n.register_on from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
  where cm.career_id=p_career and cm.status='reserved' and n.status='completed' and cm.kind in('installment','performance') order by cm.due_on,cm.id loop
  if r.kind='performance' then
   select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=r.player_id and mp.club_id=r.club_id and mp.minutes>0 and mp.on_date>=r.register_on;
   if apps<10 and d<r.due_on then continue;end if;
   if apps<10 then update public.cw_commitments set status='released' where id=r.id;continue;end if;
  elsif r.due_on>d then continue;end if;
  perform public.cw_cash(p_career,r.club_id,-r.amount,'transfer_clause',r.id::text,'Parcela ou bônus da contratação',true);
  if r.seller_club is not null then perform public.cw_cash(p_career,r.seller_club,r.amount,'player_sale_clause',r.id::text,'Recebimento de parcela ou bônus');end if;
  update public.cw_commitments set status='paid' where id=r.id;
 end loop;
 -- Moral (CM17) em lote: mesma regra de cw_cm_morale_next, calculada uma vez por clube em vez de por atleta.
 update public.cw_players xcp set last_morale_on=d
  from public.mgr_players xmp, public.cw_contracts xct
  where xcp.career_id=p_career and xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
   and xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active' and d-xct.starts_on<28
   and (xmp.club_id=own or (not public.cw_is_hybrid(p_career) and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)))))
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7);
 with m_elig as materialized(
  select distinct on (xcp.player_id) xcp.player_id m_player,xcp.morale m_morale,xmp.club_id m_club,xct.arrears m_arrears
  from public.cw_players xcp join public.mgr_players xmp on xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
  join public.cw_contracts xct on xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active'
  where xcp.career_id=p_career and (xmp.club_id=own or (not public.cw_is_hybrid(p_career) and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)))))
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7) and d-xct.starts_on>=28
  order by xcp.player_id),
 m_clubs as materialized(select distinct m_club from m_elig),
 m_res as(
  select xfd.club_id m_club,count(*) m_games,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals>xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals>xf.home_goals))) m_w,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals<xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals<xf.home_goals))) m_l
  from public.cw_club_dates xfd join public.season_fixtures xf on xf.id=xfd.fixture_id
  where xfd.career_id=p_career and xfd.club_id in(select m_club from m_clubs) and xf.status='played' and xfd.due_on between d-28 and d
  group by xfd.club_id),
 m_ap as(
  select xa.player_id m_player,xa.club_id m_club,count(*) m_apps from public.cw_appearances xa
  where xa.career_id=p_career and xa.player_id in(select m_player from m_elig) and xa.minutes>=30 and xa.on_date between d-28 and d
  group by 1,2),
 m_rk as(
  select xmp.player_id m_player,rank() over(partition by xmp.club_id order by xpr.rating+coalesce(xdv.d_rating,0) desc,xmp.player_id) m_rank
  from public.mgr_players xmp join public.sim_players xsp on xsp.id=xmp.player_id
  join public.sim_player_pos_ratings xpr on xpr.player_id=xsp.id and xpr.pos=xsp.position
  left join public.cw_player_dev xdv on xdv.career_id=xmp.career_id and xdv.player_id=xmp.player_id
  where xmp.career_id=p_career and xmp.club_id in(select m_club from m_clubs)),
 m_base as(
  select e.m_player,e.m_morale,e.m_arrears,coalesce(rs.m_games,0) m_games,coalesce(ap.m_apps,0) m_apps,coalesce(rs.m_w,0) m_w,coalesce(rs.m_l,0) m_l,
   case when coalesce(rk.m_rank,30)<=11 then .60 when coalesce(rk.m_rank,30)<=16 then .30 else .10 end m_exp
  from m_elig e left join m_res rs on rs.m_club=e.m_club left join m_ap ap on ap.m_player=e.m_player and ap.m_club=e.m_club
  left join m_rk rk on rk.m_player=e.m_player),
 m_calc as(
  select b.m_player,b.m_morale,
   greatest(0,least(100,b.m_morale
    +case when b.m_games>=3 then greatest(case when b.m_apps::numeric/b.m_games>=b.m_exp then 1 else -6 end,
          greatest(-6,least(6,round(10*(b.m_apps::numeric/b.m_games-b.m_exp)))))
     else case when b.m_morale<60 then 1 when b.m_morale>70 then -1 else 0 end end
    +greatest(-4,least(4,2*b.m_w-2*b.m_l))
    -case when coalesce(b.m_arrears,0)>0 then 8 else 0 end)) m_new
  from m_base b)
 update public.cw_players xcp set morale=mc.m_new,morale_trend=sign(mc.m_new-mc.m_morale)::smallint,last_morale_on=d,transfer_requested=false,last_warning_on=null
  from m_calc mc where xcp.career_id=p_career and xcp.player_id=mc.m_player;
 -- Alvos realistas (evolução 40): pilares (3 melhores de cada clube) não são alvo, e atletas com menos de 32 anos
 -- não são procurados por clubes de divisão inferior à deles. Calculado uma vez por dia.
 create temp table if not exists _cw_pillars(player_id text primary key) on commit drop;
 create temp table if not exists _cw_levels(club_id text primary key,lvl int not null) on commit drop;
 truncate _cw_pillars;truncate _cw_levels;
 insert into _cw_pillars select x.player_id from(select mp.player_id,row_number() over(partition by mp.club_id order by r.rating desc,mp.player_id) rk
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is not null) x where x.rk<=3 on conflict do nothing;
 insert into _cw_levels select c.id,public.cw_club_level(c.id) from public.sim_clubs c on conflict do nothing;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career))) order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>public.cw_tick_probability((select ai_bid_chance from public.cw_rules))*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id is null or mp.club_id in (select public.cw_domestic_clubs(p_career)))
    and (mp.club_id is null or public.cw_window_open(public.cw_region(c.club_id),d))
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
    and (mp.club_id is null or not exists(select 1 from _cw_pillars pl where pl.player_id=sp.id))
    and (mp.club_id is null or cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)>=32
     or (select lvl from _cw_levels where club_id=c.club_id)<=(select lvl from _cw_levels where club_id=mp.club_id))
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    public.cw_salary_demand(p_career,p.id,c.club_id),3,greatest(ceil(value*.02),case when p.club_id is null then public.cw_minimum_signing(p_career,p.id,c.club_id) else 0 end),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- Contract continuity and rational renewals run before expiry in cw_finance_tick.
end $function$;

-- cw_dev_month
CREATE OR REPLACE FUNCTION public.cw_dev_month(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare own text;c record;l record;amt bigint;today date;reg text;yr int;st record;
begin
 if not public.cw_dev_on() then return;end if;
 insert into public.cw_dev_months(career_id,month) values(p_career,p_month) on conflict do nothing;
 if not found then return;end if;
 perform public.cw_set_ctx(p_career);
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select w.today into today from public.cw_world w where w.career_id=p_career;
 for c in select distinct mp.club_id from public.mgr_players mp join public.cw_clubs cc on cc.career_id=mp.career_id and cc.club_id=mp.club_id
  where mp.career_id=p_career order by 1 loop
  perform public.cw_dev_ensure_club(p_career,c.club_id);
 end loop;
 perform public.cw_dev_grow(p_career,p_month);
 -- entrosamento esquecido aos poucos
 update public.cw_familiarity set value=greatest(40,value-2) where career_id=p_career and value>40 and coalesce(last_used,'1900-01-01')<p_month;
 -- psicólogo: moral sobe aos poucos até 75
 update public.cw_players cp set morale=least(75,cp.morale+.6*x.level)
 from(select mp.player_id,st.level from public.mgr_players mp join public.cw_staff st on st.career_id=mp.career_id and st.club_id=mp.club_id and st.role='psychologist'
  where mp.career_id=p_career and (not public.cw_is_hybrid(p_career) or mp.club_id=own))x
 where cp.career_id=p_career and cp.player_id=x.player_id and cp.morale<75;
 -- ciclo anual no início da temporada de cada região
 foreach reg in array array['BRA','ENG'] loop
  if extract(month from p_month)=(case when reg='ENG' then 7 else 1 end) then
   yr:=extract(year from p_month)::int;
   insert into public.cw_dev_years(career_id,region,year) values(p_career,reg,yr) on conflict do nothing;
   if found then
    perform public.cw_dev_retire(p_career,reg,greatest(today,p_month));
    for c in select distinct mp.club_id from public.mgr_players mp join public.cw_clubs cc on cc.career_id=mp.career_id and cc.club_id=mp.club_id
     where mp.career_id=p_career and public.cw_region(mp.club_id)=reg and (mp.club_id=own or mp.club_id in(select public.cw_domestic_clubs(p_career))) order by 1 loop
     perform public.cw_dev_youth(p_career,c.club_id,greatest(today,p_month));
    end loop;
    perform public.cw_dev_ai_facilities(p_career,reg,greatest(today,p_month));
   end if;
  end if;
 end loop;
end $function$;

-- cw_dev_grow
CREATE OR REPLACE FUNCTION public.cw_dev_grow(p_career uuid, p_month date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare p record;w public.cw_world;own text;diff_mult numeric;base numeric;gap numeric;minf numeric;trf numeric;dr numeric;k numeric;
 attrs text[];mult jsonb;nd jsonb;att text;m numeric;wsum numeric;wm numeric;n int:=0;touched text[]:='{}';cf jsonb;wts jsonb;
 phys text[]:=array['pace','stamina','strength'];hyb boolean;ai boolean;prog numeric;scale numeric;fit_lvl int;focus text;full_refresh boolean;hist jsonb;
 gk_attrs text[]:=array['gk_reflexes','gk_handling','gk_positioning','strength','pace','stamina'];
 out_attrs text[]:=array['marking','tackling','positioning','heading','passing','vision','technique','stamina','finishing','off_ball','pace','dribbling','strength'];
begin
 select * into w from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select coalesce((public.mgr_difficulty(p_career)).dev_mult,1) into diff_mult;
 select growth_scale into scale from public.cw_dev_rules;
 hyb:=public.cw_is_hybrid(p_career);
 -- Notas por posição dos clubes da IA são recalculadas a cada trimestre; as do seu clube, todo mês.
 full_refresh:=extract(month from p_month)::int in(1,4,7,10);
 -- fatores de cada clube (uma consulta) e pesos das posições (uma consulta)
 select coalesce(jsonb_object_agg(t.club_id,jsonb_build_object('focus',t.focus,
   'trf',(.85+.075*coalesce(fa.level,3))*(1+.02*(coalesce(sa.level,3)-1))*case t.intensity when 'light' then .85 when 'hard' then 1.15 else 1 end,
   'fit',coalesce(sf.level,3),'learn',.85+.075*coalesce(fa.level,3))),'{}')
 into cf from public.cw_training t
 left join public.cw_facilities fa on fa.career_id=t.career_id and fa.club_id=t.club_id and fa.kind='training'
 left join public.cw_staff sa on sa.career_id=t.career_id and sa.club_id=t.club_id and sa.role='assistant'
 left join public.cw_staff sf on sf.career_id=t.career_id and sf.club_id=t.club_id and sf.role='fitness'
 where t.career_id=p_career;
 select jsonb_object_agg(pos,x) into wts from(select pos,jsonb_object_agg(attr,weight) x from public.sim_role_weights group by pos)y;
 for p in
  select mp.player_id,mp.club_id,sp.position,cp.potential,cp.age_at_start+floor((w.today-w.started_on)/365.25)::int age,
   r.rating+coalesce(d.d_rating,0) cur,coalesce(d.d,'{}') d,d.learning_pos,coalesce(d.learning_progress,0) lp,coalesce(d.history,'[]') hist,
   coalesce((select sum(a.minutes) from public.cw_appearances a where a.career_id=p_career and a.player_id=mp.player_id
     and a.on_date>=p_month and a.on_date<(p_month+interval '1 month')::date),0) mins
  from public.mgr_players mp
  cross join lateral(select c.* from public.cw_players c where c.career_id=mp.career_id and c.player_id=mp.player_id and c.retired_on is null) cp
  cross join lateral(select s.id,s.position from public.sim_players s where s.id=mp.player_id) sp
  cross join lateral(select pr.rating from public.sim_player_pos_ratings pr where pr.player_id=sp.id and pr.pos=sp.position) r
  left join lateral(select x.* from public.cw_player_dev x where x.career_id=mp.career_id and x.player_id=mp.player_id) d on true
  where mp.career_id=p_career and mp.club_id is not null and coalesce(d.last_month,'1900-01-01')<p_month
   -- Híbrido: a IA evolui por trimestre (sem histórico); o elenco do técnico, todo mês.
   and (not hyb or mp.club_id=own or full_refresh)
  order by mp.player_id
 loop
  focus:=coalesce(cf->p.club_id->>'focus','balanced');
  trf:=coalesce((cf->p.club_id->>'trf')::numeric,1);
  fit_lvl:=coalesce((cf->p.club_id->>'fit')::int,3);
  base:=case when p.age<=19 then .40 when p.age<=21 then .34 when p.age<=23 then .25 when p.age<=25 then .15 when p.age<=27 then .06
   when p.age<=30 then 0 when p.age<=32 then -.10 when p.age<=34 then -.22 else -.38 end;
  if base>0 then
   gap:=greatest(0,least(1.15,(p.potential-p.cur)/12.0));
   ai:=hyb and p.club_id is distinct from own;
   minf:=case when ai then .9 else .6+.6*least(1,p.mins/270.0) end;
   dr:=base*gap*minf*trf*case when p.club_id=own then diff_mult else 1 end*scale;
   dr:=least(dr,greatest(0,p.potential-p.cur));
  else
   dr:=base*(1-.05*(fit_lvl-1))*case when p.mins>=270 then .9 else 1 end*scale;
  end if;
  ai:=hyb and p.club_id is distinct from own;
  if ai then
   dr:=case when dr>0 then least(dr*3,greatest(0,p.potential-p.cur)) else dr*3 end;
   if abs(dr)<.005 and p.d='{}'::jsonb then n:=n+1;continue;end if;
  end if;
  nd:=p.d;
  if abs(dr)>=.005 then
   attrs:=case when p.position='GOL' then gk_attrs else out_attrs end;
   mult:='{}';wsum:=0;wm:=0;
   foreach att in array attrs loop
    if dr>0 then
     m:=case focus
      when 'physical' then case when att=any(phys) then 1.6 else .8 end
      when 'attack' then case when att in('finishing','off_ball','dribbling','technique') then 1.6 else .8 end
      when 'defense' then case when att in('marking','tackling','positioning','heading','gk_positioning') then 1.6 else .8 end
      when 'tactical' then case when att in('passing','vision','positioning','off_ball') then 1.4 else .85 end
      when 'set_pieces' then case when att in('technique','passing','finishing','heading') then 1.3 else .9 end
      else 1 end;
     if att=any(phys) then m:=m*(1+.03*(fit_lvl-1));end if;
    else
     m:=case when att=any(phys) then 1.7 when att in('passing','vision','positioning','technique','gk_positioning') then .5 else 1 end;
    end if;
    mult:=mult||jsonb_build_object(att,m);
    k:=coalesce((wts->p.position->>att)::numeric,0);
    wsum:=wsum+k;wm:=wm+k*m;
   end loop;
   k:=case when wm>0 then dr/(wm/wsum) else dr end;
   foreach att in array attrs loop
    nd:=nd||jsonb_build_object(att,round(coalesce((nd->>att)::numeric,0)+k*(mult->>att)::numeric,3));
   end loop;
  end if;
  prog:=p.lp;
  if p.learning_pos is not null then
   prog:=least(100,p.lp+9*coalesce((cf->p.club_id->>'learn')::numeric,1)*case when focus='tactical' then 1.3 else 1 end);
  end if;
  -- histórico mensal (últimos 24 meses), com a nota estimada após o mês
  hist:=(select coalesce(jsonb_agg(e order by o),'[]') from(select e,o from jsonb_array_elements(p.hist||jsonb_build_array(
    jsonb_build_object('m',to_char(p_month,'YYYY-MM'),'r',round(p.cur+dr,1)))) with ordinality x(e,o) order by o desc limit 24)y);
  if ai then hist:='[]'::jsonb;end if;
  insert into public.cw_player_dev(career_id,player_id,d,last_month,learning_progress,history)
  values(p_career,p.player_id,nd,p_month,prog,hist)
  on conflict(career_id,player_id) do update set d=excluded.d,last_month=excluded.last_month,history=excluded.history,
   d_rating=cw_player_dev.d_rating+(case when abs(dr)>=.005 then dr else 0 end),
   learning_progress=case when cw_player_dev.learning_pos is null then 0 else excluded.learning_progress end;
  if p.learning_pos is not null and prog>=100 then
   update public.cw_player_dev set learned=array(select distinct unnest(learned||array[p.learning_pos])),learning_pos=null,learning_progress=0
   where career_id=p_career and player_id=p.player_id;
   touched:=touched||p.player_id;
   if p.club_id=own then
    perform public.cw_inbox_add(p_career,'learned:'||p.player_id||':'||p.learning_pos,'squad','squad',
     public.mgr_player_name(p.player_id)||' aprendeu uma nova posição',
     'Depois dos treinos específicos, '||public.mgr_player_name(p.player_id)||' já atua como '||p.learning_pos||' com rendimento de posição secundária.',own,p.player_id,null,'open_player');
   end if;
  elsif nd<>'{}'::jsonb and (p.club_id=own or (full_refresh and not hyb)) then
   touched:=touched||p.player_id;
  end if;
  n:=n+1;
 end loop;
 if cardinality(touched)>0 then perform public.cw_dev_refresh(p_career,touched);end if;
 return n;
end $function$;

-- cw_archive_match
CREATE OR REPLACE FUNCTION public.cw_archive_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
begin
 if new.status<>'finished' or old.status='finished' or not exists(select 1 from public.cw_world where career_id=new.career_id) then return new;end if;
 insert into public.cw_appearances(career_id,fixture_id,season_id,competition_id,player_id,club_id,on_date,minutes,goals,assists,rating,starter)
 select new.career_id,new.fixture_id,new.season_id,f.competition_id,mp.player_id,mp.club_id,coalesce(fd.due_on,w.today),mp.minutes,mp.goals,mp.assists,mp.rating,mp.starter
 from public.mgr_match_players mp join public.season_fixtures f on f.id=mp.fixture_id join public.cw_world w on w.career_id=new.career_id left join public.cw_fixture_dates fd on fd.fixture_id=f.id
 where mp.fixture_id=new.fixture_id and mp.minutes>0
  -- Híbrido: atuação por partida só do clube do técnico; a IA guarda totais em mgr_player_stats.
  and (not public.cw_is_hybrid(new.career_id) or mp.club_id=(select club_id from public.mgr_coach where career_id=new.career_id))
 on conflict do nothing;
 return new;
end $function$;
-- Fim de temporada enxuto: de cada região fica o detalhe só da última temporada encerrada (usada na classificação da seguinte).
-- Das anteriores ficam career_seasons (resumo do técnico), season_competitions (campeões), season_final_tables (tabelas)
-- e mgr_player_stats já reduzido aos artilheiros (cw_trim_closed_stats). Jogos, datas, súmulas e atuações saem.
create or replace function public.cw_archive_old_seasons(p_career uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare s record;n int:=0;nf bigint:=0;x bigint;
begin
 for s in select cs.id from public.career_seasons cs
  where cs.career_id=p_career and cs.mode='coach' and cs.status in('finished','archived')
   and exists(select 1 from public.career_seasons nx where nx.career_id=p_career and nx.mode='coach' and nx.region=cs.region
    and nx.season_no>cs.season_no and nx.status in('finished','archived'))
   and exists(select 1 from public.season_fixtures f where f.season_id=cs.id)
  order by cs.season_no loop
  delete from public.base_match_rewards where season_id=s.id;
  delete from public.cw_appearances where season_id=s.id;
  delete from public.cw_stats_opening where season_id=s.id;
  delete from public.cw_club_dates cd using public.season_fixtures f where f.season_id=s.id and cd.fixture_id=f.id;
  delete from public.cw_fixture_dates where season_id=s.id;
  delete from public.season_schedule_changes sc using public.season_fixtures f where f.season_id=s.id and sc.fixture_id=f.id;
  delete from public.mgr_matches where season_id=s.id;
  delete from public.season_fixtures where season_id=s.id;
  get diagnostics x=row_count;nf:=nf+x;n:=n+1;
 end loop;
 return jsonb_build_object('seasons',n,'fixtures',nf);
end $$;

-- cw_runtime_maintenance
CREATE OR REPLACE FUNCTION public.cw_runtime_maintenance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;n int:=0;
begin
 for r in select c.id,w.today from public.careers c join public.cw_runtime rt on rt.career_id=c.id join public.cw_world w on w.career_id=c.id
 where (rt.last_maintenance_at is null or rt.last_maintenance_at<now()-interval '1 day'
        or rt.last_maintained_on is null or w.today-rt.last_maintained_on>=30)
 and not exists(select 1 from public.mgr_matches m where m.career_id=c.id and m.status='live' and m.user_side is not null)
 order by rt.last_maintenance_at nulls first,c.id limit 1 for update of c skip locked loop
  perform public.cw_prune_career(r.id);
  perform public.cw_compact_closed_seasons(r.id);
  perform public.cw_archive_old_seasons(r.id);
  perform public.cw_trim_closed_stats(r.id);
  perform public.cw_compact_old_wages(r.id);
  delete from public.cw_ai_days where career_id=r.id and on_date<r.today-1;
  update public.cw_runtime set last_maintenance_at=now(),last_maintained_on=r.today where career_id=r.id;n:=n+1;
 end loop;
 return n;
end $function$;

-- cw_club_xi
CREATE OR REPLACE FUNCTION public.cw_club_xi(p_career uuid, p_club text, p_comp text, p_day integer)
 RETURNS TABLE(player_id text, pos text, eff numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select x.player_id,x.pos,x.eff from(
  select mp.player_id,sp.position pos,r.eff+coalesce((d.pos->sp.position->>1)::numeric,d.d_rating,0) eff,
   row_number() over(partition by sp.position='GOL' order by r.eff+coalesce((d.pos->sp.position->>1)::numeric,d.d_rating,0) desc,mp.player_id) rn
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
  join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  left join public.cw_player_dev d on d.career_id=mp.career_id and d.player_id=mp.player_id
  where mp.career_id=p_career and mp.club_id=p_club and (mp.injured_until is null or mp.injured_until<=p_day)
   and coalesce((mp.susp->>p_comp)::int,0)=0)x
 where (x.pos='GOL' and x.rn=1) or (x.pos<>'GOL' and x.rn<=10)
$function$;
-- Híbrido: limpeza de registros que só serviam a clubes da IA.
create or replace function public.cw_hybrid_trim(p_career uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare own text;today date;n_fin bigint;n_hist bigint;
begin
 if not public.cw_is_hybrid(p_career) then return jsonb_build_object('skipped',true);end if;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select w.today into today from public.cw_world w where w.career_id=p_career;
 -- Receita por jogo da IA já lançada no caixa (cw_clubs.cash); a linha servia só para não pagar duas vezes o mesmo jogo, já disputado.
 delete from public.cw_finance f where f.career_id=p_career and f.club_id is distinct from own
  and f.kind in('matchday','match_prize','matchday_operations') and f.on_date<today-7;
 get diagnostics n_fin=row_count;
 -- Histórico de propostas de negociações encerradas entre clubes da IA.
 delete from public.cw_offer_history h using public.cw_negotiations n
  where h.negotiation_id=n.id and n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds')
   and n.initiator not in('user','renewal') and own is distinct from n.buyer_club and own is distinct from n.seller_club;
 get diagnostics n_hist=row_count;
 delete from public.cw_ai_days where career_id=p_career and on_date<today-1;
 return jsonb_build_object('finance',n_fin,'offer_history',n_hist);
end $$;

-- cw_runtime_maintenance
CREATE OR REPLACE FUNCTION public.cw_runtime_maintenance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;n int:=0;
begin
 for r in select c.id,w.today from public.careers c join public.cw_runtime rt on rt.career_id=c.id join public.cw_world w on w.career_id=c.id
 where (rt.last_maintenance_at is null or rt.last_maintenance_at<now()-interval '1 day'
        or rt.last_maintained_on is null or w.today-rt.last_maintained_on>=30)
 and not exists(select 1 from public.mgr_matches m where m.career_id=c.id and m.status='live' and m.user_side is not null)
 order by rt.last_maintenance_at nulls first,c.id limit 1 for update of c skip locked loop
  perform public.cw_prune_career(r.id);
  perform public.cw_compact_closed_seasons(r.id);
  perform public.cw_archive_old_seasons(r.id);
  perform public.cw_hybrid_trim(r.id);
  perform public.cw_trim_closed_stats(r.id);
  perform public.cw_compact_old_wages(r.id);
  delete from public.cw_ai_days where career_id=r.id and on_date<r.today-1;
  update public.cw_runtime set last_maintenance_at=now(),last_maintained_on=r.today where career_id=r.id;n:=n+1;
 end loop;
 return n;
end $function$;

-- cw_dev_grow
CREATE OR REPLACE FUNCTION public.cw_dev_grow(p_career uuid, p_month date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare p record;w public.cw_world;own text;diff_mult numeric;base numeric;gap numeric;minf numeric;trf numeric;dr numeric;k numeric;
 attrs text[];mult jsonb;nd jsonb;att text;m numeric;wsum numeric;wm numeric;n int:=0;touched text[]:='{}';cf jsonb;wts jsonb;
 phys text[]:=array['pace','stamina','strength'];hyb boolean;ai boolean;prog numeric;scale numeric;fit_lvl int;focus text;full_refresh boolean;hist jsonb;
 gk_attrs text[]:=array['gk_reflexes','gk_handling','gk_positioning','strength','pace','stamina'];
 out_attrs text[]:=array['marking','tackling','positioning','heading','passing','vision','technique','stamina','finishing','off_ball','pace','dribbling','strength'];
begin
 select * into w from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select coalesce((public.mgr_difficulty(p_career)).dev_mult,1) into diff_mult;
 select growth_scale into scale from public.cw_dev_rules;
 hyb:=public.cw_is_hybrid(p_career);
 -- Notas por posição dos clubes da IA são recalculadas a cada trimestre; as do seu clube, todo mês.
 full_refresh:=extract(month from p_month)::int in(1,4,7,10);
 -- fatores de cada clube (uma consulta) e pesos das posições (uma consulta)
 select coalesce(jsonb_object_agg(t.club_id,jsonb_build_object('focus',t.focus,
   'trf',(.85+.075*coalesce(fa.level,3))*(1+.02*(coalesce(sa.level,3)-1))*case t.intensity when 'light' then .85 when 'hard' then 1.15 else 1 end,
   'fit',coalesce(sf.level,3),'learn',.85+.075*coalesce(fa.level,3))),'{}')
 into cf from public.cw_training t
 left join public.cw_facilities fa on fa.career_id=t.career_id and fa.club_id=t.club_id and fa.kind='training'
 left join public.cw_staff sa on sa.career_id=t.career_id and sa.club_id=t.club_id and sa.role='assistant'
 left join public.cw_staff sf on sf.career_id=t.career_id and sf.club_id=t.club_id and sf.role='fitness'
 where t.career_id=p_career;
 select jsonb_object_agg(pos,x) into wts from(select pos,jsonb_object_agg(attr,weight) x from public.sim_role_weights group by pos)y;
 for p in
  select mp.player_id,mp.club_id,sp.position,cp.potential,cp.age_at_start+floor((w.today-w.started_on)/365.25)::int age,
   r.rating+coalesce(d.d_rating,0) cur,coalesce(d.d,'{}') d,d.learning_pos,coalesce(d.learning_progress,0) lp,coalesce(d.history,'[]') hist,
   coalesce((select sum(a.minutes) from public.cw_appearances a where a.career_id=p_career and a.player_id=mp.player_id
     and a.on_date>=p_month and a.on_date<(p_month+interval '1 month')::date),0) mins
  from public.mgr_players mp
  cross join lateral(select c.* from public.cw_players c where c.career_id=mp.career_id and c.player_id=mp.player_id and c.retired_on is null) cp
  cross join lateral(select s.id,s.position from public.sim_players s where s.id=mp.player_id) sp
  cross join lateral(select pr.rating from public.sim_player_pos_ratings pr where pr.player_id=sp.id and pr.pos=sp.position) r
  left join lateral(select x.* from public.cw_player_dev x where x.career_id=mp.career_id and x.player_id=mp.player_id) d on true
  where mp.career_id=p_career and mp.club_id is not null and coalesce(d.last_month,'1900-01-01')<p_month
   -- Híbrido: a IA evolui por trimestre (sem histórico); o elenco do técnico, todo mês.
   and (not hyb or mp.club_id=own or full_refresh)
  order by mp.player_id
 loop
  focus:=coalesce(cf->p.club_id->>'focus','balanced');
  trf:=coalesce((cf->p.club_id->>'trf')::numeric,1);
  fit_lvl:=coalesce((cf->p.club_id->>'fit')::int,3);
  base:=case when p.age<=19 then .40 when p.age<=21 then .34 when p.age<=23 then .25 when p.age<=25 then .15 when p.age<=27 then .06
   when p.age<=30 then 0 when p.age<=32 then -.10 when p.age<=34 then -.22 else -.38 end;
  if base>0 then
   gap:=greatest(0,least(1.15,(p.potential-p.cur)/12.0));
   ai:=hyb and p.club_id is distinct from own;
   minf:=case when ai then .9 else .6+.6*least(1,p.mins/270.0) end;
   dr:=base*gap*minf*trf*case when p.club_id=own then diff_mult else 1 end*scale;
   dr:=least(dr,greatest(0,p.potential-p.cur));
  else
   dr:=base*(1-.05*(fit_lvl-1))*case when p.mins>=270 then .9 else 1 end*scale;
  end if;
  ai:=hyb and p.club_id is distinct from own;
  if ai then
   dr:=case when dr>0 then least(dr*3,greatest(0,p.potential-p.cur)) else dr*3 end;
   if abs(dr)<.005 and p.d='{}'::jsonb then n:=n+1;continue;end if;
  end if;
  nd:=p.d;
  -- Híbrido: a IA guarda só a nota (d_rating); atributos detalhados só para o elenco do técnico.
  if abs(dr)>=.005 and not ai then
   attrs:=case when p.position='GOL' then gk_attrs else out_attrs end;
   mult:='{}';wsum:=0;wm:=0;
   foreach att in array attrs loop
    if dr>0 then
     m:=case focus
      when 'physical' then case when att=any(phys) then 1.6 else .8 end
      when 'attack' then case when att in('finishing','off_ball','dribbling','technique') then 1.6 else .8 end
      when 'defense' then case when att in('marking','tackling','positioning','heading','gk_positioning') then 1.6 else .8 end
      when 'tactical' then case when att in('passing','vision','positioning','off_ball') then 1.4 else .85 end
      when 'set_pieces' then case when att in('technique','passing','finishing','heading') then 1.3 else .9 end
      else 1 end;
     if att=any(phys) then m:=m*(1+.03*(fit_lvl-1));end if;
    else
     m:=case when att=any(phys) then 1.7 when att in('passing','vision','positioning','technique','gk_positioning') then .5 else 1 end;
    end if;
    mult:=mult||jsonb_build_object(att,m);
    k:=coalesce((wts->p.position->>att)::numeric,0);
    wsum:=wsum+k;wm:=wm+k*m;
   end loop;
   k:=case when wm>0 then dr/(wm/wsum) else dr end;
   foreach att in array attrs loop
    nd:=nd||jsonb_build_object(att,round(coalesce((nd->>att)::numeric,0)+k*(mult->>att)::numeric,3));
   end loop;
  end if;
  prog:=p.lp;
  if p.learning_pos is not null then
   prog:=least(100,p.lp+9*coalesce((cf->p.club_id->>'learn')::numeric,1)*case when focus='tactical' then 1.3 else 1 end);
  end if;
  -- histórico mensal (últimos 24 meses), com a nota estimada após o mês
  hist:=(select coalesce(jsonb_agg(e order by o),'[]') from(select e,o from jsonb_array_elements(p.hist||jsonb_build_array(
    jsonb_build_object('m',to_char(p_month,'YYYY-MM'),'r',round(p.cur+dr,1)))) with ordinality x(e,o) order by o desc limit 24)y);
  if ai then hist:='[]'::jsonb;end if;
  insert into public.cw_player_dev(career_id,player_id,d,last_month,learning_progress,history)
  values(p_career,p.player_id,nd,p_month,prog,hist)
  on conflict(career_id,player_id) do update set d=excluded.d,last_month=excluded.last_month,history=excluded.history,
   d_rating=cw_player_dev.d_rating+(case when abs(dr)>=.005 then dr else 0 end),
   learning_progress=case when cw_player_dev.learning_pos is null then 0 else excluded.learning_progress end;
  if p.learning_pos is not null and prog>=100 then
   update public.cw_player_dev set learned=array(select distinct unnest(learned||array[p.learning_pos])),learning_pos=null,learning_progress=0
   where career_id=p_career and player_id=p.player_id;
   touched:=touched||p.player_id;
   if p.club_id=own then
    perform public.cw_inbox_add(p_career,'learned:'||p.player_id||':'||p.learning_pos,'squad','squad',
     public.mgr_player_name(p.player_id)||' aprendeu uma nova posição',
     'Depois dos treinos específicos, '||public.mgr_player_name(p.player_id)||' já atua como '||p.learning_pos||' com rendimento de posição secundária.',own,p.player_id,null,'open_player');
   end if;
  elsif nd<>'{}'::jsonb and (p.club_id=own or (full_refresh and not hyb)) then
   touched:=touched||p.player_id;
  end if;
  n:=n+1;
 end loop;
 if cardinality(touched)>0 then perform public.cw_dev_refresh(p_career,touched);end if;
 return n;
end $function$;

-- cw_archive_old_seasons
CREATE OR REPLACE FUNCTION public.cw_archive_old_seasons(p_career uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record;n int:=0;nf bigint:=0;x bigint;
begin
 for s in select cs.id from public.career_seasons cs
  where cs.career_id=p_career and cs.mode in('coach','world') and cs.status in('finished','archived')
   and exists(select 1 from public.career_seasons nx where nx.career_id=p_career and nx.mode in('coach','world') and nx.region=cs.region
    and nx.season_no>cs.season_no and nx.status in('finished','archived'))
   and exists(select 1 from public.season_fixtures f where f.season_id=cs.id)
  order by cs.season_no loop
  delete from public.base_match_rewards where season_id=s.id;
  delete from public.cw_appearances where season_id=s.id;
  delete from public.cw_stats_opening where season_id=s.id;
  delete from public.cw_club_dates cd using public.season_fixtures f where f.season_id=s.id and cd.fixture_id=f.id;
  delete from public.cw_fixture_dates where season_id=s.id;
  delete from public.season_schedule_changes sc using public.season_fixtures f where f.season_id=s.id and sc.fixture_id=f.id;
  delete from public.mgr_matches where season_id=s.id;
  delete from public.season_fixtures where season_id=s.id;
  get diagnostics x=row_count;nf:=nf+x;n:=n+1;
 end loop;
 return jsonb_build_object('seasons',n,'fixtures',nf);
end $function$;
