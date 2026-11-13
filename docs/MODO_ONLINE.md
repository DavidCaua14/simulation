# Modo Online — Fases 2 a 10

Situação em 12/11/2026: o modo está aberto para todos (`on_config.public_open = true`). Para fechar de novo:
`update public.on_config set public_open=false;` (volta a valer a lista `on_config.testers`).

## Arquivos

| Fase | SQL (fonte) | Migration | Tela |
|---|---|---|---|
| 2 Partida ao vivo | `supabase/online/02_match.sql` | `20261110180000_online_phase2_match.sql` | `OnlineMatchLive.jsx`, `OnlineSquad.jsx` |
| 3 Leilões | `supabase/online/03_market.sql` | `20261110190000_online_phase3_market.sql` | `OnlineMarket.jsx` |
| 4 Clube | `supabase/online/04_club.sql` | `20261110200000_online_phase4_club.sql` | `OnlineClub.jsx`, `components/MiniGames.jsx` |
| 5 Copa e temporada | `supabase/online/05_cup_season.sql` | `20261110210000_online_phase5_cup_season.sql` | `OnlineCup.jsx` |
| 6 Experiência de clube | `supabase/online/06_experience.sql` | `20261111120000_online_phase6_experience.sql` | todas (ver abaixo) |
| 7 Jogadores reais | `supabase/online/07_real_players.sql` | `20261112120000_online_phase7_real_players.sql` | ver abaixo |
| 8 Preparação para o jogo | `supabase/online/08_preparation.sql` | `20261112130000_online_phase8_preparation.sql` | `OnlinePrep.jsx` |
| 9 Lendas e mercado | `supabase/online/09_market_legends.sql`, `10_legends_data.sql` | `20261112140000_…`, `20261112150000_…` | ver abaixo |

A migration é uma cópia literal do arquivo em `supabase/online/`. Altere o arquivo de `supabase/online/` e copie.

## Decisões tomadas (seção 9 do plano)

Todas ficam em `on_config` e podem mudar sem migration.

| Assunto | Decisão | Onde |
|---|---|---|
| Treino gasta condição | Sim: 6 pontos por sessão; a tela avisa no dia de jogo | `train_cond` |
| Caixa sem dinheiro para salários | A diferença vira dívida; dívida bloqueia lances; receitas pagam a dívida primeiro | `on_money` |
| Leilão | Mudou na Fase 6 (destaques por hora; técnico: 60 min; cada lance garante 5 min; teto de 6 h) | `featured_*`, `user_lot_minutes`, `bid_extend`, `lot_extend_max` |
| Conversão de moedas | 1 moeda = $ 1, sem teto por temporada; limitado ao saldo da carteira | `coin_rate`, `coin_cap` |
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
| Moedas | Investir e completar lances: 1 moeda = $ 1 (`coin_rate` e `coin_bid_rate`). Ambos permitem usar todo o saldo da carteira, sem teto por temporada. `coins_conv` é apenas histórico acumulado em bigint; `coins.unlimited` indica a ausência de teto. As moedas viram caixa e não voltam quando o lance é coberto | `online_coins_convert`, `on_bid(p_lot,p_amount,p_coins)` |
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

### Publicação da Fase 6

1. Rodar `supabase/releases/online_fase_6.sql` no SQL Editor (aplica a fase e registra a versão `20261111120000`).
   O app antigo continua funcionando com o banco novo.
2. Publicar o app (merge do branch).
3. Rodar `supabase/releases/online_reiniciar.sql` para recomeçar com a escolha dos craques.

## Fase 7 (12/11/2026): jogadores reais e ajustes

