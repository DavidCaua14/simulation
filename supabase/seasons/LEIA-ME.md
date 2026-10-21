# Modo Temporadas — instalação e regras

## Instalar (nesta ordem)
1. **SQL Editor do Supabase**: rode `01_schema.sql`, depois `02_seed.sql` (a última linha deve listar 20, 16 e 32 clubes) e por fim `03_engine.sql`.
2. **Copie os arquivos de `src/`** para o projeto (e rode `npm run dev`). O `App.jsx`, a Home, o ClubService e a carteira foram ajustados.
3. Abra **Temporadas** na Home. A 1ª temporada é criada sozinha.

> O passo 3 do `03_engine.sql` bloqueia o `UPDATE` direto de `careers.club_id` pelo app: a escolha do clube inicial passa a usar a função `choose_initial_club`. Por isso suba o `src/` junto.

## Como funciona
- **Tudo roda no banco** (`season_play`): o app não escolhe resultado, só pede "simular". Nada em localStorage.
- **Campeonatos** (clubes reais pesquisados em out/2026): Brasileirão Série A (20 clubes, 38 rodadas), Copa do Brasil (16 clubes a partir das oitavas, ida e volta, final única) e Libertadores (32 clubes, 8 grupos, oitavas a final).
- Você joga **só as partidas do seu clube**; o restante da rodada é simulado junto. Se você é eliminado, o resto do campeonato é jogado na hora.
- **Energia**: cada partida custa 1. A energia livre volta a 10 a cada 5h (`greatest(energia, 10)`); a **bônus** (`careers.bonus_energy`, para a loja) nunca é zerada e só é gasta depois da livre.
- **Desempenho**: a qualidade do jogador sobe com o nível (`0,25 + 0,03 × nível`, máx. 0,95) e a **posição** define a chance de seus gols/assistências (atacante marca mais, meia dá mais passes). O resultado do time é aleatório (Poisson) com base na força dos clubes.
- **Prêmios por partida**: vitória 30 XP / empate 15 / derrota 8, +10 por gol, +6 por assistência; moedas 60/25/10, +30 por gol, +15 por assistência. Copa x1,2, Libertadores x1,3, mata-mata x1,2 e final x1,5. Bônus extra ao fechar cada campeonato.
- **Nível**: a cada 1000 XP (gatilho `careers_level_up`, vale também para os palpites). ~38 partidas por nível, ou seja, cerca de 1 nível por temporada.
- **Popularidade** (0–1000): sobe com vitória, gols, assistências e boas notas. Quanto maior, mais **propostas** (máx. 3 pendentes) e de clubes maiores. **Aceitar = transferência imediata** + bônus de moedas; você continua nos campeonatos do novo clube.
- **Estatísticas** guardadas em `career_stats` (jogos, V/E/D, gols, assistências, títulos) e por temporada em `career_seasons`: base do ranking.

## Ajustes fáceis
| O quê | Onde |
|---|---|
| Força dos clubes | `sim_clubs.strength` (02_seed.sql) |
| Sensibilidade à força | `0.022` em `sim_score` (03_engine.sql) |
| Energia (10 / 5h) | `sim_lock_career` (03_engine.sql) |
| XP e moedas por partida | `season_play`, bloco "prêmios" |
| Dar energia comprada | `update careers set bonus_energy = bonus_energy + 5 where id = '...';` |

## Simplificações desta 1ª versão
- Cada temporada repete os mesmos participantes (sem classificação/rebaixamento entre temporadas).
- Quartas/semis são sorteadas a cada fase; a final é em campo neutro.
- Os 20 da Série A e os grupos refletem o sorteio real; as "forças" são estimativas editáveis.
