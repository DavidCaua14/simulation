# Etapa 5 — Loja de cartas e economia (com o livro de transações antecipado da Etapa 13)

## Carteira: a mesma de sempre, agora auditável
Antes de criar a loja, os saldos existentes foram examinados: moedas, diamantes, energia e energia bônus ficam em
`careers`. **Nenhuma moeda paralela foi criada.** O que foi acrescentado:

* **Livro de transações** (`wallet_ledger`): toda alteração de saldo — inclusive as feitas pelas funções antigas
  (prêmios de partida, caixas, palpites, troca de diamantes) — vira uma linha com moeda, valor, saldo depois, motivo e
  referência. É um gatilho na tabela `careers`, então nada escapa. As carreiras que já existiam ganharam uma linha de
  "saldo de abertura". Motivos das funções novas: `shop_card`; recarga automática de energia: `energy_regen`; as funções
  antigas aparecem como `other` até a Etapa 13 dar nome a cada uma.
* **Idempotência** (`econ_requests`): cada compra leva um identificador gerado pelo app ao abrir a confirmação. Repetir o
  mesmo pedido (clique duplo, atualizar a página, internet caindo no meio) devolve **o mesmo resultado sem cobrar de novo**.
* **Débito central** (`econ_apply`): toda compra nova passa por ele. Saldo insuficiente = erro com a explicação
  ("Moedas insuficientes.") e **nada muda** (nem saldo, nem inventário).

## Loja
Aba **Loja** liberada no menu e na tela inicial. Seções:

| Seção | O que tem |
|---|---|
| **Destaques** | 6 cartas Destaque por dia (temporada atual), compráveis com moedas **ou** diamantes |
| **Lendas** | 3 cartas Lenda por dia, bem mais caras |
| **Diamantes** | "Comprar diamantes" com a etiqueta **EM BREVE**, desabilitado, sem preço e sem simular pagamento |

* A vitrine é a mesma para todos e troca às **00:00 UTC** (21:00 em Brasília); a tela mostra quanto falta.
* Cada carta mostra nome, raridade (moldura e cor próprias: azul Destaque, dourado Lenda com brilho), nota, posição,
  clube, nacionalidade, tipo (temporada atual / lenda), quantas você já tem, disponibilidade e os dois preços.
* Confirmação: carta, preço, moeda, saldo atual e saldo depois; se faltar saldo, diz quanto falta e o botão fica
  desabilitado. Resultado: carta nova ou repetida, valor pago e saldo atual, com atalho para a Coleção.
* **Repetidas:** seguem a regra que já existia — a cópia extra entra na coleção (`qty`) e pode ser descartada por
  moedas/diamantes. A loja avisa antes da compra quando você já tem a carta.
* Limite: 1 cópia de cada carta por usuário por vitrine ("1 disponível" / "Comprada neste rodízio").

### Preços (configuração única: `shop_prices`)
Pela faixa de notas da raridade: a carta mais fraca da raridade custa `base`, a mais forte custa `top`, e as demais
ficam proporcionais à nota (arredondado). Assim o preço funciona com qualquer catálogo — o de produção tem Destaques
de nota 75–80 e um banco novo, 86–90 (o catálogo é gerado com os elencos do momento).

| Raridade | Moedas (mais fraca → mais forte) | Diamantes |
|---|---|---|
| Destaque | 1.500 → 2.300 | 12 → 16 |
| Lenda | 9.000 → 21.600 | 60 → 130 |

A primeira versão usava uma nota fixa de referência; o teste em produção mostrou que ali todos os Destaques cairiam no
preço mínimo (1.000). A migração `07_shop_price_range.sql` corrigiu antes de qualquer compra real.

Balanceamento medido em produção: ~24 moedas por partida + ~40 por caixa aberta; diamantes saem quase só das caixas
raras e do descarte (0–1 por semana). Assim um Destaque custa mais ou menos uma temporada de moedas e uma Lenda exige
juntar ao longo de várias — como pedido. Tudo ajustável com `UPDATE` nas tabelas, sem mexer em código.

## Compra de diamantes com dinheiro real
**Não implementada** (não há provedor de pagamento, credenciais nem requisitos fiscais). A opção aparece desabilitada
com "EM BREVE". A arquitetura já está pronta para ela: um crédito futuro de diamantes passaria por `econ_apply`
(motivo próprio) com a mesma idempotência, disparado pela confirmação do provedor no servidor.

## Testes
* `supabase/evolution/tests/economy_shop_tests.sql` (E1–E9) — **todos passaram**: livro (abertura, crédito, débito,
  recusa, alteração de função antiga, saldo do livro = saldo da carteira); vitrine e preços; compra com moedas; pedido
  repetido sem cobrança dupla; limite por vitrine; compra com diamantes; recusas sem efeito colateral (carta fora da
  loja, moeda inválida, carta fora da vitrine do dia); saldo insuficiente; permissões (o app não altera saldo, livro
  ou compras e só vê o próprio livro).
* `supabase/evolution/tests/economy_concurrency.sh` — **duas conexões ao mesmo tempo**: o mesmo pedido enviado duas vezes
  cobra uma vez (a segunda recebe o resultado gravado); dois pedidos diferentes disputando a última cópia: um compra,
  o outro é recusado; moedas, cartas, compras e livro conferem.
* Navegador (tema escuro e claro): vitrine, confirmação, compra, resultado, disponibilidade atualizada, saldo
  insuficiente, aba Diamantes EM BREVE.
* Testes das etapas anteriores continuam passando.

## Ajustes no ambiente de teste
O banco local passou a reproduzir as permissões padrão do Supabase (toda tabela nova nasce liberada para `anon` e
`authenticated`), para os testes de permissão valerem como em produção.
