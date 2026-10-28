-- EVOLUÇÃO 17: tabelas finais e sorteios individuais com classificação esportiva.
begin;

create table if not exists public.season_final_tables (
 season_id uuid not null references public.career_seasons(id) on delete cascade,
 competition_id text not null references public.sim_competitions(id),
 standings jsonb not null check(jsonb_typeof(standings)='array'),
 recorded_at timestamptz not null default now(), primary key(season_id,competition_id)
);
alter table public.season_final_tables enable row level security;
revoke all on public.season_final_tables from public,anon,authenticated;
grant select on public.season_final_tables to authenticated;
drop policy if exists own_final_tables on public.season_final_tables;
create policy own_final_tables on public.season_final_tables for select to authenticated using
 (exists(select 1 from public.career_seasons s join public.careers c on c.id=s.career_id where s.id=season_id and c.user_id=auth.uid()));

-- Mantém as vagas do formato já modelado: 6 brasileiras / 5 inglesas.
-- Não inventa fases preliminares ou ligas que o jogo ainda não simula.
update public.sim_competitions set rules=jsonb_set(rules,'{qualification,slots}',to_jsonb(
 (select count(*)::int from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
  where cc.competition_id=sim_competitions.id and cl.region=sim_competitions.region)))
 where kind='continental' and rules ? 'qualification' and not rules->'qualification' ? 'slots';

create or replace function public.sim_record_final_tables(p_season uuid)
returns void language plpgsql security definer set search_path=public as $$
declare c record; data jsonb;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 if not found then raise exception 'Temporada inexistente'; end if;
 if exists(select 1 from public.season_fixtures where season_id=p_season and status<>'played') then raise exception 'Temporada ainda tem jogos pendentes'; end if;
 for c in select sc.competition_id from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
    where sc.season_id=p_season and co.kind='league' loop
  select jsonb_agg(to_jsonb(t) order by t.pos) into data from public.sim_standings(p_season,c.competition_id,null) t;
  if data is null then raise exception 'Liga sem classificação final: %',c.competition_id; end if;
  insert into public.season_final_tables values(p_season,c.competition_id,data,now()) on conflict do nothing;
 end loop;
end $$;


-- A Copa do Brasil é modelada a partir das oitavas (16 vagas). Na continuidade
-- as vagas vêm da liga anterior; fases estaduais/preliminares não são simuladas.
update public.sim_competitions set rules=jsonb_set(jsonb_set(rules,'{qualification}',jsonb_build_object(
 'from','brasileirao','region','BRA','slots',(select count(*) from public.sim_competition_clubs where competition_id='copa_brasil'))),
 '{phases,0,pairing,mode}','"draw"'::jsonb) where id='copa_brasil';
update public.sim_competitions set rules=jsonb_set(rules,'{phases,0,pairing,first_season}','"reference"'::jsonb) where id='copa_brasil';

-- Única leitura de vagas esportivas para copas nacionais e continentais.
create or replace function public.sim_qualification_list(p_season uuid,p_comp text)
returns text[] language plpgsql security definer set search_path=public as $$
declare s public.career_seasons;co public.sim_competitions;previous uuid;source text;slots int;clubs text[];
begin
 select * into s from public.career_seasons where id=p_season;
 select * into co from public.sim_competitions where id=p_comp;
 source:=co.rules#>>'{qualification,from}';slots:=(co.rules#>>'{qualification,slots}')::int;
 if source is null or slots is null or slots<1 then raise exception 'Critério de classificação ausente em %',p_comp;end if;
 select old.id into previous from public.career_seasons old where old.career_id=s.career_id and old.region=s.region and old.season_no<s.season_no
  and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;
 if previous is null then
  select array_agg(cc.club_id order by cc.club_id) into clubs from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id
   where cc.competition_id=p_comp and (co.kind<>'continental' or cl.region=s.region);
 else
  perform public.sim_record_final_tables(previous);
  select array_agg(t->>'club_id' order by(t->>'pos')::int) into clubs from public.season_final_tables ft
   cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=previous and ft.competition_id=source and(t->>'pos')::int<=slots;
 end if;
 if coalesce(cardinality(clubs),0)<>slots then raise exception 'Sem classificação suficiente para % (% vagas)',p_comp,slots;end if;
 return clubs;
end $$;

-- Uma tabela final é um retrato histórico, não é recalculada quando o regulamento muda.
create or replace function public.sim_keep_final_table()
returns trigger language plpgsql as $$ begin raise exception 'Classificação final é imutável'; end $$;
drop trigger if exists sim_keep_final_table_trg on public.season_final_tables;
create trigger sim_keep_final_table_trg before update on public.season_final_tables for each row execute function public.sim_keep_final_table();

