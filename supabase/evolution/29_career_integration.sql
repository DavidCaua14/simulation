begin;
do $$begin
 if to_regprocedure('public.mgr_sync_base_cards_before_world(uuid)') is null then alter function public.mgr_sync_base_cards(uuid) rename to mgr_sync_base_cards_before_world;end if;
 if to_regprocedure('public.mgr_hub_before_world()') is null then alter function public.mgr_hub() rename to mgr_hub_before_world;end if;
 if to_regprocedure('public.mgr_match_start_before_world()') is null then alter function public.mgr_match_start() rename to mgr_match_start_before_world;end if;
 if to_regprocedure('public.mgr_new_season_before_world(uuid)') is null then alter function public.mgr_new_season(uuid) rename to mgr_new_season_before_world;end if;
 if to_regprocedure('public.mgr_match_create_before_world(bigint,uuid,character,jsonb)') is null then alter function public.mgr_match_create(bigint,uuid,char,jsonb) rename to mgr_match_create_before_world;end if;
 if to_regprocedure('public.sim_next_event_before_world(uuid,text)') is null then alter function public.sim_next_event(uuid,text) rename to sim_next_event_before_world;end if;
end $$;
create or replace function public.mgr_sync_base_cards(p_career uuid)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 if exists(select 1 from public.cw_world where career_id=p_career) then return 0;end if;
 return public.mgr_sync_base_cards_before_world(p_career);
end $$;
create or replace function public.mgr_lock()
returns public.careers language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c public.careers;
begin
 c:=public.sim_lock_career();perform public.mgr_ensure(c);perform public.mgr_sync_base_cards(c.id);perform public.cw_ensure(c.id);
 if not(select stats_initialized from public.cw_world where career_id=c.id) then perform public.cw_initialize_finances(c.id);end if;
 update public.season_offers set status='expired',responded_at=now() where career_id=c.id and kind='coach' and status='pending' and expires_on<(select today from public.cw_world where career_id=c.id);
 select * into c from public.careers where id=c.id;return c;
end $$;
create or replace function public.sim_next_event(p_season uuid,p_club text)
returns table(o_comp text,o_kind text,o_stage text,o_round int)
language sql stable security definer set search_path=public as $$
 select * from public.sim_next_event_before_world(p_season,p_club) where not exists(select 1 from public.cw_seasons where season_id=p_season)
 union all
 (select f.competition_id,case when p_club in(f.home_club,f.away_club) then 'mine' else 'free' end,f.stage,f.round_no
 from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
 where f.season_id=p_season and f.status='pending'
 order by d.due_on,(p_club in(f.home_club,f.away_club)) desc nulls last,f.id limit 1)
$$;
create or replace function public.mgr_match_create(p_fixture bigint,p_career uuid,p_user_side char,p_user_lineup jsonb)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v_side text;factor numeric;club text;due date;previous_day date;recovery int;
begin
 if exists(select 1 from public.mgr_matches where fixture_id=p_fixture) then return;end if;
 if p_user_side is null and exists(select 1 from public.cw_world where career_id=p_career) then
  select due_on into due from public.cw_fixture_dates where fixture_id=p_fixture;
  if due<(select started_on from public.cw_world where career_id=p_career) then
  for club in select home_club from public.season_fixtures where id=p_fixture union all select away_club from public.season_fixtures where id=p_fixture loop
   select max(fd.due_on) into previous_day from public.cw_fixture_dates fd join public.season_fixtures fx on fx.id=fd.fixture_id where fd.career_id=p_career and fx.status='played' and club in(fx.home_club,fx.away_club) and fd.due_on<due;
   recovery:=greatest(0,least(14,coalesce(due-previous_day,3)));
   update public.mgr_players set condition=least(100,condition+recovery*4.3),
    injury=case when injured_until-recovery<=(select elapsed_days from public.cw_world where career_id=p_career) then null else injury end,
    injured_until=case when injured_until-recovery<=(select elapsed_days from public.cw_world where career_id=p_career) then null else injured_until-recovery end
    where career_id=p_career and club_id=club;
  end loop;
  end if;
 end if;
 perform public.mgr_match_create_before_world(p_fixture,p_career,p_user_side,p_user_lineup);
 if exists(select 1 from public.cw_world where career_id=p_career) then
  foreach v_side in array array['h','a'] loop
   select .90+coalesce(avg(cp.morale),65)/1000 into factor from public.mgr_match_players mp join public.cw_players cp on cp.career_id=p_career and cp.player_id=mp.player_id where mp.fixture_id=p_fixture and mp.side=v_side and mp.status='on';
   update public.mgr_matches set state=jsonb_set(state,array['form',case when v_side='h' then '0' else '1' end],to_jsonb(round((state->'form'->>case when v_side='h' then 0 else 1 end)::numeric*factor,3))) where fixture_id=p_fixture;
  end loop;
 end if;
