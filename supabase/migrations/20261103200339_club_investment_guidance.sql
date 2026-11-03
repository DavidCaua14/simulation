-- Optional club funding and board support; source: evolution/56_club_investment_guidance.sql.
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




create table if not exists public.cw_board_contributions(
 career_id uuid not null references public.careers(id) on delete cascade,
 club_id text not null references public.sim_clubs(id),season_year int not null,
 eligible_coins bigint not null default 0 check(eligible_coins>=0),
 bonus_paid bigint not null default 0 check(bonus_paid>=0),
 primary key(career_id,club_id,season_year),check(bonus_paid=eligible_coins/5));
create table if not exists public.cw_funding_dismissals(
 career_id uuid not null references public.careers(id) on delete cascade,
 club_id text not null references public.sim_clubs(id),signal_key text not null,
 primary key(career_id,club_id));
alter table public.cw_board_contributions enable row level security;
alter table public.cw_funding_dismissals enable row level security;
revoke all on public.cw_board_contributions,public.cw_funding_dismissals from public,anon,authenticated;

create or replace function public.cw_board_support(p_career uuid,p_club text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare yr int;cap bigint;eligible bigint;paid bigint;
begin
 select s.year into yr from public.cw_world w join public.career_seasons s on s.id=w.primary_season where w.career_id=p_career;
 select case when strength>=80 then 1000 when strength>=70 then 400 else 200 end into cap from public.sim_clubs where id=p_club;
 select eligible_coins,bonus_paid into eligible,paid from public.cw_board_contributions where career_id=p_career and club_id=p_club and season_year=yr;
 return jsonb_build_object('season_year',yr,'rate_percent',20,'bonus_cap',coalesce(cap,0),'eligible_coins',coalesce(eligible,0),
  'bonus_paid',coalesce(paid,0),'bonus_remaining',greatest(0,coalesce(cap,0)-coalesce(paid,0)));
end $$;
create or replace function public.cw_board_bonus(p_board jsonb,p_amount bigint)
returns bigint language sql immutable set search_path=public as $$
 select greatest(0,least((p_board->>'bonus_cap')::bigint,
  ((p_board->>'eligible_coins')::bigint+greatest(0,p_amount))/5)-(p_board->>'bonus_paid')::bigint)
$$;
create or replace function public.cw_funding_coins(p_gap bigint,p_board jsonb)
returns bigint language plpgsql immutable set search_path=public as $$
declare lo bigint:=0;hi bigint:=greatest(0,p_gap);mid bigint;
begin
 while lo<hi loop
  mid:=lo+(hi-lo)/2;
  if mid+public.cw_board_bonus(p_board,mid)>=p_gap then hi:=mid;else lo:=mid+1;end if;
 end loop;
 return lo;
end $$;

create or replace function public.cw_funding_quote(p_career uuid,p_player text,p_negotiation uuid,p_terms jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare own text;d date;player text:=p_player;n public.cw_negotiations;c public.cw_clubs;ct public.cw_contracts;
 owner text;renewal boolean;terms jsonb;fee bigint;salary bigint;signing bigint;appearance bigint;goals bigint;performance bigint;years int;role text;
 demand bigint;minimum_signing bigint;payroll bigint;reserved bigint;previous_reserve bigint:=0;existing bigint:=0;increment bigint;needed bigint;gap bigint;coins bigint;wallet bigint;reason text;board jsonb;months int;precontract boolean;cnt int;
begin
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select today into d from public.cw_world where career_id=p_career;
 if own is null or d is null then raise exception 'Assuma um clube para planejar um aporte';end if;
 if jsonb_typeof(coalesce(p_terms,'{}'))<>'object' then raise exception 'Condições inválidas';end if;
 terms:=coalesce(p_terms,'{}');
 if p_negotiation is not null then
  select * into n from public.cw_negotiations where id=p_negotiation and career_id=p_career and buyer_club=own;
  if not found then raise exception 'Negociação indisponível para este clube';end if;
  if player is not null and player<>n.player_id then raise exception 'Atleta diferente da negociação';end if;
  player:=n.player_id;terms:=(to_jsonb(n)-'decision_roll')||terms;
 end if;
 if player is null or not exists(select 1 from public.sim_players where id=player and active) then raise exception 'Atleta indisponível';end if;
 owner:=public.cw_effective_player_club(p_career,player);
 renewal:=case when n.id is not null then n.initiator='renewal' else owner=own end;
 renewal:=coalesce(renewal,false);
 select * into c from public.cw_clubs where career_id=p_career and club_id=own;
 if c.club_id is null then raise exception 'Finanças do clube indisponíveis';end if;
 select * into ct from public.cw_contracts where career_id=p_career and player_id=player and status='active';
 demand:=public.cw_salary_demand(p_career,player,own);
 minimum_signing:=case when owner is null and not renewal then public.cw_minimum_signing(p_career,player,own) else 0 end;
 fee:=coalesce((terms->>'fee')::bigint,0);salary:=coalesce((terms->>'monthly_salary')::bigint,demand);
 signing:=coalesce((terms->>'signing_bonus')::bigint,minimum_signing);appearance:=coalesce((terms->>'appearance_bonus')::bigint,0);
 goals:=coalesce((terms->>'goal_bonus')::bigint,0);performance:=coalesce((terms->>'performance_bonus')::bigint,0);
 years:=coalesce((terms->>'contract_years')::int,2);role:=coalesce(terms->>'role','rotation');precontract:=coalesce((terms->>'precontract')::boolean,false);
 if fee not between 0 and 100000000 or salary not between 1 and 10000000 or signing not between 0 and 10000000
  or appearance not between 0 and 1000000 or goals not between 0 and 1000000 or performance not between 0 and 10000000
  or years not between 1 and(select max_contract_years from public.cw_rules) or role not in('key','starter','rotation','prospect') then raise exception 'Condições inválidas';end if;
 if renewal or precontract or owner is null then fee:=0;end if;
 if n.id is not null and(n.status not in('club_counter','player_counter','club_pending','player_pending') or n.expires_on<d) then reason:='A negociação não está disponível para novas condições.';
 elsif renewal and not public.cw_valid_renewal(p_career,player,own,d) then reason:='A renovação exige um atleta e um contrato vigentes do seu clube.';
 elsif not renewal and not public.cw_window_open(public.cw_region(own),d) then reason:='Janela de transferências fechada. Apenas renovações do seu elenco estão disponíveis.';
 elsif c.financial_risk>=75 then reason:='O clube está sob restrição financeira. Reveja as dívidas e o planejamento antes de negociar.';
 elsif public.cw_project_reason(p_career,player,own) is not null then reason:=public.cw_project_reason(p_career,player,own);
 elsif salary<demand then reason:='O salário oferecido está abaixo do valor exigido pelo atleta.';
 elsif signing<minimum_signing then reason:='As luvas oferecidas estão abaixo do valor exigido pelo atleta livre.';
 elsif precontract and(owner is null or ct.id is null or ct.expires_on>d+180) then reason:='O pré-contrato exige um vínculo nos últimos seis meses.';
 elsif not renewal and public.cw_registered_in_window(p_career,own,d)>=6 then reason:='O limite de contratações registradas nesta janela foi atingido.';
 end if;
 if not renewal and reason is null and coalesce(public.cw_age(p_career,player),0)>=21 then
  select count(*) into cnt from public.cw_negotiations x where x.career_id=p_career and x.buyer_club=own and x.initiator<>'renewal' and x.status in('agreed','precontract') and coalesce(public.cw_age(p_career,x.player_id),0)>=21;
  if public.cw_squad_count(p_career,own)+cnt>=public.cw_squad_limit() then reason:='O elenco atingiu o limite de atletas adultos. Negocie uma saída antes de contratar.';end if;
 end if;
 payroll:=public.cw_payroll(p_career,own);reserved:=public.cw_reserved(p_career,own);
 if n.id is not null then
  select coalesce(sum(amount),0) into previous_reserve from public.cw_commitments where career_id=p_career and negotiation_id=n.id and club_id=own and kind='offer' and status='reserved';
 end if;
 if ct.club_id=own then existing:=public.cw_contract_cost(player,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role);end if;
 increment:=greatest(0,public.cw_contract_cost(player,salary,appearance,goals,role)-existing);
 select reserve_salary_months into months from public.cw_rules;
 needed:=fee+signing+performance+greatest(6,months)*increment;
 gap:=greatest(0,needed+months*payroll+c.debt+reserved-previous_reserve-c.cash);
 board:=public.cw_board_support(p_career,own);coins:=public.cw_funding_coins(gap,board);
 select coins into wallet from public.careers where id=p_career;
 return jsonb_build_object('club_id',own,'player_id',player,'renewal',renewal,'blocked_reason',reason,'salary_demand',demand,
  'fee',fee,'signing_bonus',signing,'performance_bonus',performance,'monthly_cost',public.cw_contract_cost(player,salary,appearance,goals,role),
  'increment',increment,'salary_reserve',greatest(6,months)*increment,'current_payroll_reserve',months*payroll,
  'reserved_other',reserved-previous_reserve,'debt',c.debt,'club_cash',c.cash,'required_cash',needed+months*payroll+c.debt+reserved-previous_reserve,
  'gap',gap,'coins_needed',coins,'personal_coins',wallet,'board_bonus',public.cw_board_bonus(board,coins),
  'can_invest',reason is null and gap>0 and coins<=least(wallet,1000000),'board',board);
end $$;
create or replace function public.career_funding_quote(p_player text default null,p_negotiation uuid default null,p_terms jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare car public.careers;
begin
 car:=public.cw_read_career();
 return public.cw_funding_quote(car.id,p_player,p_negotiation,p_terms);
end $$;

create or replace function public.career_club_investment_preview(p_amount int)
returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;c public.cw_clubs;board jsonb;bonus bigint;
begin
 car:=public.cw_read_career();select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if own is null then raise exception 'Assuma um clube antes de investir';end if;
 if p_amount is null or p_amount not between 1 and 1000000 then raise exception 'Investimento inválido';end if;
 select * into c from public.cw_clubs where career_id=car.id and club_id=own;
 if not found then raise exception 'Finanças do clube indisponíveis';end if;
 board:=public.cw_board_support(car.id,own);bonus:=public.cw_board_bonus(board,p_amount);
 return jsonb_build_object('club_id',own,'club_name',public.mgr_club_name(own),'amount',p_amount,'personal_before',car.coins,'personal_after',car.coins-p_amount,
  'cash_before',c.cash,'cash_after',c.cash+p_amount+bonus,'board_bonus',bonus,'club_credit',p_amount+bonus,'can_invest',car.coins>=p_amount,'board',board);
end $$;
create or replace function public.career_club_invest(p_amount integer,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;club text;previous jsonb;cash bigint;board jsonb;bonus bigint;eligible bigint;yr int;
begin
 car:=public.mgr_lock();previous:=public.econ_request_get(car.id,p_request,'club_invest');if previous is not null then return previous;end if;
 if p_request is null then raise exception 'Identificador do aporte obrigatório';end if;
 select club_id into club from public.mgr_coach where career_id=car.id and status='employed';
 if club is null then raise exception 'Assuma um clube antes de investir';end if;
 if p_amount is null or p_amount not between 1 and 1000000 then raise exception 'Investimento inválido';end if;
 if not exists(select 1 from public.cw_world where career_id=car.id) or not exists(select 1 from public.cw_clubs where career_id=car.id and club_id=club) then raise exception 'Abra a carreira para preparar as finanças do clube';end if;
 board:=public.cw_board_support(car.id,club);yr:=(board->>'season_year')::int;
 if yr is null then raise exception 'Temporada do clube indisponível';end if;
 bonus:=public.cw_board_bonus(board,p_amount);
 eligible:=least((board->>'bonus_cap')::bigint*5,(board->>'eligible_coins')::bigint+p_amount);
 perform public.econ_apply(car.id,'coins',-p_amount,'club_investment',p_request::text);
 cash:=public.cw_cash(car.id,club,p_amount,'coach_investment',p_request::text,'Aporte pessoal do treinador');
 if bonus>0 then cash:=public.cw_cash(car.id,club,bonus,'board_contribution',p_request::text,'Diretoria complementa 20% dos aportes da temporada',false,jsonb_build_object('season_year',yr));end if;
 insert into public.cw_board_contributions(career_id,club_id,season_year,eligible_coins,bonus_paid)
  values(car.id,club,yr,eligible,(board->>'bonus_paid')::bigint+bonus)
  on conflict(career_id,club_id,season_year) do update set eligible_coins=excluded.eligible_coins,bonus_paid=excluded.bonus_paid;
 perform public.cw_news_add(car.id,'investment:'||p_request,'finance','Treinador reforça o caixa do clube',
  p_amount||' moedas financiaram '||public.cw_money_label(p_amount)||'. A diretoria acrescentou '||public.cw_money_label(bonus)||'. O aporte permanece no clube se o treinador sair.',55,club);
 return public.econ_request_save(car.id,p_request,'club_invest',jsonb_build_object('ok',true,'club_id',club,'club_cash',cash,'personal_coins',car.coins-p_amount,'amount',p_amount,'board_bonus',bonus,'club_credit',p_amount+bonus));
end $$;
create or replace function public.career_club_investment_confirm(p_amount int,p_club text,p_expected_coins int,p_expected_cash bigint,p_expected_bonus bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;previous jsonb;q jsonb;
begin
 car:=public.mgr_lock();previous:=public.econ_request_get(car.id,p_request,'club_invest');if previous is not null then return previous;end if;
 q:=public.career_club_investment_preview(p_amount);
 if p_club is distinct from q->>'club_id' or p_expected_coins is distinct from(q->>'personal_before')::int
  or p_expected_cash is distinct from(q->>'cash_before')::bigint or p_expected_bonus is distinct from(q->>'board_bonus')::bigint then
  raise exception 'O clube ou os valores mudaram. Atualize a prévia e confirme o aporte novamente.';
 end if;
 return public.career_club_invest(p_amount,p_request);
end $$;

create or replace function public.cw_club_investment_status(p_career uuid,p_club text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare board jsonb;signal jsonb;q jsonb;ct record;n record;c public.cw_clubs;d date;payroll bigint;due bigint;forecast bigint;sigkey text;
begin
 if p_club is null then return null;end if;
 board:=public.cw_board_support(p_career,p_club);select today into d from public.cw_world where career_id=p_career;
 -- Only three active, already initiated negotiations are inspected. No world simulation or table writes.
 for n in select id,player_id,monthly_salary from public.cw_negotiations where career_id=p_career and buyer_club=p_club and status in('player_counter','club_counter') and expires_on>=d order by expires_on,id limit 3 loop
  q:=public.cw_funding_quote(p_career,n.player_id,n.id,case when n.monthly_salary=0 then jsonb_build_object('monthly_salary',public.cw_salary_demand(p_career,n.player_id,p_club)) else '{}'::jsonb end);
  if(q->>'gap')::bigint>0 and q->>'blocked_reason' is null then
   signal:=jsonb_build_object('kind','negotiation','negotiation_id',n.id,'player_id',n.player_id,'player_name',public.mgr_player_name(n.player_id),'gap',q->'gap','coins_needed',q->'coins_needed','action','deals');exit;
  end if;
 end loop;
 if signal is null then
  select x.id,x.player_id,x.expires_on,x.monthly_salary,public.cw_salary_demand(p_career,x.player_id,p_club) demand,
   public.cw_project_reason(p_career,x.player_id,p_club) project_reason into ct
  from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.club_id=p_club and x.status='active' and x.expires_on between d and d+90
   and not exists(select 1 from public.cw_negotiations y where y.career_id=p_career and y.player_id=x.player_id and y.status in('agreed','precontract'))
  order by x.expires_on,case x.role when 'key' then 0 when 'starter' then 1 else 2 end,x.player_id limit 1;
  if ct.id is not null then
   signal:=jsonb_build_object('kind','renewal','contract_id',ct.id,'player_id',ct.player_id,'player_name',public.mgr_player_name(ct.player_id),
    'expires_on',ct.expires_on,'salary_current',ct.monthly_salary,'salary_demand',ct.demand,'project_reason',ct.project_reason,'action','contracts');
  end if;
 end if;
 if signal is null then
  select * into c from public.cw_clubs where career_id=p_career and club_id=p_club;
  payroll:=public.cw_payroll(p_career,p_club);
  select coalesce(sum(amount),0) into due from public.cw_commitments where career_id=p_career and club_id=p_club and status='reserved' and kind<>'offer' and due_on<=d+90;
  forecast:=c.cash+3*(c.monthly_revenue-round(c.monthly_revenue*.12)::bigint)-3*payroll-c.debt-due;
  if forecast<0 then signal:=jsonb_build_object('kind','forecast','gap',-forecast,'action','finance','monthly_revenue',c.monthly_revenue,'monthly_operations',round(c.monthly_revenue*.12)::bigint,'monthly_payroll',payroll);end if;
 end if;
 if signal is not null then
  -- Key excludes today's date. A dismissed card stays hidden until its material facts change.
  sigkey:=md5(p_career::text||':'||p_club||':'||signal::text);
  signal:=signal||jsonb_build_object('key',sigkey);
  if exists(select 1 from public.cw_funding_dismissals where career_id=p_career and club_id=p_club and signal_key=sigkey) then signal:=null;end if;
 end if;
 return jsonb_build_object('board',board,'signal',signal);
end $$;
create or replace function public.career_funding_dismiss(p_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;s jsonb;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 s:=public.cw_club_investment_status(car.id,own)->'signal';
 if p_key is null or p_key is distinct from s->>'key' then return jsonb_build_object('ok',true,'stale',true);end if;
 insert into public.cw_funding_dismissals values(car.id,own,p_key) on conflict(career_id,club_id) do update set signal_key=excluded.signal_key;
 return jsonb_build_object('ok',true);
end $$;

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
 'investment',public.cw_club_investment_status(car.id,own),
 'coach',(select to_jsonb(c)-'career_id' from public.cw_coach c where career_id=car.id),
 'club',(select to_jsonb(c)-'career_id'||jsonb_build_object('commercial_income',greatest(c.monthly_revenue,public.cw_commercial_income(own),ceil(public.cw_payroll(car.id,own)*1.12)::bigint),'stadium_income',public.cw_match_gate(car.id,own,null),'victory_prize',public.cw_match_prize(car.id,own,null),'payroll',public.cw_payroll(car.id,own),'reserved',public.cw_reserved(car.id,own),'available',public.cw_available_budget(car.id,own),'window_open',public.cw_window_open(public.cw_region(own),w.today),'next_window',public.cw_next_window(public.cw_region(own),w.today)) from public.cw_clubs c where career_id=car.id and club_id=own),
 'seasons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select ws.region,ws.year,s.status,ws.season_id,ws.starts_on,ws.ends_on from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id order by ws.starts_on desc limit 8)x),
 'due_matches',(select count(*) from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=car.id and (not public.cw_runtime_enabled(car.id) or f.season_id=w.primary_season) and fd.due_on<=w.today and f.status='pending' and not(f.season_id=w.primary_season and own is not null and own in(f.home_club,f.away_club))),
 'news_unread',(select count(*) from public.cw_news where career_id=car.id and not read));
end $function$;

revoke all on function public.cw_board_support(uuid,text),public.cw_board_bonus(jsonb,bigint),public.cw_funding_coins(bigint,jsonb),public.cw_funding_quote(uuid,text,uuid,jsonb),public.cw_club_investment_status(uuid,text) from public,anon,authenticated;
revoke all on function public.career_funding_quote(text,uuid,jsonb),public.career_club_investment_preview(int),public.career_club_investment_confirm(int,text,int,bigint,bigint,uuid),public.career_funding_dismiss(text),public.career_club_invest(int,uuid),public.career_world_status() from public,anon;
grant execute on function public.career_funding_quote(text,uuid,jsonb),public.career_club_investment_preview(int),public.career_club_investment_confirm(int,text,int,bigint,bigint,uuid),public.career_funding_dismiss(text),public.career_club_invest(int,uuid),public.career_world_status() to authenticated;
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
