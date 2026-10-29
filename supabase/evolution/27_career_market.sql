begin;
alter table public.cw_negotiations add column if not exists appearance_bonus bigint not null default 0;
alter table public.cw_negotiations add column if not exists goal_bonus bigint not null default 0;
create or replace function public.cw_prune_lineups(p_career uuid,p_player text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 update public.mgr_lineups l set slots=coalesce((select jsonb_object_agg(key,value) from jsonb_each(l.slots) where value#>>'{}'<>p_player),'{}'),bench=array_remove(l.bench,p_player),updated_at=now()
 where l.career_id=p_career and l.club_id is distinct from(select club_id from public.mgr_players where career_id=p_career and player_id=p_player)
 and (l.slots::text like '%'||p_player||'%' or p_player=any(l.bench));
end $$;
create or replace function public.cw_neg_history(p_id uuid,p_actor text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 insert into public.cw_offer_history(career_id,negotiation_id,on_date,actor,state,terms,explanation)
 select n.career_id,n.id,w.today,p_actor,n.status,to_jsonb(n)-'decision_roll',p_reason from public.cw_negotiations n join public.cw_world w on w.career_id=n.career_id where n.id=p_id;
end $$;
create or replace function public.cw_neg_close(p_id uuid,p_status text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 update public.cw_negotiations set status=p_status,response=p_reason where id=p_id;
 update public.cw_commitments set status='released' where negotiation_id=p_id and status='reserved';
 perform public.cw_neg_history(p_id,'system',p_reason);
end $$;
create or replace function public.cw_reserve_offer(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n public.cw_negotiations;needed bigint;available bigint;
begin
 select * into n from public.cw_negotiations where id=p_id;
 needed:=n.fee+n.signing_bonus+n.performance_bonus;
 select public.cw_available_budget(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0) into available;
 if needed>available then raise exception 'Orçamento livre insuficiente para taxa, luvas e bônus';end if;
 insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
 values(n.career_id,n.buyer_club,n.id,'offer',needed,n.expires_on,n.id||':offer')
 on conflict(career_id,club_id,reference) do update set amount=excluded.amount,status='reserved',due_on=excluded.due_on;
end $$;
create or replace function public.cw_register_transfer(p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n public.cw_negotiations;ct public.cw_contracts;d date;owner text;upfront bigint;part bigint;i int;own text;new_contract uuid;ref text;other record;
begin
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into owner from public.mgr_players where career_id=n.career_id and player_id=n.player_id for update;
 select * into ct from public.cw_contracts where career_id=n.career_id and player_id=n.player_id and status='active' for update;
 if (n.status<>'precontract' and ((n.initiator<>'renewal' and owner is distinct from n.seller_club) or ct.id is distinct from n.agreed_owner_contract)) or
    (n.status='precontract' and ct.id is not null and ct.id is distinct from n.agreed_owner_contract) then
  perform public.cw_neg_close(n.id,'cancelled','O vínculo do atleta mudou durante a negociação.');return false;
 end if;
 if n.status<>'precontract' and owner is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then return false;end if;
 upfront:=ceil(n.fee::numeric/n.installments)::bigint;
 if (select cash-public.cw_reserved(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0)-(select reserve_salary_months from public.cw_rules)*(public.cw_payroll(n.career_id,n.buyer_club)+public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)-coalesce(case when ct.club_id=n.buyer_club then public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role) else 0 end,0)) from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club)<n.fee+n.signing_bonus+n.performance_bonus then
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
 update public.cw_players set morale=75,promised_role=n.role,transfer_requested=false,last_warning_on=null where career_id=n.career_id and player_id=n.player_id;
 perform public.cw_prune_lineups(n.career_id,n.player_id);
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
  coalesce(public.mgr_club_name(n.seller_club),'Livre no mercado')||' → '||public.mgr_club_name(n.buyer_club)||'. Valor: '||n.fee||' moedas. Contrato de '||n.contract_years||' anos.',
  case when own in(n.seller_club,n.buyer_club) then case when n.valuation>=150000 then 98 else 85 end else 45 end,n.buyer_club,n.player_id,null,
  jsonb_build_object('negotiation_id',n.id,'fee',n.fee,'from_club',n.seller_club,'to_club',n.buyer_club,'overall',(select round(rating) from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and sp.position=pr.pos where sp.id=n.player_id),'position',(select position from public.sim_players where id=n.player_id),'big_signing',n.valuation>=150000 and own=n.buyer_club and n.initiator<>'renewal'));
 perform public.cw_neg_history(n.id,'system','Registro concluído com pagamentos e vínculo únicos.');return true;
end $$;
create or replace function public.cw_market_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career;end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
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
     update public.cw_negotiations set status='player_pending',monthly_salary=greatest(40,ceil(coalesce(ct.monthly_salary,n.valuation*.0065)*1.15)),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
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
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,case when n.seller_club is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end) where id=n.id;
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
 -- Weekly satisfaction derives from actual minutes and promises, not a daily random penalty.
 for p in select cp.*,mp.club_id,ct.arrears,ct.starts_on,ct.role from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
  join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
  where cp.career_id=p_career and (cp.last_morale_on is null or cp.last_morale_on<=d-7) loop
  if d-p.starts_on<28 then update public.cw_players set last_morale_on=d where career_id=p_career and player_id=p.player_id;continue;end if;
  select count(*) into games from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=p_career and fd.club_id=p.club_id and f.status='played' and fd.due_on between d-28 and d;
  select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=p.player_id and mp.club_id=p.club_id and mp.minutes>=30 and mp.on_date between d-28 and d;
  expected:=case p.promised_role when 'key' then .75 when 'starter' then .55 when 'rotation' then .25 else .05 end;
  new_morale:=greatest(0,least(100,p.morale+case when games>=3 and apps::numeric/games<expected then -7 else 3 end-case when p.arrears>0 then 12 else 0 end));
  update public.cw_players set morale=new_morale,last_morale_on=d,transfer_requested=new_morale<30,
   last_warning_on=case when new_morale<45 then coalesce(last_warning_on,d) else null end where career_id=p_career and player_id=p.player_id;
  if new_morale<45 and p.club_id=own then perform public.cw_news_add(p_career,'morale:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||case when new_morale<30 then ' pede para sair' else ' cobra espaço no time' end,
   'O papel prometido, os minutos recentes e os pagamentos estão afetando a satisfação. Reveja as oportunidades e o contrato.',90,own,p.player_id);end if;
 end loop;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  if not public.cw_window_open(public.cw_region(c.club_id),d) or c.financial_risk>=75 or random()>(select ai_bid_chance from public.cw_rules) then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    greatest(40,ceil(coalesce(ct.monthly_salary,value*.0065)*1.15)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- AI contract management: renew affordable contributors before expiry; release surplus players without deleting them.
 if extract(day from d)=15 then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and x.expires_on between d and d+120
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
   if public.cw_available_budget(p_career,ct.club_id)>ct.monthly_salary*3 and (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=35 then
    update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;
    insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
     values(p_career,ct.player_id,ct.club_id,d,(d+interval '2years')::date,ceil(ct.monthly_salary*1.06),ct.role);
    perform public.cw_news_add(p_career,'ai-renew:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' renova contrato','Vínculo renovado por duas temporadas.',25,ct.club_id,ct.player_id);
   end if;
  end loop;
 end if;
end $$;

create or replace function public.career_transfer_bid(p_player text,p_fee bigint,p_installments int,p_bonus bigint,p_precontract boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;owner text;ct public.cw_contracts;d date;id uuid;prev jsonb;value bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'transfer_bid');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 if own is null then raise exception 'Assuma um clube para negociar';end if;
 select club_id into owner from public.mgr_players where career_id=car.id and player_id=p_player for update;
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
create or replace function public.career_player_offer(p_id uuid,p_salary bigint,p_years int,p_signing bigint,p_role text,p_appearance bigint,p_goal bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;n public.cw_negotiations;own text;prev jsonb;d date;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_offer');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into n from public.cw_negotiations where id=p_id and career_id=car.id and buyer_club=own for update;
 if not found or n.status<>'player_counter' or n.expires_on<d then raise exception 'Etapa de contrato indisponível';end if;
 if p_salary is null or p_salary not between 1 and 10000000 or p_years is null or (p_years<1 or p_years>(select max_contract_years from public.cw_rules)) or p_signing is null or p_signing not between 0 and 10000000 or p_role not in('key','starter','rotation','prospect') or p_appearance is null or p_appearance not between 0 and 1000000 or p_goal is null or p_goal not between 0 and 1000000 then raise exception 'Contrato inválido';end if;
 update public.cw_negotiations set monthly_salary=p_salary,contract_years=p_years,signing_bonus=p_signing,role=p_role,appearance_bonus=p_appearance,goal_bonus=p_goal,status='player_pending',reply_on=d+2,expires_on=public.cw_deadline(d) where id=n.id;
 perform public.cw_reserve_offer(n.id);perform public.cw_neg_history(n.id,'user','Condições contratuais apresentadas ao atleta.');
 return public.econ_request_save(car.id,p_request,'player_offer',jsonb_build_object('ok',true));
end $$;
create or replace function public.career_contract_renew(p_player text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;ct public.cw_contracts;d date;id uuid;prev jsonb;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'contract_renew');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and club_id=own and status='active';
 if not found then raise exception 'Atleta fora do seu elenco';end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=p_player and status in('agreed','precontract')) then raise exception 'O atleta já tem compromisso firmado';end if;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,role,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
 values(car.id,p_player,null,own,'renewal','player_counter',0,ceil(ct.monthly_salary*1.08),2,ct.role,d,d,public.cw_deadline(d),public.cw_player_value(car.id,p_player),ct.id) returning id into id;
 perform public.cw_neg_history(id,'user','Renovação aberta. Apresente as novas condições.');
 return public.econ_request_save(car.id,p_request,'contract_renew',jsonb_build_object('id',id));
end $$;
create or replace function public.career_player_role(p_player text,p_role text)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if p_role not in('key','starter','rotation','prospect') or not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player and club_id=own) then raise exception 'Papel ou atleta inválido';end if;
 update public.cw_players set promised_role=p_role where career_id=car.id and player_id=p_player;
 return jsonb_build_object('ok',true);
end $$;
commit;