end $$;
create or replace function public.mgr_match_start()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c public.careers;due date;
begin
 c:=public.mgr_lock();
 if not exists(select 1 from public.mgr_matches where career_id=c.id and status='live' and user_side is not null) then
  if(select needs_sync from public.cw_world where career_id=c.id) then raise exception 'Atualize os resultados do mundo antes de jogar';end if;
  select min(d.due_on) into due from public.cw_fixture_dates d join public.season_fixtures f on f.id=d.fixture_id join public.cw_world w on w.primary_season=f.season_id join public.mgr_coach co on co.career_id=w.career_id
   where w.career_id=c.id and f.status='pending' and co.club_id in(f.home_club,f.away_club);
  if due>(select today from public.cw_world where career_id=c.id) then raise exception 'Avance o calendário até a data da partida';end if;
 end if;
 return public.mgr_match_start_before_world();
end $$;
create or replace function public.sim_play_round(p_season uuid,p_comp text,p_stage text,p_round int)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;r record;n int:=0;
begin
 select * into s from public.career_seasons where id=p_season;
 for r in select f.id from public.season_fixtures f left join public.cw_fixture_dates d on d.fixture_id=f.id
  where f.season_id=p_season and f.competition_id=p_comp and f.stage=p_stage and f.round_no=p_round and f.status='pending'
  and (not exists(select 1 from public.cw_world where career_id=s.career_id) or d.due_on<=(select today from public.cw_world where career_id=s.career_id)) order by f.id loop
  perform public.mgr_sim_fixture(r.id,s.career_id);n:=n+1;
 end loop;return n;
end $$;
create or replace function public.mgr_day_tick(p_career uuid,p_season uuid)
returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 perform public.cw_schedule(p_season);perform public.cw_simulate_due(p_career,24);
 if not(select needs_sync from public.cw_world where career_id=p_career) then perform public.cw_step_day(p_career);end if;
 return(select elapsed_days from public.cw_world where career_id=p_career);
end $$;
create or replace function public.career_world_advance(p_days int,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;w public.cw_world;c public.mgr_coach;prev jsonb;days int:=0;n int:=0;t timestamptz:=clock_timestamp();sid uuid;summary jsonb;stopped boolean;ready boolean;s public.career_seasons;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'world_advance');if prev is not null then return prev;end if;
 if p_days is null or (p_days<0 or p_days>(select max_days_per_call from public.cw_rules)) then raise exception 'Quantidade de dias acima do limite por atualização';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 loop
  n:=n+public.cw_simulate_due(car.id,24);select * into w from public.cw_world where career_id=car.id;select * into c from public.mgr_coach where career_id=car.id;
  select * into s from public.career_seasons where id=w.primary_season;
  exit when w.needs_sync or days>=p_days or clock_timestamp()-t>interval '3seconds';
  exit when s.status='finished' and w.today>=public.cw_start(s.region,s.year+1);
  exit when exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today);
  perform public.cw_step_day(car.id);days:=days+1;
 end loop;
 if not exists(select 1 from public.season_fixtures where season_id=w.primary_season and status='pending') and(select status from public.career_seasons where id=w.primary_season)='active' then summary:=public.mgr_season_end(w.primary_season);end if;
 select exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today) into stopped;
 select cs.status='finished' and w.today>=public.cw_start(cs.region,cs.year+1) into ready from public.career_seasons cs where cs.id=w.primary_season;
 return public.econ_request_save(car.id,p_request,'world_advance',jsonb_build_object('today',w.today,'days',days,'days_remaining',greatest(0,p_days-days),'stopped_for_match',stopped,'next_season_ready',ready,'matches',n,'more',w.needs_sync,'rounds','[]'::jsonb,'offers','[]'::jsonb,'season_finished',summary is not null,'season_summary',summary));
