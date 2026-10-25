# Modo Temporadas — carreira de TREINADOR

O modo Temporadas virou um simulador de técnico (estilo Brasfoot/FM): você escala, define a tática,
acompanha a partida ao vivo, mexe no time durante o jogo e convive com diretoria, torcida, demissões e propostas.

Tudo que decide resultado roda **no banco (Supabase/Postgres)**; o app só mostra e envia as decisões do treinador.

## Como instalar (SQL Editor do Supabase, nesta ordem)

| Arquivo | O que faz |
|---|---|
| `supabase/manager/01_schema.sql` | Tabelas novas (clubes, jogadores, atributos, formações, treinador, passagens, objetivos, escalações, partidas, eventos, mensagens) + colunas novas em `career_seasons`, `season_fixtures`, `season_offers`. Só adiciona — não apaga nada. |
| `supabase/manager/02_players_seed.sql` | Elencos reais 2026 (gerado pelo script abaixo). Idempotente: pode rodar de novo. |
| `supabase/manager/03_engine.sql` | Motor de partida (minuto a minuto, probabilístico, com táticas, cansaço, cartões, lesões, substituições, prorrogação e pênaltis). |
| `supabase/manager/04_career.sql` | Carreira: calendário, rodadas, classificação com desempates oficiais, diretoria/torcida/reputação, demissão, propostas, fim de temporada e as funções chamadas pelo app. |
| `supabase/manager/05_permissions.sql` | Só as funções do app ficam liberadas para `authenticated`; o motor fica fechado. |
| `supabase/manager/06_cards_coach.sql` | (depois de `supabase/cards/01_cards.sql`) caixa de vitória conta o clube que você comandava naquele jogo. |

Desfazer: `supabase/manager/99_rollback.sql` (reativa a temporada antiga do modo atleta) e rodar de novo `supabase/seasons/03_engine.sql` e `04*.sql`.

Carreiras já existentes: na primeira abertura do modo, a temporada antiga (modo atleta) é **arquivada** e uma temporada de treinador começa no mesmo clube.

## Elencos reais (importação)

```bash
node scripts/build-squads.mjs
```

- Lê `data/squads/raw/*.txt` (uma lista por clube, com a fonte e a data de acesso no cabeçalho).
- Gera `data/squads/squads.json`, `supabase/manager/02_players_seed.sql` e o relatório `data/squads/IMPORT_REPORT.md`
  (fonte de cada clube, data do elenco, posições estimadas e conflitos resolvidos).
- Nenhum jogador é inventado. Quando a fonte só informa o setor (DEF/MEI/ATA), a posição detalhada é **estimada** e marcada.
- Atributos são **estimativa de gameplay** (força do clube + papel no elenco + perfil da posição), marcados como estimados no banco e na ficha do jogador.
  Para curar um jogador: edite `sim_player_attrs` e marque `estimated = false` — a importação não sobrescreve.

## Testes

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/manager/tests/manager_tests.sql
```

Roda numa transação com ROLLBACK (não grava nada) e verifica: dados dos elencos, início da carreira, partida ao vivo
(energia cobrada uma vez, etapa repetida não muda o jogo, substituição e tática no meio do jogo), efeito das táticas no motor,
classificação/desempates e mata-mata, demissão → propostas com o passar dos dias → troca de clube **sem reiniciar a temporada**, e permissões.

## Regras principais

- **Partida ao vivo**: o servidor simula em etapas de 5 minutos; mudanças valem dali para frente. Paradas automáticas no intervalo,
  lesão e expulsão do seu time, e antes da prorrogação. Velocidade 1x/2x/4x ou "simular até o fim" (o auxiliar decide).
- **Diretoria e torcida** reagem ao resultado comparado com o esperado (força dos times, mando de campo). Sequência ruim + pressão da
  torcida = demissão no meio da temporada. Fim de temporada avalia os objetivos.
- **Sem clube**: o campeonato continua; avance os dias e as propostas chegam conforme a reputação (depois de 6 dias sempre chega uma).
  Aceitar uma proposta no meio da temporada mantém o calendário e os resultados — você só passa a comandar outro clube.
- **Histórico**: cada passagem por clube fica registrada (jogos, V/E/D, gols, títulos e motivo da saída).
- **Mercado de transferências**: estrutura pronta (`mgr_transfers`), ainda sem negociações no jogo.
