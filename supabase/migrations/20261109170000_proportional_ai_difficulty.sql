-- =====================================================================
-- DIFICULDADE PROPORCIONAL À QUALIDADE (2026-11-09)
--
-- Problema: o adversário da IA recebia +25% fixo de rendimento (ai_match_mult 1.25 no normal). O motor usa esse
-- fator direto em ataque e defesa, então ele valia mais que a diferença real entre um time grande e um médio
-- (Real Madrid ~15% melhor que o meio da La Liga): o Real Madrid perdia quase tudo. No Brasil o Flamengo tem ~25%
-- de vantagem sobre o meio da Série A e por isso seguia vencendo.
--
-- Agora (cw_cm_match_prepare): compara a nota média dos titulares de cada lado na posição em que jogam.
--   razão R = meu time / time da IA
--   R >= 1: bônus = R·(1+base) / (1 + (R−1)·keep) → sobra a fração "keep" da vantagem, e o favorito segue favorito
--   R <  1: bônus = 1 + base → o time mais fraco perde pela qualidade, sem castigo extra
--   teto = ai_match_mult (nunca mais difícil que antes), piso = 1.
-- Fica gravado em mgr_matches.state.ai_boost (notas e multiplicador) para conferência.
-- Só muda partidas futuras. Nada de progresso, resultados ou saldos é alterado. Idempotente.
-- =====================================================================
alter table public.career_difficulty_levels add column if not exists ai_gap_keep numeric not null default 1;
alter table public.career_difficulty_levels add column if not exists ai_base_boost numeric not null default 0;
update public.career_difficulty_levels set
  ai_gap_keep   = case id when 'easy' then 0.70 when 'normal' then 0.50 when 'hard' then 0.40 else ai_gap_keep end,
  ai_base_boost = case id when 'easy' then 0.00 when 'normal' then 0.05 when 'hard' then 0.08 else ai_base_boost end
 where id in ('easy','normal','hard');

CREATE OR REPLACE FUNCTION public.cw_cm_match_prepare(p_fixture bigint, p_career uuid, p_user_side character)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare m public.mgr_matches;f public.season_fixtures;sd text;club text;spr public.cw_set_pieces;
 lvl public.career_difficulty_levels;s_me numeric;s_ai numeric;ratio numeric;boost numeric;
 fk jsonb:='{}';ck jsonb:='{}';form numeric[];spb numeric[];drills jsonb:='{}';k text;
