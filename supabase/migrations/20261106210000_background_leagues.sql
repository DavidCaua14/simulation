-- Ligas de fundo (nível B): catálogo compartilhado, sem partidas por carreira até o técnico assumir um clube da liga.
-- Ver docs/banco-hibrido.md, seção "Ligas de fundo".

alter table public.sim_competitions add column if not exists background boolean not null default false;
alter table public.sim_clubs add column if not exists lazy boolean not null default false;
alter table public.sim_clubs add column if not exists catalog_ready_at timestamptz;

comment on column public.sim_competitions.background is 'Liga de fundo: só entra numa temporada quando o técnico da carreira treina um clube dela.';
comment on column public.sim_clubs.lazy is 'Clube de nível B: notas por posição e valores-base só são gravados quando o clube entra num mundo.';

-- A competição entra nesta temporada?
create or replace function public.cw_comp_wanted(p_season uuid, p_comp text)
returns boolean language sql stable security definer set search_path to 'public' as $$
 select not co.background
  or exists(select 1 from public.season_competitions sc where sc.season_id=p_season and sc.competition_id=co.id)
  or exists(select 1 from public.career_seasons s join public.mgr_coach mc on mc.career_id=s.career_id and mc.status='employed'
            join public.sim_competition_clubs cc on cc.club_id=mc.club_id and cc.competition_id=co.id where s.id=p_season)
 from public.sim_competitions co where co.id=p_comp
$$;

-- Grava notas por posição e valores-base de um clube de nível B (uma vez, vale para todas as carreiras).
create or replace function public.sim_ensure_club_catalog(p_club text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare n int:=0;
begin
 perform 1 from public.sim_clubs where id=p_club and lazy and catalog_ready_at is null for update;
 if not found then return 0;end if;
 insert into public.sim_player_ratings(player_id,pos,rating,eff)
 select player_id,array_agg(pos order by pos),array_agg(rating order by pos),array_agg(eff order by pos) from(
  with a as materialized (select x.player_id, to_jsonb(x) j from public.sim_player_attrs x join public.sim_players p on p.id=x.player_id where p.club_id=p_club and p.career_id is null)
  select p.id player_id, w.pos,
   round(sum(w.weight*(a.j->>w.attr)::numeric)/sum(w.weight),2) rating,
   round(sum(w.weight*(a.j->>w.attr)::numeric)/sum(w.weight)*greatest(coalesce(max(f.fit),0.5),case when w.pos=any(p.secondary_positions) then 0.97 else 0 end),2) eff
  from public.sim_players p join a on a.player_id=p.id join public.sim_role_weights w on true
  left join public.sim_position_fit f on f.from_pos=p.position and f.to_pos=w.pos
  group by p.id,w.pos,p.secondary_positions) t
 group by player_id
 on conflict(player_id) do nothing;
 get diagnostics n=row_count;
 insert into public.sim_player_base(player_id,rating,age0,age_estimated,potential,contract_years,salary0,role0)
 select x.id,x.rating,x.age0,x.age_estimated,x.potential,x.contract_years,
  greatest(greatest(50,ceil(power(greatest(1,x.rating-45),2)*.65+power(greatest(0,x.rating-75),2)*12))::bigint,
   round(public.cw_base_value(x.rating,x.age0,x.potential)*.0065)::bigint),
  case when x.is_youth then 'prospect' when x.rating>=82 then 'key' when x.rating>=74 then 'starter' else 'rotation' end
 from(select p.id,r.rating,p.is_youth,coalesce(p.age,case when p.is_youth then 19 else 26 end) age0,p.age is null age_estimated,
   least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)::int potential,
   1+(abs(hashtext(p.id)::bigint)%4)::int contract_years
  from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
  where p.career_id is null and p.club_id=p_club)x
 on conflict(player_id) do nothing;
 update public.sim_clubs set catalog_ready_at=now() where id=p_club;
 return n;
end $$;

