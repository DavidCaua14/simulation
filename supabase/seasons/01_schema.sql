-- =====================================================================
-- MODO TEMPORADAS — 1/3: ESQUEMA (tabelas, segurança, energia, nível)
-- Rode os 3 arquivos NESTA ORDEM no Supabase -> SQL Editor.
-- Pode rodar de novo sem medo: tudo é "if not exists" / "create or replace".
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) ENERGIA: energia livre (recarrega) + energia bônus (comprada, nunca zera)
-- ---------------------------------------------------------------------
alter table public.careers add column if not exists bonus_energy    integer     not null default 0;
alter table public.careers add column if not exists energy_reset_at timestamptz not null default now();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'careers_bonus_energy_check') then
    alter table public.careers add constraint careers_bonus_energy_check check (bonus_energy >= 0);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- B) NÍVEL: a cada 1000 XP o jogador sobe de nível (vale para QUALQUER fonte de XP:
--    temporadas, palpites...). O XP que sobra continua na barra.
-- ---------------------------------------------------------------------
create or replace function public.careers_level_up()
returns trigger language plpgsql as $$
begin
  while new.xp >= 1000 loop
    new.xp    := new.xp - 1000;
    new.level := new.level + 1;
  end loop;
  return new;
end;
$$;

drop trigger if exists careers_level_up_trg on public.careers;
create trigger careers_level_up_trg
  before update of xp on public.careers
  for each row when (new.xp >= 1000)
  execute function public.careers_level_up();

-- ---------------------------------------------------------------------
-- C) CATÁLOGO (dados fixos, iguais para todo mundo)
-- ---------------------------------------------------------------------
create table if not exists public.sim_clubs (
  id              text primary key,                 -- slug: 'flamengo', 'boca-juniors'...
  name            text not null,
  short_name      text not null,                    -- 3 letras p/ placar
  country         text not null,                    -- 'BRA', 'ARG'...
  tier            text not null check (tier in ('serie_a', 'br_other', 'foreign')),
  strength        smallint not null check (strength between 30 and 99),  -- "força" do clube (edite à vontade)
  color_primary   text not null,
  color_secondary text not null
);

create table if not exists public.sim_competitions (
  id         text primary key,                      -- 'brasileirao' | 'copa_brasil' | 'libertadores'
  name       text not null,
  short_name text not null,
  sort_order int  not null default 100,
  xp_mult    numeric(3,2) not null default 1        -- multiplicador de XP/moedas por partida
);

-- Quem disputa o quê.
--  brasileirao : group_label = null
--  libertadores: group_label = 'A'..'H' (grupo)
--  copa_brasil : group_label = 'T1'..'T8' (confronto das oitavas); seed 1 = joga a IDA em casa, seed 2 = a VOLTA
create table if not exists public.sim_competition_clubs (
  competition_id text not null references public.sim_competitions (id) on delete cascade,
  club_id        text not null references public.sim_clubs (id) on delete cascade,
  group_label    text,
  seed           smallint,
  primary key (competition_id, club_id)
);

-- ---------------------------------------------------------------------
-- D) PROGRESSO DO JOGADOR (tudo no banco; nada em localStorage)
-- ---------------------------------------------------------------------
-- Estatísticas da carreira inteira (base do ranking futuro) + popularidade
create table if not exists public.career_stats (
  career_id     uuid primary key references public.careers (id) on delete cascade,
  matches       int not null default 0,
  wins          int not null default 0,
  draws         int not null default 0,
  losses        int not null default 0,
  goals         int not null default 0,
  assists       int not null default 0,
  popularity    int not null default 0 check (popularity between 0 and 1000),
  seasons_played int not null default 0,
  titles        int not null default 0,
  updated_at    timestamptz not null default now()
);

create table if not exists public.career_seasons (
  id          uuid primary key default gen_random_uuid(),
  career_id   uuid not null references public.careers (id) on delete cascade,
  season_no   int  not null,
  year        int  not null,
  club_id     text not null references public.sim_clubs (id),   -- clube ATUAL do jogador nesta temporada
  status      text not null default 'active' check (status in ('active', 'finished')),
  matches     int not null default 0,
  wins        int not null default 0,
  draws       int not null default 0,
  losses      int not null default 0,
  goals       int not null default 0,
  assists     int not null default 0,
  xp_earned   int not null default 0,
  coins_earned int not null default 0,
  summary     jsonb,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  unique (career_id, season_no)
);
create unique index if not exists career_seasons_one_active_idx on public.career_seasons (career_id) where status = 'active';

