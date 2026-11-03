-- Club economy and direct free-agent offers; source: evolution/54_club_economy.sql.
-- Atomic deployment: lock careers, compare protected rows per career, retain all existing progress.
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

-- Club accounting uses thousands of BRL internally; 1 stored unit = R$ 1,000.
-- Existing balances, contracts, offers, receipts and personal coins retain their purchasing power.
create table if not exists public.cw_club_economy_models(
 club_id text primary key references public.sim_clubs(id),version int not null default 54,
 catalogue_payroll bigint not null,monthly_commercial bigint not null);
insert into public.cw_club_economy_models(club_id,catalogue_payroll,monthly_commercial)
 select c.id,coalesce(sum(greatest(80,public.cw_salary_floor(p.id))) filter(where p.id is not null),0),greatest(1000,ceil(coalesce(sum(greatest(80,public.cw_salary_floor(p.id))) filter(where p.id is not null),0)*1.12))::bigint
 from public.sim_clubs c left join public.sim_players p on p.club_id=c.id and p.active group by c.id on conflict do nothing;
create table if not exists public.cw_economy_rollouts(
 career_id uuid not null,club_id text not null,applied_on date not null,primary key(career_id,club_id),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id) on delete cascade);
alter table public.cw_club_economy_models enable row level security;
alter table public.cw_economy_rollouts enable row level security;
revoke all on public.cw_club_economy_models,public.cw_economy_rollouts from public,anon,authenticated;

create or replace function public.cw_salary_floor(p_player text)
returns bigint language sql stable security definer set search_path=public as $$
 select greatest(50,ceil(power(greatest(1,r.rating-45),2)*.65+power(greatest(0,r.rating-75),2)*12))::bigint
 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=p_player
$$;
create or replace function public.cw_money_label(p_value numeric)
returns text language sql immutable set search_path=public as $$
 select 'R$ '||replace(to_char(coalesce(p_value,0)*1000,'FM999,999,999,999,999,990'),',','.')
$$;
create or replace function public.cw_commercial_income(p_club text)
returns bigint language sql stable security definer set search_path=public as $$
 select monthly_commercial from public.cw_club_economy_models where club_id=p_club
$$;
create or replace function public.cw_match_gate(p_career uuid,p_club text,p_comp text)
returns bigint language sql stable security definer set search_path=public as $$
 select least(3000,ceil((case when p<=65 then greatest(200,200+(p-55)*10)
  when p<75 then 350+(p-66)*65 else 1000+(p-75)*100 end)*m))::bigint
 from(select coalesce((select prestige from public.cw_clubs where career_id=p_career and club_id=p_club),(select strength from public.sim_clubs where id=p_club),55) p,
  coalesce((select case kind when 'continental' then 1.6 when 'cup' then 1.2 else 1 end from public.sim_competitions where id=p_comp),1) m)x
$$;
create or replace function public.cw_match_prize(p_career uuid,p_club text,p_comp text)
returns bigint language sql stable security definer set search_path=public as $$
 select ceil(greatest(200,250+greatest(0,p-55)*38)*m)::bigint
 from(select coalesce((select prestige from public.cw_clubs where career_id=p_career and club_id=p_club),(select strength from public.sim_clubs where id=p_club),55) p,
  coalesce((select case kind when 'continental' then 1.6 when 'cup' then 1.2 else 1 end from public.sim_competitions where id=p_comp),1) m)x
$$;
create or replace function public.cw_prepare_club_economy(p_career uuid,p_club text default null)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c record;d date;
begin
 perform 1 from public.careers where id=p_career for update;
 select today into d from public.cw_world where career_id=p_career;
 for c in select x.club_id from public.cw_clubs x where x.career_id=p_career
  and(p_club is not null and x.club_id=p_club or p_club is null and(
   not public.cw_runtime_enabled(p_career) or x.club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=x.club_id)))
  and not exists(select 1 from public.cw_economy_rollouts r where r.career_id=p_career and r.club_id=x.club_id)
  order by x.club_id loop
  update public.cw_clubs set monthly_revenue=greatest(monthly_revenue,public.cw_commercial_income(c.club_id),ceil(public.cw_payroll(p_career,c.club_id)*1.12)::bigint) where career_id=p_career and club_id=c.club_id;
  insert into public.cw_economy_rollouts values(p_career,c.club_id,d) on conflict do nothing;
 end loop;
end $$;
create or replace function public.cw_fixture_income(p_fixture bigint,p_club text)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('currency','BRL','scale',1000,
  'prize',coalesce(sum(amount) filter(where kind='match_prize'),0),
  'gate',coalesce(sum(amount) filter(where kind='matchday'),0),
  'operations',coalesce(sum(amount) filter(where kind='matchday_operations'),0),
  'total',coalesce(sum(amount),0))
 from public.cw_finance f join public.season_fixtures fx on fx.id=p_fixture join public.career_seasons s on s.id=fx.season_id
 where f.career_id=s.career_id and f.club_id=p_club and f.reference='match:'||p_fixture and f.kind in('matchday','matchday_operations','match_prize')
$$;

-- One transaction creates a direct personal offer; there is no seller-club fee/stage.
create or replace function public.career_free_agent_offer(p_player text,p_salary bigint,p_years int,p_signing bigint,p_role text,p_appearance bigint,p_goal bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
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
  where not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player) on conflict do nothing;
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
end $$;

