create table if not exists public.reset_rank_snapshot(
 career_id uuid primary key references public.careers(id) on delete cascade,
 taken_at timestamptz not null default now(),
 position integer not null, points bigint not null, level integer, xp integer, reputation numeric, titles integer, wins integer, draws integer,
 events integer, fired integer, coins bigint, diamonds bigint, credibility numeric,
 careers_row jsonb not null, mgr_coach_row jsonb, cw_coach_row jsonb, prediction_row jsonb);
alter table public.reset_rank_snapshot enable row level security;
revoke all on public.reset_rank_snapshot from anon,authenticated;
insert into public.reset_rank_snapshot(career_id,position,points,level,xp,reputation,titles,wins,draws,events,fired,coins,diamonds,credibility,careers_row,mgr_coach_row,cw_coach_row,prediction_row)
select s.career_id,row_number() over(order by s.points desc,s.level desc,s.wins desc,s.created_at,s.career_id),s.points,s.level,s.xp,
 (select reputation from public.mgr_coach where career_id=s.career_id),s.titles,s.wins,s.draws,s.events,s.fired,c.coins,c.diamonds,
 (select credibility from public.cw_coach where career_id=s.career_id),
 to_jsonb(c),(select to_jsonb(m) from public.mgr_coach m where m.career_id=s.career_id),(select to_jsonb(k) from public.cw_coach k where k.career_id=s.career_id),
 (select to_jsonb(p) from public.prediction_stats p where p.career_id=c.id)
from public.ranking_scores() s join public.careers c on c.id=s.career_id
on conflict(career_id) do nothing;
select career_id,position,points,credibility,prediction_row is not null pred from public.reset_rank_snapshot order by position;
