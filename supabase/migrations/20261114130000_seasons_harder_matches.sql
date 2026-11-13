-- MODO TEMPORADAS — partidas mais difíceis e mais sensíveis ao trabalho do técnico.
-- Mesmo motor do modo online (ver 20261114120000): forma inteira nas chances e na finalização, força e cansaço
-- pesando mais, sorte do dia menor. Aqui entram também a dificuldade da IA e o efeito dos exercícios pré-jogo.
-- Pode ser reaplicado.
select public.sim_patch('public.mgr_engine_run_v2(bigint,integer,character)',
 'v_pa := 0.335 * power(greatest(v_att[s] * v_amult[s] * v_form[s] * (case',
 'v_pa := 0.335 * (v_form[s] / v_form[d]) * power(greatest(v_att[s] * v_amult[s] * (case');
select public.sim_patch('public.mgr_engine_run_v2(bigint,integer,character)',
 '/ greatest(v_def[d] * v_dmult[d] * v_form[d], 1) / 0.86, 0.50)',
 '/ greatest(v_def[d] * v_dmult[d], 1) / 0.86, 0.65)');
select public.sim_patch('public.mgr_engine_run_v2(bigint,integer,character)',
 '                 + v_qual[s] + random() * 0.35',
 '                 + v_qual[s] + 0.5 * (v_form[s] / v_form[d] - 1) + random() * 0.35');
select public.sim_patch('public.mgr_engine_run_v2(bigint,integer,character)',
 'v_e := v_p[i].fit * (0.70 + 0.003 * v_p[i].cond)',
 'v_e := v_p[i].fit * (0.60 + 0.004 * v_p[i].cond)');
select public.sim_patch('public.mgr_match_create_before_world(bigint,uuid,character,jsonb)',
 'jsonb_build_array(round((0.90 + random() * 0.20)::numeric, 3), round((0.90 + random() * 0.20)::numeric, 3))',
 'jsonb_build_array(round((0.96 + random() * 0.08)::numeric, 3), round((0.96 + random() * 0.08)::numeric, 3))');

-- Dificuldade: o adversário da IA joga um percentual fixo acima do normal contra o técnico, seja qual for a diferença
-- de elenco (ai_gap_keep = 1 anula a parte proporcional). Assim a força do time continua valendo inteira.
-- Medido entre times iguais, jogando em casa: sem bônus 41% de vitórias; +8% → 32%; +14% → 27%.
-- Com 10 pontos de nota a mais: +8% → 51%; +14% → 49%.
update public.career_difficulty_levels set ai_gap_keep=1,ai_base_boost=.03,ai_match_mult=1.03,
 description='A IA joga 3% acima do normal contra você. Diretoria e torcida mais pacientes, receitas 10% maiores e verba 15% maior. Vale 15% menos no ranking.' where id='easy';
update public.career_difficulty_levels set ai_gap_keep=1,ai_base_boost=.08,ai_match_mult=1.08,
 description='A experiência padrão: a IA joga 8% acima do normal contra você.' where id='normal';
update public.career_difficulty_levels set ai_gap_keep=1,ai_base_boost=.14,ai_match_mult=1.14,
 description='A IA joga 14% acima do normal contra você. Cobrança maior, receitas 10% menores e verba 15% menor.' where id='hard';

-- Exercícios pré-jogo (4.000 moedas por 3 jogos) passam a pesar de verdade.
select public.sim_patch('public.cw_cm_match_prepare(bigint,uuid,character)',
 'set c_fin=c_fin*1.06,c_att=c_att*1.03 where','set c_fin=c_fin*1.14,c_att=c_att*1.07 where');
select public.sim_patch('public.cw_cm_match_prepare(bigint,uuid,character)',
 'set c_cre=c_cre*1.06,c_ctl=c_ctl*1.04 where','set c_cre=c_cre*1.14,c_ctl=c_ctl*1.09 where');
select public.sim_patch('public.cw_cm_match_prepare(bigint,uuid,character)',
 ']+0.06;',']+0.14;');
select public.sim_patch('public.cw_cm_match_prepare(bigint,uuid,character)',
 'set c_gk=c_gk*1.06,c_def=c_def*1.03 where','set c_gk=c_gk*1.14,c_def=c_def*1.07 where');
select public.sim_patch('public.cw_cm_match_prepare(bigint,uuid,character)',
 'set c_tack=c_tack*1.08,c_def=c_def*1.03 where','set c_tack=c_tack*1.16,c_def=c_def*1.07 where');
update public.cw_drill_rules set description=case kind
 when 'shooting' then 'Finalização 14% melhor e ataque 7% melhor nos próximos jogos.'
 when 'passing' then 'Criação 14% melhor e controle da posse 9% melhor.'
 when 'penalty' then 'Pênaltis e faltas bem mais certeiros.'
 when 'blocking' then 'Goleiro 14% melhor e defesa 7% melhor.'
 when 'tackling' then 'Desarme 16% melhor e defesa 7% melhor.' else description end;
