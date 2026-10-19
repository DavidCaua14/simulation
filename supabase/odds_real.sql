-- =====================================================================
-- ODDS REAIS (The Odds API) — rode inteiro no Supabase -> SQL Editor.
-- Só ADICIONA colunas/tabela/trigger. Não altera nem apaga dados existentes.
-- Ordem: rode este SQL ANTES de publicar o front novo (ele lê odds_source).
-- =====================================================================

-- 1) Origem e trava das odds de cada jogo
alter table public.matches
  add column if not exists odds_source    text check (odds_source in ('model', 'api')),
  add column if not exists odds_locked_at timestamptz,   -- depois disso as odds NUNCA mais mudam
  add column if not exists odds_event_id  text;          -- id do jogo na The Odds API

-- odds que já existem hoje vieram do cálculo (odds.ts)
update public.matches set odds_source = 'model'
 where odds_home is not null and odds_source is null;

-- 2) Controle de consumo: quando cada campeonato foi consultado pela última vez
create table if not exists public.odds_fetch_log (
  sport_key         text primary key,
  last_fetched_at   timestamptz not null default now(),
  last_status       text,
  credits_remaining int
);
alter table public.odds_fetch_log enable row level security;   -- sem policy: só service role acessa

-- 3) Trava: odds reais (ou as do jogo já iniciado) não mudam mais.
--    Protege mesmo que algum sync futuro tente sobrescrever.
create or replace function public.matches_lock_odds()
returns trigger language plpgsql as $$
begin
  if old.odds_locked_at is not null then
    new.odds_home := old.odds_home;           new.odds_draw := old.odds_draw;
    new.odds_away := old.odds_away;           new.odds_btts_yes := old.odds_btts_yes;
    new.odds_btts_no := old.odds_btts_no;     new.odds_source := old.odds_source;
    new.odds_event_id := old.odds_event_id;   new.odds_locked_at := old.odds_locked_at;
  elsif new.odds_home is not null and new.kickoff_at <= now() then
    new.odds_locked_at := now();               -- apitou: trava o que houver
  end if;
  return new;
end $$;

drop trigger if exists matches_lock_odds_trg on public.matches;
create trigger matches_lock_odds_trg before update on public.matches
  for each row execute function public.matches_lock_odds();

-- 4) CONFERÊNCIA: o place_ticket usa as odds do jogo? (deve retornar true)
select pg_get_functiondef('public.place_ticket(integer,jsonb)'::regprocedure) like '%odds_home%' as place_ticket_usa_odds;