| Assunto | Regra | Onde |
|---|---|---|
| Jogadores reais | Elencos, craques e leilões vêm de `sim_players` + `sim_player_base` (linhas sem `career_id`). `on_players.src` guarda o id do catálogo e tem índice único: cada jogador real existe uma vez no modo. Sem real livre na faixa, entra um gerado | `on_real_pick`, `on_real_insert`, `on_gen_squad`, `on_star_add` |
| Faixas de nota | Elenco base: nota do clube ±4 (técnico 62; bot 60 a 64). Craques do técnico 78 a 82; dos bots 76 a 80. Leilão: 77–85, 70–77, 62–70 | `07_real_players.sql` |
| Craques | As nove opções ficam reservadas (`hold`, `hold_slot`) até a escolha; as duas não escolhidas de cada linha voltam a ficar livres | `on_draft_prepare`, `on_draft_pick` |
| Leilão | Todo lance põe o relógio em 5 minutos (`bid_extend`), mesmo que faltasse mais; teto em `hard_end` | `on_bid_as` |
| Venda | O técnico não leiloa jogador do elenco. Venda direta por 60% do valor; o jogador sai do modo e, se for real, volta a ficar livre | `on_sell` (as funções `on_lot_create` e `on_lot_cancel` ficaram sem permissão para o app) |
| Energia de treino | 40 moedas da conta por treino extra no dia, até 5 por dia. Na Loja (aba Treino) e na tela de treino | `online_train_energy_buy`, `train_energy_cost`, `train_energy_max`, `TrainEnergyTab.jsx` |
| Pênaltis | Mini-game individual (grupo de ataque): 5 cobranças, arrastando até o canto; o goleiro tenta adivinhar | `MiniGames.jsx`, `on_train_start` |
| Aviso de jogo | Em qualquer tela do jogo, aviso 10 e 5 minutos antes do pontapé. Não aparece no vestiário nem na partida. Só para quem tem acesso ao modo | `OnlineKickoffAlerts.jsx`, `App.jsx` |
| Vestiário | Quando o relógio zera, a tela mostra "A partida vai começar" até a partida abrir | `OnlineMatchLive.jsx` |

`on_squad`, `on_lot_json`, `on_club` e `on_status` recebem os campos novos por `on_patch`, que troca um trecho do
texto da função e falha se o trecho não aparecer exatamente uma vez.

Os testes usam um catálogo fictício de 3.000 jogadores (`tests/support/stub.sql`).

## Fase 8 (12/11/2026): preparação para o jogo

Motivo: dar ao técnico o que fazer entre um jogo e outro, com efeito real em campo.

| Tarefa | Vale | Como conta |
|---|---|---|
| Escalação | 30 | Salvar ou montar a escalação depois do último jogo (`on_lineup_save`, `on_lineup_auto`) |
| Treino | 15 por sessão, até 30 | Sessões concluídas com resultado acima de zero desde o último jogo |
| Adversário | 20 | Abrir o relatório do olheiro (`on_scout`): formação, postura, campanha, força por setor e os 3 melhores |
| Preleção | 20 | Escolher uma das três (`on_team_talk`); a escolha é só de estilo, as três valem o mesmo |

- No pontapé (`on_prep_apply`, chamado por `on_match_open`) o percentual multiplica a forma do time: até +3%
  (`prep_bonus`). A forma sorteada vai de 0,90 a 1,10, então o bônus pesa mas não decide sozinho.
- 100% rende 5 moedas na conta (`prep_coins`) e soma na sequência. A cada 5 jogos seguidos com 100%
  (`prep_streak_every`), mais 30 moedas (`prep_streak_coins`). Menos de 100% zera a sequência.
- A partida mostra o preparo do técnico ("preparo 85% (+2,55%)"). Bots não têm preparação.
- As marcas ficam em `on_clubs.prep` e valem só para o próximo jogo.

## Fase 9 (12/11/2026): lendas, especial do dia e ajustes de tela

