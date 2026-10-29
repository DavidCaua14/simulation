begin;
do $cycle$
#variable_conflict use_column
declare cid uuid:='41414141-0000-0000-0000-000000000011';sid uuid;
begin
 if not exists(select 1 from public.career_seasons where career_id=cid and region='BRA' and year=2026 and status='finished') or not exists(select 1 from public.career_seasons where career_id=cid and region='ENG' and year=2025 and status='finished') then raise exception 'Region failed to finish';end if;
 if(select count(*) from public.cw_news where career_id=cid and kind='title')<9 then raise exception 'Missing competition title news';end if;
 if exists(select 1 from public.mgr_matches m where m.career_id=cid and m.status='finished' and m.minute<90) then raise exception 'Background match stopped before full time';end if;
 if not exists(select 1 from public.cw_news where career_id=cid and kind='title' and metadata->'mvp'->>'player_id' is not null) then raise exception 'No actual champion-player award';end if;
 if not exists(select 1 from public.cw_seasons where career_id=cid and region='ENG' and year=2026) or not exists(select 1 from public.cw_seasons where career_id=cid and region='BRA' and year=2027) then raise exception 'Regional rollover missing';end if;
 select season_id into sid from public.cw_seasons where career_id=cid and region='BRA' and year=2027;
 if not exists(select 1 from public.season_participants where season_id=sid and competition_id='libertadores' and origin='qualified') then raise exception 'Next-season qualification not historic';end if;
 if not exists(select 1 from public.cw_negotiations where career_id=cid and initiator='ai' and status='completed' and public.cw_region(seller_club)<>public.cw_region(buyer_club)) then raise exception 'AI never completed international transfer';end if;
 if exists(select 1 from public.cw_contracts where career_id=cid and status='active' group by player_id having count(*)>1) then raise exception 'Duplicate active contracts after full cycle';end if;
 if exists(select 1 from public.cw_club_dates where career_id=cid group by club_id,due_on having count(*)>1) then raise exception 'Clashing calendar';end if;
 raise notice 'PASS full calendar: two completed regions, actual champion awards, qualification and international AI transfers';
end $cycle$;
rollback;
begin;
do $legacy$
#variable_conflict use_column
declare cid uuid:='41414141-0000-0000-0000-000000000011';original uuid;reused uuid;
begin
 select season_id into original from public.cw_seasons where career_id=cid and region='ENG' and year=2025;
 delete from public.cw_seasons where career_id=cid and region='ENG' and year=2025;
 reused:=public.cw_create_region(cid,'ENG',2025);
 if reused<>original or(select count(*) from public.career_seasons where career_id=cid and region='ENG' and year=2025 and mode in('coach','world'))<>1 then raise exception 'Legacy completed season was recreated';end if;
 raise notice 'PASS legacy regional year reused without duplicating fixtures';
end $legacy$;
rollback;
begin;
select set_config('request.jwt.claim.sub','41414141-0000-0000-0000-000000000001',true);
do $preseason$
#variable_conflict use_column
declare cid uuid:='41414141-0000-0000-0000-000000000011';sid uuid;offer_id uuid;fingerprint text;
begin
 select season_id into sid from public.cw_seasons where career_id=cid and region='BRA' and year=2027;
 if exists(select 1 from public.season_fixtures where season_id=sid and status='played') then raise exception 'Pre-season fixtures played without coach';end if;
 update public.cw_world set today='2026-12-31',needs_sync=false where career_id=cid;
 update public.cw_clubs set cash=5000000 where career_id=cid and club_id='palmeiras';
 select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) into fingerprint from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=cid and f.status='played';
 insert into public.season_offers(career_id,season_id,from_club,bonus_coins,pitch,kind,expires_day,salary,contract_years,budget_guarantee,expires_on)
 select cid,primary_season,'palmeiras',0,'Pre-season job','coach',elapsed_days+7,100,2,0,today+7 from public.cw_world where career_id=cid returning id into offer_id;
 perform public.mgr_offer_respond(offer_id,true);
 if(select primary_season from public.cw_world where career_id=cid)<>sid or(select club_id from public.mgr_coach where career_id=cid)<>'palmeiras' then raise exception 'Off-season job failed to adopt upcoming season';end if;
 if(select md5(string_agg(to_jsonb(f)::text,'' order by f.id)) from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=cid and f.status='played')<>fingerprint then raise exception 'Off-season job rewrote played results';end if;
 raise notice 'PASS off-season job adopts existing upcoming year, with every result preserved';
end $preseason$;
rollback;
