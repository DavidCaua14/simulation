-- Universo esportivo individual. Migração aditiva após cartas base (23).
begin;
alter table public.mgr_spells drop constraint if exists mgr_spells_end_reason_check;
alter table public.mgr_spells add constraint mgr_spells_end_reason_check check(end_reason in('fired','left','resigned','expired'));
alter table public.career_seasons drop constraint if exists career_seasons_mode_check;
alter table public.career_seasons add constraint career_seasons_mode_check check(mode in('player','coach','world'));
drop index if exists public.career_seasons_one_active_idx;
create unique index career_seasons_one_active_idx on public.career_seasons(career_id) where status='active' and mode<>'world';
create unique index if not exists cw_career_region_year_uq on public.career_seasons(career_id,region,year) where mode in('coach','world');
create unique index if not exists cw_season_region_active_uq on public.career_seasons(career_id,region) where status='active';
alter table public.career_seasons add column if not exists was_coached boolean not null default false;
create table if not exists public.cw_rules (
 id boolean primary key default true check(id),version int not null default 1,
 max_days_per_call int not null default 14 check(max_days_per_call between 1 and 31),
 max_matches_per_batch int not null default 24 check(max_matches_per_batch between 1 and 60),
 max_contract_years int not null default 5,max_negotiation_days int not null default 7,
 ai_bid_chance numeric not null default .018,ai_foreign_preference numeric not null default .30,
 reserve_salary_months int not null default 2,annual_rescue_fraction numeric not null default .15,
 rules jsonb not null default '{}'
);
insert into public.cw_rules(id) values(true) on conflict do nothing;
create table if not exists public.cw_rivalries (
 club_a text not null references public.sim_clubs(id),club_b text not null references public.sim_clubs(id),primary key(club_a,club_b),check(club_a<club_b)
);
insert into public.cw_rivalries
 select least(a,b),greatest(a,b) from(values('flamengo','vasco'),('flamengo','fluminense'),('flamengo','botafogo'),('palmeiras','corinthians'),('gremio','internacional'),('arsenal','tottenham'),('arsenal','chelsea'),('liverpool','everton'),('man-united','man-city'),('boca-juniors','river-plate'))x(a,b)
 where exists(select 1 from public.sim_clubs where id=a) and exists(select 1 from public.sim_clubs where id=b) on conflict do nothing;
create table if not exists public.cw_windows (
 region text not null,slot int not null,start_month int not null,start_day int not null,end_month int not null,end_day int not null,
 primary key(region,slot),check(start_month between 1 and 12 and end_month between 1 and 12),check(start_day between 1 and 31 and end_day between 1 and 31)
);
insert into public.cw_windows values('BRA',1,1,3,4,20),('BRA',2,7,10,9,2),('ENG',1,6,10,9,1),('ENG',2,1,1,2,2) on conflict do nothing;
create table if not exists public.cw_world (
 career_id uuid primary key references public.careers(id),today date not null,started_on date not null,
 elapsed_days int not null check(elapsed_days>=0),primary_season uuid,
 initialized_at timestamptz not null default now(),last_services_on date,needs_sync boolean not null default true,
 foreign key(primary_season,career_id) references public.career_seasons(id,career_id)
);
create table if not exists public.cw_seasons (
 career_id uuid not null,region text not null,year int not null,season_id uuid not null unique,
 starts_on date not null,ends_on date not null,primary key(career_id,region,year),
 foreign key(season_id,career_id) references public.career_seasons(id,career_id),check(ends_on>starts_on)
);
create table if not exists public.cw_fixture_dates (
 fixture_id bigint primary key,season_id uuid not null,career_id uuid not null,due_on date not null,
 constraint cw_fixture_owner_uq unique(fixture_id,career_id),foreign key(fixture_id,season_id) references public.season_fixtures(id,season_id),
 foreign key(season_id,career_id) references public.career_seasons(id,career_id)
);
create table if not exists public.cw_club_dates (
 career_id uuid not null references public.careers(id),club_id text not null references public.sim_clubs(id),due_on date not null,
 fixture_id bigint not null references public.season_fixtures(id),constraint cw_club_fixture_owner_fk foreign key(fixture_id,career_id) references public.cw_fixture_dates(fixture_id,career_id),primary key(career_id,club_id,due_on),unique(fixture_id,club_id)
);
do $owners$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.cw_fixture_dates'::regclass and conname='cw_fixture_owner_uq') then alter table public.cw_fixture_dates add constraint cw_fixture_owner_uq unique(fixture_id,career_id);end if;
 if not exists(select 1 from pg_constraint where conrelid='public.cw_club_dates'::regclass and conname='cw_club_fixture_owner_fk') then alter table public.cw_club_dates add constraint cw_club_fixture_owner_fk foreign key(fixture_id,career_id) references public.cw_fixture_dates(fixture_id,career_id);end if;
