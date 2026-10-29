begin;
insert into auth.users(id) values('53535353-0000-0000-0000-000000000001'),('53535353-0000-0000-0000-000000000002');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values
 ('53535353-0000-0000-0000-000000000011','53535353-0000-0000-0000-000000000001','Late Brazil','flamengo','BR',30,100),
 ('53535353-0000-0000-0000-000000000022','53535353-0000-0000-0000-000000000002','Late England','arsenal','BR',30,100);
select set_config('request.jwt.claim.sub','53535353-0000-0000-0000-000000000001',true);
do $entry$
#variable_conflict use_column
declare cid uuid:='53535353-0000-0000-0000-000000000011';car public.careers;foreign_id uuid;primary_id uuid;wallet jsonb;history text;dates text;before_count int;after_count int;fixture bigint;shift_before int;today date;
begin
 car:=public.sim_lock_career();perform public.mgr_ensure(car);
 update public.career_seasons set day_no=50 where career_id=cid and mode='coach';
 select to_jsonb(c) into wallet from public.careers c where id=cid;
 perform public.cw_ensure(cid);
 select w.today,w.primary_season into today,primary_id from public.cw_world w where career_id=cid;
 select season_id into foreign_id from public.cw_seasons where career_id=cid and region='ENG';
 if today<='2026-05-01' or foreign_id is null then raise exception 'Late career setup failed';end if;
 if exists(select 1 from public.cw_fixture_dates fd where fd.season_id=foreign_id and due_on<today) then raise exception 'New foreign season requires retroactive catch-up';end if;
 if exists(select 1 from public.season_fixtures where season_id=foreign_id and status='played') then raise exception 'Foreign results invented at entry';end if;
 if(select to_jsonb(c) from public.careers c where id=cid)<>wallet then raise exception 'World entry changed personal resources';end if;
 -- Simulate one actual foreign game, then mimic a partially processed old-world backlog.
 select id into fixture from public.season_fixtures where season_id=foreign_id and status='pending' order by id limit 1;
 perform public.mgr_sim_fixture(fixture,cid);
 select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) into history from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id=cid and f.status='played';
 select md5(string_agg(to_jsonb(fd)::text,'' order by fd.fixture_id)) into dates from public.cw_fixture_dates fd where fd.season_id=primary_id;
 select count(*) into before_count from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id=cid;
 delete from public.cw_club_dates cd using public.season_fixtures f where cd.fixture_id=f.id and f.season_id=foreign_id and f.status='pending';
 update public.cw_fixture_dates fd set due_on=due_on-250 from public.season_fixtures f where fd.fixture_id=f.id and f.season_id=foreign_id and f.status='pending';
 insert into public.cw_club_dates select cid,c.club_id,fd.due_on,f.id from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id cross join lateral(values(f.home_club),(f.away_club))c(club_id) where f.season_id=foreign_id and f.status='pending';
 update public.cw_world set parallel_entry_aligned=false where career_id=cid;
 perform public.cw_align_parallel_entry(cid);
 if exists(select 1 from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.season_id=foreign_id and f.status='pending' and due_on<today) then raise exception 'Existing foreign backlog remains';end if;
 if(select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id=cid and f.status='played') is distinct from history then raise exception 'Repair rewrote real results';end if;
 if(select md5(string_agg(to_jsonb(fd)::text,'' order by fd.fixture_id)) from public.cw_fixture_dates fd where fd.season_id=primary_id) is distinct from dates then raise exception 'Repair rewrote domestic calendar';end if;
 select count(*) into after_count from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id=cid;
 if after_count<>before_count then raise exception 'Repair duplicated/deleted fixtures';end if;
 select calendar_shift into shift_before from public.cw_seasons where season_id=foreign_id;
 perform public.cw_align_parallel_entry(cid);
 if(select calendar_shift from public.cw_seasons where season_id=foreign_id)<>shift_before then raise exception 'Repair is not idempotent';end if;
 if exists(select 1 from public.cw_club_dates a join public.cw_club_dates b on a.career_id=b.career_id and a.club_id=b.club_id and a.fixture_id<b.fixture_id and abs(a.due_on-b.due_on)<2 where a.career_id=cid) then raise exception 'Calendar rest collision';end if;
 -- New phases must use the shifted calendar too, instead of generating another backlog.
 select fd.fixture_id into fixture from public.cw_fixture_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.season_id=foreign_id and f.status='pending' order by fd.due_on desc limit 1;
 delete from public.cw_club_dates where fixture_id=fixture;delete from public.cw_fixture_dates where fixture_id=fixture;
 perform public.cw_schedule(foreign_id);
 if(select due_on from public.cw_fixture_dates where fixture_id=fixture)<today then raise exception 'Later scheduling reintroduced backlog';end if;
 if has_function_privilege('authenticated','public.cw_align_parallel_entry(uuid)','execute') or has_function_privilege('anon','public.cw_align_parallel_entry(uuid)','execute') then raise exception 'Calendar helper exposed';end if;
 raise notice 'PASS late Brazil entry: no retroactive foreign games; partial history, domestic dates, IDs, resources and rest preserved; repair idempotent';