end $$;
create or replace function public.mgr_advance(p_until_offer boolean default false)
returns jsonb language sql security definer set search_path=public as $$select public.career_world_advance(least(case when p_until_offer then 14 else 7 end,(select max_days_per_call from public.cw_rules)),gen_random_uuid())$$;
create or replace function public.cw_promote_season(p_career uuid,p_season uuid,p_club text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare seq int;old_id uuid;
begin
 select primary_season into old_id from public.cw_world where career_id=p_career;
 if not exists(select 1 from public.career_seasons where id=p_season and career_id=p_career and status='active') then raise exception 'Temporada regional ainda indisponível; atualize o mundo';end if;
 if old_id is distinct from p_season then
  update public.career_seasons set mode='world',club_id=case when status='active' then null else club_id end where id=old_id;
  select max(season_no)+1 into seq from public.career_seasons where career_id=p_career;
  update public.career_seasons set mode='coach',was_coached=true,club_id=p_club,season_no=seq where id=p_season;
  update public.cw_world set primary_season=p_season,needs_sync=true where career_id=p_career;
 else update public.career_seasons set club_id=p_club,mode='coach',was_coached=true where id=p_season;end if;
end $$;
create or replace function public.mgr_offer_region_ok(p_career uuid,p_club text)
returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id join public.cw_world w on w.career_id=ws.career_id where ws.career_id=p_career and ws.region=public.cw_region(p_club) and s.status='active')$$;
create or replace function public.mgr_offer_respond(p_offer uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;o public.season_offers;c public.mgr_coach;w public.cw_world;sid uuid;spell uuid;
begin
 car:=public.mgr_lock();select * into w from public.cw_world where career_id=car.id;
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' for update;
 if not found then raise exception 'Proposta inexistente';end if;
 if o.status='accepted' and p_accept then return jsonb_build_object('ok',true,'accepted',true,'club_id',o.from_club);end if;
 if o.status<>'pending' or o.expires_on<w.today then raise exception 'Proposta encerrada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 if p_accept then
  if w.needs_sync then raise exception 'Atualize os resultados do mundo antes de trocar de clube';end if;
  select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id and ws.region=public.cw_region(o.from_club) and s.status='active' order by ws.starts_on limit 1;
  if sid is null then raise exception 'Atualize o calendário regional antes de assumir o clube';end if;
  if (select cash-public.cw_reserved(car.id,o.from_club) from public.cw_clubs where career_id=car.id and club_id=o.from_club)<coalesce(o.bonus_coins,0)+2*o.salary or greatest(0,public.cw_available_budget(car.id,o.from_club)-coalesce(o.bonus_coins,0)-2*o.salary)<coalesce(o.budget_guarantee,0) then raise exception 'O clube não pode sustentar os termos do contrato';end if;
  select * into c from public.mgr_coach where career_id=car.id;
  if c.status='employed' then perform public.mgr_end_spell(car.id,'left');end if;
  perform public.cw_promote_season(car.id,sid,o.from_club);spell:=public.mgr_start_spell(car.id,o.from_club);
  update public.cw_coach set monthly_salary=o.salary,contract_until=(w.today+make_interval(years=>o.contract_years))::date,promised_budget=o.budget_guarantee where career_id=car.id;
  update public.cw_clubs set distress_since=case when financial_risk>=75 then w.today else distress_since end where career_id=car.id and club_id=o.from_club;
  insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
   values(car.id,spell,o.from_club,w.today,(w.today+make_interval(years=>o.contract_years))::date,o.salary);
  if o.bonus_coins>0 then perform public.cw_cash(car.id,o.from_club,-o.bonus_coins,'coach_signing',o.id::text,'Luvas do treinador');perform public.econ_apply(car.id,'coins',o.bonus_coins,'coach_signing',o.id::text);end if;
  update public.season_offers set status='accepted',responded_at=now() where id=o.id;
  update public.season_offers set status='expired',responded_at=now() where career_id=car.id and kind='coach' and status='pending';
  perform public.cw_news_add(car.id,'coach-hired:'||spell,'job',public.mgr_club_name(o.from_club)||' anuncia novo treinador','Contrato por '||o.contract_years||' anos. A temporada e os resultados existentes continuam.',98,o.from_club);
 else update public.season_offers set status='declined',responded_at=now() where id=o.id;end if;
 return jsonb_build_object('ok',true,'accepted',p_accept,'club_id',o.from_club);
end $$;
create or replace function public.mgr_new_season(p_career uuid)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;c public.mgr_coach;old_s public.career_seasons;sid uuid;yr int;
begin
 if not exists(select 1 from public.cw_world where career_id=p_career) then return public.mgr_new_season_before_world(p_career);end if;
 select * into w from public.cw_world where career_id=p_career;select * into c from public.mgr_coach where career_id=p_career;
 select * into old_s from public.career_seasons where id=w.primary_season;
 if old_s.status='active' then raise exception 'A temporada atual está em andamento';end if;
 yr:=greatest(old_s.year+1,public.cw_year(old_s.region,w.today));
 if w.today<public.cw_start(old_s.region,yr) then raise exception 'Avance os dias até o início da próxima temporada';end if;
 sid:=public.cw_create_region(p_career,old_s.region,yr);perform public.cw_promote_season(p_career,sid,c.club_id);
 if c.status='employed' then
  perform public.mgr_create_objectives(p_career,sid,c.spell_id,c.club_id);
  update public.mgr_coach set board_confidence=round(board_confidence+(62-board_confidence)*.5,2),fan_mood=round(fan_mood+(60-fan_mood)*.5,2),warned=0,fan_warned=0 where career_id=p_career;
 end if;return sid;
end $$;
create or replace function public.mgr_season_next()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;sid uuid;
begin car:=public.mgr_lock();sid:=public.mgr_new_season(car.id);return jsonb_build_object('ok',true,'season_id',sid);end $$;
create or replace function public.career_world_status()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;w public.cw_world;
begin
 car:=public.mgr_lock();select * into w from public.cw_world where career_id=car.id;select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 return to_jsonb(w)-'career_id'||jsonb_build_object('coach',(select to_jsonb(c)-'career_id' from public.cw_coach c where career_id=car.id),
 'club',(select to_jsonb(c)-'career_id'||jsonb_build_object('payroll',public.cw_payroll(car.id,own),'reserved',public.cw_reserved(car.id,own),'available',public.cw_available_budget(car.id,own),'window_open',public.cw_window_open(public.cw_region(own),w.today),'next_window',public.cw_next_window(public.cw_region(own),w.today)) from public.cw_clubs c where career_id=car.id and club_id=own),
 'seasons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select ws.region,ws.year,s.status,ws.season_id,ws.starts_on,ws.ends_on from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id where ws.career_id=car.id order by ws.starts_on desc limit 8)x),
 'due_matches',(select count(*) from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=car.id and fd.due_on<=w.today and f.status='pending' and not(f.season_id=w.primary_season and own is not null and own in(f.home_club,f.away_club))),
 'news_unread',(select count(*) from public.cw_news where career_id=car.id and not read));
end $$;
create or replace function public.mgr_hub()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare h jsonb;w jsonb;d date;car uuid;
begin
 h:=public.mgr_hub_before_world();w:=public.career_world_status();car:=(h#>>'{career,id}')::uuid;
 if h#>>'{next_event,fixture_id}' is not null then
  select due_on into d from public.cw_fixture_dates where fixture_id=(h#>>'{next_event,fixture_id}')::bigint;
  h:=jsonb_set(h,'{next_event}',h->'next_event'||jsonb_build_object('scheduled_on',d,'days_until',d-(w->>'today')::date));
 end if;
 h:=jsonb_set(h,'{offers}',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'club_id',o.from_club,'pitch',o.pitch,'context',o.context,'bonus_coins',o.bonus_coins,'salary',o.salary,'contract_years',o.contract_years,'budget_guarantee',o.budget_guarantee,'expires_on',o.expires_on,'days_left',o.expires_on-(w->>'today')::date,'negotiation_round',o.negotiation_round)),'[]') from public.season_offers o where career_id=car and kind='coach' and status='pending'));
 return h||jsonb_build_object('career_world_version',1,'world',w);