create or replace function public.sim_season_transition(p_season uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_s      public.career_seasons;
  v_prev   jsonb;
  r        record;
  c        record;
  v_upper  text[];
  v_lower  text[];
  v_down   text[];
  v_up     text[];
  v_po     text[];
  v_n      int;
  v_res    jsonb := jsonb_build_object('leagues', '{}'::jsonb, 'promoted', '{}'::jsonb, 'relegated', '{}'::jsonb, 'qualified', '{}'::jsonb);
  v_q      text[];
  v_from   text;
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  perform public.sim_record_final_tables(p_season);
  select result into v_prev from public.season_transitions where from_season = p_season;
  if found then return v_prev; end if;                         -- já aplicado: não roda de novo
  if exists (select 1 from public.season_fixtures where season_id = p_season and status = 'pending') then
    raise exception 'A temporada ainda tem jogos pendentes.';
  end if;

  -- ligas que não mudam (sem regra): ficam como estão
  for c in select sp.competition_id as comp, array_agg(sp.club_id order by sp.club_id) as clubs
             from public.season_participants sp join public.sim_competitions sc on sc.id = sp.competition_id
            where sp.season_id = p_season and sc.kind = 'league' group by sp.competition_id loop
    v_res := jsonb_set(v_res, array['leagues', c.comp], to_jsonb(c.clubs));
  end loop;

  for r in select * from public.sim_promotion_rules_for(v_s.region, v_s.year) loop
    -- só aplica se as DUAS divisões foram disputadas nesta temporada (temporadas antigas não tinham Série B)
    continue when not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.upper_comp)
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = r.lower_comp);
    select array_agg(club_id order by club_id) into v_upper from public.season_participants where season_id = p_season and competition_id = r.upper_comp;
    select array_agg(club_id order by club_id) into v_lower from public.season_participants where season_id = p_season and competition_id = r.lower_comp;
    select count(*) into v_n from public.sim_standings(p_season, r.upper_comp, null);
    select array_agg(t.club_id order by t.pos) into v_down from public.sim_standings(p_season, r.upper_comp, null) t
     where t.pos > v_n - r.relegated;
    select array_agg(t.club_id order by t.pos) into v_up from public.sim_standings(p_season, r.lower_comp, null) t
     where t.pos <= r.promoted_direct;
    v_po := '{}';
    if r.promoted_playoff_phase is not null then
      select array_agg(f.tie_winner order by f.tie_no) into v_po from public.season_fixtures f
       where f.season_id = p_season and f.competition_id = r.lower_comp and f.stage = r.promoted_playoff_phase and f.tie_winner is not null;
      v_up := coalesce(v_up, '{}') || coalesce(v_po, '{}');
    end if;
    v_down := coalesce(v_down, '{}');
    v_up := coalesce(v_up, '{}');
    if cardinality(v_up) <> cardinality(v_down) then
      raise exception 'Acesso/rebaixamento desequilibrado em % / %: sobem %, caem %', r.upper_comp, r.lower_comp, cardinality(v_up), cardinality(v_down);
    end if;
    if exists (select 1 from unnest(v_up) u where u = any (v_down)) then raise exception 'Clube sobe e cai ao mesmo tempo'; end if;
    v_res := jsonb_set(v_res, array['leagues', r.upper_comp],
               to_jsonb(array(select x from unnest(v_upper) x where not x = any (v_down) union select unnest(v_up) order by 1)));
    v_res := jsonb_set(v_res, array['leagues', r.lower_comp],
               to_jsonb(array(select x from unnest(v_lower) x where not x = any (v_up) union select unnest(v_down) order by 1)));
    v_res := jsonb_set(v_res, array['promoted', r.upper_comp], to_jsonb(v_up));
    v_res := jsonb_set(v_res, array['relegated', r.lower_comp], to_jsonb(v_down));
  end loop;

  -- classificação continental: as vagas do país vão para os mais bem colocados da liga
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'continental' loop
    v_from := c.rules #>> '{qualification,from}';
    continue when v_from is null
               or not exists (select 1 from public.season_competitions where season_id = p_season and competition_id = v_from);
    v_n:=(c.rules#>>'{qualification,slots}')::int;
    if v_n is null or v_n<1 then raise exception 'Vagas continentais não configuradas: %',c.id;end if;
    select array_agg(t->>'club_id' order by (t->>'pos')::int) into v_q from public.season_final_tables ft cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=p_season and ft.competition_id=v_from and (t->>'pos')::int<=v_n;
    if cardinality(v_q)<>v_n then raise exception 'Classificação incompleta para %',c.id;end if;
    v_res := jsonb_set(v_res, array['qualified', c.id], to_jsonb(coalesce(v_q, '{}')));
  end loop;

  insert into public.season_transitions (career_id, region, from_season, year, result)
  values (v_s.career_id, v_s.region, p_season, v_s.year, v_res)
  on conflict (from_season) do nothing;
  return (select result from public.season_transitions where from_season = p_season);
end;
$$;
create or replace function public.sim_participants_build(p_season uuid)
returns int language plpgsql security definer set search_path = public as $$
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
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'league' order by sort_order loop
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
$$;
create or replace function public.sim_create_season(p_career uuid, p_region text)
returns uuid language plpgsql security definer set search_path = public as $$
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

  for c in select * from public.sim_competitions where region = p_region and active order by sort_order loop
    v_ph := public.sim_phase_at(c.id, 1);
    if v_ph is null then raise exception 'Competição sem fases: %', c.id; end if;
    insert into public.season_competitions (season_id, competition_id, stage) values (v_id, c.id, v_ph ->> 'id');
    perform public.sim_phase_create(v_id, c.id, v_ph ->> 'id', null);
  end loop;

  insert into public.career_stats (career_id) values (p_career) on conflict do nothing;
  return v_id;
end;
$$;
create or replace function public.sim_phase_create(p_season uuid, p_comp text, p_phase_id text, p_winners text[])
returns int language plpgsql security definer set search_path = public as $$
declare
  v_ph    jsonb := public.sim_phase(p_comp, p_phase_id);
  v_type  text;
  v_legs  int;
  v_teams text[];
  v_g     record;
  r       record;
  v_n     int := 0;
begin
  perform 1 from public.career_seasons where id=p_season for update;
  if not found then raise exception 'Temporada inexistente';end if;
  if v_ph is null then raise exception 'Fase % não existe em %', p_phase_id, p_comp; end if;
  if exists (select 1 from public.season_fixtures where season_id = p_season and competition_id = p_comp and stage = p_phase_id) then
    return 0;                                                    -- já criada (idempotente)
  end if;
  v_type := v_ph ->> 'type';
  v_legs := coalesce((v_ph ->> 'legs')::int, 1);

  if v_type = 'league' then
    select array_agg(club_id order by random()) into v_teams
      from public.season_participants where season_id = p_season and competition_id = p_comp
       and (entry_phase is null or entry_phase = p_phase_id);
    if coalesce(array_length(v_teams, 1), 0) < 2 or array_length(v_teams, 1) % 2 = 1 then
      raise exception 'Liga % precisa de número par de clubes (tem %)', p_comp, coalesce(array_length(v_teams, 1), 0);
    end if;
    insert into public.season_fixtures (season_id, competition_id, stage, round_no, home_club, away_club)
    select p_season, p_comp, p_phase_id, rr.round_no, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
    get diagnostics v_n = row_count;

  elsif v_type = 'groups' then
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      select array_agg(club_id order by random()) into v_teams
        from public.season_participants where season_id = p_season and competition_id = p_comp and group_label = v_g.group_label;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, group_label, home_club, away_club)
      select p_season, p_comp, p_phase_id, rr.round_no, v_g.group_label, rr.home, rr.away from public.sim_round_robin(v_teams, v_legs = 2) rr;
      v_n := v_n + array_length(v_teams, 1) * (array_length(v_teams, 1) - 1) / (case when v_legs = 2 then 1 else 2 end);
    end loop;

  elsif v_type = 'swiss' then
    v_n := public.sim_swiss_create(p_season, p_comp, v_ph);

  elsif v_type = 'knockout' then
    for r in select * from public.sim_phase_pairs(p_season, p_comp, v_ph, p_winners) loop
      if r.o_home is null or r.o_away is null then raise exception 'Confronto incompleto em % / %', p_comp, p_phase_id; end if;
      insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
      values (p_season, p_comp, p_phase_id, 1, r.o_tie, 1, r.o_home, r.o_away);
      v_n := v_n + 1;
      if v_legs = 2 then
        insert into public.season_fixtures (season_id, competition_id, stage, round_no, tie_no, leg, home_club, away_club)
        values (p_season, p_comp, p_phase_id, 2, r.o_tie, 2, r.o_away, r.o_home);
        v_n := v_n + 1;
      end if;
    end loop;
    if v_n = 0 then raise exception 'Fase eliminatória sem confrontos: % / %', p_comp, p_phase_id; end if;
  else
    raise exception 'Tipo de fase desconhecido: %', v_type;
  end if;
  return v_n;