end $entry$;
select set_config('request.jwt.claim.sub','53535353-0000-0000-0000-000000000002',true);
do $inverse$
declare car public.careers;cid uuid:='53535353-0000-0000-0000-000000000022';
begin
 car:=public.sim_lock_career();perform public.mgr_ensure(car);
 update public.career_seasons set day_no=60 where career_id=cid and mode='coach';
 perform public.cw_ensure(cid);
 if exists(select 1 from public.cw_fixture_dates fd join public.cw_world w on w.career_id=fd.career_id where fd.career_id=cid and fd.season_id<>w.primary_season and fd.due_on<w.today) then raise exception 'Inverse region entry has a backlog';end if;
 if(select parallel_entry_aligned from public.cw_world where career_id=cid) is not true then raise exception 'Alignment marker missing';end if;
 raise notice 'PASS late England entry: Brazil begins at entry and shares the global calendar';
end $inverse$;
rollback;

begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $three_days$
#variable_conflict use_column
declare cid uuid:='31313131-0000-0000-0000-000000000011';sid uuid;own text;due date;game bigint;r jsonb;n int:=0;balance int;
begin
 select primary_season into sid from public.cw_world where career_id=cid;
 select club_id into own from public.mgr_coach where career_id=cid;
 select f.id,fd.due_on into game,due from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id
  where f.season_id=sid and f.status='pending' and own in(f.home_club,f.away_club) order by fd.due_on,f.id limit 1;
 update public.cw_world set today=due-3,needs_sync=false where career_id=cid;
 select coins into balance from public.careers where id=cid;
 loop
  r:=public.career_world_advance(case when(select needs_sync from public.cw_world where career_id=cid) then 0 else least(3,greatest(0,due-(select today from public.cw_world where career_id=cid))) end,gen_random_uuid());
  n:=n+1;
  exit when (r->>'stopped_for_match')::boolean and not(r->>'more')::boolean;
  if n>30 then raise exception 'Three-day preparation failed to reach the next match';end if;
 end loop;
 if(select today from public.cw_world where career_id=cid)<>due or(select status from public.season_fixtures where id=game)<>'pending' then raise exception 'User game skipped or date exceeded';end if;
 if(select coins from public.careers where id=cid)<>balance then raise exception 'Preparation granted duplicate personal rewards';end if;
 if not exists(select 1 from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id=cid and f.season_id<>sid and f.status='played') then raise exception 'Foreign competitions did not advance in parallel';end if;
 raise notice 'PASS three-day preparation: bounded calls reach the user match, foreign games run in parallel, own game and wallet preserved';
end $three_days$;
rollback;
