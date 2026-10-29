# Evolução — migrações versionadas

Cada arquivo numerado é uma migração **idempotente** (pode rodar de novo sem duplicar nada). Em produção elas são
aplicadas pelo `apply_migration` com o mesmo nome do arquivo e aparecem em `list_migrations`.

## Ordem de instalação (banco novo)

```
supabase/seasons/01_schema.sql      supabase/seasons/02_seed.sql
supabase/seasons/03_engine.sql      supabase/seasons/04_features.sql
supabase/manager/01_schema.sql
supabase/evolution/01_schema.sql            <- regiões, divisões, participantes por temporada, acesso/rebaixamento
supabase/evolution/02_reference_data.sql    <- clubes, competições e participantes oficiais (gerado)
supabase/manager/02_players_seed.sql        <- elencos (gerado; agora com os clubes novos)
supabase/manager/03_engine.sql  04_career.sql  05_permissions.sql
supabase/cards/01..04
supabase/manager/06_cards_coach.sql
supabase/evolution/03_engine.sql            <- motor de competições configurável
supabase/evolution/04_manager.sql           <- carreira do treinador no motor configurável
supabase/evolution/05_career_start.sql      <- clube inicial pela nacionalidade + perfis de dificuldade
supabase/evolution/06_economy_shop.sql      <- livro de transações, idempotência e loja de cartas
supabase/evolution/07_shop_price_range.sql  <- preço pela faixa de notas (converte bancos com a 06 antiga; num banco novo não muda nada)
supabase/evolution/08_wheel.sql             <- roleta de cartas por diamantes
supabase/evolution/09_market.sql            <- mercado entre jogadores
supabase/evolution/10_energy_packs.sql      <- pacotes de energia (diamantes → energia bônus, com limite)
supabase/evolution/11_profile.sql           <- perfil no servidor, carta em destaque, insígnias e cosméticos
supabase/evolution/12_friends.sql           <- amigos e convites (com tempo real)
supabase/evolution/13_events.sql            <- eventos recorrentes, sequência diária e painel de administração
supabase/evolution/14_security.sql          <- origem de toda movimentação, funções internas fora da API, limites de requisição
supabase/evolution/15_season_integrity.sql  <- chaves compostas, resultados protegidos e calendário
supabase/evolution/16_match_simulation.sql  <- motor versionado, IA e disciplina
supabase/evolution/17_season_draws.sql      <- tabelas finais e classificação por mérito
supabase/evolution/18_swiss_certificates.sql <- certificados dos sorteios suíços
supabase/evolution/19_opponent_analysis.sql <- análise do rival e histórico
supabase/evolution/20_pending_calendar_repair.sql <- somente rodadas futuras; snapshots legados
supabase/evolution/31_world_advance_speed.sql <- (depois da carreira completa 24–30) avanço do calendário em lotes curtos
supabase/evolution/32_squad_morale_contracts.sql <- satisfação no rendimento, contratos/pré-contratos, limite de elenco, rescisão e demissão por falência
supabase/evolution/33_inbox.sql             <- caixa de mensagens por assunto (Elenco, Mercado, Clube, Carreira)
supabase/evolution/34_ai_balance.sql        <- equilíbrio da IA verificado pela simulação longa
```

Banco que já estava no ar: rode só `evolution/01`, `evolution/02`, `manager/02_players_seed.sql` (gerado de novo) e
`evolution/03`, `evolution/04`. Temporadas em andamento continuam (os participantes são reconstruídos a partir dos jogos
e a próxima temporada já nasce com Série B e acesso/rebaixamento).

## Dados gerados (não edite o SQL à mão)

| Arquivo | Gerado por | A partir de |
|---|---|---|
| `evolution/02_reference_data.sql`, `src/features/club/data/clubCatalog.js`, `data/clubs/generated_strength.json` | `node scripts/build-competitions.mjs` | `data/clubs/clubs_evolution.json`, `data/competitions/competitions.json`, `data/competitions/ucl_swiss_templates.json` |
| `manager/02_players_seed.sql`, `data/squads/squads.json`, `data/squads/IMPORT_REPORT.md` | `node scripts/build-squads.mjs` | `data/squads/raw/*.txt` |
| `data/competitions/ucl_swiss_templates.json` | `python3 scripts/gen-swiss-template.py 4` | — |

