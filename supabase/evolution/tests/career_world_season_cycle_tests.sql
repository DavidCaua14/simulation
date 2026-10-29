-- Complete calendar cycle with both regions and real match/player statistics; all users fictitious.
begin;
-- A single synthetic transaction freezes now(); production requests use separate transactions.
update public.rate_limit_rules set max_hits=5000 where action='economy';
insert into auth.users(id) values('41414141-0000-0000-0000-000000000001');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values('41414141-0000-0000-0000-000000000011','41414141-0000-0000-0000-000000000001','Full cycle test','palmeiras','BR',30,100);
select set_config('request.jwt.claim.sub','41414141-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
-- This observer career has no club, so all fixtures use the same AI match engine.
select public.mgr_end_spell('41414141-0000-0000-0000-000000000011','left');
do $cycle$
#variable_conflict use_column
declare cid uuid:='41414141-0000-0000-0000-000000000011';res jsonb;i int:=0;start_day date;bad int;sid uuid;
begin
 select today into start_day from public.cw_world where career_id=cid;
 loop
  res:=public.career_world_advance(14,gen_random_uuid());i:=i+1;
  exit when (select today from public.cw_world where career_id=cid)>=date '2027-01-02';
  if i>1500 then raise exception 'Calendar failed to progress: %',res;end if;
  if i%1=0 then raise notice 'Cycle progress: batch %, date %, played %',i,res->>'today',(select count(*) from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=cid and f.status='played');end if;
 end loop;
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
 raise notice 'PASS full calendar cycle: % batches, both regions complete, actual champion awards, next-season qualification and international AI transfers',i;
end $cycle$;
rollback;
