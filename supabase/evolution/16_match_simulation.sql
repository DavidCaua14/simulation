-- EVOLUÇÃO 16: motor versionado, identidade tática e disciplina contextual.
-- Partidas já iniciadas continuam no motor v1; novas partidas usam v2.
begin;
alter table public.sim_player_attrs add column if not exists aggression smallint not null default 50 check(aggression between 1 and 99);
alter table public.sim_player_attrs add column if not exists discipline smallint not null default 60 check(discipline between 1 and 99);
alter table public.mgr_ai_clubs add column if not exists style text;

-- Estimativas de gameplay configuráveis, não estatísticas oficiais dos atletas.
create or replace function public.mgr_card_chances(p_aggression numeric,p_discipline numeric,p_tack numeric,p_cond numeric,
 p_fouls int,p_booked boolean,p_tackles text,p_ref numeric,p_context numeric default 1)
returns jsonb language sql immutable as $$
 select jsonb_build_object(
 'yellow',least(0.42,greatest(0.06,0.16 * (0.65+p_aggression/100) * (1.30-p_discipline/200)
       * (1.25-p_tack/200) * (1+greatest(0,55-p_cond)/180) * (1+least(p_fouls,5)*0.04)
       * case p_tackles when 'aggressive' then 1.35 when 'cautious' then 0.70 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context * case when p_booked then 0.35 else 1 end)),
 'red',least(0.009,greatest(0.0003,0.0012 * (0.50+p_aggression/100) * (1.30-p_discipline/200)
       * case p_tackles when 'aggressive' then 2.0 when 'cautious' then 0.5 else 1 end
       * greatest(0.75,least(1.25,p_ref)) * p_context)))
$$;

-- O encaixe do elenco decide a formação; pequena preferência própria desempata
-- opções próximas. Não altera a força dos jogadores para favorecer o usuário.
create or replace function public.mgr_ai_formation(p_career uuid,p_club text)
returns text language plpgsql security definer set search_path=public as $$
declare form text; best text; score numeric; best_score numeric:=-1; lineup jsonb;
begin
 select formation into best from public.mgr_ai_clubs where career_id=p_career and club_id=p_club;
 if best is not null then return best; end if;
 for form in select id from public.sim_formations order by id loop
  lineup:=public.mgr_auto_lineup(p_career,p_club,form,null,0);
  score:=public.mgr_lineup_score(lineup,form) * (0.985 + (('x'||substr(md5(p_career::text||p_club||form),1,7))::bit(28)::int % 300)/10000.0);
  if score>best_score then best_score:=score;best:=form;end if;
 end loop;
 best:=coalesce(best,'4-3-3');
 insert into public.mgr_ai_clubs(career_id,club_id,formation) values(p_career,p_club,best) on conflict do nothing;
 return (select formation from public.mgr_ai_clubs where career_id=p_career and club_id=p_club);
end $$;

