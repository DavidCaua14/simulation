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
supabase/evolution/35_update_gift.sql       <- presente da atualização para quem já jogava e avatares de lendas
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

## Presente da atualização e avatares (35)

Banco no ar: rode `supabase/releases/presentes_atualizacao.sql` (depois de `ia_equilibrio.sql`). Na PRIMEIRA instalação
fotografa as carreiras existentes; só elas recebem, uma única vez ao entrar no jogo, +1000 XP, +20 de energia bônus e
um avatar de lenda aleatório, e veem a tela de Novidades (que pode ser revista em Perfil → Novidades). Contas criadas
depois não recebem nem veem nada; reexecutar o script não inclui ninguém novo. Avatares ganhos ficam no perfil
(`player_avatars`) e podem virar foto (`avatar:<id>`), só para quem os possui. Scripts de colar no SQL Editor são um
único comando gerado por `scripts/build-editor-releases.sh`.

## Primeiro acesso ao modo Temporadas mais rápido (36)

Banco no ar: rode `supabase/releases/primeiro_acesso_rapido.sql` (um comando só; pode repetir). Só desempenho, sem
mexer em dados de jogadores. O primeiro acesso de uma carreira monta o mundo inteiro numa chamada e passava de 20 s,
estourando o limite de 8 s da API ("canceling statement due to statement timeout"); agora leva ~3 s.
- `season_fixture_slots(fixture_id)` indexado: cada jogo criado varria a tabela inteira (que cresce com os jogadores).
- `cw_initialize_finances`: papel prometido copiado do contrato atleta a atleta pela chave primária e criação de
  contratos sem checagem de duplicidade quando a carreira ainda não tem nenhum.

## Mercado, economia e notícias (37)

Banco no ar: rode `supabase/releases/mercado_economia.sql` (um comando só; pode repetir).
- Renovar de novo antes de enviar a proposta reabre a renovação já aberta (antes: "duplicate key").
- Venda para clube da IA: se o atleta pede salário maior, o comprador da IA aceita sozinho e a venda é registrada
  (antes a negociação esperava o comprador, expirava e o dinheiro nunca entrava).
- Vendas concluídas cujo valor não entrou no caixa: a diferença é creditada uma vez no clube atual do treinador
  (lançamento "sale_fix"). É a única alteração de dados de usuários; o script libera só a impressão digital `clubs`.
- Seu clube acumula caixa até 10× o orçamento inicial (antes 3×: o excedente virava "investimento patrimonial" todo
  mês). Clubes da IA seguem com 3×.
- Receita de jogo em todos os jogos do mundo: bilheteria do mandante (torcida × 0,02) e prêmio por vitória
  (1.500 + prestígio × 30; empate = 1/3), ×1,2 em copas e ×1,6 em continentais.
- Valor de mercado: 80 de nota ≈ 40 mil, dobrando a cada 4,5 pontos; idade e potencial ajustam. Valores guardados
  são recalculados na instalação.
- Busca no mercado só lê (não trava a carreira) e filtra pelo valor guardado.
- Notícias só do seu clube (mais "world", "job", "finance" e os campeões, "title"); as antigas de outros clubes são apagadas. O gatilho de
  resultados deixou de calcular manchetes de outros clubes a cada jogo simulado.

## Banco enxuto (38)

Banco no ar: rode `supabase/releases/banco_enxuto.sql` e depois `supabase/releases/liberar_espaco.sql` (VACUUM FULL,
devolve o espaço; sozinho numa aba). Salários dos clubes da IA viram uma linha por clube por mês (seu clube segue
detalhado); `cw_settled_months` impede pagar um mês duas vezes. `tamanho_banco.sql` mostra o tamanho.

## Elenco, caixa, janela e banco menor (39)

Banco no ar: rode `supabase/releases/elenco_caixa_janela.sql` e depois `liberar_espaco.sql`.
- Elenco: limite de 40 atletas com 21+ (elencos reais têm 40–51); a contagem usa os mesmos atletas da tela Time.
- Caixa: o caixa do seu clube nunca vira "patrimônio"; o que foi recolhido desde que você assumiu o clube atual volta
  ao caixa (lançamento "infra_refund", uma vez).
- Janela: atletas livres também só são registrados com a janela aberta (IA com elenco < 18 é exceção); no máximo 6
  contratações suas por janela. Datas: Brasil 3/jan–7/abr e 10/jul–2/ago; Inglaterra 14/jun–1/set e 1/jan–2/fev.
