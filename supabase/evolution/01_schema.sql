-- =====================================================================
-- EVOLUÇÃO 01 — ESQUEMA DO MOTOR DE COMPETIÇÕES CONFIGURÁVEL
-- Regiões (Brasil / Inglaterra), divisões, participantes por temporada, acesso e rebaixamento.
--
-- Ordem de instalação: veja supabase/evolution/LEIA-ME.md
-- Tudo é idempotente (if not exists / create or replace / on conflict). Para desfazer: evolution/99_rollback.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) CLUBES: região do campeonato nacional (BRA / ENG); estrangeiros ficam sem região
-- ---------------------------------------------------------------------
alter table public.sim_clubs add column if not exists region text;
alter table public.sim_clubs drop constraint if exists sim_clubs_tier_check;
alter table public.sim_clubs add constraint sim_clubs_tier_check
  check (tier in ('serie_a', 'serie_b', 'br_other', 'foreign', 'premier_league', 'championship'));
update public.sim_clubs set region = 'BRA' where country = 'BRA' and region is null;

-- ---------------------------------------------------------------------
-- B) COMPETIÇÕES: região, tipo, divisão, temporada de referência, fontes e tema visual
-- ---------------------------------------------------------------------
alter table public.sim_competitions add column if not exists region     text not null default 'BRA';
alter table public.sim_competitions add column if not exists kind       text not null default 'league';
alter table public.sim_competitions add column if not exists division   int;
alter table public.sim_competitions add column if not exists ref_season text;
alter table public.sim_competitions add column if not exists sources    jsonb not null default '[]'::jsonb;
alter table public.sim_competitions add column if not exists theme      jsonb not null default '{}'::jsonb;
alter table public.sim_competitions add column if not exists active     boolean not null default true;
alter table public.sim_competitions drop constraint if exists sim_competitions_kind_check;
alter table public.sim_competitions add constraint sim_competitions_kind_check check (kind in ('league', 'cup', 'continental'));

-- participantes de REFERÊNCIA (temporada oficial cadastrada): fase em que o clube entra (copas inglesas)
alter table public.sim_competition_clubs add column if not exists entry_phase text;

-- ---------------------------------------------------------------------
-- C) ACESSO E REBAIXAMENTO (configurável por região e por ano)
-- ---------------------------------------------------------------------
create table if not exists public.sim_promotion_rules (
  id                     text primary key,                       -- 'BRA:brasileirao>serie_b'
  region                 text not null,
  upper_comp             text not null references public.sim_competitions (id),
  lower_comp             text not null references public.sim_competitions (id),
  relegated              int  not null check (relegated >= 0),   -- caem da divisão de cima
  promoted_direct        int  not null check (promoted_direct >= 0),
  promoted_playoff_phase text,                                   -- vencedores desta fase também sobem
  from_year              int  not null default 2026,
  to_year                int,
  source                 text,
  check (upper_comp <> lower_comp),
  check (to_year is null or to_year >= from_year)
);

-- ---------------------------------------------------------------------
-- D) TEMPORADA: região + participantes de cada competição (por carreira)
-- ---------------------------------------------------------------------
alter table public.career_seasons add column if not exists region text not null default 'BRA';

create table if not exists public.season_participants (
  season_id      uuid not null references public.career_seasons (id) on delete cascade,
  competition_id text not null references public.sim_competitions (id),
  club_id        text not null references public.sim_clubs (id),
  group_label    text,                 -- grupo (Libertadores) / confronto fixo (Copa do Brasil: T1..T8)
  seed           int,                  -- pote (UCL) / mando no confronto fixo (Copa do Brasil)
  entry_phase    text,                 -- fase em que entra (null = primeira fase)
  division_key   text,                 -- 'BRA:league' nas ligas: um clube só pode estar em UMA divisão por temporada
  origin         text not null default 'reference'
                 check (origin in ('reference', 'stayed', 'promoted', 'relegated', 'qualified', 'league', 'legacy')),
  primary key (season_id, competition_id, club_id)
);
create unique index if not exists season_participants_division_uq
  on public.season_participants (season_id, division_key, club_id) where division_key is not null;
create index if not exists season_participants_club_idx on public.season_participants (season_id, club_id);

-- resultado do fim de temporada (quem sobe, quem cai, quem se classifica). UMA linha por temporada:
-- a chave única impede que o acesso/rebaixamento seja aplicado duas vezes.
create table if not exists public.season_transitions (
  id          bigint generated always as identity primary key,
  career_id   uuid not null references public.careers (id) on delete cascade,
  region      text not null,
  from_season uuid not null unique references public.career_seasons (id) on delete cascade,
  year        int  not null,
  result      jsonb not null,          -- {leagues:{comp:[clubes]}, promoted:{...}, relegated:{...}, qualified:{comp:[clubes]}}
  applied_at  timestamptz not null default now()
);
create index if not exists season_transitions_career_idx on public.season_transitions (career_id, region, year desc);

-- ---------------------------------------------------------------------
-- E) SEGURANÇA: leitura pelo app; escrita só pelas funções do servidor
-- ---------------------------------------------------------------------
alter table public.sim_promotion_rules  enable row level security;
alter table public.season_participants  enable row level security;
alter table public.season_transitions   enable row level security;
revoke all on public.sim_promotion_rules, public.season_participants, public.season_transitions from anon, authenticated;
grant select on public.sim_promotion_rules, public.season_participants, public.season_transitions to authenticated;

drop policy if exists "read_sim_promotion_rules" on public.sim_promotion_rules;
create policy "read_sim_promotion_rules" on public.sim_promotion_rules for select to authenticated using (true);
drop policy if exists "own_season_participants" on public.season_participants;
create policy "own_season_participants" on public.season_participants for select to authenticated
  using (exists (select 1 from public.career_seasons s join public.careers c on c.id = s.career_id
                 where s.id = season_id and c.user_id = auth.uid()));
drop policy if exists "own_season_transitions" on public.season_transitions;
create policy "own_season_transitions" on public.season_transitions for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));

-- ---------------------------------------------------------------------
-- F) TEMPORADAS JÁ EXISTENTES: participantes reconstruídos a partir dos próprios jogos (nada é apagado)
-- ---------------------------------------------------------------------
insert into public.season_participants (season_id, competition_id, club_id, group_label, division_key, origin)
select distinct on (x.season_id, x.competition_id, x.club_id)
       x.season_id, x.competition_id, x.club_id, x.group_label,
       case when x.competition_id = 'brasileirao' then 'BRA:league' end, 'legacy'
  from (
    select f.season_id, f.competition_id, f.home_club as club_id, f.group_label, f.stage from public.season_fixtures f
    union all
    select f.season_id, f.competition_id, f.away_club, f.group_label, f.stage from public.season_fixtures f
  ) x
 order by x.season_id, x.competition_id, x.club_id, (x.stage in ('group', 'league')) desc
on conflict do nothing;
-- Copa do Brasil: confronto fixo e mando das oitavas de referência
update public.season_participants sp
   set group_label = cc.group_label, seed = cc.seed
  from public.sim_competition_clubs cc
 where sp.origin = 'legacy' and sp.competition_id = 'copa_brasil' and cc.competition_id = 'copa_brasil' and cc.club_id = sp.club_id;