create or replace function public.mgr_ai_plan(p_career uuid,p_club text,p_diff numeric,p_home boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_style text; t jsonb; passing numeric; speed numeric; stamina numeric; heading numeric; choice int;
begin
 perform public.mgr_ai_formation(p_career,p_club);
 select c.style into v_style from public.mgr_ai_clubs c where career_id=p_career and club_id=p_club;
 if v_style is null then
  select avg(a.passing+a.vision)/2,avg(a.pace),avg(a.stamina),avg(a.heading)
    into passing,speed,stamina,heading from public.mgr_players m join public.sim_player_attrs a on a.player_id=m.player_id
    join public.sim_players p on p.id=m.player_id
    where m.career_id=p_career and m.club_id=p_club and p.position<>'GOL';
  choice:=('x'||substr(md5(p_career::text||p_club),1,7))::bit(28)::int % 5;
  v_style:=case when choice=0 and passing>=58 then 'possession' when choice=1 and stamina>=60 then 'press'
              when choice=2 and speed>=55 then 'counter' when choice=3 and heading>=55 then 'wide' else 'balanced' end;
  update public.mgr_ai_clubs set style=v_style where career_id=p_career and club_id=p_club;
 end if;
 t:=public.mgr_ai_tactics(p_diff,p_home);
 t:=t || case v_style when 'possession' then '{"build":"short","tempo":"slow","width":"center"}'::jsonb
    when 'press' then '{"pressing":"high","line":"high","tempo":"fast"}'::jsonb
    when 'counter' then '{"pressing":"low","line":"low","build":"direct","tempo":"fast"}'::jsonb
    when 'wide' then '{"width":"wide","build":"mixed","tempo":"normal"}'::jsonb else '{}'::jsonb end;
 if p_diff < -12 then t:=t||'{"mentality":-1,"line":"low"}'; end if;
 return public.mgr_tactics_clean(t);
end $$;

-- Interações dependem dos atributos do elenco, não apenas de escolher uma opção.
create or replace function public.mgr_tactical_effect(p_t jsonb,p_opp jsonb,p_skill numeric,p_pace numeric,p_stamina numeric,p_head numeric)
returns jsonb language plpgsql immutable as $$
declare ctl numeric:=1; freq numeric:=1; quality numeric:=0;
begin
 if p_t->>'build'='short' then
  ctl:=ctl+greatest(-0.10,least(0.06,(p_skill-60)/250));
  if p_opp->>'pressing'='high' then ctl:=ctl+(p_skill-65)/400; quality:=quality+(p_skill-65)/700; end if;
 elsif p_t->>'build'='direct' and p_opp->>'line'='high' then
  freq:=freq+greatest(-0.04,least(0.10,(p_pace-55)/250));quality:=quality+greatest(-0.03,least(0.06,(p_pace-60)/500));
 end if;
 if p_t->>'build'='direct' and p_opp->>'pressing'='high' then freq:=freq*1.12;quality:=quality+0.025;end if;
 if p_t->>'width'='wide' then quality:=quality+greatest(-0.05,least(0.05,(p_head-60)/400)); end if;
 if p_t->>'pressing'='high' then ctl:=ctl+greatest(-0.06,least(0.04,(p_stamina-65)/350)); end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',quality);
end $$;

create or replace function public.mgr_tactics_clean(p_t jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'mentality', greatest(-2, least(2, coalesce((p_t ->> 'mentality')::int, 0))),
    'pressing',  case when p_t ->> 'pressing' in ('low', 'medium', 'high') then p_t ->> 'pressing' else 'medium' end,
    'line',      case when p_t ->> 'line' in ('low', 'medium', 'high') then p_t ->> 'line' else 'medium' end,
    'tempo',     case when p_t ->> 'tempo' in ('slow', 'normal', 'fast') then p_t ->> 'tempo' else 'normal' end,
    'build',     case when p_t ->> 'build' in ('short', 'mixed', 'direct') then p_t ->> 'build' else 'mixed' end,
    'width',     case when p_t ->> 'width' in ('center', 'mixed', 'wide') then p_t ->> 'width' else 'mixed' end,
    'tackles', case when p_t ->> 'tackles' in ('cautious','normal','aggressive') then p_t ->> 'tackles' else 'normal' end,
    'manage',    case when p_t ->> 'manage' in ('keep', 'normal', 'push') then p_t ->> 'manage' else 'normal' end)
$$;
create or replace function public.mgr_match_create(p_fixture bigint, p_career uuid, p_user_side char, p_user_lineup jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_f     public.season_fixtures;
  v_s     public.career_seasons;
  v_rules jsonb;
  v_lh    jsonb;
  v_la    jsonb;
  v_sh    numeric;
  v_sa    numeric;
  v_th    jsonb;
  v_ta    jsonb;
  v_neut  boolean;
  v_dec   boolean;
  v_agg_h int := 0;
  v_agg_a int := 0;
  v_first public.season_fixtures;
  v_ph    jsonb;
  v_bench int;
begin
  perform 1 from public.careers where id=p_career for update;
  select * into v_f from public.season_fixtures where id=p_fixture for update;
  if not found then raise exception 'Partida inexistente'; end if;
  if not exists(select 1 from public.career_seasons where id=v_f.season_id and career_id=p_career) then raise exception 'Partida de outra carreira'; end if;
  if exists (select 1 from public.mgr_matches where fixture_id = p_fixture) then return; end if;
  if v_f.status <> 'pending' then raise exception 'Partida já disputada'; end if;
  select * into v_f from public.season_fixtures where id = p_fixture;
  select * into v_s from public.career_seasons where id = v_f.season_id;
  select rules into v_rules from public.sim_competitions where id = v_f.competition_id;
  v_ph := public.sim_phase(v_f.competition_id, v_f.stage);
  v_bench := coalesce((v_rules ->> 'bench')::int, 12);
  if v_ph is not null then
    -- configuração da fase (evolução 03): mando neutro, jogo que decide o confronto, prorrogação e critério de empate
    v_neut := coalesce((v_ph ->> 'neutral')::boolean, false);
    v_dec  := v_ph ->> 'type' = 'knockout' and (coalesce((v_ph ->> 'legs')::int, 1) = 1 or v_f.leg = 2);
  else
    v_neut := (v_f.stage = 'final');
    v_dec  := v_f.stage in ('r16', 'qf', 'sf', 'final') and (v_f.stage = 'final' or v_f.leg = 2);
  end if;
  if v_dec and coalesce(v_f.leg, 1) = 2 then
    select * into v_first from public.season_fixtures
     where season_id = v_f.season_id and competition_id = v_f.competition_id and stage = v_f.stage and tie_no = v_f.tie_no and leg = 1;
    -- placar da ida do ponto de vista dos lados deste jogo
    v_agg_h := case when v_first.home_club = v_f.home_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
    v_agg_a := case when v_first.home_club = v_f.away_club then coalesce(v_first.home_goals, 0) else coalesce(v_first.away_goals, 0) end;
  end if;

  insert into public.mgr_matches (fixture_id, career_id, season_id, user_side, minute, state)
  values (p_fixture, p_career, v_f.season_id, p_user_side, 0, jsonb_build_object(
    'engine_version', 2, 'referee', round((0.80+random()*0.40)::numeric,3), 'seq', 0, 'score', jsonb_build_array(0, 0), 'poss', jsonb_build_array(0, 0),
    'corners', jsonb_build_array(0, 0), 'offsides', jsonb_build_array(0, 0),
    'subs', jsonb_build_object('h', jsonb_build_object('used', 0, 'windows', 0), 'a', jsonb_build_object('used', 0, 'windows', 0)),
    'max_subs', coalesce((v_rules ->> 'max_subs')::int, 5), 'max_windows', coalesce((v_rules ->> 'sub_windows')::int, 3),
    'neutral', v_neut, 'decisive', v_dec, 'agg', jsonb_build_array(v_agg_h, v_agg_a),
    'extra_time_rule', (v_dec and case when v_ph is not null then coalesce((v_ph ->> 'extra_time')::boolean, false)
                                       else v_f.stage = 'final' and coalesce((v_rules ->> 'final_extra_time')::boolean, false) end),
    'tie_rule', coalesce(v_ph ->> 'tie', 'penalties'),
    'et', false, 'comp', v_f.competition_id, 'stage', v_f.stage, 'day', v_s.day_no,
    'form', jsonb_build_array(round((0.90 + random() * 0.20)::numeric, 3), round((0.90 + random() * 0.20)::numeric, 3))));

  v_lh := case when p_user_side = 'h' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.home_club, public.mgr_ai_formation(p_career, v_f.home_club), v_f.competition_id, v_s.day_no, v_bench) end;
  v_la := case when p_user_side = 'a' then p_user_lineup
               else public.mgr_auto_lineup(p_career, v_f.away_club, public.mgr_ai_formation(p_career, v_f.away_club), v_f.competition_id, v_s.day_no, v_bench) end;
  perform public.mgr_build_side(p_fixture, 'h', p_career, v_f.home_club, v_lh);
  perform public.mgr_build_side(p_fixture, 'a', p_career, v_f.away_club, v_la);

  v_sh := public.mgr_side_strength(p_fixture, 'h');
  v_sa := public.mgr_side_strength(p_fixture, 'a');
  v_th := case when p_user_side = 'h' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_plan(p_career,v_f.home_club,v_sh-v_sa,not v_neut) end;
  v_ta := case when p_user_side = 'a' then public.mgr_tactics_clean(p_user_lineup -> 'tactics') else public.mgr_ai_plan(p_career,v_f.away_club,v_sa-v_sh,false) end;

  update public.mgr_matches
     set state = state || jsonb_build_object(
           'tactics', jsonb_build_object('h', v_th, 'a', v_ta),
           'base_mentality', jsonb_build_array((v_th ->> 'mentality')::int, (v_ta ->> 'mentality')::int),
           'formation', jsonb_build_array(v_lh ->> 'formation', v_la ->> 'formation'),
           'strength', jsonb_build_array(round(v_sh, 1), round(v_sa, 1)))
   where fixture_id = p_fixture;
end;
$$;
-- Preserva também o comportamento da IA das partidas já abertas.
do $$ begin
 if to_regprocedure('public.mgr_ai_manage_v1(bigint,character,integer)') is null then
  alter function public.mgr_ai_manage(bigint,char,int) rename to mgr_ai_manage_v1;
 end if;
end $$;
create or replace function public.mgr_ai_manage_v2(p_fixture bigint, p_side char, p_minute int)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_m     public.mgr_matches;
  v_my    int;
  v_opp   int;
  v_base  int;
  v_ment  int;
  r       record;
  v_in    text;
  v_n     int := 0;
  v_first boolean := true;
  v_max   int := case when p_minute >= 75 then 3 else 2 end;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture;
  v_my  := (v_m.state -> 'score' ->> (case when p_side = 'h' then 0 else 1 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 0 else 1 end))::int;
  v_opp := (v_m.state -> 'score' ->> (case when p_side = 'h' then 1 else 0 end))::int
         + (v_m.state -> 'agg' ->> (case when p_side = 'h' then 1 else 0 end))::int;
  v_base := (v_m.state -> 'base_mentality' ->> (case when p_side = 'h' then 0 else 1 end))::int;

  -- postura
  v_ment := v_base;
  if v_my < v_opp and p_minute >= 60 then v_ment := least(2, v_base + case when v_opp - v_my >= 2 or p_minute >= 75 then 2 else 1 end);
  elsif v_my > v_opp and p_minute >= 75 then v_ment := greatest(-2, v_base - 1);
  end if;
  if v_ment <> coalesce((v_m.state -> 'tactics' -> p_side ->> 'mentality')::int, 0) then
    update public.mgr_matches set state = jsonb_set(state, array['tactics', p_side, 'mentality'], to_jsonb(v_ment)) where fixture_id = p_fixture;
  end if;

  -- Ajusta mais que a postura: pressão/ritmo conforme placar, tempo e cansaço.
  if p_minute>=60 then
   update public.mgr_matches set state=jsonb_set(state,array['tactics',p_side],
     (state->'tactics'->p_side) || case when v_my<v_opp then
       jsonb_build_object('tempo','fast','pressing',case when (select avg(cond) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on')>60 then 'high' else 'medium' end,'manage','push')
      when v_my>v_opp and p_minute>=75 then '{"tempo":"slow","pressing":"low","manage":"keep"}'::jsonb else '{}'::jsonb end
     || case when (select count(*) from public.mgr_match_players where fixture_id=p_fixture and side=p_side and status='on' and yellow>0)>=3
         then '{"tackles":"cautious"}'::jsonb else '{}'::jsonb end)
    where fixture_id=p_fixture;
  end if;

  -- substituições (lesionados primeiro, depois os mais cansados / pendurados)
  for r in
    select mp.player_id, mp.pos, mp.status
      from public.mgr_match_players mp
     where mp.fixture_id = p_fixture and mp.side = p_side
       and ((mp.status = 'injured_off' and mp.slot is not null)
            or (mp.status = 'on' and mp.pos <> 'GOL' and p_minute >= 45
                and (mp.cond < 66 or (mp.yellow > 0 and mp.pos in ('ZAG', 'LD', 'LE', 'VOL') and p_minute >= 55)
                     or (p_minute >= 70 and mp.cond < 74 and v_my <> v_opp))))
     order by (mp.status = 'injured_off') desc, mp.cond
  loop
    exit when v_n >= v_max and r.status <> 'injured_off';
    v_in := public.mgr_best_bench(p_fixture, p_side,
              case when v_my < v_opp and p_minute >= 70 and r.pos in ('VOL', 'ZAG') and v_ment >= 1 then 'ATA' else r.pos end);
    exit when v_in is null;
    exit when public.mgr_do_sub(p_fixture, p_side, r.player_id, v_in, p_minute, v_first) is not null;
    v_first := false;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
create or replace function public.mgr_ai_manage(p_fixture bigint,p_side char,p_minute int)
returns int language plpgsql security definer set search_path=public as $$
begin
 if coalesce((select (state->>'engine_version')::int from public.mgr_matches where fixture_id=p_fixture),1)=1 then
  return public.mgr_ai_manage_v1(p_fixture,p_side,p_minute);
 end if;
 return public.mgr_ai_manage_v2(p_fixture,p_side,p_minute);
end $$;

do $$ begin
 if to_regprocedure('public.mgr_engine_run_v1(bigint,integer,character)') is null then
  alter function public.mgr_engine_run(bigint,int,char) rename to mgr_engine_run_v1;
 end if;
end $$;

create or replace function public.mgr_engine_run_v2(p_fixture bigint, p_to int, p_interactive char)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_m      public.mgr_matches;
  v_p      public.mgr_ep[];
  v_n      int;
  v_min    int;
  v_end    int;
  v_stop   text := 'segment';
  i        int;
  j        int;
  s        int;
  d        int;
  v_e      float8;
  v_att    float8[];
  v_def    float8[];
  v_ctl    float8[];
  v_gkr    float8[];
  v_gki    int[];
  v_defav  float8[];
  v_paceav float8[];
  v_non    int[];
  v_tac    jsonb;
  v_ment   int[];
  v_amult  float8[];
  v_dmult  float8[];
  v_freq   float8[];
  v_qual   float8[];
  v_drainm float8[];
  v_foulm  float8[];
  v_offm   float8[];
  v_hdr    float8[];
  v_sc     int[];
  v_agg    int[];
  v_poss   int[];
  v_corn   int[];
  v_offs   int[];
  v_ph     float8;
  v_r      float8;
  v_pa     float8;
  v_q      float8;
  v_w      float8[];
  v_k      int;
  v_a      int;
  v_gkidx  int;
  v_head   boolean;
  v_reload boolean;
  v_neut   boolean;
  v_et     boolean;
  v_side   char;
  v_oside  char;
  v_dsec   char;
  v_inj_stop boolean;
  v_lead   int;
  v_detail text;
  v_form   float8[];
  v_tpress text[];
  v_tline  text[];
  v_ttempo text[];
  v_tbuild text[];
  v_tmanage text[];
  v_tment  int[];
  v_ctlm   float8[];
  v_dws    float8[];
  v_dirty  boolean := true;
  v_profiles jsonb;
  v_card jsonb;
  v_ref float8;
  v_tackles text[];
  v_effect jsonb;
  v_skill record;
  v_yprob float8;
  v_rprob float8;
begin
  select * into v_m from public.mgr_matches where fixture_id = p_fixture for update;
  if v_m.status <> 'live' then return 'ft'; end if;
  select jsonb_object_agg(a.player_id,jsonb_build_array(a.aggression,a.discipline)) into v_profiles
   from public.mgr_match_players mp join public.sim_player_attrs a on a.player_id=mp.player_id where mp.fixture_id=p_fixture;
  v_ref:=coalesce((v_m.state->>'referee')::float8,1);
  v_form := array[coalesce((v_m.state -> 'form' ->> 0)::numeric, 1), coalesce((v_m.state -> 'form' ->> 1)::numeric, 1)];
  v_min := v_m.minute;
  v_et  := coalesce((v_m.state ->> 'et')::boolean, false);
  v_end := least(p_to, case when v_et then 120 else 90 end);
  v_neut := coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_poss := array[(v_m.state -> 'poss' ->> 0)::int, (v_m.state -> 'poss' ->> 1)::int];
  v_corn := array[(v_m.state -> 'corners' ->> 0)::int, (v_m.state -> 'corners' ->> 1)::int];
  v_offs := array[(v_m.state -> 'offsides' ->> 0)::int, (v_m.state -> 'offsides' ->> 1)::int];
  v_sc   := array[(v_m.state -> 'score' ->> 0)::int, (v_m.state -> 'score' ->> 1)::int];
  v_agg  := array[(v_m.state -> 'agg' ->> 0)::int, (v_m.state -> 'agg' ->> 1)::int];
  v_reload := true;

  while v_min < v_end loop
    v_min := v_min + 1;

    -- a IA (e o auxiliar, no modo automático) mexe nos intervalos e marcos do jogo
    if v_min in (46, 61, 71, 81, 91, 106) then
      if v_p is not null then   -- grava antes: a IA decide olhando a condição e o placar atuais
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
        update public.mgr_matches
           set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
         where fixture_id = p_fixture;
        v_p := null;
      end if;
      if p_interactive is distinct from 'h' then perform public.mgr_ai_manage(p_fixture, 'h', v_min - 1); end if;
      if p_interactive is distinct from 'a' then perform public.mgr_ai_manage(p_fixture, 'a', v_min - 1); end if;
      v_reload := true;
    end if;

    if v_reload then
      if v_p is not null then
        update public.mgr_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
      end if;
      select * into v_m from public.mgr_matches where fixture_id = p_fixture;
      select array_agg(row(mp.player_id, case when mp.side = 'h' then 1 else 2 end, mp.slot, mp.pos,
                           sp.w_att::float8, sp.w_def::float8, sp.w_ctl::float8, sp.drain::float8,
                           mp.c_att::float8, mp.c_cre::float8, mp.c_def::float8, mp.c_ctl::float8, mp.c_gk::float8, mp.c_fin::float8,
                           mp.c_head::float8, mp.c_pace::float8, mp.c_stam::float8, mp.c_tack::float8, mp.c_str::float8,
                           mp.fit::float8, mp.cond::float8, mp.rhythm::float8, mp.goals, mp.assists, mp.shots, mp.sot, mp.saves, mp.fouls, mp.yellow, mp.red,
                           false, true, mp.minutes)::public.mgr_ep order by mp.side, mp.slot)
        into v_p
        from public.mgr_match_players mp join public.sim_positions sp on sp.code = mp.pos
       where mp.fixture_id = p_fixture and mp.status = 'on';
      v_n := coalesce(array_length(v_p, 1), 0);
      v_tac := v_m.state -> 'tactics';
      v_reload := false;
      v_dirty := true;
      -- parâmetros táticos fixos até a próxima mudança
      v_tackles:=array[coalesce(v_tac->'h'->>'tackles','normal'),coalesce(v_tac->'a'->>'tackles','normal')];
      v_tpress := array[v_tac -> 'h' ->> 'pressing', v_tac -> 'a' ->> 'pressing'];
      v_tline  := array[v_tac -> 'h' ->> 'line', v_tac -> 'a' ->> 'line'];
      v_ttempo := array[v_tac -> 'h' ->> 'tempo', v_tac -> 'a' ->> 'tempo'];
      v_tbuild := array[v_tac -> 'h' ->> 'build', v_tac -> 'a' ->> 'build'];
      v_tmanage := array[v_tac -> 'h' ->> 'manage', v_tac -> 'a' ->> 'manage'];
      v_tment  := array[coalesce((v_tac -> 'h' ->> 'mentality')::int, 0), coalesce((v_tac -> 'a' ->> 'mentality')::int, 0)];
      v_freq := array[1, 1]; v_qual := array[0, 0]; v_drainm := array[1, 1]; v_foulm := array[1, 1]; v_offm := array[1, 1];
      v_hdr := array[0.2, 0.2]; v_ctlm := array[1, 1];
      for s in 1 .. 2 loop
        d := 3 - s;
        if v_tpress[s] = 'high' then v_freq[s] := v_freq[s] * 1.06; v_drainm[s] := 1.30; v_foulm[s] := 1.25; v_ctlm[d] := v_ctlm[d] * 0.93;
        elsif v_tpress[s] = 'low' then v_drainm[s] := 0.85; v_foulm[s] := 0.85; v_ctlm[d] := v_ctlm[d] * 1.04; end if;
        if v_ttempo[s] = 'fast' then v_freq[s] := v_freq[s] * 1.10; v_drainm[s] := v_drainm[s] * 1.18; v_ctlm[s] := v_ctlm[s] * 0.97;
        elsif v_ttempo[s] = 'slow' then v_freq[s] := v_freq[s] * 0.90; v_drainm[s] := v_drainm[s] * 0.90; v_ctlm[s] := v_ctlm[s] * 1.04; end if;
        if v_tbuild[s] = 'short' then v_freq[s] := v_freq[s] * 0.95; v_qual[s] := v_qual[s] + 0.04; v_ctlm[s] := v_ctlm[s] * 1.05;
        elsif v_tbuild[s] = 'direct' then v_freq[s] := v_freq[s] * 1.08; v_qual[s] := v_qual[s] - 0.03; v_offm[s] := 1.25; v_ctlm[s] := v_ctlm[s] * 0.94; end if;
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'width' when 'wide' then 0.30 when 'center' then 0.10 else 0.20 end;
        if v_hdr[s] = 0.10 then v_qual[s] := v_qual[s] + 0.02; end if;
        -- linha defensiva do ADVERSÁRIO muda a frequência de ataque e os impedimentos
        if v_tline[d] = 'high' then v_freq[s] := v_freq[s] * 0.95; v_offm[s] := v_offm[s] * 1.7;
        elsif v_tline[d] = 'low' then v_freq[s] := v_freq[s] * 1.06; v_offm[s] := v_offm[s] * 0.6; end if;
      end loop;
      for s in 1..2 loop
        select avg(c_cre) as skill,avg(c_pace) as pace,avg(c_stam * cond/100) as stamina,avg(c_head) as heading into v_skill
        from public.mgr_match_players where fixture_id=p_fixture and side=case when s=1 then 'h' else 'a' end and status='on' and pos<>'GOL';
        v_effect:=public.mgr_tactical_effect(v_tac->(case when s=1 then 'h' else 'a' end),v_tac->(case when s=1 then 'a' else 'h' end),
                  v_skill.skill,v_skill.pace,v_skill.stamina,v_skill.heading);
        v_ctlm[s]:=v_ctlm[s]*(v_effect->>'control')::float8;
        v_freq[s]:=v_freq[s]*(v_effect->>'frequency')::float8;
        v_qual[s]:=v_qual[s]+(v_effect->>'quality')::float8;
        v_foulm[s]:=v_foulm[s]*case v_tackles[s] when 'aggressive' then 1.22 when 'cautious' then 0.78 else 1 end;
      end loop;
      if not v_neut then v_ctlm[1] := v_ctlm[1] * 1.05; end if;
    end if;

    -- ---- força dos times (recalculada a cada 3 minutos ou quando alguém sai/entra) ----
    if v_dirty or v_min % 3 = 1 then
      v_dirty := false;
      v_att := array[0, 0]; v_def := array[0, 0]; v_ctl := array[0, 0]; v_gkr := array[30, 30]; v_gki := array[0, 0];
      v_defav := array[0, 0]; v_paceav := array[0, 0]; v_non := array[0, 0]; v_dws := array[0, 0];
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond) * (case when v_p[i].cond < 50 then 0.88 + 0.0024 * v_p[i].cond else 1 end)
               * (0.94 + 0.0006 * v_p[i].rhy);
        v_att[s] := v_att[s] + v_p[i].aw * (0.62 * v_p[i].att + 0.38 * v_p[i].cre) * v_e;
        v_def[s] := v_def[s] + v_p[i].dw * v_p[i].def * v_e;
        v_ctl[s] := v_ctl[s] + v_p[i].cw * v_p[i].ctl * v_e;
        v_non[s] := v_non[s] + 1;
        if v_p[i].pos = 'GOL' then v_gkr[s] := v_p[i].gk * v_e; v_gki[s] := i;
        else
          v_defav[s] := v_defav[s] + v_p[i].dw * v_p[i].def * v_e;
          v_paceav[s] := v_paceav[s] + v_p[i].dw * v_p[i].pace * v_e;
          v_dws[s] := v_dws[s] + v_p[i].dw;
        end if;
      end loop;
      for s in 1 .. 2 loop
        v_defav[s] := case when v_dws[s] > 0 then v_defav[s] / v_dws[s] else 40 end;
        v_paceav[s] := case when v_dws[s] > 0 then v_paceav[s] / v_dws[s] else 50 end;
      end loop;
    end if;

    -- ---- postura (muda com o placar conforme a "gestão do jogo") ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_ment[s] := v_tment[s];
      v_lead := (v_sc[s] + v_agg[s]) - (v_sc[d] + v_agg[d]);
      if v_tmanage[s] = 'keep' and v_lead > 0 and v_min >= 70 then v_ment[s] := greatest(-2, v_ment[s] - 1); end if;
      if v_tmanage[s] = 'push' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if;
      v_amult[s] := (array[0.80, 0.90, 1.00, 1.10, 1.20])[v_ment[s] + 3];
      v_dmult[s] := (array[1.15, 1.07, 1.00, 0.94, 0.86])[v_ment[s] + 3] * case when v_tpress[s] = 'low' then 1.03 else 1 end;
    end loop;

    -- ---- posse ----
    v_r := v_ctl[1] * v_ctlm[1];
    v_q := v_ctl[2] * v_ctlm[2];
    v_ph := greatest(0.25, least(0.75, 0.5 + 1.15 * (v_r / greatest(v_r + v_q, 1) - 0.5)));
    s := case when random() < v_ph then 1 else 2 end;
    d := 3 - s;
    v_side := case when s = 1 then 'h' else 'a' end;
    v_oside := case when d = 1 then 'h' else 'a' end;
    v_poss[s] := v_poss[s] + 1;

    -- ---- jogada de ataque? ----
    v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case when v_neut then 1 when s = 1 then 1.16 else 0.96 end), 1)
                          / greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.50)
                  * v_freq[s];
    v_pa := greatest(0.05, least(0.55, v_pa));

    if random() < v_pa then
      v_r := random();
      if v_r < 0.07 * v_offm[s] then
        -- impedimento
        v_offs[s] := v_offs[s] + 1;
        if p_interactive is not null then
          v_w := '{}';
          for i in 1 .. v_n loop v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s then v_p[i].aw * v_p[i].pace else 0 end; end loop;
          v_k := public.mgr_pick(v_w);
          if v_k > 0 then perform public.mgr_event(p_fixture, v_min, v_side, 'offside', v_p[v_k].pid); end if;
        end if;
      elsif v_r < 0.07 + 0.10 then
        -- falta do defensor na jogada (pode virar pênalti ou cartão)
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = d and v_p[i].pos <> 'GOL' then v_p[i].dw * (1 + (100 - v_p[i].tack) / 100) else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].fouls := v_p[v_k].fouls + 1;
          v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
            v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[d],v_ref::numeric,1.20);
          v_r:=random();
          if v_r<(v_card->>'red')::float8 then
            v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
            perform public.mgr_event(p_fixture,v_min,v_oside,'red',v_p[v_k].pid,null,'Entrada temerária');
            update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
            if p_interactive=v_oside then v_stop:='red';end if;
          elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
            if v_p[v_k].yel>=1 then
              v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
              perform public.mgr_event(p_fixture,v_min,v_oside,'second_yellow',v_p[v_k].pid);
              update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
              if p_interactive=v_oside then v_stop:='red';end if;
            else
              v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_oside,'yellow',v_p[v_k].pid);
            end if;
          end if;
          if random() < 0.11 then                                         -- pênalti
            v_a := 0; v_e := -1;
            for i in 1 .. v_n loop
              if v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and v_p[i].fin > v_e then v_e := v_p[i].fin; v_a := i; end if;
            end loop;
            if v_a > 0 then
              v_p[v_a].shots := v_p[v_a].shots + 1;
              v_gkidx := v_gki[d];
              if random() < greatest(0.55, least(0.88, 0.70 + 0.004 * (v_p[v_a].fin - v_gkr[d]))) then
                v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_a].goals := v_p[v_a].goals + 1; v_sc[s] := v_sc[s] + 1;
                perform public.mgr_event(p_fixture, v_min, v_side, 'pen_goal', v_p[v_a].pid);
              else
                if random() < 0.6 and v_gkidx > 0 then
                  v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1;
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, v_p[v_gkidx].pid, 'defendido');
                else
                  perform public.mgr_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, null, 'para fora');
                end if;
              end if;
            end if;
          end if;
        end if;
      elsif v_r < 0.17 + 0.12 then
        if random() < 0.45 then v_corn[s] := v_corn[s] + 1; end if;  -- cruzamento cortado / jogada desarmada
      else
        -- ---- finalização ----
        v_head := random() < v_hdr[s];
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
                   case when v_head then (v_p[i].aw + 0.25) * power(v_p[i].head / 60, 3)
                        else power(v_p[i].aw + 0.05, 1.6) * power(v_p[i].fin / 60, 2) * (0.70 + 0.003 * v_p[i].cond) end
                 else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          v_q := 0.30 + 0.0025 * ((case when v_head then v_p[v_k].head else v_p[v_k].att end) - v_defav[d])
                 + case when s = 1 and not v_neut then 0.02 else 0 end
                 + v_qual[s] + random() * 0.35
                 + case v_tline[d] when 'high' then 0.003 * (v_p[v_k].pace - v_paceav[d]) when 'low' then -0.04 else 0 end
                 - case when v_head then 0.08 else 0 end;
          v_q := greatest(0.05, least(0.95, v_q * (0.85 + 0.15*v_p[v_k].fit)));
          v_gkidx := v_gki[d];
          v_r := random();
          if v_r < 0.20 then
            -- bloqueada
            if random() < 0.60 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, 'bloqueado'); end if;
          elsif random() < greatest(0.10, least(0.75, 0.26 + 0.32 * v_q + 0.0020 * (v_p[v_k].fin - 65))) then
            v_p[v_k].sot := v_p[v_k].sot + 1;
            if random() < greatest(0.05, least(0.70, 0.11 + 0.36 * v_q + 0.0015 * (v_p[v_k].fin - v_gkr[d]))) then
              -- GOL
              v_p[v_k].goals := v_p[v_k].goals + 1;
              v_sc[s] := v_sc[s] + 1;
              v_a := 0;
              if random() < 0.78 then
                v_w := '{}';
                for i in 1 .. v_n loop
                  v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and i <> v_k and v_p[i].pos <> 'GOL'
                                     then (v_p[i].aw + 0.6 * v_p[i].cw) * power(v_p[i].cre / 60, 2) else 0 end;
                end loop;
                v_a := public.mgr_pick(v_w);
                if v_a > 0 then v_p[v_a].assists := v_p[v_a].assists + 1; end if;
              end if;
              perform public.mgr_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid,
                                       case when v_a > 0 then v_p[v_a].pid end, case when v_head then 'de cabeça' end);
            else
              if v_gkidx > 0 then v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1; end if;
              if random() < 0.40 then v_corn[s] := v_corn[s] + 1; end if;
              if p_interactive is not null or v_q > 0.62 then
                perform public.mgr_event(p_fixture, v_min, v_side, 'save', v_p[v_k].pid,
                                         case when v_gkidx > 0 then v_p[v_gkidx].pid end, case when v_q > 0.62 then 'grande chance' end);
              end if;
            end if;
          else
            if random() < 0.18 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then
              perform public.mgr_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_q > 0.62 then 'grande chance' end);
            end if;
          end if;
        end if;
      end if;
    end if;

    -- ---- faltas no meio-campo e cartões (os dois times) ----
    for s in 1 .. 2 loop
      continue when random() >= 0.125 * v_foulm[s] * (case when v_min > 75 then 1.15 else 1 end);
      v_side := case when s = 1 then 'h' else 'a' end;
      v_w := '{}';
      for i in 1 .. v_n loop
        v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL'
                           then (v_p[i].dw + 0.3) * (1 + (100 - v_p[i].tack) / 100) * case when v_p[i].yel > 0 then 0.45 else 1 end else 0 end;
      end loop;
      v_k := public.mgr_pick(v_w);
      continue when v_k = 0;
      v_p[v_k].fouls := v_p[v_k].fouls + 1;
      v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
        v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[s],v_ref::numeric,case when v_min>75 and abs(v_sc[1]-v_sc[2])<=1 then 1.10 else 1.0 end);
      v_r:=random();
      if v_r<(v_card->>'red')::float8 then
        v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
        perform public.mgr_event(p_fixture,v_min,v_side,'red',v_p[v_k].pid,null,'Entrada temerária');
        update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
        if p_interactive=v_side then v_stop:='red';end if;
      elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
        if v_p[v_k].yel>=1 then
          v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
          perform public.mgr_event(p_fixture,v_min,v_side,'second_yellow',v_p[v_k].pid);
          update public.mgr_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
          if p_interactive=v_side then v_stop:='red';end if;
        else
          v_p[v_k].yel:=1;perform public.mgr_event(p_fixture,v_min,v_side,'yellow',v_p[v_k].pid);
        end if;
      end if;
    end loop;

    -- ---- desgaste, lesões e minutos jogados ----
    v_inj_stop := false;
    if v_min % 3 = 0 then
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_side := case when s = 1 then 'h' else 'a' end;
        v_p[i].cond := greatest(0, v_p[i].cond - 3 * 0.21 * v_p[i].drain * (1.32 - v_p[i].stam / 100 * 0.62) * v_drainm[s]
                                   * case when v_et then 1.15 else 1 end);
        if random() < 3 * 0.00005 * (1 + greatest(0, 70 - v_p[i].cond) / 25) * (case when v_tpress[s] = 'high' then 1.15 else 1 end) then
          v_p[i].inj := true; v_p[i].on_field := false; v_dirty := true;
          perform public.mgr_event(p_fixture, v_min, v_side, 'injury', v_p[i].pid);
          update public.mgr_match_players set status = 'injured_off', injured = true, left_min = v_min where fixture_id = p_fixture and player_id = v_p[i].pid;
          if p_interactive = v_side then v_inj_stop := true;
          else
            -- a IA troca na hora (se ainda tiver substituição)
            v_detail := public.mgr_do_sub(p_fixture, v_side, v_p[i].pid, public.mgr_best_bench(p_fixture, v_side, v_p[i].pos), v_min, true);
            v_reload := true;
          end if;
        end if;
      end loop;
    end if;
    if v_inj_stop then v_stop := 'injury'; end if;

    if v_reload then  -- grava o estado antes de recarregar a lista de quem está em campo
      update public.mgr_matches
         set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
       where fixture_id = p_fixture;
    end if;

    exit when v_stop in ('red', 'injury');
    if v_min = 45 and not v_et then v_stop := 'ht'; exit; end if;
    if v_min = 105 and v_et then v_stop := 'et_ht'; exit; end if;
  end loop;

  -- grava tudo
  if v_p is not null then
    update public.mgr_match_players m
       set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
           fouls = x.fouls, yellow = x.yel, red = x.red,
           minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
      from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
  end if;
  update public.mgr_matches
     set minute = v_min, updated_at = now(),
         state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
   where fixture_id = p_fixture;

  if v_min >= (case when v_et then 120 else 90 end) then v_stop := 'ft'; end if;
  if v_stop = 'segment' and v_min = 45 then v_stop := 'ht'; end if;
  return v_stop;
end;
$$;
create or replace function public.mgr_engine_run(p_fixture bigint,p_to int,p_interactive char)
returns text language plpgsql security definer set search_path=public as $$
begin
 if coalesce((select (state->>'engine_version')::int from public.mgr_matches where fixture_id=p_fixture),1)=1 then
  return public.mgr_engine_run_v1(p_fixture,p_to,p_interactive);
 end if;
 return public.mgr_engine_run_v2(p_fixture,p_to,p_interactive);
end $$;

revoke all on function public.mgr_card_chances(numeric,numeric,numeric,numeric,int,boolean,text,numeric,numeric),
 public.mgr_ai_plan(uuid,text,numeric,boolean),public.mgr_tactical_effect(jsonb,jsonb,numeric,numeric,numeric,numeric),
 public.mgr_ai_manage_v1(bigint,char,int),public.mgr_ai_manage_v2(bigint,char,int),public.mgr_ai_manage(bigint,char,int),
 public.mgr_engine_run_v1(bigint,int,char),public.mgr_engine_run_v2(bigint,int,char),public.mgr_engine_run(bigint,int,char)
 from public,anon,authenticated;
commit;
