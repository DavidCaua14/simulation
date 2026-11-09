-- Abrir o elenco sem esperar pela trava da carreira.
-- mgr_squad pegava a trava duas vezes e regravava a recuperação física a cada leitura; era a função com mais
-- estouros de tempo (109 em três dias). Agora só trava quando há algo a gravar. A regra de recuperação
-- (cw_recover_club) e o conteúdo devolvido são os mesmos: a saída foi comparada com a versão anterior em três
-- carreiras, com o elenco próprio e de outros clubes, e ficou idêntica.
CREATE OR REPLACE FUNCTION public.mgr_squad_before_v90(p_club text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.careers;club text;coach_club text;own text;
begin
 c:=public.mgr_read();
 select club_id,case when status='employed' then club_id end into coach_club,own from public.mgr_coach where career_id=c.id;
 club:=coalesce(p_club,coach_club);
 -- A trava da carreira só é necessária quando abrir o elenco precisa gravar: clube ainda fora do mundo,
 -- escalação padrão por criar, atleta do técnico sem linha própria ou recuperação física de um dia que já passou.
 -- No mesmo dia de jogo, a segunda leitura em diante não grava nada e não espera na fila.
 if club is not null and (
   not public.cw_is_hybrid(c.id)
   or not exists(select 1 from public.cw_world_clubs wc where wc.career_id=c.id and wc.club_id=club)
   or (club=coach_club and not exists(select 1 from public.mgr_lineups l where l.career_id=c.id and l.club_id=club))
   or (club is not distinct from own and exists(select 1 from public.mgr_players mp where mp.career_id=c.id and mp.club_id=club
        and not exists(select 1 from public.mgr_player_rows r where r.career_id=mp.career_id and r.player_id=mp.player_id)))
   or exists(select 1 from public.mgr_player_rows r
        left join public.cw_player_clock pc on pc.career_id=r.career_id and pc.player_id=r.player_id
        where r.career_id=c.id and r.club_id=club and not r.removed
         and pc.day_no is distinct from (select w.elapsed_days from public.cw_world w where w.career_id=c.id))
  ) then
  c:=public.mgr_lock();
  perform public.cw_materialize_club(c.id,club);
  perform public.cw_recover_club(c.id,club);
 end if;
 return public.mgr_squad_before_v45(p_club);
end $function$;
CREATE OR REPLACE FUNCTION public.mgr_squad_before_v32(p_club text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_car  public.careers;
  v_c    public.mgr_coach;
  v_s    public.career_seasons;
  v_club text;
  v_l    public.mgr_lineups;
  v_comp text;
  v_ev   record;
begin
  v_car := public.mgr_read();
  select * into v_c from public.mgr_coach where career_id = v_car.id;
  select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
  v_club := coalesce(p_club, v_c.club_id);
  if v_club is null then raise exception 'Você está sem clube no momento.'; end if;
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_club);
    if found and v_ev.o_kind = 'mine' then v_comp := v_ev.o_comp; end if;
  end if;
  v_comp := coalesce(v_comp, '-');

  if v_club = v_c.club_id then
    perform public.mgr_lineup_default(v_car.id, v_club);
    select * into v_l from public.mgr_lineups where career_id = v_car.id and club_id = v_club;
  end if;

  return jsonb_build_object(
    'club_id', v_club, 'mine', v_club = v_c.club_id, 'next_competition', nullif(v_comp, '-'), 'day_no', v_s.day_no,
    'rules', (select jsonb_build_object('bench', coalesce((rules ->> 'bench')::int, 12), 'max_subs', coalesce((rules ->> 'max_subs')::int, 5),
                                        'sub_windows', coalesce((rules ->> 'sub_windows')::int, 3))
                from public.sim_competitions where id = case when v_comp = '-'
                  then coalesce((select id from public.sim_competitions where region = v_s.region and kind = 'league' order by division limit 1), 'brasileirao')
                  else v_comp end),
    'lineup', case when v_l.club_id is not null then jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots, 'bench', to_jsonb(v_l.bench),
                'tactics', v_l.tactics, 'formation_games', v_l.formation_games,
                'issues', public.mgr_lineup_issues(v_car.id, v_club, jsonb_build_object('formation', v_l.formation, 'slots', v_l.slots,
                                                   'bench', to_jsonb(v_l.bench)), v_comp, v_s.day_no)) end,
    'players', (select coalesce(jsonb_agg(jsonb_build_object(
        'club_id', mp.club_id, 'id', p.id, 'name', p.full_name, 'short_name', p.short_name, 'number', p.shirt_number, 'position', p.position,
        'secondary', to_jsonb(p.secondary_positions), 'position_estimated', p.position_estimated, 'nationality', p.nationality,
        'age', p.age, 'captain', p.is_captain, 'youth', p.is_youth,
        'overall', round((select r.rating from public.sim_player_pos_ratings r where r.player_id = p.id and r.pos = p.position)),
        'ratings', (select jsonb_object_agg(r.pos, round(r.eff)) from public.sim_player_pos_ratings r where r.player_id = p.id),
        'attrs', to_jsonb(a) - 'player_id' - 'method' - 'updated_at',
        'condition', round(mp.condition), 'rhythm', round(mp.rhythm),
        'injured_days', case when mp.injured_until > v_s.day_no then mp.injured_until - v_s.day_no end, 'injury', mp.injury,
        'suspended', (select coalesce(sum(value::int), 0) from jsonb_each_text(mp.susp)), 'susp', mp.susp, 'yellows', mp.yellows,
        'available', public.mgr_available(mp.injured_until, mp.susp, v_comp, v_s.day_no),
        'stats', (select jsonb_build_object('apps', coalesce(sum(st.apps), 0), 'starts', coalesce(sum(st.starts), 0), 'minutes', coalesce(sum(st.minutes), 0),
                    'goals', coalesce(sum(st.goals), 0), 'assists', coalesce(sum(st.assists), 0), 'yellows', coalesce(sum(st.yellows), 0),
                    'reds', coalesce(sum(st.reds), 0), 'motm', coalesce(sum(st.motm), 0),
                    'rating', case when sum(st.apps) > 0 then round(sum(st.rating_sum) / sum(st.apps), 2) end)
                    from public.mgr_player_stats st where st.season_id = v_s.id and st.player_id = p.id and st.club_id = v_club))
        order by sp.sort, p.shirt_number nulls last, p.short_name), '[]'::jsonb)
      from public.mgr_players mp
      join public.sim_players p on p.id = mp.player_id
      join public.sim_positions sp on sp.code = p.position
      join public.sim_player_attrs a on a.player_id = p.id
     where mp.career_id = v_car.id and mp.club_id = v_club));
end;
$function$

;