-- Existing engines with localized club-economy changes.
CREATE OR REPLACE FUNCTION public.cw_result_news()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare c uuid;own text;winner text;loser text;sc public.sim_competitions;mult numeric;home public.cw_clubs;prize bigint;leader record;second_team record;
begin
 if new.status<>'played' or (tg_op='UPDATE' and old.status='played') then return new;end if;
 select career_id into c from public.career_seasons where id=new.season_id;
 if c is null or not exists(select 1 from public.cw_world where career_id=c) then return new;end if;
 select * into sc from public.sim_competitions where id=new.competition_id;
 select club_id into own from public.mgr_coach where career_id=c and status='employed';
 winner:=case when new.home_goals>new.away_goals then new.home_club when new.away_goals>new.home_goals then new.away_club else new.tie_winner end;
 loser:=case when winner=new.home_club then new.away_club when winner=new.away_club then new.home_club end;
 -- Stadium receipts and result prizes are club income, booked once per fixture.
 perform public.cw_ensure_club_finance(c,new.home_club);perform public.cw_ensure_club_finance(c,new.away_club);
 prize:=public.cw_match_gate(c,new.home_club,new.competition_id);
 if coalesce((public.sim_phase(new.competition_id,new.stage)->>'neutral')::boolean,new.stage='final') then
  for loser in select unnest(array[new.home_club,new.away_club]) loop
   perform public.cw_cash(c,loser,case when loser=new.home_club then ceil(prize/2.0)::bigint else floor(prize/2.0)::bigint end,'matchday','match:'||new.id,'Bilheteria compartilhada em campo neutro');
   perform public.cw_cash(c,loser,-ceil((case when loser=new.home_club then ceil(prize/2.0) else floor(prize/2.0) end)*.20)::bigint,'matchday_operations','match:'||new.id,'Operação da partida em campo neutro');
  end loop;
 else
  perform public.cw_cash(c,new.home_club,prize,'matchday','match:'||new.id,'Bilheteria: '||public.mgr_club_name(new.home_club)||' × '||public.mgr_club_name(new.away_club));
  perform public.cw_cash(c,new.home_club,-ceil(prize*.20)::bigint,'matchday_operations','match:'||new.id,'Operação do estádio');
 end if;
 if winner is not null then
  perform public.cw_cash(c,winner,public.cw_match_prize(c,winner,new.competition_id),'match_prize','match:'||new.id,'Premiação por vitória');
 else
  for loser in select unnest(array[new.home_club,new.away_club]) loop
   perform public.cw_cash(c,loser,ceil(public.cw_match_prize(c,loser,new.competition_id)/3.0)::bigint,'match_prize','match:'||new.id,'Premiação por empate');
  end loop;
 end if;
 loser:=case when winner=new.home_club then new.away_club when winner=new.away_club then new.home_club end;
 if own is null or own not in(new.home_club,new.away_club) then return new;end if;
 if new.tie_winner is not null and new.stage not in('league','group','swiss') then
  perform public.cw_news_add(c,'knockout:'||new.id,'result',public.mgr_club_name(new.tie_winner)||' avança de fase',public.mgr_club_name(loser)||' deixa a disputa de '||sc.name||'.',60,own,null,new.season_id,jsonb_build_object('fixture_id',new.id));
 end if;
 if new.player_match then
  perform public.cw_news_add(c,'user-result:'||new.id,'result',public.mgr_club_name(new.home_club)||' '||new.home_goals||' × '||new.away_goals||' '||public.mgr_club_name(new.away_club),sc.name||' · Rodada '||new.round_no||'.',90,own,null,new.season_id,jsonb_build_object('fixture_id',new.id));
 end if;
 if sc.kind='league' and new.round_no>=8 and not exists(select 1 from public.season_fixtures fx where fx.season_id=new.season_id and fx.competition_id=new.competition_id and fx.round_no=new.round_no and fx.status='pending') then
  select * into leader from public.sim_standings(new.season_id,new.competition_id,null) where pos=1;
  select * into second_team from public.sim_standings(new.season_id,new.competition_id,null) where pos=2;
  if leader.points-second_team.points<=2 and own in(leader.club_id,second_team.club_id) then
   perform public.cw_news_add(c,'race:'||new.season_id||':'||sc.id||':'||new.round_no,'race','Disputa pela liderança de '||sc.name,
    public.mgr_club_name(leader.club_id)||' e '||public.mgr_club_name(second_team.club_id)||' terminaram a rodada '||new.round_no||' separados por até dois pontos.',50,own,null,new.season_id);
  end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.base_award_match(p_fixture bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f public.season_fixtures;s public.career_seasons;club text;mine int;opp int;won boolean;mult numeric;award public.base_match_rewards;
begin
 select * into f from public.season_fixtures where id=p_fixture;
 if f.id is null or f.status<>'played' or not coalesce(f.player_match,false) then return;end if;
 if f.played_at is null or f.played_at<(select activated_at from public.base_card_release) then return;end if;
 select * into s from public.career_seasons where id=f.season_id;
 club:=coalesce(f.coach_club,s.club_id);
 if club is null or club not in(f.home_club,f.away_club) then return;end if;
 perform 1 from public.careers where id=s.career_id for update;
 mine:=case when f.home_club=club then f.home_goals else f.away_goals end;
 opp:=case when f.home_club=club then f.away_goals else f.home_goals end;
 won:=mine>opp or(mine=opp and f.home_pens is not null and case when f.home_club=club then f.home_pens>f.away_pens else f.away_pens>f.home_pens end);
 select c.xp_mult*(case public.mgr_stage_rank(f.competition_id,f.stage) when 5 then 1.5 when 4 then 1.2 when 3 then 1.2 when 2 then 1.2 else 1 end) into mult
  from public.sim_competitions c where c.id=f.competition_id;
 insert into public.base_match_rewards(fixture_id,season_id,career_id,coins,energy)
  values(f.id,s.id,s.career_id,0,won::int)
  on conflict do nothing returning * into award;
 if award.fixture_id is null then return;end if;
 if award.coins>0 then perform public.econ_apply(s.career_id,'coins',award.coins,'match_reward',f.id::text);end if;
 if award.energy>0 then perform public.econ_apply(s.career_id,'bonus_energy',1,'match_win_energy',f.id::text);end if;
end $function$;

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
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id;
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

CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;club public.cw_clubs;coach public.mgr_coach;risk numeric;rescue bigint;ref text;ct public.cw_contracts;staff public.cw_coach_contracts;paid bigint;balance bigint;
begin
 perform public.cw_prepare_club_economy(p_career);
 perform public.cw_ai_contracts_tick(p_career);
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 perform public.cw_repay_arrears(p_career);
 select * into coach from public.mgr_coach where career_id=p_career;
 for club in select * from public.cw_clubs where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career)) or club_id=coach.club_id) order by club_id loop
  risk:=least(100,round(100.0*club.debt/greatest(club.monthly_revenue*6,1)+case when club.cash<public.cw_payroll(p_career,club.club_id) then 25 else 0 end,2));
  update public.cw_clubs set financial_risk=risk,distress_since=case when risk>=75 then coalesce(distress_since,w.today) else null end where career_id=p_career and club_id=club.club_id and (financial_risk is distinct from risk or (risk>=75 and distress_since is null) or (risk<75 and distress_since is not null));
  if risk>=75 and club.rescue_year is distinct from extract(year from w.today)::int then
   rescue:=round(club.initial_budget*(select annual_rescue_fraction from public.cw_rules));
   perform public.cw_cash(p_career,club.club_id,rescue,'recovery',extract(year from w.today)::text,'Plano limitado de recuperação financeira');
   update public.cw_clubs set debt=debt+rescue,rescue_year=extract(year from w.today)::int where career_id=p_career and club_id=club.club_id;
   perform public.cw_news_add(p_career,'recovery:'||club.club_id||':'||extract(year from w.today),'finance',public.mgr_club_name(club.club_id)||' adota recuperação financeira',
    'A diretoria limita novas contratações e oferece um plano de recuperação. O clube segue disputando suas competições.',case when coach.club_id=club.club_id then 95 else 45 end,club.club_id);
  end if;
  if coach.club_id=club.club_id and risk>=75 then
   perform public.cw_news_add(p_career,'finance-warning:'||club.club_id||':'||to_char(w.today,'IYYY-IW'),'board','A diretoria cobra responsabilidade financeira',
    'A dívida ameaça a folha salarial. Venda atletas por negociação, reduza gastos ou invista recursos. Persistir nesta situação coloca seu emprego em risco.',95,club.club_id);
   if club.distress_since is not null and w.today-club.distress_since>=45 then
    update public.mgr_coach set board_confidence=greatest(0,board_confidence-3) where career_id=p_career;
    if w.today-club.distress_since>=60 then perform public.mgr_fire(p_career,'má gestão financeira persistente');end if;
   end if;
  end if;
 end loop;
 -- Expiry is a real release; pre-contracts are registered by the market service.
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today
  and(not public.cw_runtime_enabled(p_career) or club_id=coach.club_id or club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id and n.status='precontract')) for update loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.cw_ensure_club_finance(p_career uuid, p_club text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 public.cw_commercial_income(c.id),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where c.id=p_club on conflict do nothing
$function$;

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
 where mp.career_id=p_career on conflict do nothing;
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
 'coach',(select to_jsonb(c)-'career_id' from public.cw_coach c where career_id=car.id),
 'club',(select to_jsonb(c)-'career_id'||jsonb_build_object('commercial_income',greatest(c.monthly_revenue,public.cw_commercial_income(own),ceil(public.cw_payroll(car.id,own)*1.12)::bigint),'stadium_income',public.cw_match_gate(car.id,own,null),'victory_prize',public.cw_match_prize(car.id,own,null),'payroll',public.cw_payroll(car.id,own),'reserved',public.cw_reserved(car.id,own),'available',public.cw_available_budget(car.id,own),'window_open',public.cw_window_open(public.cw_region(own),w.today),'next_window',public.cw_next_window(public.cw_region(own),w.today)) from public.cw_clubs c where career_id=car.id and club_id=own),
 'seasons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select ws.region,ws.year,s.status,ws.season_id,ws.starts_on,ws.ends_on from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id order by ws.starts_on desc limit 8)x),
 'due_matches',(select count(*) from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=car.id and (not public.cw_runtime_enabled(car.id) or f.season_id=w.primary_season) and fd.due_on<=w.today and f.status='pending' and not(f.season_id=w.primary_season and own is not null and own in(f.home_club,f.away_club))),
 'news_unread',(select count(*) from public.cw_news where career_id=car.id and not read));
