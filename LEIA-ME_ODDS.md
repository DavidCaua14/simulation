# Odds reais (The Odds API) — passo a passo

## Como funciona
1. O banco continua recebendo os jogos como hoje (com as odds calculadas pelo odds.ts, `odds_source = 'model'`).
2. A função `sync-odds` roda a cada 2h. Para cada campeonato com jogo nos próximos 4 dias SEM odd real,
   faz 1 chamada (1 crédito) que traz todos os jogos daquele campeonato.
3. Ela casa os jogos pelo horário e pelo nome dos times, tira a MEDIANA das casas de aposta e grava
   odds_home / odds_draw / odds_away com `odds_source = 'api'` e `odds_locked_at` preenchido.
4. Depois disso as odds do jogo NUNCA mais mudam (trigger do banco), como numa casa de aposta que fecha
   o mercado. O bilhete já guarda o multiplicador do momento da aposta.
5. Jogo que a API não tem (ou não casou) continua com a odd calculada. Nada quebra.
"Ambas marcam" continua calculado pelo odds.ts: na The Odds API esse mercado custa 1 crédito POR JOGO.

## 0) SEGURANÇA (faça primeiro)
A chave apareceu na conversa. Gere outra: painel da The Odds API -> regenerar chave.
Nunca coloque a chave no front-end, no zip, no GitHub. Ela vive só nos segredos do Supabase.

## 1) Banco
Supabase -> SQL Editor -> rode `supabase/odds_real.sql`.
A última linha do arquivo deve mostrar `true`. Se mostrar `false`, o place_ticket em produção ignora as
odds do jogo e paga valores fixos: me envie a função completa (o print veio cortado) que eu ajusto.

## 2) Chaves de esporte da sua conta (grátis, não gasta crédito)
Abra no navegador, com a chave NOVA:
  https://api.the-odds-api.com/v4/sports/?apiKey=SUA_CHAVE
Procure os campeonatos do seu banco e compare com `SPORT_BY_FD_LEAGUE` em
`supabase/functions/sync-odds/oddsApi.ts`. Se alguma chave for diferente (ou não existir), ajuste ali.
(As chaves do arquivo foram escritas de memória e NÃO foram verificadas contra a sua conta.)

## 3) Publicar a função
    supabase secrets set ODDS_API_KEY=SUA_CHAVE_NOVA CRON_SECRET=uma-senha-longa-e-aleatoria
    supabase functions deploy sync-odds --no-verify-jwt

(`--no-verify-jwt` é seguro aqui porque a função exige o cabeçalho x-cron-secret.)

## 4) Testar na mão (gasta alguns créditos)
    curl -X POST "https://SEU_PROJECT_REF.supabase.co/functions/v1/sync-odds?force=1" \
         -H "x-cron-secret: uma-senha-longa-e-aleatoria"
A resposta mostra, por campeonato: quantos jogos tinham, quantos receberam odd real (`updated`) e
quais não casaram (`unmatched`). Nomes em `unmatched` que deveriam casar -> acrescente em ALIASES
no `matching.ts`. Confira depois: select id, home_team, away_team, odds_home, odds_draw, odds_away,
odds_source from matches where odds_source = 'api';

## 5) Agendar
Ative as extensões pg_cron e pg_net, edite e rode `supabase/schedule_sync_odds.sql`.

## 6) Front
Copie `predictionsApi.js` e `MatchDetailsSheet.jsx` (só DEPOIS do passo 1, pois o app passa a ler
`odds_source`). O detalhe do jogo mostra se a odd é "de mercado" ou "estimada".

## Consumo de créditos (500/mês no plano grátis) — estimativa
1 crédito por consulta de campeonato. No máximo 2 consultas/dia por campeonato, só quando há jogo sem
odd real nos próximos 4 dias. Com ~8 campeonatos em temporada dá algo como 150 a 350 créditos/mês.
A função para sozinha quando restarem 40 créditos (ODDS_CREDIT_RESERVE). Para gastar menos:
ODDS_MIN_INTERVAL_HOURS=24. O consumo real aparece em `creditsRemaining` na resposta e na tabela odds_fetch_log.

## Limites conhecidos
- Séries B e C estão inativas no seu banco (a football-data.org grátis não as entrega); o mapa já tem a Série B.
- Copa do Mundo/Eurocopa só terão odds quando houver jogos próximos.
- Confira os termos da The Odds API para exibir as odds num app, e deixe claro ao jogador que é simulação.
