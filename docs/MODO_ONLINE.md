# Modo Online — Fases 2 a 6

Situação em 10/11/2026. Tudo continua atrás do portão de testes (`on_config.public_open = false`): só o e-mail
em `on_config.testers` entra.

## Arquivos

| Fase | SQL (fonte) | Migration | Tela |
|---|---|---|---|
| 2 Partida ao vivo | `supabase/online/02_match.sql` | `20261110180000_online_phase2_match.sql` | `OnlineMatchLive.jsx`, `OnlineSquad.jsx` |
| 3 Leilões | `supabase/online/03_market.sql` | `20261110190000_online_phase3_market.sql` | `OnlineMarket.jsx` |
| 4 Clube | `supabase/online/04_club.sql` | `20261110200000_online_phase4_club.sql` | `OnlineClub.jsx`, `components/MiniGames.jsx` |
| 5 Copa e temporada | `supabase/online/05_cup_season.sql` | `20261110210000_online_phase5_cup_season.sql` | `OnlineCup.jsx` |
| 6 Experiência de clube | `supabase/online/06_experience.sql` | `20261111120000_online_phase6_experience.sql` | todas (ver abaixo) |

A migration é uma cópia literal do arquivo em `supabase/online/`. Altere o arquivo de `supabase/online/` e copie.

## Decisões tomadas (seção 9 do plano)

Todas ficam em `on_config` e podem mudar sem migration.

| Assunto | Decisão | Onde |
|---|---|---|
| Treino gasta condição | Sim: 6 pontos por sessão; a tela avisa no dia de jogo | `train_cond` |
| Caixa sem dinheiro para salários | A diferença vira dívida; dívida bloqueia lances; receitas pagam a dívida primeiro | `on_money` |
| Leilão | Mudou na Fase 6 (destaques por hora; técnico: 60 min; cada lance garante 5 min; teto de 6 h) | `featured_*`, `user_lot_minutes`, `bid_extend`, `lot_extend_max` |
| Conversão de moedas | 1 moeda = $ 1.000, até 1.000 por temporada (300 até a Fase 5) | `coin_rate`, `coin_cap` |
| Nomes de jogadores | Mantido o gerador atual | — |
| Horários | 09:00, 10:00, 11:00, 14:00, 15:30 e 17:00 desde a Fase 6 | `on_seasons.slots` |
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

## Fase 6 (11/11/2026): experiência de clube

A Fase 6 redefine funções das fases anteriores com `create or replace`. Os arquivos `01` a `05` não mudaram.

| Assunto | Regra | Onde |
|---|---|---|
| Moldura | O modo usa `AppShell` (coluna de 430 px no computador, como o modo Temporadas). O voltar do topo leva ao Início do modo; sair é o botão "Sair do modo Online" | `OnlineScreen.jsx`, `online-v2.css` |
| Horários | 09:00, 10:00, 11:00, 14:00, 15:30 e 17:00 (padrão de `on_seasons.slots`) | `06_experience.sql` |
| Craques | Cartas com retrato, nota e seis atributos. O id do craque é fixo (`on_star_id`), então a carta mostrada é a do jogador contratado | `on_draft_read`, `on_card`, `OnlineDraft.jsx` |
| Leilões em destaque | Sempre 3 jogadores do sistema (faixas 77–85, 70–77 e 62–70), os mesmos para todos, das 08:00 às 22:59. Cada um fica até a virada da hora; sem lances, o jogador é apagado e entra outro. Cada lance garante mais 5 minutos (`bid_extend`), até 6 horas depois do fim original (`lot_extend_max`) | `on_market_tick`, `on_gen_featured` |
| Bots no leilão | Só entram depois do lance de um técnico, nos últimos 3 minutos, até 70% a 90% do valor | `on_market_tick` |
| Resultado do leilão | Todo técnico que deu lance recebe um aviso `auction` com vencedor e preço. A tela inicial mostra até ser visto | `on_lot_settle`, `on_status.results`, `on_news_seen` |
| Moedas | Investir: 1 moeda = $ 1.000 (`coin_rate`), teto de 1.000 por temporada (`coin_cap`). Lance direto com moedas: 1 moeda = $ 600 (`coin_bid_rate`), só a diferença que falta no caixa livre; as moedas viram caixa e não voltam | `online_coins_convert`, `on_bid(p_lot,p_amount,p_coins)` |
| Identidade | Nome, sigla (2 a 4), duas cores, desenho e formato do escudo e estádio, tudo em `on_clubs.colors` | `on_club_identity`, `OnlineClub.jsx` |
| Treino | Seis mini-games (finalização, passes, desarme, reflexo, drible, explosão). 1 jogador rende 150%, 2 a 6 rendem 100%, 7 a 11 rendem 65% | `on_train_scale`, `MiniGames.jsx` |
| Partida | Consulta a cada 20 s e tela ~3 minutos de jogo atrás do servidor (antes 40 s e ~6 minutos). Barra de postura (defensivo, equilibrado, ofensivo, contra-ataque) muda a tática na hora | `OnlineMatchLive.jsx`, `onlineUtils.js` |

### Campo 2D (`src/features/match2d/director.js`, usado também no modo Temporadas)

Só apresentação: placar e eventos continuam vindo do motor no servidor.

- Finalização: quem recebe para chutar conduz até a zona de chute (gol de 8 a 17 m). Longe demais, faz uma tabela.
- Impedimento: o time leva a bola ao campo de ataque e lança um atacante nas costas do último zagueiro.
  Se o lance não se forma, o impedimento aparece só no relato.
- Cartão: o adversário precisa estar com a bola; o infrator chega no lance, há o choque, a falta, o cartão, a
  barreira e a cobrança.
- Escanteio: parte das defesas vira espalmada para fora e parte dos chutes travados sai pela linha de fundo.
  A cobrança termina em corte da zaga, saída do goleiro ou cabeçada por cima. Não gera evento nem estatística.
- Postura: `setStyle` sobe ou recua o bloco conforme a tática do lado.
- Com mais de 3 lances na fila (relógio que não espera), os menos importantes aparecem só no relato.

Medição com 400 lances simulados sem tela (antes → depois): distância do chute de gol, mediana 31 m e máximo
59 m → mediana 16 m e máximo 20 m; bola no impedimento a 62 m do gol → 9 m; nenhum roteiro preso.

### Reiniciar o modo

`supabase/releases/online_reiniciar.sql` apaga a temporada (só tabelas `on_*`) e cria outra com os técnicos de
teste, que voltam para a escolha dos craques.