-- Gols de uma partida de fundo: mesma conta do resumo de região, semente por par de clubes.
create or replace function public.cw_bg_goals(p_seed text, p_comp text, p_year int, p_home text, p_away text, p_hs int, p_as int)
returns int[] language sql immutable set search_path to 'public' as $$
 select array[public.cw_poisson(1.4*exp(.022*(p_hs-p_as)),p_seed||':bg:'||p_comp||':'||p_year||':'||p_home||':'||p_away||':h'),
              public.cw_poisson(1.05*exp(.022*(p_as-p_hs)),p_seed||':bg:'||p_comp||':'||p_year||':'||p_home||':'||p_away||':a')]
$$;

-- Classificação calculada de uma liga de fundo numa data. Não grava nada.
create or replace function public.cw_bg_table(p_career uuid, p_comp text, p_on date)
returns table(pos int, club_id text, played int, won int, drawn int, lost int, gf int, ga int, pts int)
language plpgsql stable security definer set search_path to 'public' as $$
#variable_conflict use_column
declare co public.sim_competitions;seed text;yr int;starts date;step int;n int;t text[];
begin
 select * into co from public.sim_competitions where id=p_comp;
 if co.id is null then return;end if;
 select rt.seed::text into seed from public.cw_runtime rt where rt.career_id=p_career;
 seed:=coalesce(seed,p_career::text);
 yr:=public.cw_year(co.region,p_on);starts:=public.cw_start(co.region,yr);
 step:=greatest(1,330/greatest(coalesce((co.rules->>'calendar_rounds')::int,38)-1,1));
 select array_agg(cc.club_id order by cc.club_id) into t from public.sim_competition_clubs cc where cc.competition_id=p_comp;
 n:=coalesce(cardinality(t),0);
 if n<2 then return;end if;
 if n%2=1 then t:=t||null::text;n:=n+1;end if;
 return query
 with pairs as(
  select r.r, i.i, (r.r+i.i)%(n-1) x, case when i.i=0 then n-1 else (r.r-i.i+(n-1))%(n-1) end y
  from generate_series(0,n-2) r(r) cross join generate_series(0,n/2-1) i(i)),
 games as(
  select r+1 rnd, case when (r+i)%2=0 then t[x+1] else t[y+1] end h, case when (r+i)%2=0 then t[y+1] else t[x+1] end a from pairs
  union all
  select r+n, case when (r+i)%2=0 then t[y+1] else t[x+1] end, case when (r+i)%2=0 then t[x+1] else t[y+1] end from pairs),
 played as(
  select g.h,g.a,public.cw_bg_goals(seed,p_comp,yr,g.h,g.a,hc.strength,ac.strength) s
  from games g join public.sim_clubs hc on hc.id=g.h join public.sim_clubs ac on ac.id=g.a
  where starts+14+(g.rnd-1)*step<p_on),
 rws as(
  select h c,s[1] f,s[2] g from played union all select a,s[2],s[1] from played),
 agg as(
  select u.c, count(r.c)::int pl, (count(*) filter(where r.f>r.g))::int w, (count(*) filter(where r.f=r.g))::int d,
   (count(*) filter(where r.f<r.g))::int l, coalesce(sum(r.f),0)::int gf, coalesce(sum(r.g),0)::int ga
  from unnest(t) u(c) left join rws r on r.c=u.c where u.c is not null group by u.c)
 select (row_number() over(order by 3*agg.w+agg.d desc, agg.gf-agg.ga desc, agg.gf desc, agg.c))::int, agg.c, agg.pl, agg.w, agg.d, agg.l, agg.gf, agg.ga, 3*agg.w+agg.d
 from agg order by 1;
end $$;

