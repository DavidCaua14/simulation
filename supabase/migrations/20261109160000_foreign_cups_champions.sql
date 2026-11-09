-- =====================================================================
-- COPAS NACIONAIS DAS LIGAS ESTRANGEIRAS E LIGA DOS CAMPEÕES (2026-11-09)
--
-- * 11 copas nacionais (países do jogo que têm copa em atividade): FA Cup, Copa del Rey, Coppa Italia, DFB-Pokal,
--   Coupe de France, Taça de Portugal, Copa Argentina, Copa AUF Uruguay, Copa Chile, Copa Colombia e Copa Paraguay.
--   Formato do jogo (igual à Copa do Brasil): 16 clubes (8 no Paraguai), mata-mata ida e volta e final única.
-- * Liga dos Campeões (calendário europeu): 32 clubes, 8 grupos de 4, oitavas (1º x 2º de outro grupo), quartas,
--   semifinal e final única — o mesmo motor da Libertadores.
-- * Nada é fixo: as vagas saem da tabela final da temporada anterior desta carreira (quando a liga foi jogada) ou
--   da tabela calculada da liga de fundo do ano anterior (cw_bg_table, semente da carreira). A Champions recebe
--   ENG 4, ESP 4, ITA 4, GER 4, FRA 3, POR 3 e completa com 10 clubes europeus sem liga no jogo (força + sorteio).
-- * As novas competições são de fundo (background): só nascem numa temporada quando a liga de origem está nela
--   (rules.wanted_with). Quem treina na La Liga ganha Copa del Rey e Champions; quem está no Brasil não muda nada.
-- * Valem a partir da PRÓXIMA temporada criada. Temporadas em andamento, partidas, tabelas, saldos e progresso
--   não são tocados.
-- Idempotente.
-- =====================================================================

do $$
declare
  cb  jsonb := (select rules from public.sim_competitions where id = 'copa_brasil');
  lib jsonb := (select rules from public.sim_competitions where id = 'libertadores');
  r record; ph jsonb; rules jsonb; legs int; top numeric;
