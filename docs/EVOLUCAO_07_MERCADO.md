# Etapa 7 — Mercado entre jogadores

Aba **Mercado** na Loja, com três visões: **Comprar**, **Vender** e **Meus anúncios**. Na Coleção, o botão
"Vender no mercado" (que antes dizia "em breve") abre o anúncio da carta escolhida.

## Anunciar
1. Coleção → carta → "Vender no mercado" (ou Loja → Mercado → Vender) — só aparecem cartas que você tem.
2. Define o preço em moedas, dentro do limite da raridade (Destaque 200–20.000; Lenda 1.000–150.000; Épica 2.000–300.000).
3. A tela mostra **antes de confirmar**: taxa do mercado (5%), quanto você recebe se vender e a validade (72 h).
4. Publicado: a cópia **sai da coleção e fica guardada no anúncio** — não pode ser descartada, vendida duas vezes nem
   usada em outra operação. Cancelar ou expirar devolve a cópia.

Regras: Básicas não entram no mercado; um anúncio ativo por carta por jogador (sem anúncio duplicado); até 10
anúncios ativos por jogador; preço fora do limite, carta que não é sua ou já reservada são recusados.

## Comprar
* Anúncios reais de outros jogadores, com carta, nome, raridade, nota, posição, clube, **vendedor**, preço e tempo
  restante. Filtros por nome, raridade, faixa de preço e ordenação (mais novos, menor/maior preço, maior nota).
* Confirmação com preço, saldo atual e depois, vendedor e validade. O comprador paga só o preço anunciado.
* Na compra, na mesma transação: moedas saem do comprador, **preço − 5%** entra para o vendedor, a carta vai para o
  comprador, o anúncio fecha e tudo fica no histórico dos dois e na auditoria. A taxa sai da economia (controle de
  inflação) e fica registrada no anúncio.

## Concorrência e segurança
* Dois compradores no mesmo anúncio ao mesmo tempo: o anúncio é travado; um compra, o outro recebe "Este anúncio já
  foi vendido." — nada é cobrado nem entregue em dobro.
* Dois jogadores comprando **um do outro** ao mesmo tempo: as duas carteiras são travadas sempre na mesma ordem, então
  não há deadlock — as duas compras terminam.
* Compra, anúncio e cancelamento são idempotentes (repetir o pedido devolve o mesmo resultado).
* Só o servidor decide dono, preço, saldo e taxa. O app não lê as tabelas de anúncios diretamente (só pelas funções,
  que mostram o apelido do vendedor sem expor outros dados) e não pode alterar taxa, limites ou anúncios.
* Expiração: anúncios vencidos somem da vitrine na hora (não podem ser comprados) e a cópia volta ao vendedor na
  próxima consulta ao mercado de qualquer jogador (`market_expire_due`, com `skip locked` para não brigar com uma compra
  em andamento).
* Dinheiro: `market_buy` e `market_sale` no livro de transações; auditoria em `market_events` (criado, cancelado,
  expirado, vendido).

## Configuração (sem código)
`market_config` (taxa, validade, máximo de anúncios, liga/desliga) e `market_price_limits` (limites por raridade).

## Testes
* `supabase/evolution/tests/market_tests.sql` (M1–M10) — **todos passaram**: regras e cartas vendáveis; anúncio com
  taxa visível e cópia reservada; idempotência; duplicado, preço fora do limite, Básica, carta que não é sua e descarte
  da cópia reservada recusados; vitrine e filtros; compra sem saldo sem efeito; compra atômica com taxa, livro e
  auditoria; replay; anúncio vendido; histórico dos dois lados; só o dono cancela; não compra o próprio anúncio;
  cancelar devolve e é idempotente; expiração; limite de anúncios; permissões.
* `supabase/evolution/tests/market_concurrency.sh` — conexões simultâneas: dois compradores no mesmo anúncio (1 venda)
  e compras cruzadas (2 vendas, sem deadlock); total de moedas = inicial − taxas.
* Navegador: vitrine, filtro, compra, anúncio com preço inválido e válido, meus anúncios, cancelar, histórico, atalho da
  Coleção (abre uma vez só — um defeito em que a janela reabria ao fechar foi encontrado e corrigido no teste).
