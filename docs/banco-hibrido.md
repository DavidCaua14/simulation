# Banco híbrido (Fase 2 do plano de temporadas)

Objetivo: cada carreira grava só o que mudou em relação ao catálogo `sim_*`. Meta: até 3 MB por carreira após 3 temporadas.

Migrações: `20261106000000_hybrid_players.sql` (estrutura), `20261106010000_hybrid_functions.sql` (funções ajustadas),
`20261106070000_compact_pos_ratings.sql` (notas por posição compactas).

## Modelo

| Nome lido pelas funções | Agora | Linhas gravadas |
| --- | --- | --- |
| `mgr_players` | view: `mgr_player_rows` + atletas do catálogo dos clubes em `cw_world_clubs` | atleta que mudou de clube, tem lesão, suspensão, cartões, condição < 100 ou ritmo fora do padrão; elenco do técnico sempre |
| `cw_players` | view: `cw_player_rows` + `sim_player_base` | atleta com moral, número, listagem, aposentadoria ou valor próprios |
| `cw_contracts` | view: `cw_contract_rows` + contrato calculado (`computed = true`) | contratos negociados, encerrados, com atraso ou bônus; elenco do técnico sempre |
| `sim_player_pos_ratings` | view: `sim_player_ratings` (uma linha por atleta, vetores por posição) | catálogo |
| `cw_player_clock` | tabela, só para quem tem linha em `mgr_player_rows` | |

- O ramo do catálogo vale só para carreiras com `cw_runtime.hybrid = true` (novas e reiniciadas). `cw_is_hybrid()` usa `cw_runtime_rules.hybrid_default` quando o runtime ainda não existe.
- Gatilhos `INSTEAD OF` nas views gravam a diferença e **apagam a linha quando ela volta ao padrão**. Apagar um atleta do catálogo grava uma linha `removed = true`.
- `sim_player_base` guarda os valores iniciais de cada atleta do catálogo (idade, potencial, papel, salário, anos de contrato). Atualize com `sim_player_base_refresh()` depois de mudar o catálogo.
- Contrato calculado: id `md5(carreira||':'||atleta)`, começa no início do mundo e renova sozinho em ciclos do mesmo tamanho, sempre até 31/12. Quando o técnico assume um clube (`cw_materialize_own_contracts`), os contratos desse elenco viram linhas reais e passam a vencer.
- Views não aceitam `FOR UPDATE` nem `ON CONFLICT`: as funções que usavam isso foram ajustadas (a trava da carreira em `mgr_lock` já serializa as escritas). Buscas de contrato por `id` levam também `career_id`.

## Atributos calculados (migração `20261106090000_generated_attrs.sql`)

- `sim_player_attrs` virou view: `sim_players` + `sim_player_attr_rows` (linhas próprias). Sem linha própria, os 16 atributos
  são calculados de `sim_players.attr_pos` + `attr_level` pela mesma conta do `build-squads.mjs`
  (perfil em `sim_attr_template` + `sim_hash01`). Resultado idêntico aos valores antigos (conferido nos 3.024 atletas).
- Linha própria sempre vence: curados (`estimated = false`), jovens da base (`method = 'regen'`) e qualquer
  `insert`/`update` feito na view (gatilho `sim_player_attrs_write`). `delete` na view apaga a linha e zera `attr_level`.
- Novo atleta de catálogo precisa só de `attr_pos` e `attr_level`: é a base do nível B (ligas de fundo).
- Evite `to_jsonb(view)` repetido por linha de peso: materialize os atributos uma vez (ver `sim_refresh_ratings`).

## Simulação

- Jogo entre dois clubes da IA (`cw_sim_ai_fixture`): força pelo melhor XI (`cw_club_strength`), placar pela mesma Poisson com semente, pênaltis e prorrogação. Grava o placar e a súmula curta (gols) em `season_fixtures.stats`, gols e assistências em `mgr_player_stats` e cartões em `season_card_totals`. Não cria `mgr_matches`, `mgr_match_players`, eventos nem atuações.
- Atletas da IA não perdem condição, ritmo nem moral, e não recebem lesão ou suspensão. Quem já tinha linha volta ao padrão aos poucos (`cw_recover_club`).
- Evolução da IA: por trimestre, só a nota (`cw_player_dev.d_rating`), sem atributos detalhados nem histórico. O elenco do técnico evolui todo mês, com atributos e histórico.
- Moral semanal, psicólogo e reavaliação anual de valor: só para o elenco do técnico e quem tem linha própria.

## Retenção (cron de manutenção, fora do clique)

- `cw_archive_old_seasons`: de cada região fica o detalhe só da última temporada encerrada. Das anteriores ficam `career_seasons`, `season_competitions`, `season_final_tables` e os artilheiros em `mgr_player_stats`.
- `cw_hybrid_trim`: receita por jogo já paga dos clubes da IA, histórico de negociações encerradas entre clubes da IA e decisões diárias antigas da IA.
- `cw_appearances` por partida só para o clube do técnico.
