-- Transfer visibility and future match income; source: evolution/57_transfer_roster_match_revenue.sql.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
set local timezone='UTC';
create temporary table _scoped_table_scopes on commit drop as
 select tab.table_name,array_agg(col.column_name::text) cols from information_schema.tables tab
 join information_schema.columns col using(table_schema,table_name)
 where tab.table_schema='public' and tab.table_type='BASE TABLE' and tab.table_name in('careers','mgr_coach','cw_world','season_offers','career_seasons','mgr_spells','cw_coach','cw_coach_contracts','career_stats','wallet_ledger','user_cards','mgr_players','cw_contracts','cw_negotiations','cw_clubs','mgr_transfers','cw_players','cw_finance','base_match_rewards','econ_requests') group by tab.table_name;
do $$ begin perform 1 from public.careers order by id for update;end $$;
create temporary table _scoped_protected_before(career_id uuid,table_name text,predicate text,n bigint,hash text,primary key(career_id,table_name)) on commit drop;
do $$ declare c record;t record;pred text;h text;n bigint;begin
 for c in select id from public.careers order by id loop
  for t in select * from _scoped_table_scopes order by table_name loop
   pred:=case when t.table_name='careers' then 'id=$1' when 'career_id'=any(t.cols) then 'career_id=$1'
    when 'season_id'=any(t.cols) then 'season_id in(select id from public.career_seasons where career_id=$1)'
    when 'fixture_id'=any(t.cols) then 'fixture_id in(select f.id from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=$1)' end;
   if pred is null then continue;end if;
   execute format('select count(*),md5(coalesce(string_agg(h,'''' order by h),'''')) from(select md5(to_jsonb(x)::text) h from public.%I x where %s)z',t.table_name,pred) into n,h using c.id;
   insert into _scoped_protected_before values(c.id,t.table_name,pred,n,h);
  end loop;
 end loop;
end $$;






create or replace function public.cw_match_gate(p_career uuid,p_club text,p_comp text)
returns bigint language sql stable security definer set search_path=public as $$
 select least(case when strength<70 then case kind when 'continental' then 375 when 'cup' then 330 else 300 end else 3000 end,
  ceil(base*(case kind when 'continental' then 1.25 when 'cup' then 1.10 else 1 end)*factor))::bigint
 from(select s.strength,coalesce(cp.kind,'league') kind,
  case when s.strength<70 then greatest(100,least(300,200+(s.strength-55)*10))
   when s.strength<75 then 400+(s.strength-70)*100 else least(2500,1000+(s.strength-75)*100) end base,
  1+least(.10,greatest(-.10,(coalesce(c.prestige,s.strength)-s.strength)*.005)) factor
  from public.sim_clubs s left join public.cw_clubs c on c.club_id=s.id and c.career_id=p_career
  left join public.sim_competitions cp on cp.id=p_comp where s.id=p_club)x
$$;
create or replace function public.cw_match_prize(p_career uuid,p_club text,p_comp text)
returns bigint language sql stable security definer set search_path=public as $$
 select least(case when strength<70 then case kind when 'continental' then 200 when 'cup' then 190 else 175 end else 1200 end,
  ceil(base*(case kind when 'continental' then 1.25 when 'cup' then 1.10 else 1 end)*factor))::bigint
 from(select s.strength,coalesce(cp.kind,'league') kind,
  case when s.strength<70 then least(175,100+greatest(0,s.strength-55)*5)
   when s.strength<75 then 200+(s.strength-70)*25 else least(900,400+(s.strength-75)*30) end base,
  1+least(.10,greatest(-.10,(coalesce(c.prestige,s.strength)-s.strength)*.005)) factor
  from public.sim_clubs s left join public.cw_clubs c on c.club_id=s.id and c.career_id=p_career
  left join public.sim_competitions cp on cp.id=p_comp where s.id=p_club)x
$$;