-- Liga de fundo entra na temporada da carreira: participantes, partidas e rodadas já vencidas resolvidas pelo modelo de fundo.
create or replace function public.cw_attach_league(p_career uuid, p_season uuid, p_comp text)
returns integer language plpgsql security definer set search_path to 'public' as $$
#variable_conflict use_column
declare co public.sim_competitions;ph jsonb;s public.cw_seasons;w public.cw_world;seed text;n int:=0;r record;step int;g int[];
begin
 select * into co from public.sim_competitions where id=p_comp;
 if co.id is null or not co.background or not co.active then return 0;end if;
 if exists(select 1 from public.season_competitions where season_id=p_season and competition_id=p_comp) then return 0;end if;
 select * into s from public.cw_seasons where season_id=p_season and career_id=p_career;
 if s.season_id is null then raise exception 'Temporada sem calendário regional';end if;
 if s.region<>co.region then raise exception 'Liga % fora do calendário %',p_comp,s.region;end if;
 select * into w from public.cw_world where career_id=p_career;
 insert into public.season_participants(season_id,competition_id,club_id,division_key,origin)
  select p_season,p_comp,cc.club_id,co.region||':league','reference' from public.sim_competition_clubs cc where cc.competition_id=p_comp
  on conflict do nothing;
 for r in select cc.club_id from public.sim_competition_clubs cc where cc.competition_id=p_comp order by cc.club_id loop
  perform public.cw_materialize_club(p_career,r.club_id);
 end loop;
 ph:=public.sim_phase_at(p_comp,1);
 insert into public.season_competitions(season_id,competition_id,stage) values(p_season,p_comp,ph->>'id');
 perform public.sim_phase_create(p_season,p_comp,ph->>'id',null);
 select rt.seed::text into seed from public.cw_runtime rt where rt.career_id=p_career;
 seed:=coalesce(seed,p_career::text);
 step:=greatest(1,330/greatest(coalesce((co.rules->>'calendar_rounds')::int,38)-1,1));
 for r in select f.id,f.home_club,f.away_club,hc.strength hs,ac.strength aws,
   least(s.ends_on+s.calendar_shift,s.starts_on+s.calendar_shift+14+(f.round_no-1)*step) due
  from public.season_fixtures f join public.sim_clubs hc on hc.id=f.home_club join public.sim_clubs ac on ac.id=f.away_club
  where f.season_id=p_season and f.competition_id=p_comp and f.status='pending' loop
  continue when r.due>=w.today;
  g:=public.cw_bg_goals(seed,p_comp,s.year,r.home_club,r.away_club,r.hs,r.aws);
  update public.season_fixtures set home_goals=g[1],away_goals=g[2],status='played',played_at=now(),
   stats=jsonb_build_object('simulation','background','algorithm',1,'yellows',jsonb_build_array(0,0),'reds',jsonb_build_array(0,0))
  where id=r.id;
  insert into public.cw_fixture_dates(fixture_id,season_id,career_id,due_on) values(r.id,p_season,p_career,r.due);
  n:=n+1;
 end loop;
 perform public.cw_schedule(p_season);
 return n;
end $$;

