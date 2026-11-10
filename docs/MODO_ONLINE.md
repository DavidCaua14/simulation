# Modo Online — Fases 2 a 5

Situação em 10/11/2026. Tudo continua atrás do portão de testes (`on_config.public_open = false`): só o e-mail
em `on_config.testers` entra.

## Arquivos

| Fase | SQL (fonte) | Migration | Tela |
|---|---|---|---|
| 2 Partida ao vivo | `supabase/online/02_match.sql` | `20261110180000_online_phase2_match.sql` | `OnlineMatchLive.jsx`, `OnlineSquad.jsx` |
| 3 Leilões | `supabase/online/03_market.sql` | `20261110190000_online_phase3_market.sql` | `OnlineMarket.jsx` |
| 4 Clube | `supabase/online/04_club.sql` | `20261110200000_online_phase4_club.sql` | `OnlineClub.jsx`, `components/MiniGames.jsx` |
| 5 Copa e temporada | `supabase/online/05_cup_season.sql` | `20261110210000_online_phase5_cup_season.sql` | `OnlineCup.jsx` |

A migration é uma cópia literal do arquivo em `supabase/online/`. Altere o arquivo de `supabase/online/` e copie.

## Decisões tomadas (seção 9 do plano)

Todas ficam em `on_config` e podem mudar sem migration.

| Assunto | Decisão | Onde |
|---|---|---|
| Treino gasta condição | Sim: 6 pontos por sessão; a tela avisa no dia de jogo | `train_cond` |
| Caixa sem dinheiro para salários | A diferença vira dívida; dívida bloqueia lances; receitas pagam a dívida primeiro | `on_money` |
| Leilão | Sistema: 5 a 10 min; técnico: 10 min; cada lance garante 30 s; prorrogação máxima de 10 min | `lot_minutes`, `user_lot_minutes`, `lot_extend_max` |
| Conversão de moedas | 1 moeda = $ 1.000, até 300 por temporada | `coin_rate`, `coin_cap` |
| Nomes de jogadores | Mantido o gerador atual | — |
| Horários | Mantidos 16:00, 17:30, 19:00, 20:00, 21:00 e 22:00 | `on_seasons.slots` |
| Prêmios | Liga: $ 200 mil (1º) a $ 10 mil (12º); copa: $ 120/60/30 mil; moedas na conta: 300 a 10 (+100 pelo título da copa) | `league_prizes`, `cup_prizes`, `league_coins`, `cup_coins` |
| Segurança | Revogar o token de acesso do Supabase usado nesta etapa | painel do Supabase |

## Como o motor online foi gerado

`on_clone` lê `mgr_engine_run_v2`, `mgr_ai_manage_v2`, `mgr_do_sub`, `mgr_set_positions`, `mgr_rate` e `mgr_event`
em produção e troca nomes de tabelas e funções. Cada trecho tem de aparecer o número exato de vezes; no fim só
podem sobrar referências às funções puras (`mgr_pick`, `mgr_card_chances`, `mgr_tactical_effect`,
`mgr_tactics_clean`, `mgr_cond_factor`, `mgr_ai_tactics`) e ao tipo `mgr_ep`. Se o motor do modo Temporadas
mudar, a migration falha. Nenhuma função `mgr_*` ou `cw_*` é alterada.

Diferenças em relação ao modo Temporadas: o relógio é real, então expulsão e lesão não param a partida; o lado
presente tem 8 minutos de jogo para trocar o lesionado; os atributos do motor vêm da nota do jogador online
(mesma relação nota → atributo do catálogo, por posição).

## Testes

```bash
npm install --prefix /tmp/pglite @electric-sql/pglite
```

```bash
PGLITE_DIR=/tmp/pglite node scripts/test-online-db.mjs
```

```bash
PGLITE_DIR=/tmp/pglite node scripts/test-online-db.mjs --calibrate
```

O primeiro roda o esquema duas vezes e todos os casos (relógio, abertura, intervalo, fim único, suspensão,
duplo clique, cron, leilões, treino, salários, obras, moedas e uma temporada sandbox inteira com copa e virada).
O segundo também simula 500 partidas. Resultado em 10/11/2026: 2,39 gols, 5,3 amarelos, 0,12 vermelho e
27,6 finalizações por partida (motor Temporadas em produção: 2,9 / 4,0 / 0,1 / 27,3); pior trecho de 5 minutos
9 ms e pior bloco de 45 minutos 57 ms.

Prévia das telas sem Supabase: `npm run dev` e abrir `/tests/preview/online.html?step=3`.
`&live=200` coloca o próximo jogo em andamento (200 s depois do pontapé).

## Publicação

1. Aplicar `02` a `05` em produção, nessa ordem, numa transação, e registrar as quatro versões em
   `supabase_migrations.schema_migrations`.
2. Conferir: `select jobname from cron.job where jobname='on_tick'` e
   `select tick_hooks, finish_hooks from on_config`.
3. Só então publicar o app.
4. Testar na sandbox: assistir uma partida inteira, mexer no time, sair e voltar, dar lance, treinar.
   Para jogos a cada 15 minutos, recriar a sandbox com `p_gap => interval '15 minutes'`.

A abertura para os 5 técnicos (seção 7 do plano) fica para depois do teste na sandbox.