end $function$;

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
 if p_salary is null or p_salary not between 1 and 10000000 or p_years is null or (p_years<1 or p_years>(select max_contract_years from public.cw_rules)) or p_signing is null or p_signing not between 0 and 10000000 or p_role not in('key','starter','rotation','prospect') or p_appearance is null or p_appearance not between 0 and 1000000 or p_goal is null or p_goal not between 0 and 1000000 then raise exception 'Contrato inválido';end if;
 if n.initiator<>'renewal' and public.cw_project_reason(car.id,n.player_id,own) is not null then raise exception '%',public.cw_project_reason(car.id,n.player_id,own);end if;
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
  if n.initiator<>'renewal' and public.cw_project_reason(p_career,n.player_id,n.buyer_club) is not null then
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
  coalesce(public.mgr_club_name(n.seller_club),'Livre no mercado')||' → '||public.mgr_club_name(n.buyer_club)||'. Valor: '||public.cw_money_label(n.fee)||'. Contrato de '||n.contract_years||' anos.',
  case when own in(n.seller_club,n.buyer_club) then case when n.valuation>=150000 then 98 else 85 end else 45 end,n.buyer_club,n.player_id,null,
  jsonb_build_object('negotiation_id',n.id,'fee',n.fee,'from_club',n.seller_club,'to_club',n.buyer_club,'overall',(select round(rating) from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and sp.position=pr.pos where sp.id=n.player_id),'position',(select position from public.sim_players where id=n.player_id),'big_signing',n.valuation>=150000 and own=n.buyer_club and n.initiator<>'renewal'));
 perform public.cw_neg_history(n.id,'system','Registro concluído com pagamentos e vínculo únicos.');return true;
end $function$;