end $owners$;
create index if not exists cw_fixture_due_idx on public.cw_fixture_dates(career_id,due_on,fixture_id);
create table if not exists public.cw_clubs (
 career_id uuid not null references public.careers(id),club_id text not null references public.sim_clubs(id),
 cash bigint not null check(cash>=0),debt bigint not null default 0 check(debt>=0),
 infrastructure bigint not null default 0,initial_budget bigint not null,monthly_revenue bigint not null,prestige numeric not null,
 financial_risk numeric not null default 0 check(financial_risk between 0 and 100),
 strategy text not null,fanbase int not null,rescue_year int,distress_since date,
 primary key(career_id,club_id)
);
create table if not exists public.cw_finance (
 id bigint generated always as identity primary key,career_id uuid not null,club_id text not null,
 on_date date not null,kind text not null,amount bigint not null,cash_after bigint not null check(cash_after>=0),
 reference text not null,description text not null,metadata jsonb not null default '{}',
 unique(career_id,club_id,kind,reference),foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id)
);
create index if not exists cw_finance_history_idx on public.cw_finance(career_id,club_id,id desc);
create table if not exists public.cw_players (
 career_id uuid not null,player_id text not null,age_at_start int not null,potential int not null check(potential between 1 and 99),
 market_value bigint not null default 0,age_estimated boolean not null,morale numeric not null default 65 check(morale between 0 and 100),
 promised_role text not null default 'rotation' check(promised_role in('key','starter','rotation','prospect')),
 transfer_requested boolean not null default false,last_morale_on date,last_warning_on date,
 primary key(career_id,player_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id)
);
alter table public.cw_players add column if not exists market_value bigint not null default 0;
create table if not exists public.cw_contracts (
 id uuid primary key default gen_random_uuid(),career_id uuid not null,player_id text not null,club_id text,
 starts_on date not null,expires_on date not null,ended_on date,monthly_salary bigint not null check(monthly_salary>0),
 signing_bonus bigint not null default 0 check(signing_bonus>=0),appearance_bonus bigint not null default 0 check(appearance_bonus>=0),
 goal_bonus bigint not null default 0 check(goal_bonus>=0),role text not null check(role in('key','starter','rotation','prospect')),
 status text not null default 'active' check(status in('active','ended','expired')),arrears bigint not null default 0,
 unique(id,career_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id),check(expires_on>=starts_on)
);
create unique index if not exists cw_contract_active_uq on public.cw_contracts(career_id,player_id) where status='active';
create index if not exists cw_contract_club_idx on public.cw_contracts(career_id,club_id,status);
create table if not exists public.cw_negotiations (
 id uuid primary key default gen_random_uuid(),career_id uuid not null,player_id text not null,
 seller_club text,buyer_club text not null,initiator text not null check(initiator in('user','ai','renewal')),
 status text not null check(status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract','completed','rejected','expired','cancelled','failed_funds')),
 fee bigint not null check(fee>=0),installments int not null default 1 check(installments between 1 and 24),
 performance_bonus bigint not null default 0 check(performance_bonus>=0),
 monthly_salary bigint,contract_years int,signing_bonus bigint not null default 0,
 role text not null default 'rotation' check(role in('key','starter','rotation','prospect')),
 created_on date not null,reply_on date not null,expires_on date not null,register_on date,
 round_no int not null default 0,response text,valuation bigint not null,
 agreed_owner_contract uuid,decision_roll numeric not null default random(),
 unique(id,career_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id),
 foreign key(career_id,seller_club) references public.cw_clubs(career_id,club_id),
 foreign key(career_id,buyer_club) references public.cw_clubs(career_id,club_id),
 foreign key(agreed_owner_contract,career_id) references public.cw_contracts(id,career_id),
 check(seller_club is distinct from buyer_club),check(expires_on>=created_on)
);
create unique index if not exists cw_negotiation_buyer_uq on public.cw_negotiations(career_id,player_id,buyer_club)
 where status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract');
create unique index if not exists cw_player_signed_uq on public.cw_negotiations(career_id,player_id) where status in('agreed','precontract');
create table if not exists public.cw_offer_history (
 id bigint generated always as identity primary key,career_id uuid not null,negotiation_id uuid not null,
 on_date date not null,actor text not null,state text not null,terms jsonb not null,explanation text not null,
 foreign key(negotiation_id,career_id) references public.cw_negotiations(id,career_id)
);
create table if not exists public.cw_commitments (
 id uuid primary key default gen_random_uuid(),career_id uuid not null,club_id text not null,
 negotiation_id uuid,kind text not null,amount bigint not null check(amount>=0),due_on date not null,
 status text not null default 'reserved' check(status in('reserved','paid','released')),
 reference text not null,unique(career_id,club_id,reference),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id),
 foreign key(negotiation_id,career_id) references public.cw_negotiations(id,career_id)
);
create table if not exists public.cw_news (
 id bigint generated always as identity primary key,career_id uuid not null references public.careers(id),event_key text not null,
 on_date date not null,kind text not null,priority int not null check(priority between 0 and 100),
 title text not null,body text not null,club_id text references public.sim_clubs(id),player_id text references public.sim_players(id),
 season_id uuid,metadata jsonb not null default '{}',read boolean not null default false,
 unique(career_id,event_key),foreign key(season_id,career_id) references public.career_seasons(id,career_id)
);
create index if not exists cw_news_feed_idx on public.cw_news(career_id,on_date desc,priority desc,id desc);
create index if not exists cw_match_player_history_idx on public.mgr_match_players(player_id,fixture_id) where minutes>0;
create index if not exists cw_contract_expiry_idx on public.cw_contracts(career_id,expires_on) where status='active';
create index if not exists cw_negotiation_tick_idx on public.cw_negotiations(career_id,status,reply_on);
-- The original engine compacts AI lineups after finishing. Preserve the actual
-- appearance summary first, so wages, morale and champion awards use real events.
alter table public.cw_world add column if not exists stats_initialized boolean not null default false;
create table if not exists public.cw_appearances (
 career_id uuid not null,fixture_id bigint not null,season_id uuid not null,competition_id text not null references public.sim_competitions(id),
 player_id text not null,club_id text not null,on_date date not null,minutes int not null,goals int not null,assists int not null,rating numeric not null,starter boolean not null,
 primary key(fixture_id,player_id),foreign key(fixture_id,season_id) references public.season_fixtures(id,season_id),
 foreign key(season_id,career_id) references public.career_seasons(id,career_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id)
);
create index if not exists cw_appearance_player_idx on public.cw_appearances(career_id,player_id,on_date desc);
create index if not exists cw_appearance_awards_idx on public.cw_appearances(season_id,competition_id,club_id);
create table if not exists public.cw_stats_opening (
 career_id uuid not null,season_id uuid not null,player_id text not null,competition_id text not null,club_id text not null,
 apps int not null,minutes int not null,goals int not null,assists int not null,rating_sum numeric not null,
 primary key(season_id,player_id,competition_id),foreign key(season_id,career_id) references public.career_seasons(id,career_id),
 foreign key(career_id,player_id) references public.mgr_players(career_id,player_id)
);
create table if not exists public.cw_ai_days (
 career_id uuid not null,club_id text not null,on_date date not null,primary key(career_id,club_id,on_date),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id)
);
create table if not exists public.cw_coach (
 career_id uuid primary key references public.careers(id),credibility numeric not null default 65 check(credibility between 0 and 100),
 monthly_salary bigint not null default 120,contract_until date,promised_budget bigint not null default 0,
 last_pay_on date,last_finance_warning date,financial_dismissals int not null default 0
);
create table if not exists public.cw_coach_contracts (
 id uuid primary key default gen_random_uuid(),career_id uuid not null,spell_id uuid not null,club_id text not null,
 starts_on date not null,expires_on date not null,ended_on date,monthly_salary bigint not null check(monthly_salary>0),arrears bigint not null default 0,
 unique(spell_id),foreign key(spell_id,career_id) references public.mgr_spells(id,career_id),
 foreign key(career_id,club_id) references public.cw_clubs(career_id,club_id),check(expires_on>=starts_on)
);
alter table public.season_offers add column if not exists salary bigint;
alter table public.season_offers add column if not exists contract_years int;
alter table public.season_offers add column if not exists budget_guarantee bigint;
alter table public.season_offers add column if not exists expires_on date;
alter table public.season_offers add column if not exists negotiation_round int not null default 0;

do $$ declare name text;begin
 foreach name in array array['cw_rules','cw_rivalries','cw_windows','cw_world','cw_seasons','cw_fixture_dates','cw_club_dates','cw_clubs','cw_finance','cw_players','cw_contracts','cw_negotiations','cw_offer_history','cw_commitments','cw_news','cw_ai_days','cw_appearances','cw_stats_opening','cw_coach','cw_coach_contracts'] loop
  execute format('alter table public.%I enable row level security',name);
  execute format('revoke all on public.%I from public,anon,authenticated',name);
  if name not in('cw_rules','cw_rivalries','cw_windows') then
   execute format('drop policy if exists cw_own on public.%I',name);
   execute format('create policy cw_own on public.%I for select to authenticated using(exists(select 1 from public.careers c where c.id=career_id and c.user_id=auth.uid()))',name);
   execute format('grant select on public.%I to authenticated',name);
  end if;
 end loop;
end $$;
-- Responses are visible; the private random draw used by AI decisions is not.
revoke select on public.cw_negotiations from authenticated;
do $columns$ declare cols text;begin
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name='cw_negotiations' and column_name<>'decision_roll';
 execute 'grant select ('||cols||') on public.cw_negotiations to authenticated';
end $columns$;
commit;
