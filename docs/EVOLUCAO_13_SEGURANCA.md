# Etapa 13 — Economia, segurança e integridade

Migração: `supabase/evolution/14_security.sql` (idempotente). Testes: `evolution/tests/security_tests.sql` (S1–S5),
além das suítes e testes de concorrência das etapas anteriores, que continuam passando com ela.

## Situação de cada sistema que altera a conta

| Sistema | Autoridade | Transação + trava | Idempotência | Saldo validado | Extrato | Limite |
|---|---|---|---|---|---|---|
| Carteira (moedas, diamantes, energia) | servidor (`careers`, só funções) | sim (`sim_lock_career`) | — | `econ_apply` recusa saldo negativo | `wallet_ledger` (gatilho: nada escapa) | — |
| Compra de cartas | `shop_buy_card` | sim | `request_id` | sim | `shop_card` + carta | economia 120/min |
| Roleta | `wheel_spin` (sorteio no servidor) | sim | `request_id` | sim | `wheel_spin` | economia 120/min |
| Energia | `energy_buy`, `diamonds_exchange_energy` | sim | `request_id` | sim + teto de bônus | `energy_pack` / `energy_exchange` | economia 120/min |
| Mercado | `market_*` (custódia da carta) | sim, trava as 2 carteiras em ordem | `request_id` | sim | `market_buy` / `market_sale` com carta e contraparte | economia 120/min, 30 anúncios/h |
| Recompensas de evento | `event_claim`, `streak_claim` (progresso por gatilho) | sim | 1 conclusão por período (chave única) | — | `event_reward` / `daily_streak` | — (uma por conclusão) |
| Cosméticos | `cosmetic_buy` / `cosmetic_equip` | sim | `request_id` | sim | `cosmetic` | economia 120/min |
| Caixas, descarte, partidas, competições, contratos, palpites (funções antigas) | servidor | sim | regras próprias | sim | **agora com motivo próprio** (ver abaixo) | palpites 60/h |
| Perfil / foto | `profile_set_*` | — | — | tamanho/tipo da imagem | — | 20 trocas de foto/h |
| Amigos | `friend_*` | — | par único | — | — | 20 convites/h (Etapa 10) |
| Administração de eventos | `admin_*` (só `admins`) | sim | — | validação completa | — | 120 alterações/h |

## O que mudou nesta etapa

**1. Origem de toda movimentação.** Antes, o que vinha das funções antigas (abrir caixa, descartar carta, prêmio de
partida, energia gasta na partida, luvas de contrato, premiação de competição, palpites) entrava no livro como `other`.
Agora o gatilho do livro identifica qual função do jogo fez a alteração (pela pilha de chamadas) e grava o motivo
(`box_open`, `card_discard`, `match_reward`, `match_energy`, `signing_bonus`, `competition_prize`, `prediction_stake`,
`prediction_payout`). Alteração feita direto no banco por um administrador aparece como `manual_adjustment`. As funções
antigas não foram reescritas — o risco de regressão no motor de partidas é zero. Mapa em `econ_reason_map`.

**2. Extrato no app.** Loja → botão **Extrato**: últimas 100 movimentações com motivo, data, valor, saldo depois e, quando
há, a carta e a outra parte (apelido) nas negociações do mercado.

**3. Funções internas fora da API.** Nove funções do motor de temporadas aceitavam o id de qualquer carreira/temporada e
podiam ser chamadas por qualquer pessoa — inclusive sem login — pela API (`sim_create_season`, `sim_season_transition`,
`sim_phase_create`, `mgr_make_offer` e outras). Com isso, alguém poderia criar ou embaralhar temporadas de outro jogador.
Nenhuma tela usava essas funções. Agora só o próprio servidor as executa. Além disso, nenhuma função privilegiada pode
ser chamada sem login.

**4. Escrita direta em tabelas.** Várias tabelas ainda tinham permissão de escrita para visitantes/logados (a proteção
real era o RLS). Agora a única escrita direta do app é criar a própria carreira, só com as colunas do formulário
(apelido, foto, nacionalidade, idade); moedas, nível, clube etc. só mudam pelas funções do servidor. O padrão para
tabelas e funções futuras também ficou fechado.

**5. Limites de requisição** por usuário (tabela `rate_limit_rules`): a ação acima do limite é recusada com código
`P0429` e uma mensagem com o tempo de espera, sem cobrar nada. Tarefas do servidor (sem usuário) não são limitadas.

**6. Erros e registros.** As funções devolvem mensagens em português sem detalhes internos; as funções agendadas
(`sync-matches`, `sync-odds`) não registram segredos (só código HTTP / mensagem de erro). Os segredos ficam nos
"secrets" do Supabase, nunca no código.

## O que depende de você (painel do Supabase)

* **Proteção contra senhas vazadas** (Authentication → Providers → Email → "Leaked password protection"): está
  desligada. É um ajuste do painel, não do banco.
* Alertas do verificador que ficaram de propósito:
  * "RLS sem políticas": são tabelas que o app não lê direto (tudo passa por funções); sem política = acesso negado.
    Está correto.
  * "SECURITY DEFINER executável por logados": são as funções que o app chama de propósito; cada uma confere o usuário.
  * "search_path mutável": funções matemáticas do motor (não privilegiadas). Fixar o search_path nelas impede o
    PostgreSQL de otimizá-las e deixaria a simulação mais lenta, sem ganho real de segurança.