| Assunto | Regra | Onde |
|---|---|---|
| CSS | Um arquivo só (`online.css`). Com dois arquivos, o build de produção carregava o antigo por último e desfazia o layout novo (cartas em coluna, botões sobre o menu). Para conferir, gere a prévia com build de produção | `online.css` |
| Catálogo | `on_pool`: reais com nota-base (6.058), reais só com nível `attr_level` (2.594, antes fora do modo) e lendas (`on_legends`, 338 aposentados escritos à mão) | `09_market_legends.sql`, `10_legends_data.sql` |
| Tipos de carta | Normal até 80 (aço), especial 81+ (roxo), lenda (preto e dourado) | `cardTier`, `online.css` |
| Leilões comuns | Três, sempre até 80: 74–80, 68–74, 62–68 | `on_gen_featured` |
| Especial do dia | Criado na primeira hora do dia, travado, mostrando o horário; abre às 19:00 (`special_hour`) e dura uma hora (mais 5 min a cada lance). A cada três dias é uma lenda. Bots não disputam | `on_market_tick`, `on_gen_special` |
| Preço | Especial: $ 400 mil + $ 40 mil por ponto acima de 80. Lenda: $ 600 mil + $ 50 mil por ponto acima de 85 | `on_start_price` |
| Moedas | Teto de investimento por temporada: 5.000. Investir pede confirmação | `coin_cap`, `OnlineClub.jsx` |
| Energia de treino | Estoque (`on_clubs.train_energy`). Os 3 treinos do dia são grátis; cada treino além deles gasta 1. Compra: 1 por 40 moedas ou pacotes por diamantes (5/15, 20/50, 50/100), na tela de treino e na Loja | `online_train_energy_buy(p_pack)`, `energy_packs` |
| Treino | Dois passos: toque no mini-game, depois escolha quem treina e comece. Sem energia, abre a tela que explica como conseguir mais | `OnlineClub.jsx` |
| Pênaltis | Toque no gol para mirar; segure o botão para dar força. Força baixa: fácil de defender. Força demais: a bola sobe e abre, podendo sair. O goleiro escolhe um lado e precisa alcançar a bola | `MiniGames.jsx` |
| Melhor time | Escolhe a melhor dupla jogador-vaga a cada passo; goleiro só no gol | `on_auto_lineup` |
| Dispensar | Em Elenco > Jogadores. O clube recebe 60% do valor e o jogador volta a ficar livre para leilão | `on_sell` |
| Vestiário | Posição e formação dos dois times, confronto por setor, destaques e preparação | `OnlineMatchLive.jsx`, `on_scout(false)` |
| Preleção do intervalo | Seis conversas. O efeito na forma do segundo tempo (de -4,5% a +5%, mais um sorteio de ±0,8%) depende do saldo e de quem é o favorito | `on_talk_effect`, `on_match_talk` |

Tabela da preleção (saldo no intervalo): elogiar ajuda vencendo por pouco e atrapalha perdendo; pedir foco ajuda
vencendo; cobrar mais ajuda no empate como favorito ou perdendo por 1, e atrapalha vencendo por 2 ou perdendo por
3; incentivar ajuda perdendo por 1 ou 2; tirar a pressão ajuda o azarão que perde ou a goleada sofrida; bronca
ajuda perdendo por 2 ou mais sem ser azarão e atrapalha muito vencendo.

## Fase 10 (12/11/2026): abertura para todos

| Assunto | Regra | Onde |
|---|---|---|
| Acesso | `public_open = true`. O cartão e a aba do modo deixaram de ser só do dono; os avisos de jogo valem para todos | `App.jsx`, `home/data/gameModes.js`, `home/data/tabs.js` |
| Entrada na hora | Quem entra com a temporada em andamento assume o clube de bot pior colocado que não esteja jogando nem liderando leilão. Recebe elenco real novo (19), $ 150 mil e a escolha dos três craques; o clube mantém calendário e pontos. Se o jogo chegar antes da escolha, o time entra com os 19 | `on_join_queue`, `join_instant` |
| Liga cheia | Com os 12 clubes ocupados por técnicos, o próximo entra na fila e assume um clube na virada da temporada | `on_join_queue`, `on_season_end` |
| Mercado | Quatro leilões comuns até 80 (76–80, 72–76, 68–72, 63–68). Todo dia um destaque (81+, 19:00) e uma lenda (20:00), visíveis e travados desde cedo | `on_market_tick`, `on_gen_featured`, `on_gen_special` |
| Copa | As quartas usam os quatro clubes que folgaram na primeira fase. Antes recalculavam os quatro primeiros da liga e um clube podia ficar fora ou entrar duas vezes | `on_cup_stage`, `on_cup` (via `on_patch`) |
| Fim de partida | Painel com resultado, escudos, melhor em campo e botão | `OnlineMatchLive.jsx` (`.onm-final`) |
| Anúncio | Tela "O modo Online chegou", uma vez por carreira, com botão que leva ao modo | `update/OnlineNews.jsx`, `ONLINE_NEWS_RELEASE` |

