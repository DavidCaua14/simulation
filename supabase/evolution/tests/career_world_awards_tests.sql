begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $awards$
#variable_conflict use_column
declare cid uuid:='31313131-0000-0000-0000-000000000011';sid uuid;fx bigint;champ text;notice_row public.cw_news;expected numeric;winner_player text;pid text;ct public.cw_contracts;salary_due bigint;
begin
 insert into public.career_seasons(career_id,season_no,year,region,mode,status) values(cid,999,2030,'ENG','world','archived') returning id into sid;
 insert into public.season_participants(season_id,competition_id,club_id) values(sid,'fa_cup','arsenal'),(sid,'fa_cup','chelsea');
 insert into public.season_competitions(season_id,competition_id,stage) values(sid,'fa_cup','final');
 insert into public.season_fixtures(season_id,competition_id,stage,round_no,tie_no,leg,home_club,away_club)
 values(sid,'fa_cup','final',1,1,1,'arsenal','chelsea') returning id into fx;
 update public.cw_contracts set appearance_bonus=50,goal_bonus=25 where career_id=cid and club_id in('arsenal','chelsea') and status='active';
 perform public.mgr_sim_fixture(fx,cid);
 if(select minute from public.mgr_matches where fixture_id=fx)<90 then raise exception 'Final stopped at halftime';end if;
 if not exists(select 1 from public.cw_appearances where fixture_id=fx) then raise exception 'Appearances were discarded';end if;
 if exists(select 1 from public.mgr_match_players where fixture_id=fx) then raise exception 'Legacy compaction was lost';end if;
 perform public.sim_advance(sid,'fa_cup');
 select champion_club into champ from public.season_competitions where season_id=sid and competition_id='fa_cup';
 if champ is null then raise exception 'Final failed to determine a champion';end if;
 select * into notice_row from public.cw_news where career_id=cid and event_key='champion:'||sid||':fa_cup';
 if notice_row.id is null or notice_row.metadata->>'champion'<>champ or notice_row.metadata#>>'{mvp,club_id}'<>champ then raise exception 'Champion award/news missing or contradictory';end if;
 winner_player:=notice_row.metadata#>>'{mvp,player_id}';
 select round(avg(rating),2) into expected from public.cw_appearances where fixture_id=fx and player_id=winner_player;
 if expected is null or (notice_row.metadata#>>'{mvp,rating}')::numeric<>expected then raise exception 'Invented player award';end if;
 perform public.sim_advance(sid,'fa_cup');
 if(select count(*) from public.cw_news where career_id=cid and event_key='champion:'||sid||':fa_cup')<>1 or(select count(*) from public.cw_finance where career_id=cid and kind='competition_prize' and reference=sid||':fa_cup')<>1 then raise exception 'Duplicate title/prize';end if;
 select a.player_id into pid from public.cw_appearances a where fixture_id=fx and a.club_id='arsenal' limit 1;
 select * into ct from public.cw_contracts where career_id=cid and player_id=pid and status='active';
 perform public.cw_settle_month(cid,'2026-01-01');
 select -amount into salary_due from public.cw_finance where career_id=cid and kind='wages' and reference=ct.id||':2026-01';
 if salary_due<>ct.monthly_salary+50+(select goals*25 from public.cw_appearances where fixture_id=fx and player_id=pid) then raise exception 'Appearance/goal bonus did not use archived real performance';end if;
 raise notice 'PASS actual full-time final, compact AI archive, champion-team MVP, deduplicated club prizes and appearance/goal salary bonuses';
end $awards$;
rollback;
