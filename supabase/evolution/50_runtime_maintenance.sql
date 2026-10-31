begin;
alter table public.cw_runtime add column if not exists last_maintenance_at timestamptz;
create or replace function public.cw_settle_month(p_career uuid,p_month date)
returns void language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from public.cw_settled_months where career_id=p_career and month=p_month) then return;end if;
 perform public.cw_settle_month_before_v38(p_career,p_month);
 insert into public.cw_settled_months(career_id,month) values(p_career,p_month) on conflict do nothing;
 if not public.cw_runtime_enabled(p_career) then perform public.cw_compact_month(p_career,p_month);end if;
end $$;

-- The established retention rules (v41) run outside player requests, at most 3 idle careers/hour.
create or replace function public.cw_runtime_maintenance()
returns integer language plpgsql security definer set search_path=public as $$
declare r record;n int:=0;
begin
 for r in select c.id from public.careers c join public.cw_runtime rt on rt.career_id=c.id
 where (rt.last_maintenance_at is null or rt.last_maintenance_at<now()-interval '1 day')
 and not exists(select 1 from public.mgr_matches m where m.career_id=c.id and m.status='live' and m.user_side is not null)
 order by rt.last_maintenance_at nulls first,c.id limit 3 for update of c skip locked loop
  perform public.cw_prune_career(r.id);
  delete from public.cw_ai_days where career_id=r.id and on_date<(select today-1 from public.cw_world where career_id=r.id);
  update public.cw_runtime set last_maintenance_at=now() where career_id=r.id;n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.cw_settle_month(uuid,date),public.cw_runtime_maintenance() from public,anon,authenticated;
do $$ begin
 if to_regprocedure('cron.schedule(text,text,text)') is not null then
 perform cron.schedule('career-runtime-retention','41 * * * *','select public.cw_runtime_maintenance()');
 end if;
end $$;
commit;