CREATE OR REPLACE FUNCTION public.cw_register_transfer_before_v32(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

CREATE OR REPLACE FUNCTION public.career_world_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;w public.cw_world;
begin
 car:=public.cw_read_career();select * into w from public.cw_world where career_id=car.id;select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 return to_jsonb(w)-'career_id'||jsonb_build_object('economy',jsonb_build_object('version',54,'currency','BRL','unit_scale',1000,'personal_currency','coins'),
 'roster_revision',(select md5(coalesce(string_agg(player_id,',' order by player_id),'')) from public.mgr_players where career_id=car.id and club_id=own),
 'investment',public.cw_club_investment_status(car.id,own),
 'coach',(select to_jsonb(c)-'career_id' from public.cw_coach c where career_id=car.id),
 'club',(select to_jsonb(c)-'career_id'||jsonb_build_object('commercial_income',greatest(c.monthly_revenue,public.cw_commercial_income(own),ceil(public.cw_payroll(car.id,own)*1.12)::bigint),'stadium_income',public.cw_match_gate(car.id,own,null),'victory_prize',public.cw_match_prize(car.id,own,null),'payroll',public.cw_payroll(car.id,own),'reserved',public.cw_reserved(car.id,own),'available',public.cw_available_budget(car.id,own),'window_open',public.cw_window_open(public.cw_region(own),w.today),'next_window',public.cw_next_window(public.cw_region(own),w.today)) from public.cw_clubs c where career_id=car.id and club_id=own),
 'seasons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select ws.region,ws.year,s.status,ws.season_id,ws.starts_on,ws.ends_on from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id order by ws.starts_on desc limit 8)x),
 'due_matches',(select count(*) from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=car.id and (not public.cw_runtime_enabled(car.id) or f.season_id=w.primary_season) and fd.due_on<=w.today and f.status='pending' and not(f.season_id=w.primary_season and own is not null and own in(f.home_club,f.away_club))),
 'news_unread',(select count(*) from public.cw_news where career_id=car.id and not read));
end $function$;

CREATE OR REPLACE FUNCTION public.career_negotiations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;own text;d date;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;select today into d from public.cw_world where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.id,n.player_id,public.mgr_player_name(n.player_id) as player_name,n.seller_club,n.buyer_club,n.status,n.initiator,n.fee,n.installments,n.performance_bonus,n.monthly_salary,n.contract_years,n.signing_bonus,n.role,n.appearance_bonus,n.goal_bonus,n.created_on,n.reply_on,n.expires_on,n.register_on,n.round_no,n.response,n.valuation,
 case when n.buyer_club=own and n.initiator<>'renewal' then
  case when n.status='completed' and exists(select 1 from public.mgr_players mp join public.cw_contracts ct using(career_id,player_id)
    where mp.career_id=n.career_id and mp.player_id=n.player_id and mp.club_id=n.buyer_club and ct.club_id=n.buyer_club and ct.status='active' and ct.expires_on>=d) then 'registered'
   when n.status='completed' then 'left'
   when n.status in('agreed','precontract') then case when not public.cw_window_open(public.cw_region(n.buyer_club),d) then 'waiting_window' else 'waiting_registration' end
   when n.status in('player_pending','player_counter') then 'player_decision'
   when n.status in('club_pending','club_counter') then 'club_agreement'
   else 'not_registered' end end as arrival_status,
  public.cw_salary_demand(car.id,n.player_id,n.buyer_club) salary_demand,public.cw_minimum_signing(car.id,n.player_id,n.buyer_club) minimum_signing_bonus,
  public.cw_project_reason(car.id,n.player_id,n.buyer_club) project_reason,
  (select coalesce(jsonb_agg(jsonb_build_object('date',h.on_date,'actor',h.actor,'state',h.state,'explanation',h.explanation,'terms',h.terms) order by h.id),'[]') from public.cw_offer_history h where h.negotiation_id=n.id and h.career_id=car.id) as history
 from public.cw_negotiations n where n.career_id=car.id and own in(n.buyer_club,n.seller_club) order by n.created_on desc,n.id limit 60)x);
end $function$;

revoke all on function public.cw_match_gate(uuid,text,text),public.cw_match_prize(uuid,text,text),public.cw_register_transfer_before_v32(uuid) from public,anon,authenticated;
revoke all on function public.career_world_status(),public.career_negotiations() from public,anon;
grant execute on function public.career_world_status(),public.career_negotiations() to authenticated;
notify pgrst,'reload schema';

do $$ declare r record;h text;n bigint;begin
 for r in select * from _scoped_protected_before order by career_id,table_name loop
  execute format('select count(*),md5(coalesce(string_agg(h,'''' order by h),'''')) from(select md5(to_jsonb(x)::text) h from public.%I x where %s)z',r.table_name,r.predicate) into n,h using r.career_id;
  if n<>r.n or h<>r.hash then raise exception 'Protected progress differs in table %; deployment rolled back',r.table_name;end if;
 end loop;
 raise notice 'Protected progress verified for % careers, % table comparisons',(select count(distinct career_id) from _scoped_protected_before),(select count(*) from _scoped_protected_before);
end $$;
notify pgrst,'reload schema';
commit;