CREATE OR REPLACE FUNCTION public.career_player_release(p_player text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;ct public.cw_contracts;d date;prev jsonb;months int;cost bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_release');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and club_id=own and status='active' for update;
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

CREATE OR REPLACE FUNCTION public.cw_neg_inbox_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare own text;who text;pl text;buyer text;seller text;t text;b text;fee text;mine_buy boolean;
begin
 select club_id into own from public.mgr_coach where career_id=new.career_id and status='employed';
 if own is null or own not in(coalesce(new.buyer_club,''),coalesce(new.seller_club,'')) then return null;end if;
 if tg_op='UPDATE' and new.status is not distinct from old.status then return null;end if;
 pl:=public.mgr_player_name(new.player_id);buyer:=public.mgr_club_name(new.buyer_club);seller:=coalesce(public.mgr_club_name(new.seller_club),'o clube');
 fee:=public.cw_money_label(new.fee);mine_buy:=new.buyer_club=own;
 if tg_op='INSERT' then
  if new.initiator='ai' and new.seller_club=own and new.status='seller_review' then
   t:=buyer||' faz proposta por '||pl;b:='Oferta de '||fee||'. Aceite, recuse ou faça uma contraproposta até '||to_char(new.expires_on,'DD/MM')||'.';
  elsif new.initiator='ai' and new.seller_club=own and new.status='precontract' then
   t:=pl||' assina pré-contrato com '||buyer;b:='Sem renovação, o atleta deixa o clube de graça em '||to_char(new.register_on,'DD/MM/YYYY')||'.';
  else return null;end if;
 elsif new.status='club_counter' and mine_buy then t:=seller||' faz contraproposta por '||pl;b:='O clube pede '||fee||'. Responda até '||to_char(new.expires_on,'DD/MM')||'.';
 elsif new.status='player_counter' and mine_buy and old.status='club_pending' then t:=seller||' aceita negociar '||pl;b:='Clubes de acordo. Agora apresente salário, duração (até 5 anos) e papel ao atleta.';
 elsif new.status='player_counter' and mine_buy and old.status='player_pending' then t:=pl||' pede melhores condições';b:=coalesce(new.response,'O atleta quer um contrato melhor.')||' Pedido: '||public.cw_money_label(new.monthly_salary)||' por mês.';
 elsif new.status in('agreed','precontract') and mine_buy then
  t:=case when new.initiator='renewal' then pl||' aceita renovar' else 'Acordo fechado com '||pl end;
  b:=case when new.register_on>(select today from public.cw_world where career_id=new.career_id) then 'Registro em '||to_char(new.register_on,'DD/MM/YYYY')||'.' else 'Contrato registrado.' end;
 elsif new.status='completed' and new.initiator<>'renewal' then
  t:=case when mine_buy then pl||' é reforço do '||buyer else pl||' é vendido ao '||buyer end;
  b:=case when new.fee>0 then 'Valor: '||fee||'. ' else 'Transferência sem custo. ' end||'Contrato de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='completed' and new.initiator='renewal' then t:=pl||' renova contrato';b:='Novo vínculo de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='rejected' then
  who:=case when old.status='player_pending' then pl when mine_buy then seller else buyer end;
  t:=case when not mine_buy and old.status='player_pending' then pl||' recusa ir para o '||buyer when new.initiator='renewal' then pl||' recusa a renovação' else who||' recusa a proposta por '||pl end;
  b:=coalesce(new.response,'Negociação encerrada.');
 elsif new.status='expired' then t:='Proposta por '||pl||' expirou';b:='O prazo terminou sem acordo.';
 elsif new.status='failed_funds' then t:='Negócio por '||pl||' cancelado';b:=coalesce(new.response,'Orçamento insuficiente para concluir.');
 elsif new.status='cancelled' and old.status in('agreed','precontract','club_pending','player_pending') then t:='Negociação por '||pl||' cancelada';b:=coalesce(new.response,'');
 else return null;end if;
 perform public.cw_inbox_add(new.career_id,'neg:'||new.id||':'||new.status||':'||coalesce(new.round_no,0),'transfer','market',t,b,
  case when new.buyer_club=own then coalesce(new.seller_club,own) else new.buyer_club end,new.player_id,new.id,'open_negotiations');
 return null;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_career_adjust(p_career uuid, p_field text, p_amount numeric, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mc public.mgr_coach;cur bigint;delta bigint;rep numeric;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 if p_amount is null or p_amount=0 then raise exception 'Valor inválido.';end if;
 select * into mc from public.mgr_coach where career_id=p_career;
 if mc.career_id is null or not exists(select 1 from public.cw_world where career_id=p_career) then raise exception 'Este jogador ainda não entrou no modo Temporadas.';end if;
 if p_field='cash' then
  if mc.status<>'employed' or mc.club_id is null then raise exception 'O jogador está sem clube.';end if;
  if abs(p_amount)>100000000 then raise exception 'Valor acima do limite.';end if;
  select cash into cur from public.cw_clubs where career_id=p_career and club_id=mc.club_id;
  delta:=greatest(round(p_amount)::bigint,-cur);
  perform public.cw_cash(p_career,mc.club_id,delta,'admin_adjust','admin:'||gen_random_uuid(),'Ajuste da administração: '||left(trim(p_reason),120));
  perform public.admin_notify(p_career,'finance',case when delta>0 then 'Reforço no caixa do clube' else 'Ajuste no caixa do clube' end,
   public.mgr_club_name(mc.club_id)||(case when delta>0 then ' recebeu ' else ' teve retirado ' end)||public.cw_money_label(abs(delta))||' no caixa. Motivo: '||trim(p_reason));
 elsif p_field='reputation' then
  rep:=greatest(0,least(100,coalesce(mc.reputation,0)+p_amount));
  update public.mgr_coach set reputation=rep where career_id=p_career;
  perform public.admin_notify(p_career,'reputation','Sua reputação mudou',
   'Reputação de treinador: '||round(coalesce(mc.reputation,0))||' → '||round(rep)||'. Isso muda as propostas que você recebe. Motivo: '||trim(p_reason));
 else raise exception 'Campo inválido.';end if;
 insert into public.admin_actions(admin_id,action,career_id,detail) values(auth.uid(),'adjust',p_career,jsonb_build_object('field',p_field,'amount',p_amount,'reason',left(trim(p_reason),200)));
 return public.admin_career(p_career);
end $function$;

CREATE OR REPLACE FUNCTION public.career_club_invest(p_amount integer, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;club text;previous jsonb;cash bigint;
begin
 car:=public.mgr_lock();perform public.cw_ensure(car.id);
 previous:=public.econ_request_get(car.id,p_request,'club_invest');if previous is not null then return previous;end if;
 select club_id into club from public.mgr_coach where career_id=car.id and status='employed';
 if club is null then raise exception 'Assuma um clube antes de investir';end if;
 if p_amount is null or p_amount<1 or p_amount>1000000 then raise exception 'Investimento inválido';end if;
 perform public.econ_apply(car.id,'coins',-p_amount,'club_investment',p_request::text);
 cash:=public.cw_cash(car.id,club,p_amount,'coach_investment',p_request::text,'Investimento pessoal do treinador');
 perform public.cw_news_add(car.id,'investment:'||p_request,'finance','Treinador reforça o caixa do clube',p_amount||' moedas da carteira financiaram '||public.cw_money_label(p_amount)||' no caixa do clube.',70,club);
 return public.econ_request_save(car.id,p_request,'club_invest',jsonb_build_object('ok',true,'club_cash',cash,'personal_coins',car.coins-p_amount));
end $function$;

CREATE OR REPLACE FUNCTION public.mgr_after_user_match(p_fixture bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_f     public.season_fixtures;
  v_m     public.mgr_matches;
  v_s     public.career_seasons;
  v_c     public.mgr_coach;
  v_dp    record;   -- perfil de dificuldade em vigor (evolução 05: public.mgr_difficulty)
  v_comp  public.sim_competitions;
  v_side  char;
  v_my    int;
  v_opp   int;
  v_res   text;
  v_home  boolean;
  v_d     numeric;
  v_es    numeric;
  v_as    numeric;
  v_db    numeric;
  v_df    numeric;
  v_dr    numeric;
  v_pos   int;
  v_obj   public.mgr_objectives;
  v_out   boolean := false;   -- eliminado neste jogo
  v_adv   boolean := false;   -- classificado neste jogo
  v_streak int;
  v_mult  numeric;
  v_xp    int;
  v_coins int;
  v_fire  text;
  v_inj   jsonb;
  v_susp  jsonb;
  v_b0    numeric;
  v_f0    numeric;
  v_r0    numeric;
  v_lvl0  int;
  v_car   public.careers;
begin
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select * into v_c from public.mgr_coach where career_id = v_m.career_id for update;
  select * into v_comp from public.sim_competitions where id = v_f.competition_id;
  select * into v_car from public.careers where id = v_m.career_id;
  v_lvl0 := v_car.level;
  v_b0 := v_c.board_confidence; v_f0 := v_c.fan_mood; v_r0 := v_c.reputation;

  v_side := v_m.user_side;
  v_home := (v_side = 'h') and not coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_my  := case when v_side = 'h' then v_f.home_goals else v_f.away_goals end;
  v_opp := case when v_side = 'h' then v_f.away_goals else v_f.home_goals end;
  v_res := case when v_my > v_opp then 'win' when v_my = v_opp then 'draw' else 'loss' end;
  if v_f.tie_winner is not null then
    v_out := v_f.tie_winner <> v_c.club_id;
    v_adv := not v_out;
  end if;

  -- expectativa x resultado (força média do 11 de cada lado + mando)
  v_d := (v_m.state -> 'strength' ->> (case when v_side = 'h' then 0 else 1 end))::numeric
       - (v_m.state -> 'strength' ->> (case when v_side = 'h' then 1 else 0 end))::numeric
       + case when coalesce((v_m.state ->> 'neutral')::boolean, false) then 0 when v_home then 3 else -3 end;
  v_es := 1 / (1 + power(10, -v_d / 25));
  v_as := case v_res when 'win' then 1 when 'draw' then 0.5 else 0 end;

  -- diretoria: resultado x expectativa | torcida: também pesa a expectativa, mas cobra um pouco mais (e mais em casa)
  v_db := 8 * (v_as - v_es);
  v_df := 8 * (v_as - (0.15 + 0.7 * v_es + case when v_home then 0.05 else 0 end));
  if v_my - v_opp >= 3 then v_df := v_df + 2; v_db := v_db + 1; end if;
  if v_opp - v_my >= 3 then v_df := v_df - 4; v_db := v_db - 2; end if;
  if v_out then v_db := v_db - 6; v_df := v_df - 6; end if;
  if v_adv then v_db := v_db + 3; v_df := v_df + 3; end if;

  -- sequência de derrotas
  select count(*) into v_streak from (
    select case when (f.home_club = v_c.club_id and f.home_goals < f.away_goals) or (f.away_club = v_c.club_id and f.away_goals < f.home_goals) then 1 else 0 end as l
      from public.season_fixtures f
     where f.season_id = v_s.id and f.player_match and f.coach_club = v_c.club_id and f.status = 'played'
     order by f.played_at desc, f.id desc limit 4) x where x.l = 1;
  if v_streak >= 4 then v_df := v_df - 3; v_db := v_db - 2; end if;

  -- pressão da tabela na liga nacional (depois da 8ª rodada)
  select * into v_obj from public.mgr_objectives where spell_id = v_c.spell_id and season_id = v_s.id
     and competition_id = v_f.competition_id and kind = 'league_pos';
  if v_obj.id is not null and v_f.stage = 'league' then
    select t.pos into v_pos from public.sim_standings(v_s.id, v_f.competition_id, null) t where t.club_id = v_c.club_id;
    if (select count(*) from public.season_fixtures where season_id = v_s.id and competition_id = v_f.competition_id and stage = 'league' and status = 'played'
         and (home_club = v_c.club_id or away_club = v_c.club_id)) >= 8 then
      if v_pos > v_obj.target + 3 then v_db := v_db - 1.5; elsif v_pos <= v_obj.target then v_db := v_db + 0.6; end if;
      if v_pos > (select count(*) from public.season_participants where season_id = v_s.id and competition_id = v_f.competition_id) - 4 then
        v_df := v_df - 1;
      end if;
    end if;
  end if;

  v_dr := 1.0 * (v_as - v_es) + case when v_res = 'win' then 0.12 else 0 end + case when v_res = 'win' and v_d < -5 then 0.3 else 0 end;

  -- perfil de dificuldade (evolução 05): só suaviza QUEDAS de confiança/humor e acelera a reputação; o placar não muda
  v_dp := public.mgr_difficulty(v_c.career_id);
  if v_db < 0 then v_db := v_db * v_dp.board_loss_mult; end if;
  if v_df < 0 then v_df := v_df * v_dp.fan_loss_mult; end if;
  if v_dr > 0 then v_dr := v_dr * v_dp.rep_gain_mult; end if;

  update public.mgr_coach
     set board_confidence = round(greatest(0, least(100, board_confidence + v_db + (55 - board_confidence) * 0.02)), 2),
         fan_mood = round(greatest(0, least(100, fan_mood + v_df + (55 - fan_mood) * 0.04)), 2),
         reputation = round(greatest(0, least(100, reputation + v_dr)), 2),
         matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         gf = gf + v_my, ga = ga + v_opp
   where career_id = v_c.career_id
  returning * into v_c;
  update public.mgr_spells
     set matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         gf = gf + v_my, ga = ga + v_opp
   where id = v_c.spell_id;

  -- prêmios (moedas e XP da conta)
  v_mult  := v_comp.xp_mult * (case public.mgr_stage_rank(v_f.competition_id, v_f.stage) when 5 then 1.5 when 4 then 1.2 when 3 then 1.2 when 2 then 1.2 else 1 end);
  v_xp := 0;
  v_coins := coalesce((select coins from public.base_match_rewards where fixture_id=p_fixture),0);
  -- Account resources are credited once by base_fixture_reward.
  update public.career_seasons
     set matches = matches + 1, wins = wins + (v_res = 'win')::int, draws = draws + (v_res = 'draw')::int, losses = losses + (v_res = 'loss')::int,
         xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins
   where id = v_s.id;

  -- departamento médico e disciplina (do seu time)
  select coalesce(jsonb_agg(jsonb_build_object('player', mp.player_id, 'name', p.short_name, 'injury', mp.injury,
                                              'days', mp.injured_until - v_s.day_no)), '[]'::jsonb)
    into v_inj
    from public.mgr_match_players x join public.mgr_players mp on mp.career_id = v_c.career_id and mp.player_id = x.player_id
    join public.sim_players p on p.id = x.player_id
   where x.fixture_id = p_fixture and x.side = v_side and x.injured;
  select coalesce(jsonb_agg(jsonb_build_object('player', mp.player_id, 'name', p.short_name, 'games', (mp.susp ->> v_f.competition_id)::int)), '[]'::jsonb)
    into v_susp
    from public.mgr_match_players x join public.mgr_players mp on mp.career_id = v_c.career_id and mp.player_id = x.player_id
    join public.sim_players p on p.id = x.player_id
   where x.fixture_id = p_fixture and x.side = v_side and coalesce((mp.susp ->> v_f.competition_id)::int, 0) > 0;
  if jsonb_array_length(v_inj) > 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'medical', 'Departamento médico',
      (select string_agg(format('%s: %s (%s dia%s fora)', e ->> 'name', e ->> 'injury', e ->> 'days',
                                case when (e ->> 'days')::int = 1 then '' else 's' end), ' · ') from jsonb_array_elements(v_inj) e), v_c.club_id);
  end if;
  if jsonb_array_length(v_susp) > 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'press', 'Suspensão',
      (select string_agg(format('%s cumpre %s jogo%s de suspensão (%s)', e ->> 'name', e ->> 'games',
                                case when (e ->> 'games')::int = 1 then '' else 's' end, v_comp.short_name), ' · ') from jsonb_array_elements(v_susp) e), v_c.club_id);
  end if;

  -- avisos da diretoria e da torcida
  if v_c.board_confidence < 22 and v_c.warned < 2 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'board', 'Ultimato da diretoria',
      'A paciência acabou. Sem resultados imediatos, o seu cargo estará em risco.', v_c.club_id);
    update public.mgr_coach set warned = 2 where career_id = v_c.career_id;
  elsif v_c.board_confidence < 35 and v_c.warned < 1 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'board', 'Diretoria preocupada',
      'Os resultados estão abaixo do esperado. A diretoria quer ver reação nos próximos jogos.', v_c.club_id);
    update public.mgr_coach set warned = 1 where career_id = v_c.career_id;
  elsif v_c.board_confidence > 45 and v_c.warned > 0 then
    update public.mgr_coach set warned = 0 where career_id = v_c.career_id;
  end if;
  if v_c.fan_mood < 25 and v_c.fan_warned = 0 then
    perform public.mgr_msg(v_c.career_id, v_s.id, v_s.day_no, 'fans', 'Protesto da torcida',
      'Faixas e vaias no estádio: a torcida pede a saída do treinador.', v_c.club_id);
    update public.mgr_coach set fan_warned = 1 where career_id = v_c.career_id;
  elsif v_c.fan_mood > 40 and v_c.fan_warned = 1 then
    update public.mgr_coach set fan_warned = 0 where career_id = v_c.career_id;
  end if;

  -- DEMISSÃO: desempenho muito ruim ou pressão da torcida (depois de pelo menos 6 jogos no clube)
  if (select matches from public.mgr_spells where id = v_c.spell_id) >= 6 then
    if v_c.board_confidence <= v_dp.fire_threshold then v_fire := 'resultados muito abaixo do esperado';
    elsif v_c.board_confidence <= 25 and v_c.fan_mood <= 15 then v_fire := 'pressão da torcida';
    end if;
  end if;

  return jsonb_build_object(
    'result', v_res, 'my_goals', v_my, 'opp_goals', v_opp, 'eliminated', v_out, 'advanced', v_adv,
    'expected', round(v_es, 2),
    'board', jsonb_build_object('before', round(v_b0), 'after', round(v_c.board_confidence), 'delta', round(v_c.board_confidence - v_b0, 1)),
    'fans', jsonb_build_object('before', round(v_f0), 'after', round(v_c.fan_mood), 'delta', round(v_c.fan_mood - v_f0, 1)),
    'reputation', jsonb_build_object('before', round(v_r0, 1), 'after', round(v_c.reputation, 1), 'delta', round(v_c.reputation - v_r0, 2)),
    'rewards', jsonb_build_object('energy', coalesce((select energy from public.base_match_rewards where fixture_id=p_fixture),0), 'xp', v_xp, 'coins', v_coins)||jsonb_build_object('club',public.cw_fixture_income(p_fixture,coalesce((select coach_club from public.season_fixtures where id=p_fixture),(select club_id from public.career_seasons where id=(select season_id from public.season_fixtures where id=p_fixture))))),
    'injuries', v_inj, 'suspensions', v_susp,
    'fire_reason', v_fire);
