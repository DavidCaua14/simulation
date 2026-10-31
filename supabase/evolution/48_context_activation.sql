begin;
-- A busca lê o catálogo compartilhado e sobrepõe o estado individual quando existir.
create or replace function public.career_player_search(p_query text default '',p_position text default '',p_region text default '',p_club text default '',p_max_value bigint default null,p_page integer default 0,p_country text default '')
returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare car uuid:=public.cw_current_career();own text;w public.cw_world;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by x.overall desc,x.id),'[]') from(
 select b.*,public.cw_player_value(car,b.id) value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
 coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=car and ss.status='active' and st.player_id=b.id),0) minutes
 from(
 select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,round(pr.rating) overall,
 round(coalesce(mp.condition,100)) condition,
 coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0) age,
 coalesce(cp.age_estimated,sp.age is null) age_estimated,coalesce(cp.potential,least(99,round(pr.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) potential,
 coalesce(cp.morale,65) morale,coalesce(cp.promised_role,'rotation') promised_role,coalesce(cp.transfer_requested,false) transfer_requested,
 coalesce(cp.shirt_number,sp.shirt_number) number
 from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
 left join public.mgr_players mp on mp.career_id=car and mp.player_id=sp.id
 left join public.cw_players cp on cp.career_id=car and cp.player_id=sp.id
 cross join lateral(select case when mp.player_id is null then sp.club_id else mp.club_id end club_id)e
 left join public.sim_clubs sc on sc.id=e.club_id
 where sp.active and (coalesce(p_query,'')='' or sp.full_name ilike '%'||left(p_query,60)||'%')
 and (coalesce(p_country,'')='' or sc.country=upper(p_country))
 and (coalesce(p_position,'')='' or sp.position=p_position)
 and (coalesce(p_region,'')='' or public.cw_region(e.club_id)=p_region or(p_region='free' and e.club_id is null))
 and (coalesce(p_club,'')='' or e.club_id=case when p_club='mine' then own else p_club end)
 and (p_max_value is null or public.cw_player_value(car,sp.id)<=p_max_value)
 order by pr.rating desc,sp.id limit 30 offset least(greatest(coalesce(p_page,0),0),200)*30)b
 left join public.cw_contracts ct on ct.career_id=car and ct.player_id=b.id and ct.status='active')x);
end $$;

-- Prizes need a club account, without requiring its roster or league engine.
create or replace function public.cw_ensure_club_finance(p_career uuid,p_club text)
returns void language sql security definer set search_path=public as $$
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((2000+power(greatest(5,c.strength-40),2)*25)*case when public.cw_region(c.id)='ENG' then 1.5 else 1 end),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where c.id=p_club on conflict do nothing
$$;
revoke all on function public.cw_ensure_club_finance(uuid,text) from public,anon,authenticated;