create or replace function public.cw_attach_club_leagues(p_career uuid, p_season uuid, p_club text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record;n int:=0;
begin
 if p_season is null then return 0;end if;
 for r in select co.id from public.sim_competitions co join public.sim_competition_clubs cc on cc.competition_id=co.id and cc.club_id=p_club
  join public.cw_seasons s on s.season_id=p_season and s.region=co.region
  where co.background and co.active order by co.sort_order loop
  n:=n+public.cw_attach_league(p_career,p_season,r.id);
 end loop;
 return n;
end $$;

revoke all on function public.cw_comp_wanted(uuid,text), public.sim_ensure_club_catalog(text), public.cw_attach_league(uuid,uuid,text),
 public.cw_attach_club_leagues(uuid,uuid,text), public.cw_bg_table(uuid,text,date), public.cw_bg_goals(text,text,int,text,text,int,int) from public, anon, authenticated;

-- Funções existentes: ligas de fundo só entram quando desejadas; catálogo de nível B sob demanda; liga anexada ao assumir clube.
CREATE OR REPLACE FUNCTION public.cw_create_region(p_career uuid, p_region text, p_year integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare sid uuid;seq int;co record;phase jsonb;starts date;
begin
 perform 1 from public.careers where id=p_career for update;
 select season_id into sid from public.cw_seasons where career_id=p_career and region=p_region and year=p_year;
 if sid is not null then return sid;end if;
 -- Reuse legacy regional history; a completed year must never be generated twice.
 select cs.id into sid from public.career_seasons cs where cs.career_id=p_career and cs.region=p_region and cs.year=p_year and cs.mode in('coach','world') order by cs.season_no desc limit 1;
 if sid is not null then
  starts:=public.cw_start(p_region,p_year);
  insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date);
  update public.career_seasons set was_coached=was_coached or mode='coach' where id=sid;
  if(select status from public.career_seasons where id=sid)='active' then perform public.cw_schedule(sid);end if;
  return sid;
 end if;
 if not exists(select 1 from public.sim_competitions where region=p_region and active) then raise exception 'Região sem competições cadastradas';end if;
 select coalesce(max(season_no),0)+1 into seq from public.career_seasons where career_id=p_career;
 insert into public.career_seasons(career_id,season_no,year,club_id,region,mode,day_no)
 values(p_career,seq,p_year,null,p_region,'world',coalesce((select elapsed_days from public.cw_world where career_id=p_career),0)) returning id into sid;
 perform public.mgr_init_world(p_career);perform public.cw_initialize_finances(p_career);
 starts:=public.cw_start(p_region,p_year);
 insert into public.cw_seasons(career_id,region,year,season_id,starts_on,ends_on,calendar_shift) values(p_career,p_region,p_year,sid,starts,(starts+interval '1 year - 1 day')::date,case when public.cw_runtime_enabled(p_career) then 0 else greatest(0,(select today from public.cw_world where career_id=p_career)-starts) end);
 perform public.sim_participants_build(sid);
 for co in select * from public.sim_competitions where region=p_region and active and public.cw_comp_wanted(sid,id) order by sort_order loop
  phase:=public.sim_phase_at(co.id,1);
  insert into public.season_competitions(season_id,competition_id,stage) values(sid,co.id,phase->>'id');
  perform public.sim_phase_create(sid,co.id,phase->>'id',null);
 end loop;
 perform public.cw_schedule(sid);return sid;
end $function$;

CREATE OR REPLACE FUNCTION public.sim_create_season(p_career uuid, p_region text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_club text;
  v_no   int;
  v_id   uuid;
  c      record;
  v_ph   jsonb;
begin
  perform 1 from public.careers where id=p_career for update;
  if not found then raise exception 'Carreira inexistente';end if;
  if exists(select 1 from public.career_seasons where career_id=p_career and status='active') then raise exception 'Carreira já tem temporada ativa';end if;
  select club_id into v_club from public.careers where id = p_career;
  if v_club is null then raise exception 'Escolha um clube antes de iniciar a temporada'; end if;
  if not exists (select 1 from public.sim_competitions where region = p_region and active) then
    raise exception 'Região sem competições: %', p_region;
  end if;

  select coalesce(max(season_no), 0) + 1 into v_no from public.career_seasons where career_id = p_career;
  insert into public.career_seasons (career_id, season_no, year, club_id, region)
  values (p_career, v_no, 2025 + v_no, v_club, p_region) returning id into v_id;

  perform public.sim_participants_build(v_id);

  for c in select * from public.sim_competitions where region = p_region and active and public.cw_comp_wanted(v_id, id) order by sort_order loop
    v_ph := public.sim_phase_at(c.id, 1);
    if v_ph is null then raise exception 'Competição sem fases: %', c.id; end if;
    insert into public.season_competitions (season_id, competition_id, stage) values (v_id, c.id, v_ph ->> 'id');
    perform public.sim_phase_create(v_id, c.id, v_ph ->> 'id', null);
  end loop;

  insert into public.career_stats (career_id) values (p_career) on conflict do nothing;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sim_participants_build(p_season uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_s     public.career_seasons;
  v_t     public.season_transitions;
  c       record;
  v_list  text[];
  v_q     text[];
  v_slots record;
  v_i     int;
  v_n     int := 0;
  v_entry jsonb;
  v_lg    record;
  v_previous uuid;
  v_from text;
  v_count int;
begin
  select * into v_s from public.career_seasons where id = p_season;
  if exists (select 1 from public.season_participants where season_id = p_season) then
    return 0;                                            -- já montado (idempotente)
  end if;
  select t.* into v_t from public.season_transitions t
    join public.career_seasons fs on fs.id = t.from_season
   where t.career_id = v_s.career_id and fs.career_id=v_s.career_id and t.region = v_s.region and fs.status in ('finished','archived') and fs.season_no < v_s.season_no
   order by fs.season_no desc limit 1;

  select old.id into v_previous from public.career_seasons old where old.career_id=v_s.career_id and old.region=v_s.region
    and old.season_no<v_s.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;

  -- 2a) LIGAS
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'league' and public.cw_comp_wanted(p_season, id) order by sort_order loop
    v_list := null;
    if v_t.id is not null and v_t.result -> 'leagues' ? c.id then
      select array_agg(x) into v_list from jsonb_array_elements_text(v_t.result -> 'leagues' -> c.id) x;
    end if;
    if v_list is null then
      select array_agg(club_id order by club_id) into v_list from public.sim_competition_clubs where competition_id = c.id;
    end if;
    insert into public.season_participants (season_id, competition_id, club_id, division_key, origin)
    select p_season, c.id, x,
           v_s.region || ':league',
           case when v_t.id is null then 'reference'
                when coalesce(v_t.result -> 'promoted' -> c.id, '[]'::jsonb) ? x then 'promoted'
                when coalesce(v_t.result -> 'relegated' -> c.id, '[]'::jsonb) ? x then 'relegated'
                else 'stayed' end
      from unnest(v_list) x;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- 2b) COPAS NACIONAIS: com "entry" (copas inglesas) = todos os clubes das ligas da temporada, entrando na fase da sua divisão;
  --     com qualification = mérito na liga anterior; primeira edição pode conservar a chave de referência
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'cup' order by sort_order loop
    v_entry := c.rules -> 'entry';
    if c.rules ? 'qualification' and v_previous is null and c.rules#>>'{phases,0,pairing,first_season}'='reference' then
      insert into public.season_participants(season_id,competition_id,club_id,group_label,seed,entry_phase,origin)
       select p_season,c.id,cc.club_id,cc.group_label,cc.seed,cc.entry_phase,'reference' from public.sim_competition_clubs cc where cc.competition_id=c.id;
    elsif c.rules ? 'qualification' then
      v_list:=public.sim_qualification_list(p_season,c.id);
      insert into public.season_participants(season_id,competition_id,club_id,origin)
       select p_season,c.id,x,'league' from unnest(v_list) x;
    elsif v_entry is not null then
      for v_lg in select key as comp, value #>> '{}' as phase from jsonb_each(v_entry) loop
        insert into public.season_participants (season_id, competition_id, club_id, entry_phase, origin)
        select p_season, c.id, sp.club_id, v_lg.phase, 'league'
          from public.season_participants sp
         where sp.season_id = p_season and sp.competition_id = v_lg.comp
        on conflict do nothing;
      end loop;
    else
      insert into public.season_participants (season_id, competition_id, club_id, group_label, seed, entry_phase, origin)
      select p_season, c.id, cc.club_id, cc.group_label, cc.seed, cc.entry_phase, 'reference'
        from public.sim_competition_clubs cc where cc.competition_id = c.id
      on conflict do nothing;
    end if;
    get diagnostics v_i = row_count;
    v_n := v_n + v_i;
  end loop;

  -- As vagas nacionais são preenchidas pela tabela FINAL da própria carreira.
  select old.id into v_previous from public.career_seasons old where old.career_id=v_s.career_id and old.region=v_s.region
    and old.season_no<v_s.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;
  for c in select * from public.sim_competitions where region=v_s.region and active and kind='continental' loop
    v_from:=c.rules#>>'{qualification,from}';
    v_count:=(c.rules#>>'{qualification,slots}')::int;
    if v_count is null or v_count<1 then raise exception 'Vagas não configuradas: %',c.id;end if;
    v_q:=public.sim_qualification_list(p_season,c.id);
    if cardinality(v_q)<>v_count then raise exception 'Lista regional incoerente em %',c.id;end if;
    insert into public.season_participants(season_id,competition_id,club_id,origin)
      select p_season,c.id,x,case when v_previous is null then 'reference' else 'qualified' end from unnest(v_q) x;
    insert into public.season_participants(season_id,competition_id,club_id,origin)
      select p_season,c.id,cc.club_id,'reference' from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
      where cc.competition_id=c.id and cl.region is distinct from v_s.region;
    if (select count(*) from public.season_participants where season_id=p_season and competition_id=c.id)
       <> (select count(*) from public.sim_competition_clubs where competition_id=c.id) then
      raise exception 'Quantidade de participantes incoerente em %',c.id;
    end if;
    perform public.sim_continental_draw(p_season,c.id);
  end loop;

  select count(*) into v_n from public.season_participants where season_id = p_season;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_initialize_finances(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 -- Nível B: notas e valores-base do catálogo só nascem quando o clube entra num mundo.
 perform public.sim_ensure_club_catalog(wc.club_id) from public.cw_world_clubs wc join public.sim_clubs c on c.id=wc.club_id
  where wc.career_id=p_career and c.lazy and c.catalog_ready_at is null;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 public.cw_commercial_income(c.id),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c where exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.club_id=c.id) on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and not exists(select 1 from public.cw_players x where x.career_id=p_career and x.player_id=p.id);
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 perform public.cw_materialize_own_contracts(p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(public.cw_salary_floor(mp.player_id),round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' and not exists(select 1 from public.cw_runtime where career_id=p_career) loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

CREATE OR REPLACE FUNCTION public.sim_refresh_ratings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
delete from public.sim_player_pos_ratings;
insert into public.sim_player_pos_ratings (player_id, pos, rating, eff)
with a as materialized (select x.player_id, to_jsonb(x) j from public.sim_player_attrs x)
select p.id, w.pos,
round(sum(w.weight * (a.j ->> w.attr)::numeric) / sum(w.weight), 2),
round(sum(w.weight * (a.j ->> w.attr)::numeric) / sum(w.weight)
* greatest(coalesce(max(f.fit), 0.5), case when w.pos = any (p.secondary_positions) then 0.97 else 0 end), 2)
from public.sim_players p
join a on a.player_id = p.id
left join public.sim_clubs lc on lc.id = p.club_id
join public.sim_role_weights w on true
left join public.sim_position_fit f on f.from_pos = p.position and f.to_pos = w.pos
where not coalesce(lc.lazy, false) or lc.catalog_ready_at is not null
group by p.id, w.pos, p.secondary_positions;
get diagnostics v_n = row_count;
return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mgr_offer_respond(p_offer uuid, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
 car public.careers;o public.season_offers;c public.mgr_coach;w public.cw_world;
 target public.career_seasons;sid uuid;spell uuid;region text;
 keep_closed boolean:=false;off_season boolean:=false;
begin
 car:=public.mgr_lock();
 select * into w from public.cw_world where career_id=car.id;
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' for update;
 if not found then raise exception 'Proposta inexistente';end if;
 if o.status='accepted' and p_accept then
  return jsonb_build_object('ok',true,'accepted',true,'club_id',o.from_club,'today',w.today,
   'off_season',(select s.status='finished' or w.today<public.cw_start(s.region,s.year) from public.career_seasons s where s.id=w.primary_season),
   'state_version',(select version from public.cw_runtime where career_id=car.id));
 end if;
 if o.status<>'pending' or o.expires_on<w.today then raise exception 'Proposta encerrada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 if p_accept then
  region:=public.cw_region(o.from_club);
  if public.cw_runtime_enabled(car.id) then
   perform public.cw_simulate_due(car.id,24);
   select * into w from public.cw_world where career_id=car.id;
   sid:=public.cw_activate_region(car.id,region);
  else
   select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id
    where ws.career_id=car.id and ws.region=region and s.status='active' order by ws.starts_on limit 1;
  end if;
  if w.needs_sync then raise exception 'Atualize os resultados do mundo antes de trocar de clube';end if;
  -- A completed current season is a valid employment context during its off-season.
  -- Keep its club, summary, results and sequence untouched; only the coach changes club.
  if sid is null then
   select s.id into sid from public.career_seasons s where s.id=w.primary_season and s.career_id=car.id
    and s.region=region and s.status='finished' and s.year=public.cw_year(region,w.today);
  end if;
  select * into target from public.career_seasons where id=sid and career_id=car.id;
  keep_closed:=coalesce(target.id=w.primary_season and target.status='finished'
   and target.region=region and target.year=public.cw_year(region,w.today),false);
  -- Moving to a country whose year is already closed prepares its next calendar,
  -- without advancing the save date or reopening that country's historical results.
  if target.status='finished' and not keep_closed and public.cw_runtime_enabled(car.id) then
   sid:=public.cw_create_region(car.id,region,greatest(target.year+1,public.cw_year(region,w.today)));
   select * into target from public.career_seasons where id=sid and career_id=car.id;
  end if;
  if sid is null or (target.status is distinct from 'active' and not keep_closed) then
   raise exception 'Atualize o calendário regional antes de assumir o clube';
  end if;
  -- Liga de fundo (nível B): só ganha partidas nesta carreira quando o técnico assume um clube dela.
  perform public.cw_attach_club_leagues(car.id,sid,o.from_club);
  off_season:=keep_closed or w.today<public.cw_start(target.region,target.year);
  if (select cash-public.cw_reserved(car.id,o.from_club) from public.cw_clubs where career_id=car.id and club_id=o.from_club)<coalesce(o.bonus_coins,0)+2*o.salary
   or greatest(0,public.cw_available_budget(car.id,o.from_club)-coalesce(o.bonus_coins,0)-2*o.salary)<coalesce(o.budget_guarantee,0) then
   raise exception 'O clube não pode sustentar os termos do contrato';
  end if;
  select * into c from public.mgr_coach where career_id=car.id;
  if c.status='employed' then perform public.mgr_end_spell(car.id,'left');end if;
  if not keep_closed then perform public.cw_promote_season(car.id,sid,o.from_club);end if;
  perform public.mgr_init_world(car.id);
  perform public.cw_initialize_finances(car.id);
  spell:=public.mgr_start_spell(car.id,o.from_club);
  update public.cw_coach set monthly_salary=o.salary,contract_until=(w.today+make_interval(years=>o.contract_years))::date,
   promised_budget=o.budget_guarantee where career_id=car.id;
  update public.cw_clubs set distress_since=case when financial_risk>=75 then w.today else distress_since end
   where career_id=car.id and club_id=o.from_club;
  insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
   values(car.id,spell,o.from_club,w.today,(w.today+make_interval(years=>o.contract_years))::date,o.salary);
  if o.bonus_coins>0 then
   perform public.cw_cash(car.id,o.from_club,-o.bonus_coins,'coach_signing',o.id::text,'Luvas do treinador');
   perform public.econ_apply(car.id,'coins',o.bonus_coins,'coach_signing',o.id::text);
  end if;
  update public.season_offers set status='accepted',responded_at=now() where id=o.id;
  update public.season_offers set status='expired',responded_at=now() where career_id=car.id and kind='coach' and status='pending';
  perform public.cw_news_add(car.id,'coach-hired:'||spell,'job',public.mgr_club_name(o.from_club)||' anuncia novo treinador',
   'Contrato por '||o.contract_years||' anos. A temporada e os resultados existentes continuam.',98,o.from_club);
 else
  update public.season_offers set status='declined',responded_at=now() where id=o.id;
 end if;
 -- Other tabs must refresh after this employment decision before preparing another advance.
 update public.cw_runtime set version=version+1 where career_id=car.id;
 return jsonb_build_object('ok',true,'accepted',p_accept,'club_id',o.from_club,'off_season',off_season,'today',w.today,
  'state_version',(select version from public.cw_runtime where career_id=car.id));
end $function$;