begin
  if cb is null or lib is null then raise exception 'Copa do Brasil/Libertadores ausentes: modelo de regras indisponível'; end if;

  for r in select * from (values
    ('fa_cup',       'FA Cup',            'FA Cup',          'ENG', 'eng_premier',    16, '#0a1f5c', '#e30613', 'FA',  'Copa nacional', 300, 'https://en.wikipedia.org/wiki/FA_Cup'),
    ('esp_copa_rey', 'Copa del Rey',      'Copa del Rey',    'ENG', 'esp_laliga',     16, '#8b0000', '#f1bf00', 'CR',  'Copa nacional', 301, 'https://en.wikipedia.org/wiki/Copa_del_Rey'),
    ('ita_coppa',    'Coppa Italia',      'Coppa Italia',    'ENG', 'ita_seriea',     16, '#003c8f', '#c9a227', 'CI',  'Copa nacional', 302, 'https://en.wikipedia.org/wiki/Coppa_Italia'),
    ('ger_pokal',    'DFB-Pokal',         'DFB-Pokal',       'ENG', 'ger_bundesliga', 16, '#111111', '#dd0000', 'DFB', 'Copa nacional', 303, 'https://en.wikipedia.org/wiki/DFB-Pokal'),
    ('fra_coupe',    'Coupe de France',   'Coupe de France', 'ENG', 'fra_ligue1',     16, '#002395', '#ed2939', 'CF',  'Copa nacional', 304, 'https://en.wikipedia.org/wiki/Coupe_de_France'),
    ('por_taca',     'Taça de Portugal',  'Taça de Portugal','ENG', 'por_primeira',   16, '#006600', '#ff0000', 'TP',  'Copa nacional', 305, 'https://en.wikipedia.org/wiki/Ta%C3%A7a_de_Portugal'),
    ('arg_copa',     'Copa Argentina',    'Copa Argentina',  'BRA', 'arg_primera',    16, '#75aadb', '#1d2b4a', 'CA',  'Copa nacional', 310, 'https://en.wikipedia.org/wiki/Copa_Argentina'),
    ('uru_copa',     'Copa AUF Uruguay',  'Copa Uruguay',    'BRA', 'uru_primera',    16, '#5cbfeb', '#0b2a4a', 'CU',  'Copa nacional', 311, 'https://en.wikipedia.org/wiki/Copa_AUF_Uruguay'),
    ('chi_copa',     'Copa Chile',        'Copa Chile',      'BRA', 'chi_primera',    16, '#d52b1e', '#0039a6', 'CCH', 'Copa nacional', 312, 'https://en.wikipedia.org/wiki/Copa_Chile'),
    ('col_copa',     'Copa Colombia',     'Copa Colombia',   'BRA', 'col_primera',    16, '#fcd116', '#003893', 'CC',  'Copa nacional', 313, 'https://en.wikipedia.org/wiki/Copa_Colombia'),
    ('par_copa',     'Copa Paraguay',     'Copa Paraguay',   'BRA', 'par_primera',     8, '#d52b1e', '#0038a8', 'CP',  'Copa nacional', 314, 'https://en.wikipedia.org/wiki/Copa_Paraguay')
  ) v(id, name, short, region, league, slots, c1, c2, code, kicker, sort, src) loop
    if not exists (select 1 from public.sim_competitions where id = r.league) then raise exception 'Liga de origem ausente: %', r.league; end if;
    if (select count(*) from public.sim_competition_clubs where competition_id = r.league) < r.slots then
      raise exception 'Liga % tem menos de % clubes', r.league, r.slots;
    end if;
    -- fases da Copa do Brasil; com 8 clubes começa nas quartas. Sorteio livre em todas as fases (sem chave de referência).
    select jsonb_agg((e - 'pairing') || jsonb_build_object('pairing', jsonb_build_object('mode', 'draw')) order by o) into ph
      from jsonb_array_elements(cb -> 'phases') with ordinality x(e, o) where r.slots = 16 or o > 1;
    select sum(coalesce((e ->> 'legs')::int, 1)) into legs from jsonb_array_elements(ph) e;
    select percentile_cont(0.8) within group (order by c.strength) into top
      from public.sim_competition_clubs cc join public.sim_clubs c on c.id = cc.club_id where cc.competition_id = r.league;
    rules := (cb - 'qualification' - 'cup_objectives') || jsonb_build_object(
      'phases', ph, 'start_stage', ph -> 0 ->> 'id', 'calendar_rounds', legs, 'calendar_priority', 2,
      'qualification', jsonb_build_object('sources', jsonb_build_array(jsonb_build_object('from', r.league, 'slots', r.slots)), 'total', r.slots),
      'wanted_with', jsonb_build_array(r.league),
      'cup_objectives', jsonb_build_array(
        jsonb_build_object('label', r.short || ': chegar à semifinal', 'target', 4, 'priority', 2, 'min_strength', round(top)),
        jsonb_build_object('label', r.short || ': chegar às quartas', 'target', 3, 'priority', 1, 'min_strength', 0)));
    insert into public.sim_competitions (id, name, short_name, sort_order, xp_mult, rules, region, kind, division, ref_season, sources, theme, active, background)
    values (r.id, r.name, r.short, r.sort, 1.15, rules, r.region, 'cup', null, '2026', jsonb_build_array(r.src),
            jsonb_build_object('c1', r.c1, 'c2', r.c2, 'code', r.code, 'kicker', r.kicker), true, true)
    on conflict (id) do update set name = excluded.name, short_name = excluded.short_name, sort_order = excluded.sort_order,
      xp_mult = excluded.xp_mult, rules = excluded.rules, region = excluded.region, kind = excluded.kind, theme = excluded.theme,
      sources = excluded.sources, active = true, background = true;
  end loop;

  -- LIGA DOS CAMPEÕES
  rules := (lib - 'qualification' - 'cup_objectives') || jsonb_build_object(
    'calendar_priority', 1,
    'qualification', jsonb_build_object(
      'sources', jsonb_build_array(
        jsonb_build_object('from', 'eng_premier', 'slots', 4), jsonb_build_object('from', 'esp_laliga', 'slots', 4),
        jsonb_build_object('from', 'ita_seriea', 'slots', 4),  jsonb_build_object('from', 'ger_bundesliga', 'slots', 4),
        jsonb_build_object('from', 'fra_ligue1', 'slots', 3),  jsonb_build_object('from', 'por_primeira', 'slots', 3)),
      'total', 32,
      'fill', jsonb_build_array('club-brugge', 'psv', 'feyenoord', 'bodo-glimt', 'fenerbahce', 'shakhtar', 'galatasaray',
                                'slavia-praha', 'slovan-bratislava', 'aek', 'lask', 'viking', 'sabah')),
    'wanted_with', jsonb_build_array('eng_premier', 'esp_laliga', 'ita_seriea', 'ger_bundesliga', 'fra_ligue1', 'por_primeira'),
    'cup_objectives', jsonb_build_array(
      jsonb_build_object('label', 'Champions: chegar à semifinal', 'target', 4, 'priority', 2, 'min_strength', 85),
      jsonb_build_object('label', 'Champions: passar da fase de grupos', 'target', 2, 'priority', 2, 'min_strength', 0)));
  if (select count(*) from public.sim_clubs where id in (select jsonb_array_elements_text(rules #> '{qualification,fill}'))) < 10 then
    raise exception 'Clubes europeus de complemento ausentes';
  end if;
  insert into public.sim_competitions (id, name, short_name, sort_order, xp_mult, rules, region, kind, division, ref_season, sources, theme, active, background)
  values ('ucl', 'Liga dos Campeões da UEFA', 'Champions League', 40, 1.4, rules, 'ENG', 'continental', null, '2026',
          '["https://en.wikipedia.org/wiki/UEFA_Champions_League"]'::jsonb,
          '{"c1":"#0b1a4a","c2":"#c9d3e6","code":"UCL","kicker":"Continental"}'::jsonb, true, true)
  on conflict (id) do update set name = excluded.name, short_name = excluded.short_name, sort_order = excluded.sort_order,
    xp_mult = excluded.xp_mult, rules = excluded.rules, region = excluded.region, kind = excluded.kind, theme = excluded.theme,
    sources = excluded.sources, active = true, background = true;
end $$;

-- ---------------------------------------------------------------------
-- FUNÇÕES (versões atuais do banco com os ajustes marcados nos comentários)
-- ---------------------------------------------------------------------
-- Catálogo dos clubes europeus que podem entrar na Champions (lazy): notas e valores-base gravados uma vez agora,
-- para a criação da temporada não pagar esse custo (~7 s) no clique do jogador. Só dado compartilhado do catálogo.
select count(*) from (
  select public.sim_ensure_club_catalog(c.id) from public.sim_clubs c
  where c.lazy and c.catalog_ready_at is null
    and c.id in (select cc.club_id from public.sim_competition_clubs cc
                  where cc.competition_id in ('eng_premier','esp_laliga','ita_seriea','ger_bundesliga','fra_ligue1','por_primeira'))) x;



CREATE OR REPLACE FUNCTION public.cw_comp_wanted(p_season uuid, p_comp text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select not co.background
  or exists(select 1 from public.season_competitions sc where sc.season_id=p_season and sc.competition_id=co.id)
  or exists(select 1 from public.career_seasons s join public.mgr_coach mc on mc.career_id=s.career_id and mc.status='employed'
            join public.sim_competition_clubs cc on cc.club_id=mc.club_id and cc.competition_id=co.id where s.id=p_season)
  -- clube que o técnico está assumindo nesta transação (mgr_offer_respond)
  or exists(select 1 from public.sim_competition_clubs cc where cc.competition_id=co.id and cc.club_id=nullif(current_setting('cw.incoming_club',true),''))
  -- copas nacionais e Liga dos Campeões: entram quando alguma liga de origem (rules.wanted_with) entra na temporada
  or exists(select 1 from jsonb_array_elements_text(coalesce(co.rules->'wanted_with','[]'::jsonb)) w(comp) where public.cw_comp_wanted(p_season,w.comp))
 from public.sim_competitions co where co.id=p_comp
$function$;

CREATE OR REPLACE FUNCTION public.sim_qualification_list(p_season uuid, p_comp text)
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.career_seasons;co public.sim_competitions;previous uuid;source text;slots int;clubs text[];
 src jsonb;part text[];need int;on_date date;seed text;
begin
 select * into s from public.career_seasons where id=p_season;
 select * into co from public.sim_competitions where id=p_comp;
 -- Vagas por várias ligas (Liga dos Campeões, copas das ligas estrangeiras). Cada liga usa a tabela FINAL da
 -- temporada anterior desta carreira quando ela foi disputada; senão, a tabela calculada da liga de fundo do ano
 -- anterior (cw_bg_table: mesma semente da carreira, muda a cada ano). "fill" completa com clubes sem liga no jogo,
 -- sorteados por força + semente da carreira e do ano.
 if co.rules #> '{qualification,sources}' is not null then
  select old.id into previous from public.career_seasons old where old.career_id=s.career_id and old.region=s.region and old.season_no<s.season_no
   and old.year=s.year-1
   and (old.status='finished' or (old.status='archived' and not exists(select 1 from public.season_fixtures f where f.season_id=old.id and f.status='pending'))) order by old.season_no desc limit 1;
  -- temporada anterior incompleta (não deveria acontecer): usa a tabela calculada
  if previous is not null and exists(select 1 from public.season_fixtures f where f.season_id=previous and f.status='pending') then previous:=null;end if;
  if previous is not null then perform public.sim_record_final_tables(previous);end if;
  on_date:=public.cw_start(s.region,s.year)-1;
  clubs:='{}';
  for src in select * from jsonb_array_elements(co.rules#>'{qualification,sources}') loop
   slots:=(src->>'slots')::int;part:=null;
   if previous is not null then
    select array_agg(t->>'club_id' order by(t->>'pos')::int) into part from public.season_final_tables ft
     cross join lateral jsonb_array_elements(ft.standings) t where ft.season_id=previous and ft.competition_id=src->>'from' and(t->>'pos')::int<=slots;
   end if;
   if coalesce(cardinality(part),0)<>slots then
    select array_agg(b.club_id order by b.pos) into part from public.cw_bg_table(s.career_id,src->>'from',on_date) b where b.pos<=slots;
   end if;
   if coalesce(cardinality(part),0)<>slots then raise exception 'Sem classificação suficiente em % para %',src->>'from',p_comp;end if;
   clubs:=clubs||part;
  end loop;
  need:=coalesce((co.rules#>>'{qualification,total}')::int,cardinality(clubs));
  if need>cardinality(clubs) then
   select coalesce(rt.seed::text,s.career_id::text) into seed from public.career_seasons x left join public.cw_runtime rt on rt.career_id=x.career_id where x.id=p_season;
   clubs:=clubs||coalesce((select array_agg(f.id order by f.score desc,f.id) from (
     select c.id,c.strength+abs(hashtext(seed||':'||s.year||':'||c.id))%9 as score from public.sim_clubs c
      where c.id in(select jsonb_array_elements_text(co.rules#>'{qualification,fill}')) and not c.id=any(clubs)
      order by 2 desc,1 limit need-cardinality(clubs)) f),'{}');
  end if;
  if cardinality(clubs)<>need then raise exception 'Sem classificação suficiente para % (% vagas)',p_comp,need;end if;
  return clubs;
 end if;
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
end $function$;

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
  for c in select * from public.sim_competitions where region = v_s.region and active and kind = 'cup' and public.cw_comp_wanted(p_season, id) order by sort_order loop
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
  for c in select * from public.sim_competitions where region=v_s.region and active and kind='continental' and public.cw_comp_wanted(p_season,id) loop
    -- Liga dos Campeões: vagas por liga (sim_qualification_list com "sources"); clubes de fora entram no mundo da carreira
    if c.rules #> '{qualification,sources}' is not null then
      v_q:=public.sim_qualification_list(p_season,c.id);
      insert into public.season_participants(season_id,competition_id,club_id,origin)
        select p_season,c.id,x,case when x in(select jsonb_array_elements_text(c.rules#>'{qualification,fill}')) then 'reference' else 'qualified' end from unnest(v_q) x;
      if public.cw_is_hybrid(v_s.career_id) then
        insert into public.cw_world_clubs(career_id,club_id) select v_s.career_id,x from unnest(v_q) x on conflict do nothing;
        if found and exists(select 1 from public.cw_world where career_id=v_s.career_id) then perform public.cw_initialize_finances(v_s.career_id);end if;
      else
        perform public.cw_materialize_club(v_s.career_id,x) from unnest(v_q) x;
      end if;
      perform public.sim_continental_draw(p_season,c.id);
      continue;
    end if;
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

CREATE OR REPLACE FUNCTION public.season_hub()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_c     public.careers;
  v_st    public.career_stats;
  v_s     public.career_seasons;
  v_sc    public.season_competitions;
  v_nf    public.season_fixtures;
  r       record;
  v_total int;
  v_played int;
  v_pending int;
  v_status text;
  v_grp   text;
  v_pos   int;
  v_pts   int;
  v_pl    int;
  v_item  jsonb;
  v_comps jsonb := '[]'::jsonb;
  v_offers jsonb;
  v_hist  jsonb;
  v_ev    record;
  v_next  jsonb := null;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is null then raise exception 'Escolha um clube antes de jogar temporadas.'; end if;

  insert into public.career_stats (career_id) values (v_c.id) on conflict do nothing;
  select * into v_st from public.career_stats where career_id = v_c.id;

  select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  if v_s.id is null then
    perform public.sim_create_season(v_c.id);
    select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  end if;

  for r in select id, name, short_name, kind from public.sim_competitions order by sort_order loop
    select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = r.id;

    select count(*), count(*) filter (where status = 'played'), count(*) filter (where status = 'pending')
      into v_total, v_played, v_pending
      from public.season_fixtures
     where season_id = v_s.id and competition_id = r.id and (home_club = v_s.club_id or away_club = v_s.club_id);

    v_status := case when v_sc.status = 'finished' then 'finished'
                     when v_total = 0 then 'not_in'
                     when v_pending = 0 then 'out'
                     else 'active' end;

    v_item := jsonb_build_object(
      'id', r.id, 'name', r.name, 'short_name', r.short_name, 'status', v_status, 'stage', v_sc.stage,
      'played', v_played, 'total', v_total,
      'champion', v_sc.champion_club, 'runner_up', v_sc.runner_up_club,
      'player_result', v_sc.player_result, 'bonus_xp', v_sc.player_bonus_xp, 'bonus_coins', v_sc.player_bonus_coins);

    if v_status = 'active' then
      select * into v_nf from public.season_fixtures
       where season_id = v_s.id and competition_id = r.id and status = 'pending'
         and (home_club = v_s.club_id or away_club = v_s.club_id)
       order by round_no, id limit 1;
      v_item := v_item || jsonb_build_object('next', jsonb_build_object(
        'home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
        'leg', v_nf.leg, 'group', v_nf.group_label,
        'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end,
        'neutral', (v_nf.stage = 'final')));
    end if;

    -- posição na tabela (Brasileirão e fase de grupos da Libertadores)
    if v_total > 0 and r.kind <> 'cup' then
      v_grp := null;
      if r.kind = 'continental' then
        select group_label into v_grp from public.season_fixtures
         where season_id = v_s.id and competition_id = r.id and stage = 'group'
           and (home_club = v_s.club_id or away_club = v_s.club_id) limit 1;
      end if;
      select t.pos, t.points, t.played into v_pos, v_pts, v_pl
        from public.sim_standings(v_s.id, r.id, v_grp) t where t.club_id = v_s.club_id;
      v_item := v_item || jsonb_build_object('table', jsonb_build_object('group', v_grp, 'pos', v_pos, 'points', v_pts, 'played', v_pl));
    end if;

    v_comps := v_comps || jsonb_build_array(v_item);
  end loop;

  -- o que vem agora no calendário: uma partida do seu clube ("mine") ou rodadas de outros campeonatos ("free")
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
    if found then
      if v_ev.o_kind = 'mine' then
        select * into v_nf from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and status = 'pending'
           and (home_club = v_s.club_id or away_club = v_s.club_id)
         order by round_no, id limit 1;
        v_next := jsonb_build_object('kind', 'mine', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round,
          'match', jsonb_build_object('home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
            'leg', v_nf.leg, 'group', v_nf.group_label,
            'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end, 'neutral', (v_nf.stage = 'final')));
      else
        select count(*) into v_total from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and stage = v_ev.o_stage and round_no = v_ev.o_round;
        v_next := jsonb_build_object('kind', 'free', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round, 'matches', v_total);
      end if;
    end if;
  end if;

  select coalesce(jsonb_agg(x.j order by x.ts desc), '[]'::jsonb) into v_hist from (
    select jsonb_build_object('id', h.id, 'club_id', h.from_club, 'status', h.status, 'bonus_coins', h.bonus_coins) as j,
           coalesce(h.responded_at, h.created_at) as ts
      from public.season_offers h
     where h.career_id = v_c.id and h.status <> 'pending' and h.season_id is not null
     order by 2 desc limit 8) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch, 'created_at', o.created_at, 'expires_at', o.expires_at)
         order by o.created_at desc), '[]'::jsonb)
    into v_offers from public.season_offers o where o.career_id = v_c.id and o.status = 'pending';

  return jsonb_build_object(
    'career', jsonb_build_object(
      'id', v_c.id, 'nickname', v_c.nickname, 'position', v_c.position, 'level', v_c.level, 'xp', v_c.xp,
      'coins', v_c.coins, 'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy,
      'next_reset_at', v_c.energy_reset_at + interval '5 hours', 'club_id', v_c.club_id),
    'stats', to_jsonb(v_st) - 'career_id',
    'season', to_jsonb(v_s) - 'career_id',
    'competitions', v_comps,
    'next_event', v_next,
    'offers', v_offers,
    'offer_history', v_hist);
end;
$function$;

CREATE OR REPLACE FUNCTION public.career_world_leagues()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;
begin
 car:=public.cw_read_career();
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',co.id,'name',co.name,'short',co.short_name,'kind',co.kind,'region',co.region,'background',co.background,
   'theme',co.theme,'zones',co.rules->'zones',
   'country',(select c.country from public.sim_competition_clubs cc join public.sim_clubs c on c.id=cc.club_id
     where cc.competition_id=co.id group by c.country order by count(*) desc,c.country limit 1),
   'clubs',(select count(*) from public.sim_competition_clubs cc where cc.competition_id=co.id),
   'in_season',exists(select 1 from public.season_competitions sc join public.career_seasons s on s.id=sc.season_id
     where s.career_id=car.id and s.status='active' and sc.competition_id=co.id))
   order by co.background,co.sort_order)
  from public.sim_competitions co where co.active and (co.kind='league' or not co.background)),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.cw_attach_league(p_career uuid, p_season uuid, p_comp text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare co public.sim_competitions;ph jsonb;s public.cw_seasons;w public.cw_world;seed text;n int:=0;r record;step int;g int[];
begin
 select * into co from public.sim_competitions where id=p_comp;
 if co.id is null or not co.background or not co.active or co.kind<>'league' then return 0;end if;
 select * into s from public.cw_seasons where season_id=p_season and career_id=p_career;
 if s.season_id is null then raise exception 'Temporada sem calendário regional';end if;
 if s.region<>co.region then raise exception 'Liga % fora do calendário %',p_comp,s.region;end if;
 select * into w from public.cw_world where career_id=p_career;
 -- Clubes da liga no mundo da carreira (idempotente), mesmo quando a liga já nasceu com a temporada.
 if public.cw_is_hybrid(p_career) then
  -- Todos os clubes da liga entram no mundo de uma vez; finanças e contratos numa chamada só.
  insert into public.cw_world_clubs(career_id,club_id) select p_career,cc.club_id from public.sim_competition_clubs cc where cc.competition_id=p_comp
  on conflict do nothing;
  get diagnostics n=row_count;
  if n>0 or exists(select 1 from public.sim_competition_clubs cc where cc.competition_id=p_comp
    and not exists(select 1 from public.cw_clubs c where c.career_id=p_career and c.club_id=cc.club_id)) then
   perform public.cw_initialize_finances(p_career);
  end if;
  n:=0;
 else
  for r in select cc.club_id from public.sim_competition_clubs cc where cc.competition_id=p_comp order by cc.club_id loop
   perform public.cw_materialize_club(p_career,r.club_id);
  end loop;
 end if;
 if exists(select 1 from public.season_competitions where season_id=p_season and competition_id=p_comp) then return 0;end if;
 insert into public.season_participants(season_id,competition_id,club_id,division_key,origin)
  select p_season,p_comp,cc.club_id,co.region||':league','reference' from public.sim_competition_clubs cc where cc.competition_id=p_comp
  on conflict do nothing;
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
end $function$;