end;
$$;

create or replace function public.sim_continental_draw(p_season uuid,p_comp text)
returns void language plpgsql security definer set search_path=public as $$
declare
 n int; pot_size int; previous uuid; ids text[]; assigned text[]; groups int[]; available int[]; team text;
 cty jsonb; country text; ok boolean; g int; attempt int; pot int;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 if exists(select 1 from public.season_fixtures where season_id=p_season and competition_id=p_comp) then
  raise exception 'Não é permitido refazer sorteio com calendário criado';
 end if;
 select count(*) into n from public.season_participants where season_id=p_season and competition_id=p_comp;
 if n not in(32,36) then raise exception 'Formato continental sem sorteio configurado: % clubes',n; end if;
 pot_size:=n/4;
 select old.id into previous from public.career_seasons old join public.career_seasons cur on cur.id=p_season
 where old.career_id=cur.career_id and old.region=cur.region and old.season_no<cur.season_no and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending')))
 order by old.season_no desc limit 1;
 -- UCL usa os potes de coeficiente cadastrados para ligas não simuladas.
 -- As vagas da região são ocupadas por mérito (ordem final da liga), nunca
 -- pelos nomes originais. Conserva a distribuição de associações dos potes;
 -- ordenar só por força podia colocar cinco ingleses em um pote de nove,
 -- tornando matematicamente impossível evitar confrontos nacionais.
 if n=36 then
  update public.season_participants sp set seed=cc.seed,group_label=null
   from public.sim_competition_clubs cc,public.sim_clubs cl,public.career_seasons cs
   where sp.season_id=p_season and sp.competition_id=p_comp and cc.competition_id=p_comp and cc.club_id=sp.club_id
     and cl.id=sp.club_id and cs.id=p_season and cl.region is distinct from cs.region;
  with places as (
   select cc.seed,row_number() over(order by cc.seed,cc.club_id) as rn
   from public.sim_competition_clubs cc join public.sim_clubs cl on cl.id=cc.club_id join public.career_seasons cs on cs.id=p_season
   where cc.competition_id=p_comp and cl.region=cs.region
  ), qualifiers as (
   select sp.club_id,row_number() over(order by coalesce((select (t->>'pos')::int from public.season_final_tables ft
      cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=previous
       and ft.competition_id=(select rules#>>'{qualification,from}' from public.sim_competitions where id=p_comp)
       and t->>'club_id'=sp.club_id),999),cl.strength desc,sp.club_id) as rn
   from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id join public.career_seasons cs on cs.id=p_season
   where sp.season_id=p_season and sp.competition_id=p_comp and cl.region=cs.region
  ) update public.season_participants sp set seed=places.seed,group_label=null
    from qualifiers join places using(rn) where sp.season_id=p_season and sp.competition_id=p_comp and sp.club_id=qualifiers.club_id;
  return;
 end if;
 -- Cabeças de chave: campeão continental anterior; depois força de referência +
 -- mérito recente na continental da MESMA carreira. Coeficiente é estimativa de gameplay.
 with ranked as (
  select sp.club_id,row_number() over(order by
   case when exists(select 1 from public.season_competitions sc where sc.season_id=previous and sc.competition_id=p_comp and sc.champion_club=sp.club_id) then 1 else 0 end desc,
   cl.strength+least(6,coalesce((select sum(case when (f.home_club=sp.club_id and f.home_goals>f.away_goals)
      or(f.away_club=sp.club_id and f.away_goals>f.home_goals) then 3 when f.home_goals=f.away_goals then 1 else 0 end)*0.15
      from public.season_fixtures f where f.season_id=previous and f.competition_id=p_comp and f.status='played'
       and sp.club_id in(f.home_club,f.away_club)),0)) desc,sp.club_id) as rank
   from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
   where sp.season_id=p_season and sp.competition_id=p_comp
 ) update public.season_participants sp set seed=1+(ranked.rank-1)/pot_size,group_label=null
 from ranked where sp.season_id=p_season and sp.competition_id=p_comp and sp.club_id=ranked.club_id;
 if n=36 then return; end if;
 select jsonb_object_agg(sp.club_id,cl.country) into cty from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
 where sp.season_id=p_season and sp.competition_id=p_comp;
 -- Um clube de cada pote por grupo; nenhuma associação repetida no grupo.
 for attempt in 1..500 loop
  assigned:=array_fill(null::text,array[32]);ok:=true;
  for pot in 1..4 loop
   select array_agg(club_id order by random()) into ids from public.season_participants
    where season_id=p_season and competition_id=p_comp and seed=pot;
   available:=array[1,2,3,4,5,6,7,8];
   foreach team in array ids loop
    select x into g from unnest(available) x where not exists(
      select 1 from generate_series(0,pot-2) k where cty->>assigned[k*8+x]=cty->>team)
     order by random() limit 1;
    if g is null then ok:=false;exit;end if;
    assigned[(pot-1)*8+g]:=team;available:=array_remove(available,g);
   end loop;
   exit when not ok;
  end loop;
  exit when ok;
 end loop;
 if not ok then raise exception 'Não foi possível sortear grupos respeitando as associações'; end if;
 for pot in 1..4 loop
  for g in 1..8 loop
   update public.season_participants set group_label=chr(64+g)
    where season_id=p_season and competition_id=p_comp and club_id=assigned[(pot-1)*8+g];
  end loop;
 end loop;
end $$;

create or replace function public.sim_swiss_cost(p_slots text[],p_tpl jsonb,p_cty jsonb)
returns bigint language sql immutable as $$
 with edges as (
  select (m->>1)::int+1 as a,(m->>2)::int+1 as b from jsonb_array_elements(p_tpl) m
 ), sides as(select a,b from edges union all select b,a from edges),
 countries as(select a,p_cty->>p_slots[b] as country,count(*) as n from sides group by 1,2)
 select (select count(*)*1000 from edges where p_cty->>p_slots[a]=p_cty->>p_slots[b])
       +coalesce((select sum(greatest(n-2,0))*100 from countries),0)
$$;

-- Busca por restrições sobre ASSOCIAÇÕES, não permutações de clubes equivalentes.
-- MRV + verificação antecipada: sem compatriotas; até dois rivais de cada país.
create or replace function public.sim_swiss_search(p_adj int[],p_left int[],p_assignment int[],p_neighbors int[],p_countries int,p_steps int default 0)
returns jsonb language plpgsql volatile set search_path=public as $$
declare
 slot int; country int; k int; neighbor int; pot int; domain int[]; best_domain int[]; best_slot int:=0;
 best_n int:=100;best_degree int:=-1;degree int;allowed boolean;a int[];remaining int[];neighbors int[];result jsonb;
begin
 p_steps:=p_steps+1;
 if p_steps>30000 then return jsonb_build_object('assignment',null,'steps',p_steps);end if;
 for slot in 1..36 loop
  continue when p_assignment[slot]<>0;
  pot:=(slot-1)/9;domain:='{}';degree:=0;
  for k in 1..8 loop
   if p_assignment[p_adj[(slot-1)*8+k]]<>0 then degree:=degree+1;end if;
  end loop;
  for country in 1..p_countries loop
   continue when p_left[pot*p_countries+country]=0 or p_neighbors[(slot-1)*p_countries+country]>0;
   allowed:=true;
   for k in 1..8 loop
    neighbor:=p_adj[(slot-1)*8+k];
    if p_neighbors[(neighbor-1)*p_countries+country]>=2 then allowed:=false;exit;end if;
   end loop;
   if allowed then domain:=array_append(domain,country);end if;
  end loop;
  if cardinality(domain)=0 then return jsonb_build_object('assignment',null,'steps',p_steps);end if;
  if cardinality(domain)<best_n or (cardinality(domain)=best_n and degree>best_degree) then
   best_slot:=slot;best_domain:=domain;best_n:=cardinality(domain);best_degree:=degree;
  end if;
 end loop;
 if best_slot=0 then return jsonb_build_object('assignment',to_jsonb(p_assignment),'steps',p_steps);end if;
 pot:=(best_slot-1)/9;
 select array_agg(x order by p_left[pot*p_countries+x] desc,random()) into best_domain from unnest(best_domain) x;
 foreach country in array best_domain loop
  a:=p_assignment;remaining:=p_left;neighbors:=p_neighbors;
  a[best_slot]:=country;remaining[pot*p_countries+country]:=remaining[pot*p_countries+country]-1;
  for k in 1..8 loop
   neighbor:=p_adj[(best_slot-1)*8+k];
   neighbors[(neighbor-1)*p_countries+country]:=neighbors[(neighbor-1)*p_countries+country]+1;
  end loop;
  result:=public.sim_swiss_search(p_adj,remaining,a,neighbors,p_countries,p_steps);
  p_steps:=(result->>'steps')::int;
  if jsonb_typeof(result->'assignment')='array' then return result;end if;
  exit when p_steps>30000;
 end loop;
 return jsonb_build_object('assignment',null,'steps',p_steps);
end $$;

create or replace function public.sim_swiss_create(p_season uuid,p_comp text,p_phase jsonb)
returns int language plpgsql security definer set search_path=public as $$
declare
 templates jsonb;tpl jsonb;cty jsonb;countries text[];slots text[];ids text[];adj int[];degree int[];remaining int[];colors int[];
 result jsonb;signature jsonb;certificate jsonb;pot int;c int;k int;a int;b int;v_count int;try int;m jsonb;n int:=0;nc int;
begin
 perform 1 from public.career_seasons where id=p_season for update;
 select rules->'swiss_templates' into templates from public.sim_competitions where id=p_comp;
 if coalesce(jsonb_array_length(templates),0)=0 then raise exception 'Sem modelos de calendário suíço';end if;
 if (select count(*) from public.season_participants where season_id=p_season and competition_id=p_comp)<>36 then raise exception 'Fase suíça exige 36 clubes';end if;
 select array_agg(distinct cl.country order by cl.country),jsonb_object_agg(sp.club_id,cl.country) into countries,cty
  from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id where sp.season_id=p_season and sp.competition_id=p_comp;
 nc:=cardinality(countries);remaining:=array_fill(0,array[4*nc]);
 for pot in 0..3 loop
  if (select count(*) from public.season_participants where season_id=p_season and competition_id=p_comp and seed=pot+1)<>9 then raise exception 'Pote inválido';end if;
  for c in 1..nc loop
   select count(*) into v_count from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
    where sp.season_id=p_season and sp.competition_id=p_comp and sp.seed=pot+1 and cl.country=countries[c];
   remaining[pot*nc+c]:=v_count;
  end loop;
 end loop;
 -- Primeiro utiliza uma solução previamente certificada para o perfil de países.
 -- O certificado contém somente associações por vaga, nunca clubes classificados.
 -- Os nomes são sorteados individualmente abaixo, preservando o histórico da carreira.
 with counts as(select sp.seed,cl.country,count(*) as n from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
   where sp.season_id=p_season and sp.competition_id=p_comp group by 1,2),
 pots as(select seed,jsonb_object_agg(counts.country,counts.n) as association_counts from counts group by seed)
 select jsonb_agg(pots.association_counts order by seed) into signature from pots;
 select cert into certificate from public.sim_competitions co cross join lateral jsonb_array_elements(co.rules->'swiss_certificates') cert
 where co.id=p_comp and cert->'signature'=signature order by random() limit 1;
 if certificate is not null then
  tpl:=templates->(certificate->>'template')::int;
  select array_agg(array_position(countries,x) order by o) into colors
   from jsonb_array_elements_text(certificate->'assignment') with ordinality t(x,o);
 end if;
 -- Configurações novas sem certificado ainda passam pela busca de restrições.
 -- Cada modelo é tentado uma vez, em ordem sorteada; nenhuma solução inválida é aceita.
 for try in select i from generate_series(0,jsonb_array_length(templates)-1) i order by random() loop
  exit when colors is not null;
  tpl:=templates->try;adj:=array_fill(0,array[36*8]);degree:=array_fill(0,array[36]);
  for m in select * from jsonb_array_elements(tpl) loop
   a:=(m->>1)::int+1;b:=(m->>2)::int+1;
   degree[a]:=degree[a]+1;degree[b]:=degree[b]+1;
   if a=b or a not between 1 and 36 or b not between 1 and 36 or degree[a]>8 or degree[b]>8 then raise exception 'Modelo suíço inválido';end if;
   adj[(a-1)*8+degree[a]]:=b;adj[(b-1)*8+degree[b]]:=a;
  end loop;
  if exists(select 1 from unnest(degree) x where x<>8) then raise exception 'Modelo suíço incompleto';end if;
  result:=public.sim_swiss_search(adj,remaining,array_fill(0,array[36]),array_fill(0,array[36*nc]),nc);
  if jsonb_typeof(result->'assignment')='array' then
   select array_agg(x::int order by o) into colors from jsonb_array_elements_text(result->'assignment') with ordinality t(x,o);
   exit;
  end if;
 end loop;
 if colors is null then raise exception 'Não há sorteio válido para os potes configurados. Nenhuma temporada parcial foi gravada.';end if;
 slots:=array_fill(null::text,array[36]);
 for pot in 0..3 loop
  for c in 1..nc loop
   select array_agg(sp.club_id order by random()) into ids from public.season_participants sp join public.sim_clubs cl on cl.id=sp.club_id
    where sp.season_id=p_season and sp.competition_id=p_comp and sp.seed=pot+1 and cl.country=countries[c];
   k:=0;
   for a in pot*9+1..pot*9+9 loop
    if colors[a]=c then k:=k+1;slots[a]:=ids[k];end if;
   end loop;
  end loop;
 end loop;
 if public.sim_swiss_cost(slots,tpl,cty)<>0 then raise exception 'Sorteio violou as regras de associação';end if;
 for m in select * from jsonb_array_elements(tpl) loop
  insert into public.season_fixtures(season_id,competition_id,stage,round_no,home_club,away_club)
   values(p_season,p_comp,p_phase->>'id',(m->>0)::int,slots[(m->>1)::int+1],slots[(m->>2)::int+1]);
  n:=n+1;
 end loop;
 return n;
end $$;


create or replace function public.sim_phase_pairs(p_season uuid, p_comp text, p_phase jsonb, p_winners text[])
returns table (o_tie int, o_home text, o_away text)
language plpgsql security definer set search_path = public as $$
declare
  v_mode  text := coalesce(p_phase #>> '{pairing,mode}', 'draw');
  v_legs  int  := coalesce((p_phase ->> 'legs')::int, 1);
  v_from  text := p_phase #>> '{pairing,from}';
  v_seedf text := p_phase #>> '{pairing,seed_from}';
  v_ent   text[];
  v_pos   jsonb;
  v_i     int;
  v_a     text;
  v_b     text;
  v_hi    text;
  v_lo    text;
  pr      jsonb;
  v_wc text[]; v_wg text[]; v_rc text[]; v_rg text[];
  v_perm int[];
  v_ok   boolean;
  v_try  int;
  v_g    record;
  v_s1   text[];
  v_s2   text[];
  v_w    text[];
  v_tie  int := 0;
  v_grp  int;
  v_seedpairs int[][] := array[[1,2],[7,8],[3,4],[5,6]];
begin
  -- quem entra nesta fase: vencedores da fase anterior + clubes que entram aqui (copas inglesas)
  v_ent := coalesce(p_winners, '{}') || coalesce((select array_agg(club_id order by club_id) from public.season_participants
            where season_id = p_season and competition_id = p_comp
              and (entry_phase = p_phase ->> 'id' or (entry_phase is null and (p_phase ->> 'idx')::int = 1))), '{}');

  if p_phase#>>'{pairing,first_season}'='reference' and exists(select 1 from public.season_participants where season_id=p_season and competition_id=p_comp and origin='reference' and group_label is not null) then
    v_mode:='fixed';
  end if;

  -- posição na fase de liga (quando a chave depende dela)
  if coalesce(v_from, v_seedf) is not null then
    select jsonb_object_agg(t.club_id, t.pos) into v_pos from public.sim_standings(p_season, p_comp, null) t;
  end if;

  if v_mode = 'fixed' then
    -- Copa do Brasil: confrontos de referência (T1..T8), seed 1 manda o 1º jogo
    for v_g in
      select sp.group_label, max(sp.club_id) filter (where sp.seed = 1) as c1, max(sp.club_id) filter (where sp.seed = 2) as c2
        from public.season_participants sp
       where sp.season_id = p_season and sp.competition_id = p_comp and sp.group_label is not null
       group by sp.group_label order by sp.group_label
    loop
      o_tie := coalesce(nullif(regexp_replace(v_g.group_label, '\D', '', 'g'), '')::int, v_tie + 1);
      v_tie := o_tie;
      o_home := v_g.c1; o_away := v_g.c2; return next;
    end loop;

  elsif v_mode = 'draw' then
    select array_agg(x order by random()) into v_ent from unnest(v_ent) x;
    for v_i in 1 .. coalesce(array_length(v_ent, 1), 0) / 2 loop
      o_tie := v_i; o_home := v_ent[2 * v_i - 1]; o_away := v_ent[2 * v_i]; return next;
    end loop;

  elsif v_mode = 'lib_r16' then
    -- 1º de cada grupo x 2º de OUTRO grupo; o 1º decide em casa
    for v_g in select distinct group_label from public.season_participants
                where season_id = p_season and competition_id = p_comp and group_label is not null order by 1 loop
      v_wc := coalesce(v_wc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 1);
      v_rc := coalesce(v_rc, '{}') || (select s.club_id from public.sim_standings(p_season, p_comp, v_g.group_label) s where s.pos = 2);
      v_wg := coalesce(v_wg, '{}') || v_g.group_label;
      v_rg := coalesce(v_rg, '{}') || v_g.group_label;
    end loop;
    for v_try in 1 .. 300 loop
      select array_agg(i order by random()) into v_perm from generate_series(1, array_length(v_rc, 1)) as i;
      v_ok := true;
      for v_i in 1 .. array_length(v_wc, 1) loop
        if v_rg[v_perm[v_i]] = v_wg[v_i] then v_ok := false; exit; end if;
      end loop;
      exit when v_ok;
    end loop;
    if not v_ok then raise exception 'Sorteio de oitavas sem combinação válida';end if;
    for v_i in 1 .. array_length(v_wc, 1) loop
      o_tie := v_i; o_home := v_rc[v_perm[v_i]]; o_away := v_wc[v_i]; return next;
    end loop;

  elsif v_mode = 'positions' then
    -- pares de posições da liga (ex.: Série B [[3,6],[4,5]]); o melhor colocado decide em casa
    v_i := 0;
    for pr in select * from jsonb_array_elements(p_phase #> '{pairing,pairs}') loop
      v_i := v_i + 1;
      select club_id into v_hi from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 0)::int;
      select club_id into v_lo from public.sim_standings(p_season, p_comp, null) where pos = (pr ->> 1)::int;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'champ_sf' then
    -- playoff da Championship: 3º x vencedor de pior campanha; 4º x o outro (melhor colocado decide em casa)
    select club_id into v_a from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,0}')::int;
    select club_id into v_b from public.sim_standings(p_season, p_comp, null) where pos = (p_phase #>> '{pairing,seeds,1}')::int;
    select array_agg(x order by (v_pos ->> x)::int desc) into v_w from unnest(p_winners) x;   -- pior campanha primeiro
    o_tie := 1; o_home := v_w[1]; o_away := v_a; return next;
    o_tie := 2; o_home := v_w[2]; o_away := v_b; return next;

  elsif v_mode = 'bracket' then
    -- chave fixa: vencedor do confronto k x vencedor do k+1; com seed_from, o melhor colocado decide em casa
    for v_i in 1 .. coalesce(array_length(p_winners, 1), 0) / 2 loop
      v_a := p_winners[2 * v_i - 1]; v_b := p_winners[2 * v_i];
      if v_seedf is not null and (v_pos ->> v_a)::int < (v_pos ->> v_b)::int then
        v_hi := v_a; v_lo := v_b;
      elsif v_seedf is not null then
        v_hi := v_b; v_lo := v_a;
      elsif random() < 0.5 then v_hi := v_a; v_lo := v_b;
      else v_hi := v_b; v_lo := v_a; end if;
      o_tie := v_i;
      if v_legs = 2 then o_home := v_lo; o_away := v_hi; else o_home := v_hi; o_away := v_lo; end if;
      return next;
    end loop;

  elsif v_mode = 'ucl_po' then
    -- (9º/10º x 23º/24º), (11º/12º x 21º/22º), (13º/14º x 19º/20º), (15º/16º x 17º/18º); cabeça de chave decide em casa
    for v_grp in 0 .. 3 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (9 + 2 * v_grp, 10 + 2 * v_grp);
      select array_agg(club_id order by random()) into v_s2 from public.sim_standings(p_season, p_comp, null)
       where pos in (23 - 2 * v_grp, 24 - 2 * v_grp);
      for v_i in 1 .. 2 loop
        v_tie := v_tie + 1;
        o_tie := v_tie; o_home := v_s2[v_i]; o_away := v_s1[v_i]; return next;
      end loop;
    end loop;

  elsif v_mode = 'ucl_r16' then
    -- vencedores do playoff chegam na ordem dos confrontos: 1-2 (9º/10º), 3-4 (11º/12º), 5-6 (13º/14º), 7-8 (15º/16º)
    -- 1º/2º x vencedores 7-8 · 7º/8º x vencedores 1-2 · 3º/4º x vencedores 5-6 · 5º/6º x vencedores 3-4
    -- ordem dos confrontos = chave: [1/2, 7/8, 3/4, 5/6] de um lado e os outros do outro (1º e 2º em lados opostos)
    for v_grp in 1 .. 4 loop
      select array_agg(club_id order by random()) into v_s1 from public.sim_standings(p_season, p_comp, null)
       where pos in (v_seedpairs[v_grp][1], v_seedpairs[v_grp][2]);
      v_wc := coalesce(v_wc, '{}') || v_s1;
    end loop;
    -- v_wc = [s(1/2)a, s(1/2)b, s(7/8)a, s(7/8)b, s(3/4)a, s(3/4)b, s(5/6)a, s(5/6)b]
    v_rc := array[p_winners[7], p_winners[8], p_winners[1], p_winners[2], p_winners[5], p_winners[6], p_winners[3], p_winners[4]];
    if random() < 0.5 then v_rc := array[v_rc[2], v_rc[1], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[4], v_rc[3], v_rc[5], v_rc[6], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[6], v_rc[5], v_rc[7], v_rc[8]]; end if;
    if random() < 0.5 then v_rc := array[v_rc[1], v_rc[2], v_rc[3], v_rc[4], v_rc[5], v_rc[6], v_rc[8], v_rc[7]]; end if;
    -- lado A: confrontos 1-4 ; lado B: 5-8
    o_tie := 1; o_home := v_rc[1]; o_away := v_wc[1]; return next;
    o_tie := 2; o_home := v_rc[3]; o_away := v_wc[3]; return next;
    o_tie := 3; o_home := v_rc[5]; o_away := v_wc[5]; return next;
    o_tie := 4; o_home := v_rc[7]; o_away := v_wc[7]; return next;
    o_tie := 5; o_home := v_rc[2]; o_away := v_wc[2]; return next;
    o_tie := 6; o_home := v_rc[4]; o_away := v_wc[4]; return next;
    o_tie := 7; o_home := v_rc[6]; o_away := v_wc[6]; return next;
    o_tie := 8; o_home := v_rc[8]; o_away := v_wc[8]; return next;

  else
    raise exception 'Chaveamento desconhecido: %', v_mode;
  end if;
end;
$$;

create or replace function public.sim_resolve_ties(p_season uuid, p_comp text, p_stage text)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  v_ph      jsonb := public.sim_phase(p_comp, p_stage);
  v_rule    text  := coalesce(public.sim_phase(p_comp, p_stage) ->> 'tie', 'penalties');
  v_t       record;
  v_c1      text;
  v_c2      text;
  v_g1      int;
  v_g2      int;
  v_last    bigint;
  v_lasthome text;
  v_lastwin text;
  v_w       text;
  v_wp      int;
  v_lp      int;
  v_out     text[] := '{}';
begin
  if exists(select 1 from public.season_fixtures where season_id=p_season and competition_id=p_comp and stage=p_stage and status<>'played') then raise exception 'Confronto ainda não terminou';end if;
  for v_t in
    select distinct tie_no from public.season_fixtures
    where season_id = p_season and competition_id = p_comp and stage = p_stage order by tie_no
  loop
    select home_club, away_club into v_c1, v_c2 from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no and leg = 1;
    select id, home_club, tie_winner into v_last, v_lasthome, v_lastwin from public.season_fixtures
     where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no
     order by leg desc limit 1;

    if v_lastwin is not null then
      v_w := v_lastwin;
    else
      select coalesce(sum(case when home_club = v_c1 then home_goals else away_goals end), 0),
             coalesce(sum(case when home_club = v_c2 then home_goals else away_goals end), 0)
        into v_g1, v_g2
        from public.season_fixtures
       where season_id = p_season and competition_id = p_comp and stage = p_stage and tie_no = v_t.tie_no;
      if v_g1 > v_g2 then v_w := v_c1;
      elsif v_g2 > v_g1 then v_w := v_c2;
      elsif v_rule = 'higher_seed' then
        v_w := v_lasthome;
      else
        v_w  := public.sim_pens_winner(v_c1, v_c2);
        v_wp := 3 + floor(random() * 3)::int;
        v_lp := greatest(0, v_wp - 1 - floor(random() * 2)::int);
        update public.season_fixtures
           set home_pens = case when v_lasthome = v_w then v_wp else v_lp end,
               away_pens = case when v_lasthome = v_w then v_lp else v_wp end
         where id = v_last;
      end if;
      update public.season_fixtures set tie_winner = v_w where id = v_last;
    end if;
    v_out := v_out || v_w;
  end loop;
  return v_out;
end;
$$;

-- Segurança explícita em todas as novas funções internas.
revoke all on function public.sim_continental_draw(uuid,text),public.sim_swiss_cost(text[],jsonb,jsonb),
 public.sim_swiss_search(int[],int[],int[],int[],int,int),public.sim_qualification_list(uuid,text),public.sim_record_final_tables(uuid),public.sim_keep_final_table(),public.sim_swiss_create(uuid,text,jsonb),
 public.sim_participants_build(uuid),public.sim_create_season(uuid,text),public.sim_phase_create(uuid,text,text,text[]),
 public.sim_phase_pairs(uuid,text,jsonb,text[]),public.sim_season_transition(uuid),public.sim_resolve_ties(uuid,text,text)
 from public,anon,authenticated;
commit;
