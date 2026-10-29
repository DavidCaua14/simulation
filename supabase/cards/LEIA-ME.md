> Sistema histórico: caixas e cartas especiais foram encerradas nas migrações 21–23. Não reaplique estes scripts isoladamente em um banco atualizado. Consulte `docs/CARTAS_BASE.md` e `supabase/releases/cartas_base.sql`. CardView/AutoCard continuam como apresentação das cartas base.

# Cartas e caixas — instalação e uso

## Instalar (uma vez)
1. Supabase → SQL Editor, rode **nesta ordem** (depois dos arquivos de `supabase/seasons`):
   1. `supabase/cards/01_cards.sql`  (tabelas, sorteio, caixa de entrada, gatilho de vitória)
   2. `supabase/cards/02_cards_seed.sql`  (as 9 cartas de exemplo)
2. Copie para o projeto, mantendo as pastas: `src/`, `public/cards/`, `scripts/`.
3. `npm run dev` / `npm run build`. Nenhuma dependência nova.

Ao abrir a Home, cada jogador recebe sozinho: **3 caixas de boas-vindas** (1ª vez) e **1 caixa Destaque por dia** (virada à meia-noite de Brasília). Cada **vitória em Temporadas** gera 1 caixa.

## Como funciona
- A **cor da caixa = raridade da carta**: cinza (Básica), azul (Destaque), dourada (Lenda), roxa (Épica).
- Diária: 1 caixa Destaque garantida. Vitória: Básica 94,65% · Destaque 5% · Lenda 0,3% · Épica 0,05%. Boas-vindas: 2 básicas + 1 destaque.
- Prêmios extras por caixa (moedas / energia / diamantes): Básica 10–40 / 0–1 / 0 · Destaque 50–150 / 1–2 / 0–1 · Lenda 200–500 / 2–4 / 1–5 · Épica 500–1000 / 4–6 / 5–15. A energia vai para a energia "bônus" (nunca é zerada).
- Tudo é sorteado no banco (`box_open`); o navegador só anima. Se uma raridade ainda não tem cartas, a caixa entrega uma carta da raridade logo abaixo.
- Repetidas: ficam como quantidade (`x2`...). Dá para **descartar** (sempre sobra 1) por moedas/diamantes conforme a raridade. Diamantes: **1 💎 = 2 ⚡** (botão "trocar" na tela Cartas).

## ➕ Cartas automáticas (padrão)
As cartas são geradas a partir dos **atletas reais do jogo** (elencos 2026 em `sim_players`) e de uma lista de **lendas aposentadas**:

```bash
node scripts/build-auto-cards.mjs --epica 50 --destaque 200 --basica 300
```
Gera `supabase/cards/03_auto_cards.sql` → rode no SQL Editor (pode rodar de novo).

- **Épica**: os N atletas atuais de maior overall · **Destaque**: os N seguintes · **Básica**: N atletas do restante, espalhados entre os 48 clubes.
- **Lenda**: só jogadores aposentados, de `data/cards/legends.json` (`[nome, posição, país, clube no jogo ou null, nome do clube, overall]`). Para incluir mais lendas, acrescente linhas e rode o script.
- Overall dos atuais = nota estimada do jogo; overall das lendas = estimativa de gameplay (não são números oficiais).
- A arte é **desenhada pelo app** (`image = 'auto'`): moldura da raridade, nota, posição, escudo, país e um atleta **ilustrado** com a camisa do clube (não é foto).
- Atleta que sai da seleção para de cair nas caixas; quem já tem a carta continua com ela.
- Também é preciso rodar uma vez `supabase/cards/04_box_open_meta.sql` (a caixa aberta devolve os dados para desenhar a carta).

## Cartas manuais (com imagem própria, opcional)
1. Salve a imagem em `public/cards/<id>.webp` (~420×640, moldura já na imagem).
2. Acrescente em `supabase/cards/cards.json`: `{ "id": "...", "name": "...", "tier": "lenda", "overall": 90, "position": "ATA", "club": "flamengo" }`
3. `node scripts/build-cards.mjs` e rode `supabase/cards/02_cards_seed.sql`.

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
