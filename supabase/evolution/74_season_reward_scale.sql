-- Evolução 74: prêmio de fim de temporada na escala da economia atual.
--
-- Cumprir a meta principal da liga pagava 450 moedas (150 por prioridade + 75 por posição acima da meta), menos que
-- dois jogos de copa: um título de liga paga 20 mil, a premiação de competição chega a 100 mil e a receita mensal de um
-- clube médio passa de 10 mil. Agora:
--   liga: 5.000 por prioridade (meta principal = 15.000) + 2.500 por posição acima da meta;
--   copa: 3.500 por prioridade.
-- Os prêmios já pagos com a regra antiga recebem a diferença (uma vez só: marca 'rescaled' no detalhe).
update public.cw_season_reward_rules set league_coins_per_priority=5000,league_coins_per_place=2500,cup_coins_per_priority=3500;

do $$
declare r record;novo int;itens jsonb;
begin
 for r in select * from public.cw_season_rewards where coins>0 and not coalesce((detail->>'rescaled')::boolean,false) for update loop
  select coalesce(jsonb_agg(case it->>'kind'
     when 'league' then it||jsonb_build_object('coins',round((it->>'coins')::numeric*100/3)::int)
     when 'cup' then it||jsonb_build_object('coins',((it->>'coins')::numeric*35)::int) else it end),'[]'::jsonb)
   into itens from jsonb_array_elements(r.detail->'items') it;
  select coalesce(sum((it->>'coins')::int),0)+coalesce((r.detail->>'title_coins')::int,0) into novo from jsonb_array_elements(itens) it;
  if novo>r.coins then
   perform public.econ_apply(r.career_id,'coins',novo-r.coins,'season_reward','rescale:'||r.season_id);
  end if;
  update public.cw_season_rewards set coins=greatest(novo,coins),detail=detail||jsonb_build_object('items',itens,'rescaled',true)
   where season_id=r.season_id;
 end loop;
end $$;