end;
$function$;

CREATE OR REPLACE FUNCTION public.season_play()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_c     public.careers;
  v_s     public.career_seasons;
  v_cid   text;
  v_ev    record;
  v_comp  public.sim_competitions;
  v_sc    public.season_competitions;
  v_f     public.season_fixtures;
  v_f2    public.season_fixtures;
  v_lvl0  int;
  v_home  boolean;
  v_sh    int;
  v_sa    int;
  v_q     double precision;
  v_gs    double precision;
  v_as    double precision;
  v_fac   double precision;
  v_sco   int[];
  v_hg    int;
  v_ag    int;
  v_my    int;
  v_opp   int;
  v_pg    int := 0;
  v_pa    int := 0;
  v_i     int;
  v_res   text;
  v_rat   numeric;
  v_mult  numeric;
  v_xp    int;
  v_coins int;
  v_pop   int;     -- popularidade TOTAL (para a chance de proposta)
  v_dpop  int;     -- variação de popularidade desta partida
  v_pending int;
  v_cst   text;
  v_offer jsonb;
  v_round jsonb;
  v_comp_done boolean := false;
  v_season_done boolean := false;
begin
  v_c := public.sim_lock_career();
  v_lvl0 := v_c.level;
  if v_c.energy + v_c.bonus_energy < 1 then
    raise exception 'Sem energia. Espere a recarga para simular a próxima partida.';
  end if;

  select * into v_s from public.career_seasons where career_id = v_c.id and status = 'active';
  if not found then raise exception 'Não há temporada em andamento. Inicie a próxima temporada.'; end if;

  -- O calendário decide qual campeonato é o próximo. Só dá para jogar se for dia de jogo do SEU clube.
  select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
  if not found then raise exception 'Não há partidas pendentes nesta temporada.'; end if;
  if v_ev.o_kind <> 'mine' then
    raise exception 'Hoje não é dia de jogo do seu clube. Toque em "Próximo" para avançar os outros campeonatos.';
  end if;
  v_cid := v_ev.o_comp;

  select * into v_comp from public.sim_competitions where id = v_cid;
  if not found then raise exception 'Campeonato inválido'; end if;
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_cid;

  select * into v_f from public.season_fixtures
   where season_id = v_s.id and competition_id = v_cid and status = 'pending'
     and (home_club = v_s.club_id or away_club = v_s.club_id)
   order by round_no, id limit 1;
  if not found then raise exception 'Seu clube não tem partidas pendentes neste campeonato.'; end if;

  -- gasta a energia livre primeiro; a bônus (comprada) só quando a livre acabar
  if v_c.energy >= 1 then
    update public.careers set energy = energy - 1 where id = v_c.id;
  else
    update public.careers set bonus_energy = bonus_energy - 1 where id = v_c.id;
  end if;

  -- ---- a partida ----------------------------------------------------
  v_home := (v_f.home_club = v_s.club_id);
  select strength into v_sh from public.sim_clubs where id = v_f.home_club;
  select strength into v_sa from public.sim_clubs where id = v_f.away_club;

  -- qualidade do jogador: sobe com o nível (nível 1 = 0.28 ... nível 24+ = 0.95)
  v_q := least(0.95, 0.25 + 0.03 * v_c.level);

  v_sco := public.sim_score(v_sh, v_sa, v_f.stage = 'final',
             case when v_home then 1 + 0.18 * v_q else 1 - 0.06 * v_q end,
             case when v_home then 1 - 0.06 * v_q else 1 + 0.18 * v_q end);
  v_hg := v_sco[1];  v_ag := v_sco[2];
  v_my  := case when v_home then v_hg else v_ag end;
  v_opp := case when v_home then v_ag else v_hg end;
  v_res := case when v_my > v_opp then 'win' when v_my = v_opp then 'draw' else 'loss' end;

  -- chance de o gol / a assistência do SEU time ter sido seu: depende da POSIÇÃO e do NÍVEL
  v_gs := case v_c.position when 'ATA' then 0.36 when 'PE' then 0.26 when 'PD' then 0.26 when 'MEI' then 0.24
            when 'MC' then 0.12 when 'VOL' then 0.05 when 'LD' then 0.05 when 'LE' then 0.05
            when 'ZAG' then 0.06 when 'GOL' then 0.002 else 0.12 end;
  v_as := case v_c.position when 'ATA' then 0.15 when 'PE' then 0.25 when 'PD' then 0.25 when 'MEI' then 0.32
            when 'MC' then 0.28 when 'VOL' then 0.12 when 'LD' then 0.22 when 'LE' then 0.22
            when 'ZAG' then 0.04 when 'GOL' then 0.02 else 0.12 end;
  v_fac := 0.35 + 0.65 * v_q;
  for v_i in 1 .. v_my loop
    if random() < v_gs * v_fac then v_pg := v_pg + 1;
    elsif random() < v_as * v_fac then v_pa := v_pa + 1;
    end if;
  end loop;

  -- nota da partida (3.0 a 10.0)
  v_rat := 5.8 + 1.0 * (v_q - 0.5)
         + case v_res when 'win' then 0.6 when 'draw' then 0.1 else -0.4 end
         + v_pg * 1.1 + v_pa * 0.6
         + case when v_opp = 0 and v_c.position in ('GOL', 'ZAG', 'LD', 'LE', 'VOL') then 0.7 else 0 end
         + (random() - 0.5) * 1.2;
  v_rat := round(greatest(3.0, least(10.0, v_rat))::numeric, 1);

  update public.season_fixtures
     set home_goals = v_hg, away_goals = v_ag, status = 'played', player_match = true,
         player_goals = v_pg, player_assists = v_pa, player_rating = v_rat, played_at = now()
   where id = v_f.id;
  update public.season_competitions set status = 'active'
   where season_id = v_s.id and competition_id = v_cid and status = 'pending';

  -- ---- prêmios, estatísticas e popularidade -------------------------
  v_mult := v_comp.xp_mult * (case v_f.stage when 'final' then 1.5 when 'r16' then 1.2 when 'qf' then 1.2 when 'sf' then 1.2 else 1 end);
  v_xp := 0;
  v_coins := coalesce((select coins from public.base_match_rewards where fixture_id=v_f.id),0);
  v_dpop  := (case v_res when 'win' then 8 when 'draw' then 3 else -2 end) + v_pg * 6 + v_pa * 4
           + (case when v_rat >= 8 then 5 when v_rat < 5 then -3 else 0 end)
           + (case when v_f.stage in ('r16', 'qf', 'sf', 'final') then 2 else 0 end);

  -- Account resources are credited once by base_fixture_reward.

  update public.career_stats
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         popularity = greatest(0, least(1000, popularity + v_dpop)),
         updated_at = now()
   where career_id = v_c.id;

  update public.career_seasons
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins
   where id = v_s.id;

  -- ---- o resto da rodada, o próximo mata-mata e o fim do campeonato --
  perform public.sim_play_round(v_s.id, v_cid, v_f.stage, v_f.round_no);
  perform public.sim_advance(v_s.id, v_cid);

  -- (se o seu clube caiu, o campeonato continua no calendário: os próximos dias viram "Próximo")
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_cid;
  v_comp_done := (v_sc.status = 'finished');

  -- ---- proposta de outro clube? -------------------------------------
  select popularity into v_pop from public.career_stats where career_id = v_c.id;
  v_offer := public.sim_maybe_offer(v_c.id, v_s.id, v_s.club_id, v_pop);

  -- ---- acabou a temporada? ------------------------------------------
  if not exists (select 1 from public.season_fixtures where season_id = v_s.id and status = 'pending') then
    perform public.sim_finalize_season(v_s.id);
    v_season_done := true;
  end if;

  -- ---- resposta para a tela -----------------------------------------
  select * into v_c  from public.careers where id = v_c.id;
  select * into v_f2 from public.season_fixtures where id = v_f.id;
  select jsonb_agg(jsonb_build_object('home', o.home_club, 'away', o.away_club, 'hg', o.home_goals, 'ag', o.away_goals, 'group', o.group_label) order by o.id)
    into v_round
    from public.season_fixtures o
   where o.season_id = v_s.id and o.competition_id = v_cid and o.stage = v_f.stage
     and o.round_no = v_f.round_no and o.id <> v_f.id;

  return jsonb_build_object(
    'competition', v_cid,
    'stage', v_f.stage, 'round', v_f.round_no, 'leg', v_f.leg, 'group', v_f.group_label,
    'venue', case when v_home then 'home' else 'away' end,
    'home', v_f2.home_club, 'away', v_f2.away_club,
    'home_goals', v_f2.home_goals, 'away_goals', v_f2.away_goals,
    'home_pens', v_f2.home_pens, 'away_pens', v_f2.away_pens, 'tie_winner', v_f2.tie_winner,
    'my_club', v_s.club_id, 'result', v_res,
    'player', jsonb_build_object('goals', v_pg, 'assists', v_pa, 'rating', v_rat),
    'rewards', jsonb_build_object('energy', coalesce((select energy from public.base_match_rewards where fixture_id=v_f.id),0), 'xp', v_xp, 'coins', v_coins, 'popularity', v_dpop)||jsonb_build_object('club',public.cw_fixture_income(v_f.id,v_s.club_id)),
    'level_up', v_c.level > v_lvl0, 'new_level', v_c.level,
    'round_results', coalesce(v_round, '[]'::jsonb),
    'competition_finished', v_comp_done,
    'competition_result', case when v_comp_done then v_sc.player_result end,
    'competition_bonus', case when v_comp_done and coalesce(v_sc.player_bonus_xp, 0) + coalesce(v_sc.player_bonus_coins, 0) > 0
                              then jsonb_build_object('xp', v_sc.player_bonus_xp, 'coins', v_sc.player_bonus_coins) end,
    'champion', case when v_comp_done then v_sc.champion_club end,
    'offer', v_offer,
    'season_finished', v_season_done,
    'energy', v_c.energy + v_c.bonus_energy);
