# Balanceamento das partidas (14/11/2026)

Os modos Temporadas e Online usam o mesmo motor (`mgr_engine_run_v2` e `on_engine_run`). O ajuste foi medido com o motor real: `PGLITE_DIR=/tmp/pglite N=300 node scripts/calibrate-online-engine.mjs` roda 300 jogos por cenário de `supabase/online/tests/calibration_scenarios.json` (times de nota fixa, mandante primeiro). Margem de erro perto de 3 pontos.

Fontes: `supabase/online/17_engine_balance.sql` (migração `20261114120000`) e `supabase/migrations/20261114130000_seasons_harder_matches.sql`.

## O que mudou no motor

- **Forma** (preparação, preleção, bônus da IA): entrava só nas chances criadas, com raiz quadrada, e quase não mudava o resultado. Agora entra inteira nas chances e também na qualidade da finalização.
- **Força**: o expoente da razão ataque/defesa foi de 0,50 para 0,65.
- **Cansaço**: rendimento do atleta passou de `0,70 + 0,003 x condição` para `0,60 + 0,004 x condição`.
- **Tática** (`mgr_tactical_effect`): encaixes mais fortes. Bola longa contra pressão alta ou linha alta, contra-ataque contra time ofensivo, saída curta dependente da técnica, pressão alta dependente do fôlego, ritmo lento sofrendo contra pressão alta.
- **Sorte do dia**: de ±10% para ±4%.

## Resultados (mandante, 300 jogos)

| Cenário | Antes (V/E/D) | Depois (V/E/D) |
|---|---|---|
| Times iguais | 43/25/32 | 38/30/31 |
| +6 de nota | 50/29/21 | 54/25/20 |
| +10 de nota | 59/25/17 | 61/24/15 |
| −10 de nota | 21/28/51 | 23/29/49 |
| Condição 60% | 30/28/43 | 20/29/51 |
| Condição 80% | não medido | 30/32/38 |
| Preparação completa (antes 3%, agora 6%) | 42/28/31 | 46/30/24 |
| Bola longa contra pressão e linha alta | não medido | 46/24/31 |
| Contra-ataque contra time ofensivo | não medido | 50/25/24 |
| Lento e curto contra pressão alta | não medido | 34/34/32 |

## Temporadas

- **Dificuldade**: a IA joga um percentual fixo acima do normal contra o técnico (fácil 3%, normal 8%, difícil 14%), sem a parte proporcional que reduzia a vantagem de elenco. Times iguais com IA +8%: 30/31/39. Com 10 de nota a mais e IA +8%: 49/32/20.
- **Exercícios pré-jogo**: finalização e criação +14%, goleiro +14%, desarme +16%, bola parada +0,14 (antes 6% a 8%).

## Online

- Preparação completa vale 6% de forma (antes 3%). Dois técnicos preparados se anulam; só um preparado ganha a diferença.
- Não há bônus de IA no online: bots e técnicos usam as mesmas regras.

## Fase 24 — partidas fiéis às táticas (13/11/2026)

Fonte: `supabase/online/26_match_realism.sql` (migração `20261114220000`). Medido com 200 jogos por cenário no banco de produção (transação desfeita no fim) e no PGlite.

- **Estatísticas**: finalizações e chutes no gol saem da súmula dos jogadores (`on_match_payload.stats.shots/sot`). Antes a tela contava lances gravados, e jogo sem ninguém assistindo não grava cada chute: um 11 x 9 aparecia como 0 x 1.
- **Técnico ausente**: `on_ai_manage` não muda mais postura, ritmo, pressão nem gestão do jogo de clube de usuário. O motor aplica a "gestão do jogo" escolhida pelo técnico; o auxiliar só substitui por cansaço, cartão ou lesão. Bots seguem com a IA.
- **Atacar tem custo**: cada nível de postura ofensiva dá ao adversário +5% de chances e +0,03 de qualidade de finalização; pressão alta com linha alta, mais +0,02.

| Cenário (PGlite, 200 jogos) | Antes (produção) | Depois |
|---|---|---|
| Iguais, casa ataque total (+2, pressão alta, rápido) | 56/21/23, sofre 1,36 | 47/20/34, sofre 1,31 com mais gols dos dois lados |
| Contra-ataque x ataque total | 42/19/39 | 56/18/27 |
| +18 de nota, neutro | 76/17/7 | 73/17/10 |
| +18 ataque total x retranca | 83/15/2 | 87/10/4 |
