-- Satisfação equilibrada: jogar sobe a moral na hora (2026-11-10).
-- 1. Depois de cada jogo do treinador, quem entrou em campo ganha moral na hora:
--    titular: revoltado (abaixo de 35) +20 e no mínimo 45, insatisfeito (35–59) +12, neutro (60–79) +7, satisfeito +3;
--    quem entrou durante o jogo: revoltado +10 e no mínimo 30, depois +7, +4, +2.
--    Revoltado que joga como titular agradece ao treinador pela chance e deixa de lado o pedido para sair.
-- 2. Moral semanal (todos os clubes): entrar durante o jogo (menos de 30 minutos) conta como meio jogo;
--    quem jogou nos últimos 7 dias não perde moral por falta de minutos; a queda por falta de minutos
--    vai de -1 a -5 por semana (era de -2 a -8).
-- 3. Revoltado que jogou nos últimos 7 dias não perde os 3 pontos extras da semana.
-- Nada do progresso é apagado: só funções.

create or replace function public.mgr_match_morale(p_fixture bigint, p_car jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare car uuid; us char; own text; opp text; f public.season_fixtures;
 r record; gain numeric; up jsonb := '[]'::jsonb;
begin
 select career_id, user_side into car, us from public.mgr_matches where fixture_id = p_fixture;
 select club_id into own from public.mgr_coach where career_id = car and status = 'employed';
 if car is null or own is null then return p_car; end if;
 select * into f from public.season_fixtures where id = p_fixture;
 opp := case when f.home_club = own then f.away_club else f.home_club end;
 for r in select mp.player_id, mp.starter, cp.morale, sp.short_name pname
            from public.mgr_match_players mp
            join public.cw_players cp on cp.career_id = car and cp.player_id = mp.player_id
            join public.sim_players sp on sp.id = mp.player_id
           where mp.fixture_id = p_fixture and mp.club_id = own and mp.minutes > 0 loop
  gain := case when r.starter then case when r.morale < 35 then greatest(20, 45 - r.morale) when r.morale < 60 then 12 when r.morale < 80 then 7 else 3 end
               else case when r.morale < 35 then greatest(10, 30 - r.morale) when r.morale < 60 then 7 when r.morale < 80 then 4 else 2 end end;
  update public.cw_players set morale = least(100, morale + gain), morale_trend = 1
   where career_id = car and player_id = r.player_id;
  up := up || jsonb_build_object('id', r.player_id, 'before', r.morale, 'after', least(100, r.morale + gain));
  -- revoltado titular: agradece a chance e encerra o pedido para sair
  if r.starter and r.morale < 35 then
   delete from public.cw_player_unrest where career_id = car and player_id = r.player_id;
   perform public.cw_inbox_add(car, 'thanks:' || r.player_id || ':' || p_fixture, 'squad', 'squad',
    r.pname || ' agradece a oportunidade',
    format('%s agradeceu ao treinador pela oportunidade de jogar como titular contra %s. Ele deixou de lado o pedido para sair e promete retribuir em campo.',
           r.pname, coalesce((select name from public.sim_clubs where id = opp), 'o adversário')),
    own, r.player_id, null, 'open_player');
  end if;
 end loop;
 return p_car || jsonb_build_object('morale_up', up);
end $$;
revoke all on function public.mgr_match_morale(bigint, jsonb) from public, anon, authenticated;

-- Entra logo antes da checagem do elenco (o clima do vestiário já considera quem jogou).
do $$ declare src text; a text := 'v_car := public.mgr_squad_check(p_fixture, v_club, v_car);'; begin
 select pg_get_functiondef('public.mgr_user_match_finished(bigint)'::regprocedure) into src;
 if src like '%mgr_match_morale%' then return; end if;
 if position(a in src) = 0 then raise exception 'mgr_user_match_finished diferente do esperado'; end if;
 execute replace(src, a, 'v_car := public.mgr_match_morale(p_fixture, v_car);' || chr(10) || a);
end $$;

-- Moral semanal mais leve.
do $$ declare src text; n text; begin
 select pg_get_functiondef('public.cw_market_tick_before_v37(uuid)'::regprocedure) into src;
 if src like '%m_recent%' then return; end if;
 n := src;
 n := replace(n, 'count(*) m_apps from public.cw_appearances xa',
  'sum(case when xa.minutes>=30 then 1 else .5 end) m_apps,count(*) filter(where xa.on_date>=d-7) m_recent from public.cw_appearances xa');
 n := replace(n, 'xa.minutes>=30 and xa.on_date between d-28 and d', 'xa.minutes>0 and xa.on_date between d-28 and d');
 n := replace(n, 'coalesce(ap.m_apps,0) m_apps,', 'coalesce(ap.m_apps,0) m_apps,coalesce(ap.m_recent,0) m_recent,');
 n := replace(n, 'else -(2+round(6*(b.m_exp-b.m_apps::numeric/b.m_games)/b.m_exp)) end',
  'when b.m_recent>0 then 1 else -(1+round(4*(b.m_exp-b.m_apps::numeric/b.m_games)/b.m_exp)) end');
 if n not like '%m_recent,count%' and n not like '%m_recent from%' then raise exception 'cw_market_tick_before_v37 diferente do esperado (apps)'; end if;
 if n not like '%coalesce(ap.m_recent,0)%' or n not like '%when b.m_recent>0 then 1%' or n like '%xa.minutes>=30 and%' then
  raise exception 'cw_market_tick_before_v37 diferente do esperado';
 end if;
 execute n;
end $$;

-- Revoltado que jogou na semana não perde os 3 pontos extras.
do $$ declare src text; a text := 'update public.cw_players set morale=greatest(0,morale-3),morale_trend=-1 where career_id=p_career and player_id=p.player_id;'; begin
 select pg_get_functiondef('public.cw_unrest_tick(uuid)'::regprocedure) into src;
 if src like '%a.on_date>d-7%' then return; end if;
 if position(a in src) = 0 then raise exception 'cw_unrest_tick diferente do esperado'; end if;
 execute replace(src, a, 'if not exists(select 1 from public.cw_appearances a where a.career_id=p_career and a.player_id=p.player_id and a.on_date>d-7) then '
  || a || ' end if;');
end $$;
