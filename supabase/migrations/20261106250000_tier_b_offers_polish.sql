-- Ligas de fundo, ajustes das propostas:
-- 1) Clube de liga de fundo que joga a Libertadores nesta carreira (participante sem division_key) continua elegível a propostas.
-- 2) context.abroad = clube de outro país, mesmo no mesmo calendário (ex.: técnico no Brasil recebe proposta do River).

CREATE OR REPLACE FUNCTION public.mgr_region_league_clubs(p_career uuid, p_region text)
 RETURNS TABLE(o_club text, o_league text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res jsonb;
begin
  -- temporada ativa da região: participantes atuais
  if exists (select 1 from public.career_seasons s where s.career_id = p_career and s.region = p_region and s.status = 'active') then
    return query
      select sp.club_id, sp.competition_id from public.season_participants sp
        join public.career_seasons s on s.id = sp.season_id
       where s.career_id = p_career and s.region = p_region and s.status = 'active' and sp.division_key is not null
      union all
      select cc.club_id, cc.competition_id from public.sim_competition_clubs cc
        join public.sim_competitions c on c.id = cc.competition_id
       where c.region = p_region and c.kind = 'league' and c.active and c.background
         and not exists (select 1 from public.season_participants sp join public.career_seasons s on s.id = sp.season_id
                          where s.career_id = p_career and s.region = p_region and s.status = 'active' and sp.club_id = cc.club_id
                            and sp.division_key is not null);
    return;
  end if;
  -- última transição da região (quem subiu/caiu no fim da última temporada jogada lá)
  select t.result into v_res from public.season_transitions t
   where t.career_id = p_career and t.region = p_region order by t.year desc, t.id desc limit 1;
  if v_res is not null then
    return query
      select x.value #>> '{}', l.key from jsonb_each(v_res -> 'leagues') l cross join lateral jsonb_array_elements(l.value) x;
    return;
  end if;
  return query
    select cc.club_id, cc.competition_id from public.sim_competition_clubs cc
      join public.sim_competitions c on c.id = cc.competition_id
     where c.region = p_region and c.kind = 'league' and c.active;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mgr_make_offer_before_world(p_career uuid, p_season uuid, p_day integer, p_force_weak boolean DEFAULT false, p_any_region boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_coach public.mgr_coach;
  v_s     public.career_seasons;
  v_reach numeric;
  v_cur   int;
  v_cand  record;
  v_pos   int;
  v_bonus int;
  v_pitch text;
  v_id    uuid;
  v_band  jsonb;
  v_obj   text;
  v_rank  int;
  v_lname text;
  v_rules jsonb;
begin
  select * into v_coach from public.mgr_coach where career_id = p_career;
  select * into v_s from public.career_seasons where id = p_season;
  v_reach := 56 + v_coach.reputation * 0.32;
  select strength into v_cur from public.sim_clubs where id = v_coach.club_id;

  with st as (   -- classificação atual das ligas da temporada (calculada uma vez só)
    select sc.competition_id as league, s.club_id, s.pos
      from public.season_competitions sc
      join public.sim_competitions c on c.id = sc.competition_id and c.kind = 'league'
      cross join lateral public.sim_standings(p_season, sc.competition_id, null) s
     where sc.season_id = p_season
  )
  select x.club_id as id, x.strength, x.name, x.league, x.other, t.pos, public.sim_club_weight(p_career, x.club_id) as w
    into v_cand
    from (
      select l.o_club as club_id, l.o_league as league, c.strength, c.name, false as other
        from public.mgr_region_league_clubs(p_career, v_s.region) l join public.sim_clubs c on c.id = l.o_club
      union all
      select l.o_club, l.o_league, c.strength, c.name, true
        from (select distinct region from public.sim_competitions where active and kind = 'league' and region <> v_s.region) r
        cross join lateral public.mgr_region_league_clubs(p_career, r.region) l
        join public.sim_clubs c on c.id = l.o_club
       where p_any_region and (not (select public.cw_runtime_enabled(p_career)) or (v_coach.reputation>=(select foreign_reputation from public.cw_runtime_rules) and coalesce((select credibility from public.cw_coach where career_id=p_career),65)>=(select foreign_credibility from public.cw_runtime_rules)))
    ) x
    left join st t on t.club_id = x.club_id and t.league = x.league and not x.other
   where x.club_id is distinct from v_coach.club_id
     and exists (select 1 from public.sim_players p where p.club_id = x.club_id and p.active)
     and x.strength <= v_reach + 2
     and (p_force_weak or x.strength >= v_reach - 14)
     and (v_coach.status = 'unemployed' or x.strength >= coalesce(v_cur, 0) - 1)
     and x.club_id not in (select o.from_club from public.season_offers o where o.career_id = p_career and o.status = 'pending')
     and x.club_id not in (select sp.club_id from public.mgr_spells sp where sp.career_id = p_career and sp.end_reason = 'fired'
                            and sp.ended_season = v_s.season_no)
   order by power(random(), 1.0 / greatest(public.sim_club_weight(p_career, x.club_id) * (1 + coalesce(t.pos, 10) / 20.0)
                                           * case when p_force_weak then 1 + (80 - x.strength) / 10.0 else 1 end
                                           * case when x.other then 0.6 else 1 end, 0.05)) desc
   limit 1;
  if v_cand.id is null then return null; end if;
  if not p_force_weak and random() > v_cand.w then return null; end if;

  -- meta que a diretoria vai cobrar (força do clube entre os rivais da mesma liga)
  select rules, name into v_rules, v_lname from public.sim_competitions where id = v_cand.league;
  select count(*) + 1 into v_rank
    from public.mgr_region_league_clubs(p_career, (select region from public.sim_competitions where id = v_cand.league)) l
    join public.sim_clubs c2 on c2.id = l.o_club
   where l.o_league = v_cand.league and c2.strength > v_cand.strength;
  select b into v_band from jsonb_array_elements(coalesce(v_rules -> 'objectives', '[]'::jsonb)) b
   where (b ->> 'rank_max')::int >= v_rank order by (b ->> 'rank_max')::int limit 1;
  v_obj := lower(left(coalesce(v_band ->> 'label', 'fazer uma boa campanha'), 1)) || substr(coalesce(v_band ->> 'label', 'fazer uma boa campanha'), 2);
  v_pos := v_cand.pos;
  v_bonus := (round((200 + v_cand.strength * 6) / 50.0) * 50)::int;
  v_pitch := case
    when v_cand.other then format('%s, da %s, quer você no comando na próxima temporada. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_lname, v_obj)
    when v_pos is not null and v_pos > 14 then format('%s está em %sº e precisa de um treinador. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_obj)
    when v_pos is not null then format('%s (%sº na %s) quer você no comando. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_pos, v_lname, v_obj)
    else format('%s quer você no comando. Meta: %s.', public.mgr_club_o(v_cand.id, true), v_obj) end;

  insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch, kind, expires_day, context)
  values (p_career, p_season, v_cand.id, v_bonus, v_pitch, 'coach', p_day + 5,
          jsonb_build_object('position', v_pos, 'objective', v_obj, 'strength', v_cand.strength, 'league', v_cand.league,
                             'region', (select region from public.sim_competitions where id = v_cand.league),
                             'abroad', v_cand.other or (select country from public.sim_clubs where id = v_cand.id) is distinct from coalesce((select country from public.sim_clubs where id = v_coach.club_id), 'BRA')))
  returning id into v_id;
  perform public.mgr_msg(p_career, p_season, p_day, 'offer', 'Proposta: ' || v_cand.name, v_pitch, v_cand.id);
  return jsonb_build_object('id', v_id, 'club_id', v_cand.id, 'bonus_coins', v_bonus, 'pitch', v_pitch, 'expires_day', p_day + 5,
                            'context', jsonb_build_object('position', v_pos, 'objective', v_obj, 'league', v_cand.league,
                            'abroad', v_cand.other or (select country from public.sim_clubs where id = v_cand.id) is distinct from coalesce((select country from public.sim_clubs where id = v_coach.club_id), 'BRA')));
end;
$function$;