end $$;
-- Owned global search. Catalog is shared, assignments/contracts/values are per career.
drop function if exists public.career_player_search(text,text,text,text,bigint,int);
create or replace function public.career_player_search(p_query text default '',p_position text default '',p_region text default '',p_club text default '',p_max_value bigint default null,p_page int default 0,p_country text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(
  select sp.id,sp.full_name as name,sp.short_name,sp.position,mp.club_id,sp.nationality,round(pr.rating) as overall,round(mp.condition) as condition,
   cp.age_at_start+floor(((select today-started_on from public.cw_world where career_id=car.id))/365.25)::int as age,cp.age_estimated,cp.potential,cp.morale,cp.promised_role,cp.transfer_requested,
   public.cw_player_value(car.id,sp.id) as value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
   coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=car.id and ss.status='active' and st.player_id=sp.id),0) as minutes
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id left join public.cw_contracts ct on ct.career_id=car.id and ct.player_id=sp.id and ct.status='active'
  where mp.career_id=car.id and sp.active and (coalesce(p_query,'')='' or sp.full_name ilike '%'||left(p_query,60)||'%')
   and (coalesce(p_country,'')='' or (select country from public.sim_clubs sc where sc.id=mp.club_id)=upper(p_country))
   and (coalesce(p_position,'')='' or sp.position=p_position)
   and (coalesce(p_region,'')='' or public.cw_region(mp.club_id)=p_region or(p_region='free' and mp.club_id is null))
   and (coalesce(p_club,'')='' or mp.club_id=case when p_club='mine' then own else p_club end)
   and (p_max_value is null or public.cw_player_value(car.id,sp.id)<=p_max_value)
  order by pr.rating desc,sp.id limit 30 offset least(greatest(coalesce(p_page,0),0),200)*30)x);
