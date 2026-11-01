-- Keep every valid reward reachable, including earlier recurring periods.
-- Read-only overview change: existing completions, deadlines and claims are untouched.
begin;
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
commit;