create table if not exists public.season_competitions (
  season_id      uuid not null references public.career_seasons (id) on delete cascade,
  competition_id text not null references public.sim_competitions (id),
  stage          text not null,                                  -- fase atual: league|group|r16|qf|sf|final
  status         text not null default 'pending' check (status in ('pending', 'active', 'finished')),
  champion_club  text,
  runner_up_club text,
  player_club    text,                                           -- clube do jogador quando acabou
  player_result  text,                                           -- 'Campeão', '3º lugar', 'Eliminado nas quartas'...
  player_bonus_xp    int,
  player_bonus_coins int,
  primary key (season_id, competition_id)
);
alter table public.season_competitions add column if not exists player_bonus_xp    int;
alter table public.season_competitions add column if not exists player_bonus_coins int;

create table if not exists public.season_fixtures (
  id             bigint generated always as identity primary key,
  season_id      uuid not null references public.career_seasons (id) on delete cascade,
  competition_id text not null references public.sim_competitions (id),
  stage          text not null,
  round_no       int  not null,                                  -- rodada (liga/grupos) ou 1=ida, 2=volta
  group_label    text,
  tie_no         int,
  leg            int,
  home_club      text not null references public.sim_clubs (id),
  away_club      text not null references public.sim_clubs (id),
  home_goals     int,
  away_goals     int,
  home_pens      int,
  away_pens      int,
  tie_winner     text,                                           -- preenchido no jogo que decide a eliminatória
  status         text not null default 'pending' check (status in ('pending', 'played')),
  player_match   boolean not null default false,                 -- partida jogada pelo usuário
  player_goals   int,
  player_assists int,
  player_rating  numeric(3,1),
  played_at      timestamptz
);
create index if not exists season_fixtures_comp_idx  on public.season_fixtures (season_id, competition_id, status, round_no);
create index if not exists season_fixtures_home_idx  on public.season_fixtures (season_id, home_club);
create index if not exists season_fixtures_away_idx  on public.season_fixtures (season_id, away_club);

create table if not exists public.season_offers (
  id           uuid primary key default gen_random_uuid(),
  career_id    uuid not null references public.careers (id) on delete cascade,
  season_id    uuid references public.career_seasons (id) on delete set null,
  from_club    text not null references public.sim_clubs (id),
  bonus_coins  int  not null default 0,
  pitch        text,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists season_offers_career_idx on public.season_offers (career_id, status);

-- ---------------------------------------------------------------------
-- E) SEGURANÇA: o app só LÊ. Toda escrita passa pelas funções (security definer).
-- ---------------------------------------------------------------------
alter table public.sim_clubs             enable row level security;
alter table public.sim_competitions      enable row level security;
alter table public.sim_competition_clubs enable row level security;
alter table public.career_stats          enable row level security;
alter table public.career_seasons        enable row level security;
alter table public.season_competitions   enable row level security;
alter table public.season_fixtures       enable row level security;
alter table public.season_offers         enable row level security;

revoke all on public.sim_clubs, public.sim_competitions, public.sim_competition_clubs,
              public.career_stats, public.career_seasons, public.season_competitions,
              public.season_fixtures, public.season_offers from anon, authenticated;
grant select on public.sim_clubs, public.sim_competitions, public.sim_competition_clubs,
                public.career_stats, public.career_seasons, public.season_competitions,
                public.season_fixtures, public.season_offers to authenticated;

drop policy if exists "read_sim_clubs" on public.sim_clubs;
create policy "read_sim_clubs" on public.sim_clubs for select to authenticated using (true);
drop policy if exists "read_sim_competitions" on public.sim_competitions;
create policy "read_sim_competitions" on public.sim_competitions for select to authenticated using (true);
drop policy if exists "read_sim_competition_clubs" on public.sim_competition_clubs;
create policy "read_sim_competition_clubs" on public.sim_competition_clubs for select to authenticated using (true);

drop policy if exists "own_career_stats" on public.career_stats;
create policy "own_career_stats" on public.career_stats for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));

drop policy if exists "own_career_seasons" on public.career_seasons;
create policy "own_career_seasons" on public.career_seasons for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));

drop policy if exists "own_season_competitions" on public.season_competitions;
create policy "own_season_competitions" on public.season_competitions for select to authenticated
  using (exists (select 1 from public.career_seasons s join public.careers c on c.id = s.career_id
                 where s.id = season_id and c.user_id = auth.uid()));

drop policy if exists "own_season_fixtures" on public.season_fixtures;
create policy "own_season_fixtures" on public.season_fixtures for select to authenticated
  using (exists (select 1 from public.career_seasons s join public.careers c on c.id = s.career_id
                 where s.id = season_id and c.user_id = auth.uid()));

drop policy if exists "own_season_offers" on public.season_offers;
create policy "own_season_offers" on public.season_offers for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));
