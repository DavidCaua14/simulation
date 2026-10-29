-- Cartas base: estruturas e regras centrais. Aplicar após 20, com 22 e 23.
begin;
create table if not exists public.base_card_conversion_rates (
 tier text primary key references public.card_tiers(id),
 coins int not null check(coins>=0),diamonds int not null check(diamonds>=0),energy int not null check(energy>=0),
 version int not null default 1 check(version=1)
);
insert into public.base_card_conversion_rates(tier,coins,diamonds,energy) values
 ('basica',15,0,0),('destaque',2300,16,2),('lenda',21600,130,4),('epica',43200,260,6)
on conflict do nothing;
create table if not exists public.base_card_compensations (
 career_id uuid not null references public.careers(id),source_kind text not null check(source_kind in('card','box')),
 source_id text not null,tier text not null,qty int not null check(qty>0),coins int not null,diamonds int not null,energy int not null,
 version int not null default 1,created_at timestamptz not null default now(),
 primary key(career_id,source_kind,source_id,version)
);
create table if not exists public.base_card_players (
 card_id text primary key references public.cards(id),player_id text not null unique references public.sim_players(id)
);
insert into public.base_card_players select c.id,p.id from public.cards c join public.sim_players p on p.id=c.player_key where c.tier='basica'
on conflict do nothing;
create table if not exists public.base_card_roster (
 career_id uuid not null references public.careers(id),player_id text not null references public.sim_players(id),
 card_id text not null references public.base_card_players(card_id),original_club_id text,last_club_id text,
 primary key(career_id,player_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id)
);
alter table public.streak_rewards add column if not exists energy int not null default 0 check(energy>=0);
create table if not exists public.base_event_reward_migrations (
 reward_id uuid primary key,original jsonb not null,created_at timestamptz not null default now()
);
create table if not exists public.base_card_release (
 id boolean primary key default true check(id),activated_at timestamptz not null default now(),version int not null default 1
);
insert into public.base_card_release(id) values(true) on conflict do nothing;
create table if not exists public.base_match_rewards (
 fixture_id bigint primary key,season_id uuid not null,career_id uuid not null,
 coins int not null check(coins>=0),energy int not null check(energy in(0,1)),created_at timestamptz not null default now(),
 foreign key(fixture_id,season_id) references public.season_fixtures(id,season_id),
 foreign key(season_id,career_id) references public.career_seasons(id,career_id)
);
do $$ declare t text; begin
 foreach t in array array['base_event_reward_migrations','base_card_conversion_rates','base_card_compensations','base_card_players','base_card_roster','base_card_release','base_match_rewards'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;
grant select on public.base_card_compensations to authenticated;
drop policy if exists own_base_compensation on public.base_card_compensations;
create policy own_base_compensation on public.base_card_compensations for select to authenticated using
 (exists(select 1 from public.careers c where c.id=career_id and c.user_id=auth.uid()));

create or replace function public.mgr_sync_base_cards(p_career uuid)
returns int language plpgsql security definer set search_path=public as $$
declare target text;r record;original text;changed int:=0;
begin
 perform 1 from public.careers where id=p_career for update;
 select club_id into target from public.mgr_coach where career_id=p_career and status='employed';
 if target is null then return 0;end if;
 for r in select m.card_id,m.player_id from public.user_cards u join public.base_card_players m on m.card_id=u.card_id
   where u.career_id=p_career and u.qty>0 order by m.player_id loop
  insert into public.mgr_players(career_id,player_id,club_id,rhythm)
   select p_career,p.id,p.club_id,case when p.is_youth then 50 else 70 end from public.sim_players p where p.id=r.player_id
   on conflict do nothing;
  select club_id into original from public.mgr_players where career_id=p_career and player_id=r.player_id;
  insert into public.base_card_roster(career_id,player_id,card_id,original_club_id,last_club_id)
   values(p_career,r.player_id,r.card_id,original,target) on conflict(career_id,player_id) do update set last_club_id=excluded.last_club_id;
  if original is distinct from target then
   -- Preserve saved tactics; only remove this transferred athlete from old club selections.
   update public.mgr_lineups l set
    slots=coalesce((select jsonb_object_agg(k,v) from jsonb_each(l.slots) e(k,v) where v<>to_jsonb(r.player_id)),'{}'),
    bench=array_remove(l.bench,r.player_id)
    where l.career_id=p_career and l.club_id<>target and
     (exists(select 1 from jsonb_each_text(l.slots) where value=r.player_id)
       or r.player_id=any(l.bench));
   update public.mgr_players set club_id=target where career_id=p_career and player_id=r.player_id;
   changed:=changed+1;
  end if;
 end loop;
 return changed;
end $$;

create or replace function public.base_award_match(p_fixture bigint)
returns void language plpgsql security definer set search_path=public as $$
declare f public.season_fixtures;s public.career_seasons;club text;mine int;opp int;won boolean;mult numeric;award public.base_match_rewards;
begin
 select * into f from public.season_fixtures where id=p_fixture;
 if f.id is null or f.status<>'played' or not coalesce(f.player_match,false) then return;end if;
 if f.played_at is null or f.played_at<(select activated_at from public.base_card_release) then return;end if;
 select * into s from public.career_seasons where id=f.season_id;
 club:=coalesce(f.coach_club,s.club_id);
 if club is null or club not in(f.home_club,f.away_club) then return;end if;
 perform 1 from public.careers where id=s.career_id for update;
 mine:=case when f.home_club=club then f.home_goals else f.away_goals end;
 opp:=case when f.home_club=club then f.away_goals else f.home_goals end;
 won:=mine>opp or(mine=opp and f.home_pens is not null and case when f.home_club=club then f.home_pens>f.away_pens else f.away_pens>f.home_pens end);
 select c.xp_mult*(case public.mgr_stage_rank(f.competition_id,f.stage) when 5 then 1.5 when 4 then 1.2 when 3 then 1.2 when 2 then 1.2 else 1 end) into mult
  from public.sim_competitions c where c.id=f.competition_id;
 insert into public.base_match_rewards(fixture_id,season_id,career_id,coins,energy)
  values(f.id,s.id,s.career_id,round((case when won then 60 when mine=opp then 25 else 10 end)*mult)::int,won::int)
  on conflict do nothing returning * into award;
 if award.fixture_id is null then return;end if;
 if award.coins>0 then perform public.econ_apply(s.career_id,'coins',award.coins,'match_reward',f.id::text);end if;
 if award.energy>0 then perform public.econ_apply(s.career_id,'bonus_energy',1,'match_win_energy',f.id::text);end if;
end $$;

create or replace function public.base_fixture_reward_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status='played' and old.status is distinct from 'played' then perform public.base_award_match(new.id);end if;
 return new;
end $$;
drop trigger if exists card_on_fixture_played on public.season_fixtures;
drop trigger if exists base_fixture_reward on public.season_fixtures;
create trigger base_fixture_reward after update on public.season_fixtures for each row execute function public.base_fixture_reward_trigger();
revoke all on function public.mgr_sync_base_cards(uuid),public.base_award_match(bigint),public.base_fixture_reward_trigger() from public,anon,authenticated;
create or replace function public.mgr_player_detail(p_player text,p_fixture bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car public.careers;club text;detail jsonb;
begin
 car:=public.mgr_lock();
 if p_fixture is not null and not exists(select 1 from public.mgr_matches m join public.mgr_match_players mp on mp.fixture_id=m.fixture_id
   where m.fixture_id=p_fixture and m.career_id=car.id and mp.player_id=p_player) then raise exception 'Jogador ou partida fora desta carreira';end if;
 select club_id into club from public.mgr_players where career_id=car.id and player_id=p_player;
 if not found or club is null then raise exception 'Jogador não encontrado nesta carreira';end if;
 select value into detail from jsonb_array_elements(public.mgr_squad(club)->'players') where value->>'id'=p_player;
 if detail is null then raise exception 'Ficha não encontrada nesta carreira';end if;
 return detail;
end $$;
revoke all on function public.mgr_player_detail(text,bigint) from public,anon;
grant execute on function public.mgr_player_detail(text,bigint) to authenticated;
commit;
