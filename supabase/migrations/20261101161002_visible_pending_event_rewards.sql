-- Visible pending event rewards; source: evolution/52_visible_pending_event_rewards.sql.
-- Atomic deployment: lock careers, compare protected rows per career, retain all existing progress.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
set local timezone='UTC';
create temporary table _scoped_table_scopes on commit drop as
 select tab.table_name,array_agg(col.column_name::text) cols from information_schema.tables tab
 join information_schema.columns col using(table_schema,table_name)
 where tab.table_schema='public' and tab.table_type='BASE TABLE' and tab.table_name in('careers','event_completions','event_progress','player_streaks','wallet_ledger') group by tab.table_name;
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

-- Keep every valid reward reachable, including earlier recurring periods.
-- Read-only overview change: existing completions, deadlines and claims are untouched.
create or replace function public.events_overview()
returns jsonb language plpgsql security definer set search_path=public as $function$
declare
 v_c public.careers;v_active jsonb;v_upcoming jsonb;v_ended jsonb;
 v_pending jsonb;v_claimable bigint;
begin
 select * into v_c from public.careers where user_id=auth.uid() and status='active';
 if not found then raise exception 'Carreira ativa não encontrada';end if;
 select coalesce(jsonb_agg(public.event_json(e,v_c.id) order by e.category='daily' desc,e.category='weekly' desc,e.sort_order,e.ends_at),'[]'::jsonb)
  into v_active from public.events e where e.status='published' and now()>=e.starts_at and now()<e.ends_at;
 select coalesce(jsonb_agg(public.event_json(e,v_c.id) order by e.starts_at),'[]'::jsonb)
  into v_upcoming from public.events e where e.status='published' and e.starts_at>now() and e.starts_at<now()+interval '30 days';
 select coalesce(jsonb_agg(public.event_json(e,v_c.id) order by e.ends_at desc),'[]'::jsonb)
  into v_ended from public.events e where e.status='published' and e.ends_at<=now() and e.ends_at>now()-interval '7 days';
 -- Count all valid completions, but list separately only those without a button
 -- in the current event cards. A claimed current period must not hide an older one.
 select count(*),coalesce(jsonb_agg(jsonb_build_object(
   'id',e.id,'name',e.name,'period_key',c.period_key,
   'completed_at',c.completed_at,'claim_until',c.claim_until,'completion_id',c.id,
   'rewards',public.event_json(e,v_c.id)->'rewards'
  ) order by c.claim_until,c.completed_at,c.id) filter(where not exists(
   select 1 from jsonb_array_elements(v_active||v_upcoming||v_ended) card
    where card->'completion'->>'id'=c.id::text
  )),'[]'::jsonb)
  into v_claimable,v_pending
  from public.event_completions c join public.events e on e.id=c.event_id
  where c.career_id=v_c.id and c.claimed_at is null and now()<c.claim_until and e.status<>'cancelled';
 return jsonb_build_object(
  'now',now(),'is_admin',public.is_admin(),'active',v_active,'upcoming',v_upcoming,'ended',v_ended,
  'claimable',v_claimable,'pending_rewards',v_pending,
  'history',coalesce((select jsonb_agg(jsonb_build_object('event',e.name,'period',c.period_key,'claimed_at',c.claimed_at,'rewards',c.rewards) order by c.claimed_at desc)
   from(select * from public.event_completions where career_id=v_c.id and claimed_at is not null order by claimed_at desc limit 30)c
   join public.events e on e.id=c.event_id),'[]'::jsonb),
  'streak',public.streak_status_for(v_c.id));
end $function$;
revoke all on function public.events_overview() from public,anon;
grant execute on function public.events_overview() to authenticated;

do $$ declare r record;h text;n bigint;begin
 for r in select * from _scoped_protected_before order by career_id,table_name loop
  execute format('select count(*),md5(coalesce(string_agg(h,'''' order by h),'''')) from(select md5(to_jsonb(x)::text) h from public.%I x where %s)z',r.table_name,r.predicate) into n,h using r.career_id;
  if n<>r.n or h<>r.hash then raise exception 'Protected progress differs in table %; deployment rolled back',r.table_name;end if;
 end loop;
 raise notice 'Protected progress verified for % careers, % table comparisons',(select count(distinct career_id) from _scoped_protected_before),(select count(*) from _scoped_protected_before);
end $$;
notify pgrst,'reload schema';
commit;