end $$;
create or replace function public.career_negotiations()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.id,n.player_id,public.mgr_player_name(n.player_id) as player_name,n.seller_club,n.buyer_club,n.status,n.initiator,n.fee,n.installments,n.performance_bonus,n.monthly_salary,n.contract_years,n.signing_bonus,n.role,n.appearance_bonus,n.goal_bonus,n.created_on,n.reply_on,n.expires_on,n.register_on,n.round_no,n.response,n.valuation,
  (select coalesce(jsonb_agg(jsonb_build_object('date',h.on_date,'actor',h.actor,'state',h.state,'explanation',h.explanation,'terms',h.terms) order by h.id),'[]') from public.cw_offer_history h where h.negotiation_id=n.id and h.career_id=car.id) as history
 from public.cw_negotiations n where n.career_id=car.id and own in(n.buyer_club,n.seller_club) order by n.created_on desc,n.id limit 60)x);
end $$;
create or replace function public.career_news(p_before bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;
begin car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by x.on_date desc,(x.club_id=own) desc nulls last,x.priority desc,x.id desc),'[]') from(select n.id,n.on_date,n.kind,n.priority,n.title,n.body,n.club_id,n.player_id,n.season_id,n.metadata,n.read from public.cw_news n where n.career_id=car.id and (p_before is null or n.id<p_before) order by n.id desc limit 40)x);
end $$;
create or replace function public.career_news_read(p_ids bigint[])
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;
begin car:=public.mgr_lock();update public.cw_news set read=true where career_id=car.id and id=any(p_ids);return jsonb_build_object('ok',true);end $$;
create or replace function public.career_finance_history()
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;
begin car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by id desc),'[]') from(select id,on_date,kind,amount,cash_after,description,metadata from public.cw_finance where career_id=car.id and club_id=own order by id desc limit 60)x);end $$;

create or replace function public.mgr_history()
returns jsonb language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_car public.careers;
  v_c   public.mgr_coach;
