# Evolução — migrações versionadas

Cada arquivo numerado é uma migração **idempotente** (pode rodar de novo sem duplicar nada). Em produção elas são
aplicadas pelo `apply_migration` com o mesmo nome do arquivo e aparecem em `list_migrations`.

## Ordem de instalação (banco novo)

```
supabase/seasons/01_schema.sql      supabase/seasons/02_seed.sql
supabase/seasons/03_engine.sql      supabase/seasons/04_features.sql
supabase/manager/01_schema.sql
supabase/evolution/01_schema.sql            <- regiões, divisões, participantes por temporada, acesso/rebaixamento
supabase/evolution/02_reference_data.sql    <- clubes, competições e participantes oficiais (gerado)
supabase/manager/02_players_seed.sql        <- elencos (gerado; agora com os clubes novos)
supabase/manager/03_engine.sql  04_career.sql  05_permissions.sql
supabase/cards/01..04
supabase/manager/06_cards_coach.sql
supabase/evolution/03_engine.sql            <- motor de competições configurável
supabase/evolution/04_manager.sql           <- carreira do treinador no motor configurável
supabase/evolution/05_career_start.sql      <- clube inicial pela nacionalidade + perfis de dificuldade
supabase/evolution/06+ ...                  <- próximas etapas
```

Banco que já estava no ar: rode só `evolution/01`, `evolution/02`, `manager/02_players_seed.sql` (gerado de novo) e
`evolution/03`, `evolution/04`. Temporadas em andamento continuam (os participantes são reconstruídos a partir dos jogos
e a próxima temporada já nasce com Série B e acesso/rebaixamento).

## Dados gerados (não edite o SQL à mão)

| Arquivo | Gerado por | A partir de |
|---|---|---|
| `evolution/02_reference_data.sql`, `src/features/club/data/clubCatalog.js`, `data/clubs/generated_strength.json` | `node scripts/build-competitions.mjs` | `data/clubs/clubs_evolution.json`, `data/competitions/competitions.json`, `data/competitions/ucl_swiss_templates.json` |
| `manager/02_players_seed.sql`, `data/squads/squads.json`, `data/squads/IMPORT_REPORT.md` | `node scripts/build-squads.mjs` | `data/squads/raw/*.txt` |
| `data/competitions/ucl_swiss_templates.json` | `python3 scripts/gen-swiss-template.py 4` | — |

## Mudar um regulamento

Edite `data/competitions/competitions.json` (fases, mando, prorrogação, pênaltis, chaveamento, desempates, zonas,
objetivos, rodadas do calendário) e rode `node scripts/build-competitions.mjs`. Acesso e rebaixamento por ano ficam em
`promotion` (tabela `sim_promotion_rules`, com `from_year`/`to_year`). O motor lê a configuração; não há regra fixa no código.

## Clube inicial por nacionalidade

Tabela `sim_start_rules` (uma linha por nacionalidade, mesmo código de `careers.country`) e `sim_difficulty_profiles`.
Nova nacionalidade = inserir uma linha em `sim_start_rules` + a bandeira em `src/features/player/components/flags.jsx` e
`src/features/player/data/countries.js`. A tela de criação só mostra nacionalidades que têm regra ativa no banco, e o
banco recusa (`careers_country_fkey`) carreira com nacionalidade sem regra.

## Testes

```
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/competitions_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/manager/tests/manager_tests.sql
psql -v ON_ERROR_STOP=1 -f supabase/evolution/tests/career_start_tests.sql
```

## Desfazer

`evolution/99_rollback.sql` remove as tabelas novas e as competições novas (as temporadas antigas continuam).
As funções voltam ao comportamento anterior rodando de novo `supabase/seasons/03_engine.sql`, `04_features.sql`
e `supabase/manager/03_engine.sql`, `04_career.sql`.