## Mudar um regulamento

Edite `data/competitions/competitions.json` (fases, mando, prorrogação, pênaltis, chaveamento, desempates, zonas,
objetivos, rodadas do calendário) e rode `node scripts/build-competitions.mjs`. Acesso e rebaixamento por ano ficam em
`promotion` (tabela `sim_promotion_rules`, com `from_year`/`to_year`). O motor lê a configuração; não há regra fixa no código.

## Clube inicial por nacionalidade

Tabela `sim_start_rules` (uma linha por nacionalidade, mesmo código de `careers.country`) e `sim_difficulty_profiles`.
Nova nacionalidade = inserir uma linha em `sim_start_rules` + a bandeira em `src/features/player/components/flags.jsx` e
`src/features/player/data/countries.js`. A tela de criação só mostra nacionalidades que têm regra ativa no banco, e o
banco recusa (`careers_country_fkey`) carreira com nacionalidade sem regra.

## Testes

```
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/competitions_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/manager/tests/manager_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/career_start_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/economy_shop_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/wheel_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/market_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/energy_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/profile_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/friends_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/events_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/security_tests.sql
PSQL="psql ..." bash supabase/evolution/tests/market_concurrency.sh      # compradores simultâneos e compras cruzadas
PSQL="psql ..." bash supabase/evolution/tests/economy_concurrency.sh     # duas conexões ao mesmo tempo
PSQL="psql ..." bash supabase/evolution/tests/events_concurrency.sh      # resgates de evento/sequência simultâneos
```

## Economia e loja

* Saldos continuam em `careers` (coins, diamonds, energy, bonus_energy). Toda alteração vira uma linha em `wallet_ledger`
  (gatilho), com motivo e referência quando a função informa (`econ_apply` / `econ_tag`).
* Compras novas: `econ_apply(carreira, moeda, delta, motivo, ref)` (recusa saldo insuficiente) + `econ_request_get/save`
  (idempotência por `request_id`).
* Loja: `shop_sections` (raridades à venda, cartas por vitrine, rodízio em horas UTC, limite por usuário) e
  `shop_prices` (por raridade e moeda: `base` = carta mais fraca da raridade, `top` = mais forte). Ajuste com UPDATE, sem código.
* Roleta: `wheel_config` (custo, garantia) e `wheel_segments` (fatias: raridade, faixa de nota, chance em %). Mude as chances
  numa transação só (`begin; update ...; update ...; commit;`): o banco confere no COMMIT que as fatias ativas somam 100%.
* Perfil: `cosmetics` (catálogo visual; `price_diamonds = 0` = grátis para todos) e `badges` (regras: `kind` + `threshold`,
  calculadas em `badge_metric`). Nova insígnia de um tipo existente = uma linha em `badges`.
* Mercado: `market_config` (taxa %, validade em horas, máximo de anúncios por jogador, liga/desliga) e
  `market_price_limits` (preço mínimo/máximo por raridade; raridade fora da tabela não pode ser vendida).

## Desfazer

`evolution/99_rollback.sql` remove as tabelas novas e as competições novas (as temporadas antigas continuam).
As funções voltam ao comportamento anterior rodando de novo `supabase/seasons/03_engine.sql`, `04_features.sql`
e `supabase/manager/03_engine.sql`, `04_career.sql`.

## Eventos (evolução 13)

* Evento = linhas em `events` + `event_objectives` + `event_rewards`. Criar/editar pelo painel **Eventos → Admin** (só quem
  está em `admins`). Para dar acesso: `insert into public.admins (user_id) values ('<id do usuário em auth.users>');`
* Tipos de objetivo possíveis: tabela `event_objective_kinds` (cada um com os filtros aceitos). Tipo novo exige gatilho
  novo no banco — o painel não aceita código livre.
* Detalhes, regras de período/fuso e limitações: `docs/EVOLUCAO_12_EVENTOS.md`.

## Segurança (evolução 14)

* Funções novas nascem SEM permissão para `anon`/PUBLIC e tabelas novas sem escrita para `anon`/`authenticated`
  (privilégios padrão). Toda migração deve terminar com `grant execute ... to authenticated` só no que o app chama.
