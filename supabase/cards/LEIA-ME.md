# Cartas e caixas — instalação e uso

## Instalar (uma vez)
1. Supabase → SQL Editor, rode **nesta ordem** (depois dos arquivos de `supabase/seasons`):
   1. `supabase/cards/01_cards.sql`  (tabelas, sorteio, caixa de entrada, gatilho de vitória)
   2. `supabase/cards/02_cards_seed.sql`  (as 9 cartas de exemplo)
2. Copie para o projeto, mantendo as pastas: `src/`, `public/cards/`, `scripts/`.
3. `npm run dev` / `npm run build`. Nenhuma dependência nova.

Ao abrir a Home, cada jogador recebe sozinho: **3 caixas de boas-vindas** (1ª vez; contas já existentes também recebem) e **3 caixas por dia** (virada à meia-noite de Brasília). Cada **vitória em Temporadas** gera 1 caixa.

## Como funciona
- A **cor da caixa = raridade da carta**: cinza (Básica), azul (Destaque), dourada (Lenda), roxa (Épica).
- Chances de cada caixa diária/vitória: Básica 94,65% · Destaque 5% · Lenda 0,3% · Épica 0,05%. Boas-vindas: 2 básicas + 1 destaque.
- Prêmios extras por caixa (moedas / energia / diamantes): Básica 10–40 / 0–1 / 0 · Destaque 50–150 / 1–2 / 0–1 · Lenda 200–500 / 2–4 / 1–5 · Épica 500–1000 / 4–6 / 5–15. A energia vai para a energia "bônus" (nunca é zerada).
- Tudo é sorteado no banco (`box_open`); o navegador só anima. Se uma raridade ainda não tem cartas, a caixa entrega uma carta da raridade logo abaixo.
- Repetidas: ficam como quantidade (`x2`...). Dá para **descartar** (sempre sobra 1) por moedas/diamantes conforme a raridade. Diamantes: **1 💎 = 2 ⚡** (botão "trocar" na tela Cartas).

## ➕ Adicionar cartas (3 passos)
1. Salve a imagem em `public/cards/<id>.webp` (fundo transparente, ~420×640; a moldura da raridade já faz parte da imagem).
2. Acrescente uma linha em `supabase/cards/cards.json`:
   `{ "id": "pedro-90", "name": "Pedro", "tier": "lenda", "overall": 90, "position": "ATA", "club": "flamengo" }`
   (`tier`: basica | destaque | lenda | epica. Opcionais: `weight`, `player`, `image`, `active`, `meta`.)
3. `node scripts/build-cards.mjs` e rode no SQL Editor o arquivo gerado `supabase/cards/02_cards_seed.sql`.

A carta já cai nas caixas e aparece na coleção, sem mexer em código. `"active": false` tira a carta de circulação (quem já tem, mantém). `"weight"` menor (ex.: 20 contra 100) deixa a carta mais rara dentro da própria raridade.

## Ajustar o equilíbrio (sem código)
```sql
-- chances das caixas diárias
update box_sources set weights = '{"basica":90,"destaque":8,"lenda":1.5,"epica":0.5}' where source = 'daily';
-- caixas por dia
update box_sources set draws = 5 where source = 'daily';
-- prêmio da caixa épica
update card_tiers set box_diamonds_max = 20 where id = 'epica';
```
Nova fonte de caixas (evento, loja…): `insert into box_sources ...` e chame `card_grant_source(career_id, 'evento', 'ref-unica')` no servidor.

## Já preparado para o futuro
`user_cards` (quantidade por carta), `cards.position/club_id/meta` (escalação online) e o botão "Vender no mercado" (desativado) já existem.

## Testes feitos
SQL executado em PostgreSQL 16 local com os arquivos de Temporadas: entrega única de boas-vindas/diária, abertura atômica, caixa repetida bloqueada, descarte, troca de diamantes, 18 vitórias = 18 caixas, 200 mil sorteios batendo com as chances, e bloqueio de escrita direta pelo navegador. Interface testada em navegador com banco simulado. **Ainda não foi rodado no seu Supabase real.**