- Banco: `cw_prune_career` (todo mês e uma vez na instalação) apaga partidas da IA com mais de 30 dias (o relatório
  usa placar, estatísticas e gols guardados no jogo), finanças da IA com mais de 60 dias, negociações e contratos
  encerrados entre clubes da IA e o cache de requisições. A tabela `season_fixture_slots` deixa de ser usada.
- Scripts de release com o jogo no ar usam o modo `live` do gerador (sem comparação de impressões digitais, que
  abortaria sempre com jogadores online).

## Negociações realistas e idade nas cartas (40)

Banco no ar: rode `supabase/releases/negociacoes_realistas.sql`.
- Clube vendedor da IA: 3 melhores do elenco intocáveis (exceção rara: 3× o valor, de clube bem maior); titulares 4º–7º
  por 1,6–2× o valor, 8º–11º por 1,25–1,5× (entre clubes da IA, regra normal); às vezes não negocia titular. Quem pediu
  para sair ou está no fim do contrato segue a regra normal.
- Atleta: não desce de divisão (salvo 32+ anos, ou quer sair e recebe +30%); na mesma divisão recusa clube bem mais fraco
  (salvo +50% de salário, 31+ ou pedido de saída); livre muito acima do nível do clube espera proposta melhor.
- IA escolhe alvos realistas (não mira pilares nem atletas de divisão acima, salvo 32+). Simulação de 1,5 ano: 140
  transferências e 35 pré-contratos da IA.
- Idade em todas as cartas (`cw_patch_players` sempre envia `age`).

## Histórico de partidas enxuto (41)

Banco no ar: rode `supabase/releases/historico_enxuto.sql` e depois `liberar_espaco.sql`.
- Premiações usam `mgr_player_stats` (idêntico à soma jogo a jogo + abertura); `cw_stats_opening` esvaziada.
- Atuações jogo a jogo por 45 dias (cláusulas de desempenho em aberto guardam desde o registro); partidas da IA por
  7 dias; escalações da IA apagadas ao fim; lances da IA guardam gols, pênaltis e cartões.
- Correção: amarelos não são mais apagados (desempate por fair play em `sim_standings`).
- Agendador: `purge-cron-history` apaga diariamente o histórico com mais de 1 dia.

## Painel administrativo (42)

Banco no ar: rode `supabase/releases/painel_admin.sql`. Abra o jogo com contatodavidcaua@gmail.com e use Perfil → Painel
ou o endereço `/#admin`. `is_admin()` exige estar em `admins` E o e-mail do token ser o do dono; todas as funções
`admin_*` conferem no servidor. Seções: visão geral (jogadores, carreiras, eventos, banco), eventos (evolução 13),
jogadores (busca e envio/retirada de moedas, diamantes e energia bônus com motivo), avisos para todos (caixa de
mensagens) e registro (`admin_actions`). Teste de tela: `tests/admin_ui_smoke.py`.

## Caixa de entrada, avisos com período e painel com modo Temporadas (43)

Banco no ar: rode `supabase/releases/caixa_avisos_painel.sql` (depois de `painel_admin.sql`).
- `announcements`: título, texto, início, fim e premiação opcional; aparecem em modal na tela inicial (uma vez por
  jogador, `announcement_reads`) e na caixa de entrada enquanto estão no período.
- `player_notices`: toda ação do painel sobre um jogador (premiação, retirada, troca de clube, caixa, reputação) gera um
  comunicado em modal. Premiações são resgatadas pelo jogador (`inbox_claim`, uma vez).
- Jogador: `inbox_list`, `inbox_pending`, `inbox_seen`, `inbox_claim`. Tela: botão Mensagens na tela inicial.
- Painel: visão geral (cadastros por dia, partidas, economia da semana, eventos, avisos, melhores jogadores, clubes),
  Temporadas (`admin_career`, `admin_career_set_club`, `admin_career_adjust`) e Avisos (`admin_announcement_*`).

## Ranking geral dos treinadores (44)

Banco no ar: rode `supabase/releases/ranking.sql`. `ranking_overall(limite)` devolve o top (apelido, nível, clube,
títulos, V-E-D, reputação, eventos, pontos) e a posição de quem chama. Pontos: nível×100 + XP÷10 + títulos×500 +
vitórias×20 + empates×7 + reputação×15 + eventos concluídos×25 − demissões×150. Desempate: nível, vitórias, cadastro.
A faixa da tela inicial e o card Ranking usam este ranking (não mais o de palpites).