Limite atual: uma liga de 12 clubes. Com mais de 12 técnicos ativos será preciso criar ligas paralelas
(em 12/11/2026 havia 9 contas com carreira).

### Equilíbrio da economia online (12/11/2026)

Aplicado em produção, nesta ordem: `online_economy_shared_season_cap` e `online_investments_unlimited_one_to_one`. Os scripts correspondentes estão em `supabase/releases/online_economia_equilibrada.sql` e `supabase/releases/online_aportes_sem_limite.sql`; executar atomicamente e uma única vez após a Fase 10 em instalações novas. A segunda atualização prevalece: câmbio 1:1, sem limite de aporte por temporada, conforme solicitado.

A conversão antiga registrada foi estornada com devolução integral das moedas e lançamento compensatório no extrato, sem apagar o histórico. Carteiras pessoais, prêmios, jogadores e temporadas foram preservados. O saldo é validado no servidor e bloqueado durante o débito, impedindo gasto duplicado por chamadas simultâneas.

Os payloads mantêm compatibilidade com clientes antigos: `cap - converted` equivale ao saldo atual da carteira. O campo de configuração `coin_cap` permanece por compatibilidade, mas não restringe aportes ou lances. A interface nova oferece aportes de 1.000, 10.000, 30.000 ou todo o saldo, além de um campo para digitar qualquer quantidade disponível.

Verificação: `supabase/online/tests/economy_regression.sql`, com testes revertidos ao final.

### Acesso temporário a Temporadas

O modo Temporadas está indisponível para o público; somente a conta `contatodavidcaua@gmail.com` mantém acesso. A interface mostra cadeado no banner e no menu e bloqueia a navegação. A migration `20261112165026_restrict_seasons_to_owner.sql` protege as RPCs públicas de Temporadas, conferindo `auth.uid()` contra o email armazenado em `auth.users`. Não usa metadados editáveis e não apaga progresso. O modo Online e as carteiras permanecem disponíveis.
## Fase 11 — ranking pelo online, horário do mercado e rodadas a cada 7 horas (13/11/2026)

Fonte: `supabase/online/12_ranking_market_hours.sql` (migração `20261113130000`, pacote `supabase/releases/online_fase_11.sql`).

- **Ranking geral**: só o modo online pontua. `on_ranking` guarda os pontos por usuário; `on_rank_hook` soma a cada partida e `on_rank_season` no fim da temporada. Regras em `on_config.rank_rules`: vitória 30 (+10 contra outro técnico), empate 10, 2 por gol (até 5 por jogo), 5 por jogo sem sofrer gol, 5 por preparação completa; liga 1000/600/400/250/150/100/50/50; copa 400 (campeão), 200 (vice), 80 (semifinal). `ranking_overall` devolve as regras para a tela.
- **Moedas por resultado**: `win_coins` (15) e `draw_coins` (5) caem na conta do técnico.
- **Horário do mercado**: `market_open` (8) a `market_close` (23), no fuso da temporada. Fora dele não há lance, anúncio nem leilão novo; `on_market` devolve `hours`.
- **Destaque e lenda**: trocam a cada `special_every` horas (janelas 08–13, 13–18, 18–23). Ficam à mostra travados; o destaque abre na penúltima hora da janela e a lenda na última.
- **Bots**: não dão lance em destaque nem em lenda (recusa em `on_bid_as`). No pontapé usam `on_bot_lineup`: testa cada formação e fica com a que soma mais nota em campo.
- **Leilão do próprio jogador**: `on_lot_create` voltou para o técnico. Uma hora, lance inicial de 50% a 300% do valor (`on_lot_range`), sem lance do dono, cada lance põe o relógio em 5 minutos. Sem lances, um bot paga o preço pedido só se ele for até 80% do valor; acima disso o jogador volta ao elenco.
- **Calendário**: rodada a cada `round_gap` (7 horas), jogos da rodada espaçados em `match_stagger` (10 minutos). A fase K da copa entra meia janela depois da rodada 5K. A condição física recupera 5 pontos por hora.
- **Força do clube** (`on_strength`): média de titulares e reservas relacionados. A tela de escalação mostra força dos onze, com reservas e do banco.
- **Idade**: não sobe mais na virada de temporada.