* Limites por usuário: tabela `rate_limit_rules` (ajuste `max_hits`/`window_seconds` sem mexer em código).
* Função antiga nova que mexa na carteira sem `econ_apply`/`econ_tag`: registre-a em `econ_reason_map` para o extrato
  mostrar a origem. Detalhes: `docs/EVOLUCAO_13_SEGURANCA.md`.

## Reestruturação do Modo Temporadas

Ver [TEMPORADAS_V2.md](../../docs/TEMPORADAS_V2.md) para causas, critérios, testes isolados, limitações dos formatos e implantação transacional com backup e preflight. Não executar os scripts de suporte/teste no banco dos usuários.

## Cartas base (após Temporadas v2)

Aplicar 21_base_cards.sql, 22_base_card_functions.sql e 23_base_card_migration.sql juntos pelo pacote transacional `supabase/releases/cartas_base.sql`, após backup e `preflight_base_cards.sql`. Ver `docs/CARTAS_BASE.md` para tabela de compensação, preservação e testes. Os scripts antigos de cartas/loja/roleta/mercado fazem parte do histórico de instalação; não reaplicá-los isoladamente após esta migração. A manutenção deve permanecer ativa.

## Avanço do calendário mais rápido (31)

Banco que já está no ar: rode só `supabase/evolution/31_world_advance_speed.sql` no SQL Editor. Substitui apenas
`career_world_advance` e `cw_step_day` (mesmo resultado, lotes menores e menos escrita por dia); não altera tabelas
nem dados. O app já trata lotes parciais e funciona com ou sem esta migração.

## Elenco, satisfação e contratos (32)

Banco que já está no ar: rode `31_world_advance_speed.sql` (se ainda não rodou) e depois `32_squad_morale_contracts.sql`.
Adiciona duas colunas com padrão em `cw_players` (`shirt_number`, `transfer_listed`) e embrulha funções existentes
(`*_before_v32`). Não altera carreiras, saldos, resultados nem jogadores. Regras:

- Satisfação (0–100) muda o rendimento individual na partida: abaixo de 45 até −12%; acima de 80 até +3%.
  Abaixo de 30 o atleta pede para sair e passa a receber propostas.
- Limite de inscrição: 30 atletas com 21 anos ou mais por clube (sub-21 livres), em `cw_rules.rules.squad_limit`.
  Inspirado na lista de 25 adultos + sub-21 da Premier League, ajustado ao tamanho médio dos elencos do jogo.
- Lista de transferências e rescisão (até seis salários) para abrir vagas.
- Contratos nos seis meses finais recebem pré-contratos: sem renovação, o atleta sai de graça. Máximo de 5 anos.
- Clube com risco financeiro ≥ 90% por 21 dias demite o treinador (após 45 dias no cargo), além da regra antiga de 60 dias.
- Atleta transferido recebe um número livre no novo clube; cartas de notícias usam o atleta real.

Teste: `supabase/evolution/tests/squad_morale_contracts_tests.sql`.

## Equilíbrio da IA (34)

Banco no ar: rode `supabase/releases/ia_equilibrio.sql` (depois de `mensagens.sql`). Só substitui funções e adiciona um
gatilho para contratos novos; confere ao final que nenhum dado de usuário mudou.

Verificado por `tests/career_world_journey.py` (Brasil → Inglaterra → Brasil, de janeiro a fevereiro do ano seguinte):

- Satisfação: reservas e promessas aceitam o papel; titular prometido encostado cobra espaço e pode pedir para sair.
  Nos clubes da IA quem não tem espaço passa a reserva. Quem volta a jogar recupera mais rápido.
- Mercado da IA: transferências com clube vendedor só na janela; atletas livres também fora dela; clubes com elenco
  muito acima do limite param de comprar.
- Propostas de emprego: dependem da reputação (alcance de força dos clubes). Clubes de outra região chamam sobretudo
  na pré-temporada ou janela deles; empregado, você é procurado com mais frequência.
- Contratos novos terminam no fim da temporada do país (Brasil 31/12, Inglaterra 30/06), sem passar de 5 anos.
