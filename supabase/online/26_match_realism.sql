-- MODO ONLINE — Fase 24: partidas mais fiéis ao que foi configurado e estatísticas corretas.
--
-- Problemas medidos no banco de produção (rodada 5 da temporada 5 e 200 jogos simulados por cenário):
--  • Estatísticas: a tela contava finalizações e chutes no gol pelos lances gravados. Quando ninguém assiste, o motor
--    não grava cada chute (só gols e defesas difíceis), então um jogo de 11 x 9 finalizações aparecia como 0 x 1.
--    on_match_payload passa a mandar finalizações e chutes no gol somados da súmula dos jogadores.
--  • Táticas do técnico ausente: on_ai_manage tratava todo lado sem ninguém assistindo como bot e, a partir dos 60
--    minutos, trocava postura, ritmo, pressão e gestão do jogo do clube de um usuário. Agora clube de usuário mantém
--    as táticas dele (inclusive a "gestão do jogo", que o motor já aplica conforme o placar); o auxiliar só faz
--    substituições por cansaço, cartão ou lesão.
--  • Atacar não tinha custo: postura +2 com pressão alta e ritmo rápido levava um time igual de 39% para 56% de
--    vitórias sem sofrer um gol a mais. Agora quem se lança ao ataque deixa espaço: o adversário cria mais e chuta
--    melhor nos contra-ataques.

-- 1) Estatísticas da partida: finalizações e chutes no gol vêm da súmula (iguais com ou sem alguém assistindo).
do $$ begin
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''saves'',jsonb_build_array(coalesce(sum(saves) filter(where side=''h''),0),coalesce(sum(saves) filter(where side=''a''),0)),',
  '''saves'',jsonb_build_array(coalesce(sum(saves) filter(where side=''h''),0),coalesce(sum(saves) filter(where side=''a''),0)),
   ''shots'',jsonb_build_array(coalesce(sum(shots) filter(where side=''h''),0),coalesce(sum(shots) filter(where side=''a''),0)),
   ''sot'',jsonb_build_array(coalesce(sum(sot) filter(where side=''h''),0),coalesce(sum(sot) filter(where side=''a''),0)),');
end $$;

-- 2) Técnico ausente: o clube de um usuário joga com as táticas que ele deixou; o auxiliar só substitui.
do $$ begin
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  v_max   int := case when p_minute >= 75 then 3 else 2 end;',
  '  v_max   int := case when p_minute >= 75 then 3 else 2 end;
  v_human boolean;');
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  -- postura
  v_ment := v_base;',
  '  -- clube de usuário: as táticas são as do técnico (a "gestão do jogo" dele já reage ao placar no motor)
  select c.user_id is not null into v_human from public.on_fixtures f
    join public.on_clubs c on c.id = case when p_side = ''h'' then f.home else f.away end where f.id = p_fixture;
  v_human := coalesce(v_human, false);
  -- postura
  v_ment := v_base;');
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  if v_ment <> coalesce((v_m.state -> ''tactics'' -> p_side ->> ''mentality'')::int, 0) then',
  '  if v_human then v_ment := coalesce((v_m.state -> ''tactics'' -> p_side ->> ''mentality'')::int, v_base);
  elsif v_ment <> coalesce((v_m.state -> ''tactics'' -> p_side ->> ''mentality'')::int, 0) then');
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  if p_minute>=60 then',
  '  if p_minute>=60 and not v_human then');
end $$;

-- 3) Quem ataca deixa espaço: cada nível de postura ofensiva (+1, +2) dá ao adversário mais contra-ataques
--    e finalizações mais limpas; pressão alta com a linha alta deixa as costas da defesa ainda mais expostas.
do $$ begin
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '                  * v_freq[s];
    v_pa := greatest(0.05, least(0.55, v_pa));',
  '                  * v_freq[s] * (1 + 0.05 * greatest(0, v_ment[d]));
    v_pa := greatest(0.05, least(0.55, v_pa));');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '                 + v_qual[s] + 0.5 * (v_form[s] / v_form[d] - 1) + random() * 0.35',
  '                 + v_qual[s] + 0.5 * (v_form[s] / v_form[d] - 1) + random() * 0.35
                 + 0.03 * greatest(0, v_ment[d]) + case when v_tpress[d] = ''high'' and v_tline[d] = ''high'' then 0.02 else 0 end');
end $$;