## Fase 12 — mercado das 08:00 às 18:30

Fonte: `supabase/online/13_market_hours_minutes.sql` (migração `20261113150000`). `on_config.market_close_min` guarda os minutos do fechamento (18 + 30). `on_market_hours` devolve `open_label` e `close_label`. As janelas de destaque e lenda passam a ser duas por dia: 08–13 (destaque 11:00, lenda 12:00) e 13–18 (destaque 16:00, lenda 17:00). A tela de escalação mostra a mesma "Força geral" do início do modo (média de titulares e reservas).

## Fase 13 — prêmios em moedas e confronto direto

Fonte: `supabase/online/14_coin_prizes_head_to_head.sql` (migração `20261113170000`).

- Vitória rende 5.000 moedas e empate 1.500 (`win_coins`, `draw_coins`).
- Fim de temporada: o técnico recebe moedas pela colocação (`league_coins`: 500 mil, 400 mil, 320 mil … 40 mil) e pela copa (`cup_coin_prizes`: 250 mil, 120 mil, 60 mil). O caixa do clube dele não recebe prêmio; bots continuam recebendo em caixa.
- Ranking: vencer outro técnico soma 20 além dos 30 da vitória; perder para outro técnico tira 15 (`rank_rules.human`, `human_loss`).
- Energia de treino com moedas custa 5.000.
- O aviso de leilão encerrado abre em qualquer aba (a tela consulta o servidor a cada 15 a 30 segundos).

## Fase 14 — nada passa do fechamento

Fonte: `supabase/online/15_market_close_cleanup.sql` (migração `20261113180000`). Leilão do mercado marcado para depois do fechamento é retirado; o último leilão comum do dia termina no fechamento; lance perto do fechamento não empurra o relógio para depois dele.

## Fase 15 — escalações do jogo e ficha do jogador

Fonte: `supabase/online/16_fixture_lineups.sql` (migração `20261113190000`). `on_fixture_lineups(fixture)` devolve formação e onze de cada lado: antes do pontapé, a escalação salva; com a partida aberta, quem está em campo agora. A tela (`LineupsSheet`) abre no vestiário ("Ver escalações") e durante o jogo ("Adversário") e se atualiza sozinha. Em Elenco > Jogadores, tocar em um atleta abre a ficha (`PlayerSheet`) com nota atual, potencial, valor, salário, contrato e as ações de leiloar, renovar e dispensar. O botão Novidades do Perfil aparece para todos.

## Fase 17 — recuperação por hora, obras rápidas e bilheteria

Fonte: `supabase/online/18_recovery_gate_build.sql` (migração `20261114140000`).

- Condição física: +6 por hora, mais +1,5 por hora a cada nível do departamento médico (`on_recovery_rate`). Entre duas rodadas (7 horas): 42 pontos sem médico, 73 no nível 3, 94 no nível 5. O bônus diário do médico saiu.
- Lesão: 1 ou 2 dias; com médico nível 3 ou mais, sempre 1 dia.
- Obras: 1 hora por nível (`on_build_time`), de 1 h a 5 h. Obras em andamento foram encurtadas para o prazo novo.
- Bilheteria por jogo em casa: $ 15 mil + $ 10 mil por nível do estádio (`on_gate_value`); copa paga 50% a mais.

## Fase 18 — bots dão lance como um técnico

Fonte: `supabase/online/19_bot_bidding.sql` (migração `20261114160000`). `on_bot_limit(clube, leilão, jogador)` devolve o teto de cada bot: 0 se o jogador não melhora o elenco (nota abaixo da força do clube menos 2, ou menos 6 em posição carente) ou se aquele clube não entrou na disputa (perfil fixo por leilão e clube, 45% de chance); senão, entre 50% e 90% do valor. O bot só cobre lance até o próprio teto, e só compra jogador anunciado por técnico se tiver interesse.
