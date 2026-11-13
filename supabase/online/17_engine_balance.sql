-- MODO ONLINE — Fase 16: balanceamento do motor da partida (medido com 300 jogos simulados por cenário).
--
-- O que se media antes: 10 pontos de nota a mais davam 59% de vitórias em casa e condição física 60 tirava 13 pontos
-- de vitória, mas o fator de forma (preparação, preleção) quase não mudava o resultado: +10% de forma, nenhum ganho
-- mensurável. Táticas isoladas também rendiam pouco.
--
-- Agora:
--  • forma entra inteira nas chances criadas e também na qualidade da finalização (6% de preparação: de 41% para 49%
--    de vitórias entre times iguais);
--  • a diferença de força pesa mais (expoente 0,50 → 0,65);
--  • cansaço pesa mais (rendimento 0,60 + 0,004 x condição: 85% de condição já custa uns 5 pontos de vitória);
--  • encaixes táticos mais fortes: bola longa contra pressão/linha alta, contra-ataque contra time ofensivo,
--    saída curta depende da técnica, pressão alta depende do fôlego, ritmo lento sofre contra pressão alta;
--  • a sorte do dia fica menor (±4% em vez de ±10%) para o trabalho do técnico decidir mais;
--  • preparação completa vale 6% (antes 3%).
do $$ begin
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  'v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case',
  'v_pa := 0.335 * (v_form[s] / v_form[d]) * power(greatest(v_att[s] * v_amult[s] * (case');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '/ greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.50)',
  '/ greatest(v_def[d] * v_dmult[d], 1) / 0.86, 0.65)');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '                 + v_qual[s] + random() * 0.35',
  '                 + v_qual[s] + 0.5 * (v_form[s] / v_form[d] - 1) + random() * 0.35');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  'v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond)',
  'v_e := v_p[i].fit * (0.60 + 0.004 * v_p[i].cond)');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  'jsonb_build_array(round((0.90+random()*0.20)::numeric,3),round((0.90+random()*0.20)::numeric,3))',
  'jsonb_build_array(round((0.96+random()*0.08)::numeric,3),round((0.96+random()*0.08)::numeric,3))');
end $$;
update public.on_config set prep_bonus=.06;

-- Encaixe tático (usado pelos dois modos): controle da posse, frequência de ataques e qualidade da finalização.
create or replace function public.mgr_tactical_effect(p_t jsonb, p_opp jsonb, p_skill numeric, p_pace numeric, p_stamina numeric, p_head numeric)
returns jsonb language plpgsql immutable set search_path=public,pg_temp as $$
declare ctl numeric:=1; freq numeric:=1; quality numeric:=0; om int:=coalesce((p_opp->>'mentality')::int,0); m int:=coalesce((p_t->>'mentality')::int,0);
begin
 -- saída curta: rende com técnica; contra pressão alta, time técnico sai jogando e time fraco perde a bola
 if p_t->>'build'='short' then
  ctl:=ctl+greatest(-0.16,least(0.10,(p_skill-60)/150));
  if p_opp->>'pressing'='high' then ctl:=ctl+greatest(-0.10,least(0.08,(p_skill-65)/200)); quality:=quality+greatest(-0.05,least(0.04,(p_skill-65)/350)); end if;
 elsif p_t->>'build'='direct' and p_opp->>'line'='high' then
  freq:=freq+greatest(-0.06,least(0.16,(p_pace-55)/150));quality:=quality+greatest(-0.04,least(0.08,(p_pace-60)/300));
 end if;
 -- bola longa fura a pressão alta
 if p_t->>'build'='direct' and p_opp->>'pressing'='high' then freq:=freq*1.18;quality:=quality+0.04;end if;
 -- contra-ataque castiga quem se lança ao ataque e rende pouco contra time fechado
 if p_t->>'style'='counter' then
  if om>=1 then freq:=freq*(1+0.07*om);quality:=quality+0.02*om; elsif om<=-1 then freq:=freq*0.92; end if;
 end if;
 -- linha alta contra time lento sufoca; contra time veloz e direto abre espaço (regra acima)
 if p_t->>'line'='high' and p_opp->>'build' is distinct from 'direct' then ctl:=ctl+0.04; end if;
 if p_t->>'width'='wide' then quality:=quality+greatest(-0.07,least(0.07,(p_head-60)/250)); end if;
 if p_t->>'pressing'='high' then ctl:=ctl+greatest(-0.10,least(0.07,(p_stamina-65)/220)); end if;
 -- ritmo lento contra pressão alta: a bola não sai
 if p_t->>'tempo'='slow' and p_opp->>'pressing'='high' then ctl:=ctl-0.05;freq:=freq*0.94; end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',quality);
end $$;