begin
 select * into m from public.mgr_matches where fixture_id=p_fixture for update;
 if not found or coalesce((m.state->>'cm64')::boolean,false) or m.minute>0 then return;end if;
 select * into f from public.season_fixtures where id=p_fixture;
 form:=array[coalesce((m.state->'form'->>0)::numeric,1),coalesce((m.state->'form'->>1)::numeric,1)];
 spb:=array[coalesce((m.state->'sp_bonus'->>0)::numeric,0),coalesce((m.state->'sp_bonus'->>1)::numeric,0)];
 foreach sd in array array['h','a'] loop
  club:=case when sd='h' then f.home_club else f.away_club end;
  spr:=null;
  select * into spr from public.cw_set_pieces where career_id=p_career and club_id=club;
  -- batedor de falta: o escolhido; senÃ£o, o melhor em finalizaÃ§Ã£o+criaÃ§Ã£o em campo
  fk:=fk||jsonb_build_object(sd,coalesce(
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.free_kick),
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and pos<>'GOL' order by c_fin+c_cre desc limit 1)));
  ck:=ck||jsonb_build_object(sd,coalesce(
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.corner),
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and pos<>'GOL' order by c_cre desc limit 1)));
  if spr.captain is not null and exists(select 1 from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.captain) then
   form[case when sd='h' then 1 else 2 end]:=form[case when sd='h' then 1 else 2 end]*1.02;
  end if;
 end loop;
 -- insatisfaÃ§Ã£o no elenco do treinador derruba o rendimento do time
 if p_user_side in('h','a') then
  form[case when p_user_side='h' then 1 else 2 end]:=form[case when p_user_side='h' then 1 else 2 end]
   *coalesce((public.cw_squad_unrest(p_career,case when p_user_side='h' then f.home_club else f.away_club end)->>'factor')::numeric,1);
 end if;
 -- dificuldade: o adversÃ¡rio da IA entra mais concentrado contra o time do treinador
 if p_user_side in('h','a') then
  -- Bônus proporcional à diferença de qualidade dos titulares (nota na posição): o time melhor continua favorito,
  -- só com vantagem menor (ai_gap_keep = fração da vantagem que sobra); time pior não ganha ajuda além de ai_base_boost.
  -- O teto é ai_match_mult. Antes era um multiplicador fixo, que invertia jogos de time grande contra time médio.
  lvl:=public.cw_difficulty_level(p_career);
  select avg(r.eff) into s_me from public.mgr_match_players mp join public.sim_player_pos_ratings r on r.player_id=mp.player_id and r.pos=mp.pos
   where mp.fixture_id=p_fixture and mp.side=p_user_side and mp.status='on';
  select avg(r.eff) into s_ai from public.mgr_match_players mp join public.sim_player_pos_ratings r on r.player_id=mp.player_id and r.pos=mp.pos
   where mp.fixture_id=p_fixture and mp.side<>p_user_side and mp.status='on';
  if s_me is null or s_ai is null or s_ai<=0 then
   boost:=coalesce(lvl.ai_match_mult,1);
  else
   ratio:=s_me/s_ai;
   boost:=case when ratio>=1 then ratio*(1+coalesce(lvl.ai_base_boost,0))/(1+(ratio-1)*coalesce(lvl.ai_gap_keep,1))
               else 1+coalesce(lvl.ai_base_boost,0) end;
   boost:=least(coalesce(lvl.ai_match_mult,1),greatest(1,boost));
  end if;
  form[case when p_user_side='h' then 2 else 1 end]:=form[case when p_user_side='h' then 2 else 1 end]*boost;
 end if;
 -- exercÃ­cios prÃ©-jogo sÃ³ valem para o time do treinador e gastam um jogo cada
 if p_user_side in('h','a') then
  for k in select kind from public.cw_match_boosts where career_id=p_career and games_left>0 for update loop
   drills:=drills||jsonb_build_object(k,true);
   if k='shooting' then update public.mgr_match_players set c_fin=c_fin*1.06,c_att=c_att*1.03 where fixture_id=p_fixture and side=p_user_side;
   elsif k='passing' then update public.mgr_match_players set c_cre=c_cre*1.06,c_ctl=c_ctl*1.04 where fixture_id=p_fixture and side=p_user_side;
   elsif k='penalty' then spb[case when p_user_side='h' then 1 else 2 end]:=spb[case when p_user_side='h' then 1 else 2 end]+0.06;
   elsif k='blocking' then update public.mgr_match_players set c_gk=c_gk*1.06,c_def=c_def*1.03 where fixture_id=p_fixture and side=p_user_side;
   elsif k='tackling' then update public.mgr_match_players set c_tack=c_tack*1.08,c_def=c_def*1.03 where fixture_id=p_fixture and side=p_user_side;
   end if;
  end loop;
  update public.cw_match_boosts set games_left=games_left-1,updated_at=now() where career_id=p_career and games_left>0;
 end if;
 update public.mgr_matches set state=state||jsonb_build_object('cm64',true,'fk_taker',fk,'ck_taker',ck,'form',to_jsonb(form),
  'sp_bonus',to_jsonb(spb),'drills',drills,'ai_boost',jsonb_build_object('mine',round(s_me,1),'ai',round(s_ai,1),'mult',round(boost,3))) where fixture_id=p_fixture;
end $function$;