begin
  v_car := public.mgr_lock();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  return jsonb_build_object(
    'coach', jsonb_build_object('reputation', round(v_c.reputation, 1), 'matches', v_c.matches, 'wins', v_c.wins, 'draws', v_c.draws,
      'losses', v_c.losses, 'gf', v_c.gf, 'ga', v_c.ga, 'titles', v_c.titles, 'fired_count', v_c.fired_count, 'seasons', v_c.seasons,
      'status', v_c.status, 'club_id', v_c.club_id),
    'spells', (select coalesce(jsonb_agg(jsonb_build_object('id', sp.id, 'club_id', sp.club_id, 'current', sp.id = v_c.spell_id,
        'started_year', sp.started_year, 'started_day', sp.started_day, 'started_season', sp.started_season,
        'ended_year', sp.ended_year, 'ended_day', sp.ended_day, 'end_reason', sp.end_reason,
        'matches', sp.matches, 'wins', sp.wins, 'draws', sp.draws, 'losses', sp.losses, 'gf', sp.gf, 'ga', sp.ga, 'titles', sp.titles)
        order by sp.created_at desc), '[]'::jsonb) from public.mgr_spells sp where sp.career_id = v_car.id),
    'seasons', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'year', s.year, 'region', s.region, 'season_no', s.season_no, 'status', s.status,
        'club_id', s.club_id, 'matches', s.matches, 'wins', s.wins, 'draws', s.draws, 'losses', s.losses,
        'xp_earned', s.xp_earned, 'coins_earned', s.coins_earned, 'summary', s.summary,
        'final_tables', (select coalesce(jsonb_object_agg(ft.competition_id,ft.standings),'{}'::jsonb) from public.season_final_tables ft where ft.season_id=s.id),
        'clubs', (select coalesce(jsonb_agg(distinct f.coach_club), '[]'::jsonb) from public.season_fixtures f where f.season_id = s.id and f.player_match),
        'objectives', (select coalesce(jsonb_agg(jsonb_build_object('label', o.label, 'status', o.status, 'club_id', o.club_id) order by o.priority desc), '[]'::jsonb)
                         from public.mgr_objectives o where o.season_id = s.id))
        order by s.season_no desc), '[]'::jsonb)
        from public.career_seasons s where s.career_id = v_car.id and (s.mode = 'coach' or s.was_coached)));
end;
$$;
do $acl$ declare fn record;begin
 for fn in select p.oid::regprocedure as sig,p.proname as name from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='public' and (p.proname like 'cw\_%' escape '\' or p.proname like '%before_world%' or p.proname like 'career\_%' escape '\') loop
  execute format('revoke all on function %s from public,anon,authenticated,service_role',fn.sig);
  if fn.name in('career_club_invest','career_transfer_bid','career_transfer_respond','career_player_offer','career_contract_renew','career_player_role','career_job_negotiate','career_coach_renew','career_world_advance','career_world_status','career_player_search','career_negotiations','career_news','career_news_read','career_finance_history') then execute format('grant execute on function %s to authenticated',fn.sig);end if;
 end loop;
end $acl$;
revoke all on function public.mgr_lock(),public.mgr_sync_base_cards(uuid),public.mgr_match_create(bigint,uuid,char,jsonb),public.sim_play_round(uuid,text,text,int),public.mgr_day_tick(uuid,uuid),public.mgr_new_season(uuid),public.mgr_fire(uuid,text),public.mgr_end_spell(uuid,text),public.mgr_make_offer(uuid,uuid,int,boolean,boolean) from public,anon,authenticated,service_role;
revoke all on function public.mgr_hub(),public.mgr_match_start(),public.mgr_advance(boolean),public.mgr_offer_respond(uuid,boolean),public.mgr_season_next(),public.mgr_history(),public.sim_next_event(uuid,text),public.mgr_offer_region_ok(uuid,text) from public,anon,service_role;
grant execute on function public.mgr_hub(),public.mgr_match_start(),public.mgr_advance(boolean),public.mgr_offer_respond(uuid,boolean),public.mgr_season_next(),public.mgr_history() to authenticated;
notify pgrst,'reload schema';
commit;
