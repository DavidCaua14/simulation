# Etapa 8 — Pacotes de energia

Aba **Energia** na Loja.

## Regras (mantidas as que já existiam)
* **Energia normal:** volta a 10 a cada 5 h (regra antiga, inalterada).
* **Energia bônus:** a que nunca zera; os pacotes somam aqui.
* **Limite de energia bônus para compras: 200** (configurável). Regra: se o pacote passaria do limite, a compra é
  **recusada antes de cobrar** — a tela avisa no próprio pacote ("passaria do limite") e na confirmação.
* A troca avulsa que já existia (Cartas → trocar diamantes, 1 💎 = 2 ⚡) passou a respeitar o mesmo limite e a entrar no
  livro de transações (antes não havia limite: era um jeito de contornar a regra).

## Pacotes (configuráveis em `energy_packs`)
| Pacote | Energia | Preço | Rende |
|---|---|---|---|
| Fôlego | +10 | 5 💎 | igual à troca avulsa |
| Treino extra | +22 | 10 💎 | 10% a mais |
| Pré-temporada | +50 | 20 💎 | 25% a mais |

Cada pacote mostra: energia recebida, preço, limite, energia atual (normal e bônus) e como fica depois da compra.

## Segurança
Cobrança de diamantes e crédito de energia na mesma transação, idempotente (repetir o pedido não cobra de novo),
com motivo `energy_pack` no livro. O app não altera preços nem o limite.

## Testes
`supabase/evolution/tests/energy_tests.sql` (N1–N5) — **todos passaram**: catálogo (energia atual, limite, regra,
pacotes não rendem menos que a troca avulsa); compra cobrada uma vez e idempotente; diamantes insuficientes; limite
respeitado em pacotes e na troca avulsa (e pacote que cabe exatamente); permissões. Navegador: compra e recusa por limite
em tela de 360 px.
