# Etapa 6 — Roleta de cartas por diamantes

Aba **Roleta** dentro da Loja.

## Regras
* **10 diamantes por giro** (configurável em `wheel_config`), cobrados no servidor pelo mesmo débito central da loja:
  sem saldo, nada acontece; cada giro entra no livro de transações (`wheel_spin`).
* **Prêmios: só Lendas e Épicas**, em fatias com chances próprias (`wheel_segments`):

| Fatia | Cartas | Chance |
|---|---|---|
| Lenda clássica | Lendas de nota até 89 (63 cartas) | 70% |
| Lenda estrela | Lendas de nota 90–93 (29) | 22% |
| Lenda imortal | Lendas de nota 94+ (8) | 5% |
| **Épica** | todas as Épicas (50) | **3%** |

  Épica é a mais rara de propósito: em média 1 a cada 33 giros, então costuma levar muitos giros ou uma boa dose de
  sorte. Dentro de cada fatia a carta é sorteada pelo peso de cada carta (o mesmo das caixas).
* **Soma = 100%** validada pelo banco: qualquer alteração nas fatias que não some 100% é recusada no COMMIT, e o giro
  também confere antes de cobrar.
* **Proteção contra azar (implementada e mostrada antes do giro):** se você girar 40 vezes seguidas sem tirar uma Épica,
  o 40º giro é Épica garantida. O contador zera sempre que sair uma Épica (pela sorte ou pela garantia). A tela mostra
  quantos giros faltam.
* **Repetidas:** mesma regra do jogo — a cópia extra entra na coleção e pode ser descartada.

## Como funciona por dentro
* O sorteio é feito no servidor (`wheel_spin`): cobra, sorteia a fatia (ou aplica a garantia), sorteia a carta, entrega
  no inventário, registra o giro (`wheel_spins`, com o número sorteado) e atualiza o contador da garantia — tudo na
  mesma transação.
* **Idempotência:** o app gera um identificador por giro; repetir o pedido (clique duplo, atualizar a página, queda de
  rede) devolve o mesmo giro, sem cobrar nem entregar outra carta. Testado também com duas conexões simultâneas.
* A animação só começa **depois** que o servidor responde, e para dentro da fatia sorteada. As fatias da roda são
  desenhadas proporcionais às chances reais (3% ocupa 3% da volta). Com "reduzir movimento" ligado no aparelho, o
  resultado aparece sem animação.
* Tela: roda, botão "Girar · 10 💎" (desabilitado e explicando quanto falta quando não há saldo), tabela de chances,
  regra da garantia com o contador, resultado com a carta (moldura e efeito da raridade) e os últimos 10 giros.

## Testes
* `supabase/evolution/tests/wheel_tests.sql` (W1–W8) — **todos passaram**: configuração (soma 100%, chances diferentes,
  Épica mais rara, toda fatia com cartas, custo 10); soma ≠ 100% recusada; giro cobrado uma vez, carta entregue,
  registrado e no livro; repetição idempotente; saldo insuficiente sem efeito; garantia no 40º giro e contador zerado;
  **2.000 giros reais** com a distribuição dentro do esperado (ex.: Épica 2,95% para 3%; Lenda clássica 69,6% para 70%),
  em 3 s; permissões (o app não altera chances, contador, giros nem chama funções internas).
* `economy_concurrency.sh`: o mesmo giro enviado por duas conexões ao mesmo tempo → 1 giro, 10 diamantes cobrados.
* Navegador: roleta, dois giros (o segundo pela garantia, parando na fatia Épica), saldo insuficiente, telas de 390 e
  340 px sem rolagem lateral, tema claro e escuro.
