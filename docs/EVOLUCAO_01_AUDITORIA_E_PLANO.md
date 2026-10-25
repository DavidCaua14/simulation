# Evolução completa — Etapa 1: auditoria técnica e plano

Data da auditoria: 25/10/2026. Base analisada: `main` em `5b010dd` (após o PR #8, cartas automáticas).

Este documento é o inventário pedido na Etapa 1 do "Projeto de evolução completa". Ele descreve o que existe hoje,
o que é real, o que é temporário e em que ordem as próximas etapas serão feitas. Ao final de cada etapa, um
documento `docs/EVOLUCAO_NN_*.md` registra o que mudou, os testes e as pendências.

---

## 1. Tecnologias

| Camada | O que é usado |
|---|---|
| Frontend | React 19 + Vite 8 (SPA, sem roteador: `App.jsx` troca de tela por estado). Ícones `lucide-react`; avatares `@dicebear`. CSS por feature (sem framework). |
| Backend | Supabase: Postgres + Auth + Realtime + Edge Functions (Deno). **Toda regra de jogo roda no banco** em funções `plpgsql security definer`; o app só lê tabelas (RLS) e chama RPCs. |
| Funções externas | `supabase/functions/sync-matches` e `sync-odds` (cron) alimentam os palpites com jogos reais. |
| Testes | `supabase/manager/tests/manager_tests.sql` (T0–T6, roda dentro de `BEGIN … ROLLBACK`). Testes de interface feitos com Playwright num ambiente local (Postgres 16 + ponte HTTP), não versionados no app. Não há suíte JS no `package.json`. |

## 2. Autenticação e identidade

* Supabase Auth (e-mail/senha e provedores do painel). `auth.uid()` identifica o usuário em todas as RPCs.
* Cada usuário tem **uma** linha ativa em `careers` (`user_id`, `nickname` único, `country`, `photo_id`, `level`, `xp`,
  `coins`, `energy`, `bonus_energy`, `diamonds`, `club_id`, `created_at`).
* Permissões atuais em `careers` (verificadas em produção): o papel `authenticated` só pode **inserir** (colunas
  `user_id, nickname, age, country, photo_id`) e **ler** a própria linha; **não pode** dar `UPDATE` — saldo, energia,
  nível e clube só mudam por funções do servidor. O papel `anon` ainda tem privilégios de tabela herdados (sem efeito
  prático porque a RLS exige `auth.uid() = user_id`), e serão revogados na Etapa 13.
* `sim_lock_career()` trava a linha da carreira (`FOR UPDATE`) e aplica a recarga de energia; é o ponto de entrada de
  praticamente todas as RPCs.

## 3. Modelo de dados por domínio

### Clubes e jogadores
* `sim_clubs` (48): 20 da Série A 2026, Fortaleza e Juventude (Série B, só para a Copa do Brasil) e 26 estrangeiros da
  Libertadores 2026. `strength` (30–99) é uma estimativa editável. `tier` aceita `serie_a | br_other | foreign`.
* `sim_players` (1.613), `sim_player_attrs`, `sim_player_pos_ratings` — gerados por `scripts/build-squads.mjs` a partir de
  `data/squads/raw/<clube>.txt` (fonte + data de acesso + data do elenco em cada arquivo). Atributos são **estimativa de
  gameplay**, documentada em `data/squads/IMPORT_REPORT.md`.
* Escudos: 3 em imagem (`src/features/club/assets`); os demais são desenhados pelo app (`ClubCrest`) com as cores do clube.
  `scripts/fetch-crests.mjs` baixa escudos oficiais quando rodado na máquina do usuário.

### Competições e temporadas
* Catálogo: `sim_competitions` (3: brasileirao, copa_brasil, libertadores) com `rules` jsonb (desempates, banco,
  substituições, prorrogação na final…) e `sim_competition_clubs` (participantes de referência, grupos e chaves).
* Por carreira: `career_seasons` (`mode` player|coach, `day_no`), `season_competitions` (fase atual, campeão, vice),
  `season_fixtures` (todas as partidas; `coach_club`, `stats`, `extra_time`, pênaltis, `tie_winner`).
* Motor: `sim_create_season` gera **toda** a temporada; `sim_next_event` escolhe o próximo "dia" pelo campeonato mais
  atrasado; `sim_play_round` → `mgr_sim_fixture` (motor de atributos, ~33 ms por jogo da IA); `sim_advance` fecha fases e
  sorteia o mata-mata; `sim_finish_competition` / `mgr_on_comp_finished` dão bônus, títulos e mensagens.
* **Limitação central:** o motor tem os três campeonatos fixos no código (`'brasileirao'`, `'copa_brasil'`,
  `'libertadores'`, 38/7/13 rodadas, oitavas da Libertadores 1º×2º, fases `r16/qf/sf/final`). Não há Série B, divisões,
  acesso/rebaixamento, fase de liga de 36 clubes, chaves com jogo único, prorrogação fora da final, nem mais de um país.

### Carreira de treinador
* `mgr_coach` (reputação, diretoria, torcida, demissões), `mgr_spells` (passagens), `mgr_objectives`, `mgr_players`
  (estado de cada jogador por carreira), `mgr_lineups`, `mgr_matches` + `mgr_match_players` + `mgr_match_events`
  (partida ao vivo), `mgr_player_stats`, `mgr_messages`, `mgr_ai_clubs`.
* Escolha inicial: `get_initial_offers()` sorteia 2 entre os 6 clubes mais fracos da Série A e **grava** (recarregar não
  sorteia de novo); `choose_initial_club(offer)` aplica. A nacionalidade (`careers.country`) **não** influencia nada.
* Propostas: `mgr_make_offer` só considera `tier = 'serie_a'`.

### Economia
* Saldos em `careers`: `coins`, `diamonds`, `energy` (recarga a cada 5 h até 10) e `bonus_energy` (comprada/ganha, nunca zera).
* Quem altera saldo hoje: fim de competição (`sim_finish_competition`), palpites (`tickets`), caixas (`box_open`),
  descarte de cartas (`card_discard`), troca diamante→energia (`diamonds_exchange_energy`, 1:2), propostas.
* **Não existe livro de transações**: as alterações de saldo não deixam histórico (só os efeitos). Não há chave de
  idempotência nas RPCs de compra (as caixas usam `ref` único, que é o único mecanismo anti-duplicação existente).

### Cartas
* `card_tiers` (basica, destaque, lenda, epica: prêmios e valor de descarte), `cards` (650 automáticas, `image = 'auto'`,
  coluna `weight` escondida do navegador), `user_cards` (inventário com `qty`), `reward_boxes` (caixa de entrada com
  `ref` único), `box_sources` (welcome / daily = 1 Destaque garantida / season_win), `career_card_state`.
* Cartas são **empilháveis** (`qty`); não há identificador por cópia — relevante para o mercado (Etapa 7).

### Palpites (apostas simuladas)
* `competitions`, `matches` (sincronizadas de API externa), `tickets`, `ticket_picks`, `prediction_stats`; liquidação no
  servidor; moedas do jogo, sem dinheiro real.

## 4. Telas e estado de cada módulo

| Módulo | Estado real |
|---|---|
| Temporadas / treinador | Completo e ligado ao banco (escalação com arrastar e soltar, partida ao vivo, demissão, propostas). |
| Palpites | Completo e ligado ao banco. |
| Cartas | Completo: coleção, caixas, descarte, caixa diária. |
| **Loja** | **Não existe.** Aba `store` travada em `home/data/tabs.js` e `gameModes.js`. |
| **Amigos / convites / mensagens** | **Não existem** no backend; atalhos travados. |
| **Eventos** | **Não existem**; aba travada. |
| **Ranking / partida online** | Travados (fora do escopo deste projeto, continuam travados). |
| Perfil | Parcial: banner, foto e "vitrine" ficam no **localStorage** (`profileStore.js`); `CardShowcase` usa dados de exemplo desligados (`USE_SAMPLE_CARDS = false`) com raridades antigas (bronze…lenda) diferentes das reais. Tema e música funcionam. |
| Áudio | Só música: `AudioContext.jsx` + `playlist.js` (4 faixas em `public/audio`), volume e mudo em `localStorage('fc:audio')`, desbloqueio no primeiro gesto. **Não há efeitos sonoros nem ambientação de partida.** Licença das faixas não está documentada. |

## 5. Dependências entre módulos (o que a ordem precisa respeitar)

1. Motor de competições genérico → Premier League/copas/UCL **e** Série B **e** escolha por nacionalidade (precisa saber
   em que divisão/país o clube está) **e** eventos ("vencer uma partida", "participar de uma competição").
2. Livro de transações + idempotência → loja, roleta, mercado, energia, cosméticos e recompensas de eventos. Por isso
   o livro (parte da Etapa 13) é **antecipado** para o início da Etapa 5: construir as compras já em cima dele evita
   reescrevê-las depois.
3. Cartas por cópia (ou reserva de quantidade) → mercado → carta em destaque no perfil (precisa ser retirada se vendida).
4. Perfil público → amigos (o amigo abre o perfil público).
5. Eventos → insígnias e cosméticos como recompensa.

## 6. Decisões de arquitetura

1. **Regiões do mundo.** Cada temporada de treinador é criada para a região do clube do técnico:
   * `BRA` — Série A, Série B, Copa do Brasil, Libertadores (temporada 2026, 2027…);
   * `ENG` — Premier League, Championship, FA Cup, EFL Cup, Champions League (2026/27, 2027/28…).
   Assim o custo de simulação continua aceitável (cada dia simula só a região ativa) e cada campeonato tem participantes
   coerentes. Propostas no meio da temporada vêm da mesma região; no fim da temporada podem vir da outra.
2. **Competições configuráveis.** `sim_competitions` ganha `region`, `kind`, `division`, `ref_season`, `sources` e um
   `rules.phases` que descreve as fases (liga, fase de liga suíça, grupos, mata-mata de jogo único ou ida e volta,
   prorrogação, pênaltis, campo neutro, quem entra em cada fase, chaveamento). O motor lê a configuração; os três
   campeonatos atuais recebem uma configuração equivalente ao comportamento de hoje (testado para não mudar).
3. **Participantes por temporada.** Nova tabela `season_participants` (temporada × competição × clube, com divisão,
   origem — referência, acesso, rebaixamento, classificação — e restrição de unicidade) substitui a leitura direta de
   `sim_competition_clubs` na criação da temporada. `sim_competition_clubs` passa a ser só a **referência oficial**.
4. **Acesso e rebaixamento configuráveis** em `sim_promotion_rules` (por região e por ano, com vagas diretas e playoff),
   aplicados uma única vez por temporada (registro em `season_transitions` com chave única → não roda duas vezes).
5. **Dados oficiais** pelo mesmo pipeline já usado: `data/squads/raw/*.txt` (fonte e data em cada arquivo) →
   `scripts/build-squads.mjs` → seed idempotente. Novos clubes entram em `supabase/seasons/` por script idempotente
   (`on conflict do update`).
6. **Migrações versionadas**: cada etapa entra como arquivos numerados em `supabase/evolution/NN_*.sql`, todos
   idempotentes, com um `NN_rollback.sql` correspondente quando a mudança é estrutural, e são aplicados em produção via
   `apply_migration` com o mesmo nome (aparecem em `list_migrations`).

## 7. Riscos de migração e como serão tratados

| Risco | Tratamento |
|---|---|
| Temporadas em andamento em produção (4 temporadas, 1.996 jogos) quebrarem com o motor novo | Funções novas mantêm a assinatura; temporadas antigas recebem `region = 'BRA'` e participantes reconstruídos dos próprios jogos. Teste: jogar uma temporada criada no motor antigo até o fim no motor novo. |
| Timeout de 8 s das RPCs do Supabase com mais jogos por dia | Medido: ~33 ms por jogo da IA; o pior dia (Championship + Premier League) fica < 1 s. `mgr_advance` já corta em 3,5 s. |
| Duplicar clubes/jogadores ao importar | IDs estáveis (slug), `on conflict do update`, verificação de nomes duplicados entre listas (já existe no build-squads). |
| Dados oficiais incompletos (ex.: participantes de divisões inferiores) | Não serão inventados: a adaptação é documentada (ver Etapa 2) e listada nas pendências. |
| Compras duplicadas por clique duplo/queda de rede | Chave de idempotência por requisição + livro de transações com restrição única. |
| Corridas no mercado | `SELECT … FOR UPDATE` no anúncio e nas duas carteiras, em ordem determinística (evita deadlock). |

## 8. Ordem de implementação

A ordem do anexo é mantida, com um ajuste justificado pela dependência 5.2:

1. Auditoria e plano (este documento).
2. Motor configurável + Premier League, Championship (necessária para as copas e para o técnico inglês), FA Cup,
   EFL Cup e Champions League 2026/27.
3. Série B 2026 + acesso/rebaixamento (Brasil e Inglaterra) + classificação para Libertadores/Champions pela liga.
4. Escolha inicial por nacionalidade (módulo único de regras por país).
5. **Livro de transações e idempotência** (antecipado da Etapa 13) → loja de cartas → "Comprar diamantes" (EM BREVE).
6. Roleta.
7. Mercado entre jogadores.
8. Pacotes de energia e itens cosméticos.
9. Perfil (servidor) e amigos.
10. Áudio.
11. Eventos recorrentes.
12. Segurança (limites de requisição, revisão de privilégios) e testes de integração.
13. Polimento visual e relatório final.

Cada etapa termina com: SQL testado no Postgres local, testes automatizados em SQL, teste de interface quando há tela,
PR no GitHub e migração aplicada em produção.
