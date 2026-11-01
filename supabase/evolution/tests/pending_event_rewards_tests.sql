-- All fixtures and claims below roll back; never run against production.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('52520000-0000-0000-0000-000000000001','pending-rewards@example.test'),('52520000-0000-0000-0000-000000000002','other-rewards@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins)
 values('52520000-0000-0000-0000-000000000011','52520000-0000-0000-0000-000000000001','PendingRewardsTest','avai','1',30,1000),
 ('52520000-0000-0000-0000-000000000012','52520000-0000-0000-0000-000000000002','OtherRewardsTest','avai','1',30,1000);
select set_config('request.jwt.claim.sub','52520000-0000-0000-0000-000000000001',true);
do $test$
#variable_conflict use_column
declare cid uuid:='52520000-0000-0000-0000-000000000011';other_cid uuid:='52520000-0000-0000-0000-000000000012';
 daily public.events;weekly public.events;old_event public.events;oid uuid;hidden uuid;current_key text;previous_key text;
 h jsonb;again jsonb;before_data jsonb;result jsonb;expected int;starting_coins int;reward_id uuid;
begin
 insert into public.events(slug,name,description,category,status,recurrence,starts_at,ends_at)
  values('pending-test-daily','Pending daily','Test','daily','published','daily',now()-interval '60 days',now()+interval '10 days') returning * into daily;
 insert into public.events(slug,name,description,category,status,recurrence,starts_at,ends_at)
  values('pending-test-weekly','Pending weekly','Test','weekly','published','weekly',now()-interval '60 days',now()+interval '10 days') returning * into weekly;
 insert into public.events(slug,name,description,category,status,starts_at,ends_at,claim_grace_hours)
  values('pending-test-ended','Older event','Test','themed','published',now()-interval '20 days',now()-interval '8 days',720) returning * into old_event;
 insert into public.event_rewards(event_id,kind,amount) values(daily.id,'coins',125),(weekly.id,'energy',2),(old_event.id,'coins',25);
 select period_key into current_key from public.event_period(daily);
 select period_key into previous_key from public.event_period(daily,now()-interval '1 day');
 -- Today's reward is already claimed; yesterday's remains owed during its grace period.
 insert into public.event_completions(event_id,career_id,period_key,claim_until,claimed_at,rewards)
  values(daily.id,cid,current_key,now()+interval '2 days',now(),'[{"kind":"coins","amount":125}]');
 insert into public.event_completions(event_id,career_id,period_key,completed_at,claim_until)
  values(daily.id,cid,previous_key,now()-interval '1 day',now()+interval '1 day') returning id into hidden;
 insert into public.event_completions(event_id,career_id,period_key,claim_until)
  select weekly.id,cid,period_key,now()+interval '1 day' from public.event_period(weekly,now()-interval '7 days');
 -- This current weekly reward already has its own button, so must not be duplicated.
 insert into public.event_completions(event_id,career_id,period_key,claim_until)
  select weekly.id,cid,period_key,now()+interval '2 days' from public.event_period(weekly);
 -- An ended event outside the seven-day listing still honors its configured deadline.
 insert into public.event_completions(event_id,career_id,period_key,claim_until)
  values(old_event.id,cid,'unico',now()+interval '1 day');
 -- Expired, cancelled and another career's rewards must not leak into the count/list.
 insert into public.event_completions(event_id,career_id,period_key,claim_until)
  values(daily.id,cid,'expired',now()-interval '1 second'),(daily.id,other_cid,previous_key,now()+interval '1 day');
 insert into public.events(slug,name,description,category,status,starts_at,ends_at)
  values('pending-test-cancelled','Cancelled','Test','themed','cancelled',now()-interval '1 day',now()+interval '1 day') returning id into oid;
 insert into public.event_completions(event_id,career_id,period_key,claim_until) values(oid,cid,'unico',now()+interval '1 day');
 select jsonb_build_object('career',to_jsonb(c),'completions',(select jsonb_agg(to_jsonb(ec) order by ec.id) from public.event_completions ec where career_id=cid)) into before_data from public.careers c where id=cid;
 h:=public.events_overview();again:=public.events_overview();
 if h<>again or(select jsonb_build_object('career',to_jsonb(c),'completions',(select jsonb_agg(to_jsonb(ec) order by ec.id) from public.event_completions ec where career_id=cid)) from public.careers c where id=cid)<>before_data then raise exception 'Overview modified progress';end if;
 if(h->>'claimable')::int<>4 or jsonb_array_length(h->'pending_rewards')<>3 then raise exception 'Count/list mismatch: %',h->'pending_rewards';end if;
 if not exists(select 1 from jsonb_array_elements(h->'active') e where e->>'id'=daily.id::text and e->'completion'->>'claimed_at' is not null) then raise exception 'Claimed current period changed';end if;
 if not exists(select 1 from jsonb_array_elements(h->'pending_rewards') r where r->>'completion_id'=hidden::text and r->>'period_key'=previous_key) then raise exception 'Previous daily period hidden';end if;
 if exists(select 1 from jsonb_array_elements(h->'pending_rewards') r join jsonb_array_elements((h->'active')||(h->'ended')||(h->'upcoming')) e on r->>'completion_id'=e->'completion'->>'id') then raise exception 'Visible completion duplicated';end if;
 -- Every counted event reward has exactly one reachable completion ID.
 select count(distinct id) into expected from(
  select r->>'completion_id' id from jsonb_array_elements(h->'pending_rewards') r
  union all select e->'completion'->>'id' from jsonb_array_elements((h->'active')||(h->'ended')||(h->'upcoming')) e where(e->'completion'->>'claimable')::boolean
 )reachable;
 if expected<>(h->>'claimable')::int then raise exception 'Badge has unreachable rewards';end if;
 select coins into starting_coins from public.careers where id=cid;
 result:=public.event_claim(hidden);again:=public.event_claim(hidden);
 if not(again->>'replayed')::boolean or(select coins from public.careers where id=cid)<>starting_coins+125 then raise exception 'Old reward duplicated or missing';end if;
 h:=public.events_overview();
 if(h->>'claimable')::int<>3 or jsonb_array_length(h->'pending_rewards')<>2 or exists(select 1 from jsonb_array_elements(h->'pending_rewards') r where r->>'completion_id'=hidden::text) then raise exception 'Claim did not clear pending badge';end if;
 -- Claim all remaining rewards through the existing endpoint; the badge must reach zero.
 for reward_id in select ec.id from public.event_completions ec join public.events e on e.id=ec.event_id where ec.career_id=cid and ec.claimed_at is null and now()<ec.claim_until and e.status<>'cancelled' loop
  perform public.event_claim(reward_id);
 end loop;
 h:=public.events_overview();
 if(h->>'claimable')::int<>0 or jsonb_array_length(h->'pending_rewards')<>0 then raise exception 'Claimed rewards still advertised';end if;
 raise notice 'PASS pending daily/weekly/older events reachable, current rewards deduplicated, expired/cancelled/foreign excluded, read-only overview, one-time claim and zero badge after all claims';
end $test$;
rollback;