-- Resumo de calendário inativo: atualiza placares em lote sem atletas, lances ou XP.
create or replace function public.cw_summarize_region(p_career uuid,p_season uuid,p_until date)
returns integer language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;r record;iteration int;n int:=0;changed int;seed text;w public.cw_world;gh int;ga int;winner text;pen_h int;pen_a int;rule text;club text;
begin
 select * into s from public.career_seasons where id=p_season and career_id=p_career;
 select * into w from public.cw_world where career_id=p_career;
 if s.id is null or s.id=w.primary_season then raise exception 'Resumo permitido apenas para o contexto inativo';end if;
 if exists(select 1 from public.mgr_matches where season_id=s.id and status='live' and user_side is not null) then raise exception 'Partida em andamento preservada';end if;
 select rt.seed::text||':'||s.id into seed from public.cw_runtime rt where rt.career_id=p_career;
 for iteration in 1..24 loop
  perform public.cw_schedule(s.id);
  update public.season_fixtures f set home_goals=public.cw_poisson(1.4*exp(.022*(h.strength-a.strength)),seed||':'||f.id||':h'),
   away_goals=public.cw_poisson(1.05*exp(.022*(a.strength-h.strength)),seed||':'||f.id||':a'),status='played',played_at=now(),
   stats=jsonb_build_object('simulation','inactive_summary','algorithm',1,'yellows',jsonb_build_array(0,0),'reds',jsonb_build_array(0,0))
  from public.cw_fixture_dates d,public.sim_clubs h,public.sim_clubs a
  where f.season_id=s.id and f.status='pending' and not coalesce(f.player_match,false)
   and d.fixture_id=f.id and d.due_on<=p_until and h.id=f.home_club and a.id=f.away_club;
  get diagnostics changed=row_count;n:=n+changed;
  -- Resolve only ties produced by this summary; retain all existing match results.
  for r in select fx.* from public.season_fixtures fx where fx.season_id=s.id and fx.status='played' and fx.tie_no is not null
   and fx.stats->>'simulation'='inactive_summary' and fx.tie_winner is null
   and not exists(select 1 from public.season_fixtures z where z.season_id=s.id and z.competition_id=fx.competition_id and z.stage=fx.stage and z.tie_no=fx.tie_no and(z.leg>fx.leg or z.status<>'played')) loop
   select sum(case when z.home_club=r.home_club then z.home_goals else z.away_goals end),
    sum(case when z.home_club=r.away_club then z.home_goals else z.away_goals end) into gh,ga
   from public.season_fixtures z where z.season_id=s.id and z.competition_id=r.competition_id and z.stage=r.stage and z.tie_no=r.tie_no;
   rule:=coalesce(public.sim_phase(r.competition_id,r.stage)->>'tie','penalties');pen_h:=null;pen_a:=null;
   if gh>ga then winner:=r.home_club;elsif ga>gh then winner:=r.away_club;
   elsif rule='higher_seed' then winner:=r.home_club;
   else
    winner:=case when public.cw_random(seed||':'||r.id||':penalty-winner')<(select 1/(1+exp(.04*(a.strength-h.strength))) from public.sim_clubs h,public.sim_clubs a where h.id=r.home_club and a.id=r.away_club) then r.home_club else r.away_club end;
    pen_h:=3+floor(public.cw_random(seed||':'||r.id||':penalty-score')*3)::int;pen_a:=greatest(0,pen_h-1-floor(public.cw_random(seed||':'||r.id||':penalty-gap')*2)::int);
    if winner=r.away_club then gh:=pen_h;pen_h:=pen_a;pen_a:=gh;end if;
   end if;
   update public.season_fixtures set tie_winner=winner,home_pens=pen_h,away_pens=pen_a where id=r.id;
  end loop;
  for r in select competition_id from public.season_competitions where season_id=s.id and status<>'finished' loop
   if not exists(select 1 from public.season_fixtures where season_id=s.id and competition_id=r.competition_id and status='pending') then
    for club in select club_id from public.season_participants where season_id=s.id and competition_id=r.competition_id loop perform public.cw_ensure_club_finance(p_career,club);end loop;
   end if;
   perform public.sim_advance(s.id,r.competition_id);
  end loop;
  exit when changed=0 and not exists(select 1 from public.season_fixtures fx join public.cw_fixture_dates fd on fd.fixture_id=fx.id where fx.season_id=s.id and fx.status='pending' and not coalesce(fx.player_match,false) and fd.due_on<=p_until);
 end loop;
 if not exists(select 1 from public.season_fixtures where season_id=s.id and status='pending') and not exists(select 1 from public.season_competitions where season_id=s.id and status<>'finished') then
  perform public.sim_season_transition(s.id);
  update public.career_seasons set status='finished',finished_at=now(),summary=coalesce(summary,'{}')||jsonb_build_object('world',true,'simulation','inactive_summary') where id=s.id and status='active';
 end if;
 return n;
end $$;

create or replace function public.cw_activate_region(p_career uuid,p_region text)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;s public.career_seasons;sid uuid;yr int;
begin
 select * into w from public.cw_world where career_id=p_career for update;
 yr:=public.cw_year(p_region,w.today);
 for s in select cs.* from public.career_seasons cs join public.cw_seasons ws on ws.season_id=cs.id
 where ws.career_id=p_career and ws.region=p_region and cs.status='active' and ws.year<yr loop
 perform public.cw_summarize_region(p_career,s.id,w.today);
 end loop;
 sid:=public.cw_create_region(p_career,p_region,yr);
 if sid<>w.primary_season then perform public.cw_summarize_region(p_career,sid,w.today-1);end if;
 return sid;
end $$;

create or replace function public.career_calendar(p_comp text default null,p_scope text default 'preview',p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c public.careers;sid uuid;own text;
begin
 c:=public.cw_read_career();select primary_season into sid from public.cw_world where career_id=c.id;
 select club_id into own from public.mgr_coach where career_id=c.id;
 if p_scope not in('preview','mine','competition') or p_page<0 or p_page>100 then raise exception 'Consulta de calendário inválida';end if;
 if p_scope='preview' then
 return(select coalesce(jsonb_agg(to_jsonb(x)-'stats'),'[]') from(
 (select f.* from public.season_fixtures f where f.season_id=sid and f.status='played' and f.player_match order by f.played_at desc,f.id desc limit 10)
 union all
 (select f.* from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id where f.season_id=sid and f.status='pending' and own in(f.home_club,f.away_club) order by d.due_on,f.id limit 20)
 )x);
 end if;
 return(select coalesce(jsonb_agg(to_jsonb(x)-'stats' order by round_no,id),'[]') from(
 select f.* from public.season_fixtures f where f.season_id=sid and (p_comp is null or f.competition_id=p_comp)
 and (p_scope<>'mine' or f.player_match or own in(f.home_club,f.away_club)) order by f.round_no,f.id limit 500 offset p_page*500)x);
end $$;

revoke all on function public.cw_summarize_region(uuid,uuid,date),public.cw_activate_region(uuid,text) from public,anon,authenticated;
revoke all on function public.career_player_search(text,text,text,text,bigint,integer,text) from public,anon;
grant execute on function public.career_player_search(text,text,text,text,bigint,integer,text) to authenticated;
revoke all on function public.career_calendar(text,text,integer) from public,anon;
grant execute on function public.career_calendar(text,text,integer) to authenticated;
commit;