end;
$function$;

-- Keep renewal defaults in sync with the server's salary demand.
do $$ begin if to_regprocedure('public.career_contract_renew_before_v54(text,uuid)') is null then
 alter function public.career_contract_renew(text,uuid) rename to career_contract_renew_before_v54;
end if;end $$;
create or replace function public.career_contract_renew(p_player text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;cid uuid;own text;
begin
 r:=public.career_contract_renew_before_v54(p_player,p_request);
 cid:=public.cw_current_career();select club_id into own from public.mgr_coach where career_id=cid and status='employed';
 return r||jsonb_build_object('salary_demand',public.cw_salary_demand(cid,p_player,own));
end $$;
revoke all on function public.career_contract_renew_before_v54(text,uuid) from public,anon,authenticated;
revoke all on function public.career_contract_renew(text,uuid) from public,anon;
grant execute on function public.career_contract_renew(text,uuid) to authenticated;

revoke all on function public.cw_money_label(numeric),public.cw_commercial_income(text),public.cw_match_gate(uuid,text,text),
 public.cw_match_prize(uuid,text,text),public.cw_prepare_club_economy(uuid,text),public.cw_fixture_income(bigint,text)
 from public,anon,authenticated;
revoke all on function public.career_free_agent_offer(text,bigint,integer,bigint,text,bigint,bigint,uuid) from public,anon;
grant execute on function public.career_free_agent_offer(text,bigint,integer,bigint,text,bigint,bigint,uuid) to authenticated;
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
