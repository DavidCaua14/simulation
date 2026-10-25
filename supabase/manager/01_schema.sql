-- =====================================================================
-- MODO CARREIRA (TREINADOR) — 1/5: ESQUEMA
-- Rode DEPOIS de supabase/seasons/01..04 e supabase/cards/01..02.
-- Ordem: 01_schema -> 02_players_seed -> 03_engine -> 04_career -> 05_permissions
-- 100% ADITIVO: nenhuma tabela antiga é apagada. O modo antigo (jogador) continua funcionando
-- e os dados dele ficam guardados (temporadas antigas viram status 'archived' quando a carreira
-- de treinador começa). Para voltar atrás: supabase/manager/99_rollback.sql
-- Pode rodar de novo sem medo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) CATÁLOGO (igual para todos; o app só lê)
-- ---------------------------------------------------------------------
alter table public.sim_clubs add column if not exists full_name text;
alter table public.sim_clubs add column if not exists city text;
alter table public.sim_clubs add column if not exists article text not null default 'o';   -- "o Flamengo" / "a Chapecoense"
update public.sim_clubs set article = 'a' where id in ('chapecoense', 'u-catolica', 'ldu', 'u-central');

-- Regras configuráveis de cada competição (formato, desempate, banco, substituições...)
alter table public.sim_competitions add column if not exists rules jsonb not null default '{}'::jsonb;
update public.sim_competitions set rules = jsonb_build_object(
  'format', 'league', 'legs', 2, 'points', jsonb_build_object('win', 3, 'draw', 1),
  'tiebreakers', jsonb_build_array('points', 'wins', 'gd', 'gf', 'h2h_pts', 'reds', 'yellows'),
  'relegation', 4, 'bench', 12, 'max_subs', 5, 'sub_windows', 3,
  'yellow_limit', 3, 'season_matches', 38)
 where id = 'brasileirao';
update public.sim_competitions set rules = jsonb_build_object(
  'format', 'knockout', 'start_stage', 'r16', 'legs', 2, 'final_legs', 1, 'final_extra_time', false,
  'away_goals', false, 'tie', 'penalties', 'bench', 12, 'max_subs', 5, 'sub_windows', 3, 'yellow_limit', 3)
 where id = 'copa_brasil';
update public.sim_competitions set rules = jsonb_build_object(
  'format', 'groups_knockout', 'groups', 8, 'group_size', 4, 'qualify', 2, 'legs', 2, 'final_legs', 1,
  'final_extra_time', true, 'away_goals', false, 'tie', 'penalties',
  'tiebreakers', jsonb_build_array('points', 'h2h_pts', 'h2h_gd', 'h2h_gf', 'gd', 'gf', 'fairplay'),
  'bench', 12, 'max_subs', 5, 'sub_windows', 3, 'yellow_limit', 3)
 where id = 'libertadores';

-- Posições (o app usa os códigos em português)
create table if not exists public.sim_positions (
  code   text primary key,           -- GOL LD ZAG LE VOL MC MEI PD PE ATA
  name   text not null,
  line   text not null check (line in ('GK', 'DEF', 'MID', 'ATT')),
  sort   smallint not null,
  w_att  numeric(4,2) not null,      -- peso da posição no ATAQUE do time (motor)
  w_def  numeric(4,2) not null,      -- peso na DEFESA
  w_ctl  numeric(4,2) not null,      -- peso no CONTROLE (posse)
  drain  numeric(4,2) not null       -- desgaste físico relativo por minuto
);
insert into public.sim_positions (code, name, line, sort, w_att, w_def, w_ctl, drain) values
  ('GOL', 'Goleiro',          'GK',  1, 0.00, 0.00, 0.20, 0.30),
  ('LD',  'Lateral-direito',  'DEF', 2, 0.35, 0.75, 0.50, 1.10),
  ('ZAG', 'Zagueiro',         'DEF', 3, 0.10, 1.00, 0.35, 0.85),
  ('LE',  'Lateral-esquerdo', 'DEF', 4, 0.35, 0.75, 0.50, 1.10),
  ('VOL', 'Volante',          'MID', 5, 0.20, 0.70, 0.85, 1.05),
  ('MC',  'Meio-campista',    'MID', 6, 0.35, 0.40, 1.00, 1.10),
  ('MEI', 'Meia',             'MID', 7, 0.75, 0.15, 0.85, 1.00),
  ('PD',  'Ponta-direita',    'ATT', 8, 0.90, 0.15, 0.45, 1.10),
  ('PE',  'Ponta-esquerda',   'ATT', 9, 0.90, 0.15, 0.45, 1.10),
  ('ATA', 'Atacante',         'ATT', 10, 1.00, 0.05, 0.30, 0.95)
on conflict (code) do update set name = excluded.name, line = excluded.line, sort = excluded.sort,
  w_att = excluded.w_att, w_def = excluded.w_def, w_ctl = excluded.w_ctl, drain = excluded.drain;

-- Adequação: quão bem um jogador da posição "from" rende jogando em "to" (1 = posição natural)
create table if not exists public.sim_position_fit (
  from_pos text not null references public.sim_positions (code),
  to_pos   text not null references public.sim_positions (code),
  fit      numeric(3,2) not null check (fit between 0 and 1),
  primary key (from_pos, to_pos)
);
insert into public.sim_position_fit (from_pos, to_pos, fit)
select f.code, t.code,
  case
    when f.code = t.code then 1.00
    when f.code = 'GOL' or t.code = 'GOL' then 0.45
    when (f.code, t.code) in (('LD','LE'),('LE','LD'),('PD','PE'),('PE','PD'),('VOL','MC'),('MC','VOL'),('MC','MEI'),('MEI','MC')) then 0.93
    when (f.code, t.code) in (('ZAG','VOL'),('VOL','ZAG'),('LD','ZAG'),('LE','ZAG'),('ZAG','LD'),('ZAG','LE'),
                              ('MEI','PD'),('MEI','PE'),('PD','MEI'),('PE','MEI'),('PD','ATA'),('PE','ATA'),('ATA','PD'),('ATA','PE'),
                              ('MEI','ATA'),('ATA','MEI'),('LD','PD'),('LE','PE'),('PD','LD'),('PE','LE')) then 0.88
    when f.line = t.line then 0.85
    when (f.line, t.line) in (('DEF','MID'),('MID','DEF'),('MID','ATT'),('ATT','MID')) then 0.78
    else 0.65
  end
from public.sim_positions f cross join public.sim_positions t
on conflict (from_pos, to_pos) do nothing;   -- valores editados à mão são preservados

-- Pesos de cada atributo na nota por posição (balanceamento ajustável SEM mexer nos atributos)
create table if not exists public.sim_role_weights (
  pos    text not null references public.sim_positions (code),
  attr   text not null,
  weight numeric(4,2) not null check (weight > 0),
  primary key (pos, attr)
);
insert into public.sim_role_weights (pos, attr, weight) values
  ('GOL','gk_reflexes',4),('GOL','gk_handling',3),('GOL','gk_positioning',3),('GOL','passing',0.5),
  ('ZAG','marking',3),('ZAG','tackling',3),('ZAG','positioning',3),('ZAG','heading',2.5),('ZAG','strength',1.5),('ZAG','pace',1),('ZAG','passing',1),
  ('LD','tackling',2),('LD','marking',2),('LD','positioning',1.5),('LD','pace',2.5),('LD','stamina',2),('LD','passing',1.5),('LD','dribbling',1),('LD','technique',1),
  ('LE','tackling',2),('LE','marking',2),('LE','positioning',1.5),('LE','pace',2.5),('LE','stamina',2),('LE','passing',1.5),('LE','dribbling',1),('LE','technique',1),
  ('VOL','tackling',3),('VOL','marking',2),('VOL','positioning',2.5),('VOL','passing',2),('VOL','stamina',2),('VOL','strength',1),('VOL','vision',1),
  ('MC','passing',3),('MC','vision',2),('MC','technique',2),('MC','stamina',2),('MC','tackling',1),('MC','positioning',1),('MC','off_ball',0.5),('MC','finishing',0.5),
  ('MEI','vision',3),('MEI','passing',2.5),('MEI','technique',2.5),('MEI','dribbling',2),('MEI','off_ball',1.5),('MEI','finishing',1.5),
  ('PD','pace',2.5),('PD','dribbling',2.5),('PD','technique',2),('PD','off_ball',1.5),('PD','finishing',1.5),('PD','passing',1),('PD','stamina',1),
  ('PE','pace',2.5),('PE','dribbling',2.5),('PE','technique',2),('PE','off_ball',1.5),('PE','finishing',1.5),('PE','passing',1),('PE','stamina',1),
  ('ATA','finishing',3.5),('ATA','off_ball',2.5),('ATA','heading',1.5),('ATA','strength',1.5),('ATA','pace',1.5),('ATA','technique',1),('ATA','dribbling',1)
on conflict (pos, attr) do nothing;

-- Formações: cada vaga tem uma posição real e coordenadas no campo (x 0-100 esquerda->direita, y 0-100 ataque->defesa)
create table if not exists public.sim_formations (
  id     text primary key,          -- '4-3-3'
  name   text not null,
  sort   smallint not null,
  slots  jsonb not null             -- [{"slot":"GOL","pos":"GOL","x":50,"y":92}, ...] (11 vagas)
);
insert into public.sim_formations (id, name, sort, slots) values
('4-3-3', '4-3-3', 1, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"LD","pos":"LD","x":86,"y":72},{"slot":"ZAG1","pos":"ZAG","x":62,"y":77},{"slot":"ZAG2","pos":"ZAG","x":38,"y":77},{"slot":"LE","pos":"LE","x":14,"y":72},
  {"slot":"VOL","pos":"VOL","x":50,"y":58},{"slot":"MC1","pos":"MC","x":70,"y":46},{"slot":"MC2","pos":"MC","x":30,"y":46},
  {"slot":"PD","pos":"PD","x":82,"y":22},{"slot":"ATA","pos":"ATA","x":50,"y":14},{"slot":"PE","pos":"PE","x":18,"y":22}]'),
('4-4-2', '4-4-2', 2, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"LD","pos":"LD","x":86,"y":72},{"slot":"ZAG1","pos":"ZAG","x":62,"y":77},{"slot":"ZAG2","pos":"ZAG","x":38,"y":77},{"slot":"LE","pos":"LE","x":14,"y":72},
  {"slot":"MD","pos":"PD","x":84,"y":44},{"slot":"VOL","pos":"VOL","x":60,"y":52},{"slot":"MC","pos":"MC","x":40,"y":48},{"slot":"ME","pos":"PE","x":16,"y":44},
  {"slot":"ATA1","pos":"ATA","x":62,"y":17},{"slot":"ATA2","pos":"ATA","x":38,"y":17}]'),
('4-2-3-1', '4-2-3-1', 3, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"LD","pos":"LD","x":86,"y":72},{"slot":"ZAG1","pos":"ZAG","x":62,"y":77},{"slot":"ZAG2","pos":"ZAG","x":38,"y":77},{"slot":"LE","pos":"LE","x":14,"y":72},
  {"slot":"VOL1","pos":"VOL","x":62,"y":56},{"slot":"VOL2","pos":"MC","x":38,"y":56},
  {"slot":"PD","pos":"PD","x":82,"y":32},{"slot":"MEI","pos":"MEI","x":50,"y":34},{"slot":"PE","pos":"PE","x":18,"y":32},
  {"slot":"ATA","pos":"ATA","x":50,"y":13}]'),
('4-1-4-1', '4-1-4-1', 4, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"LD","pos":"LD","x":86,"y":72},{"slot":"ZAG1","pos":"ZAG","x":62,"y":77},{"slot":"ZAG2","pos":"ZAG","x":38,"y":77},{"slot":"LE","pos":"LE","x":14,"y":72},
  {"slot":"VOL","pos":"VOL","x":50,"y":60},
  {"slot":"MD","pos":"PD","x":85,"y":38},{"slot":"MC1","pos":"MC","x":63,"y":42},{"slot":"MC2","pos":"MEI","x":37,"y":42},{"slot":"ME","pos":"PE","x":15,"y":38},
  {"slot":"ATA","pos":"ATA","x":50,"y":14}]'),
('3-5-2', '3-5-2', 5, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"ZAG1","pos":"ZAG","x":72,"y":76},{"slot":"ZAG2","pos":"ZAG","x":50,"y":79},{"slot":"ZAG3","pos":"ZAG","x":28,"y":76},
  {"slot":"ALD","pos":"LD","x":90,"y":46},{"slot":"VOL","pos":"VOL","x":50,"y":56},{"slot":"MC1","pos":"MC","x":67,"y":42},{"slot":"MC2","pos":"MEI","x":33,"y":42},{"slot":"ALE","pos":"LE","x":10,"y":46},
  {"slot":"ATA1","pos":"ATA","x":62,"y":16},{"slot":"ATA2","pos":"ATA","x":38,"y":16}]'),
('3-4-3', '3-4-3', 6, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"ZAG1","pos":"ZAG","x":72,"y":76},{"slot":"ZAG2","pos":"ZAG","x":50,"y":79},{"slot":"ZAG3","pos":"ZAG","x":28,"y":76},
  {"slot":"ALD","pos":"LD","x":88,"y":48},{"slot":"VOL","pos":"VOL","x":60,"y":52},{"slot":"MC","pos":"MC","x":40,"y":52},{"slot":"ALE","pos":"LE","x":12,"y":48},
  {"slot":"PD","pos":"PD","x":80,"y":20},{"slot":"ATA","pos":"ATA","x":50,"y":14},{"slot":"PE","pos":"PE","x":20,"y":20}]'),
('5-3-2', '5-3-2', 7, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"ALD","pos":"LD","x":90,"y":64},{"slot":"ZAG1","pos":"ZAG","x":70,"y":77},{"slot":"ZAG2","pos":"ZAG","x":50,"y":80},{"slot":"ZAG3","pos":"ZAG","x":30,"y":77},{"slot":"ALE","pos":"LE","x":10,"y":64},
  {"slot":"VOL","pos":"VOL","x":50,"y":54},{"slot":"MC1","pos":"MC","x":70,"y":44},{"slot":"MC2","pos":"MC","x":30,"y":44},
  {"slot":"ATA1","pos":"ATA","x":62,"y":17},{"slot":"ATA2","pos":"ATA","x":38,"y":17}]'),
('4-3-1-2', '4-3-1-2', 8, '[
  {"slot":"GOL","pos":"GOL","x":50,"y":92},
  {"slot":"LD","pos":"LD","x":86,"y":72},{"slot":"ZAG1","pos":"ZAG","x":62,"y":77},{"slot":"ZAG2","pos":"ZAG","x":38,"y":77},{"slot":"LE","pos":"LE","x":14,"y":72},
  {"slot":"VOL","pos":"VOL","x":50,"y":58},{"slot":"MC1","pos":"MC","x":72,"y":49},{"slot":"MC2","pos":"MC","x":28,"y":49},
  {"slot":"MEI","pos":"MEI","x":50,"y":34},
  {"slot":"ATA1","pos":"ATA","x":63,"y":16},{"slot":"ATA2","pos":"ATA","x":37,"y":16}]')
on conflict (id) do update set name = excluded.name, sort = excluded.sort, slots = excluded.slots;

-- Jogadores reais (sem foto). club_id = clube de REFERÊNCIA (o snapshot importado).
create table if not exists public.sim_players (
  id                  text primary key,                 -- slug estável (nome + nacionalidade)
  full_name           text not null,
  short_name          text not null,
  club_id             text references public.sim_clubs (id) on delete set null,
  shirt_number        smallint,
  position            text not null references public.sim_positions (code),
  secondary_positions text[] not null default '{}',
  position_estimated  boolean not null default false,  -- a fonte só dizia DEF/MEI/ATA
  nationality         text,                             -- código de 3 letras; null = desconhecida
  birth_date          date,                             -- desconhecida nas fontes atuais
  age                 smallint,
  foot                text check (foot in ('D', 'E', 'A')),
  is_captain          boolean not null default false,
  is_youth            boolean not null default false,
  notes               text,
  active              boolean not null default true,
  source_url          text,
  source_as_of        date,
  imported_at         timestamptz not null default now()
);
create index if not exists sim_players_club_idx on public.sim_players (club_id) where active;

-- Atributos (1-99). SEPARADOS das notas derivadas: dá para rebalancear sem tocar aqui.
create table if not exists public.sim_player_attrs (
  player_id      text primary key references public.sim_players (id) on delete cascade,
  gk_reflexes    smallint not null, gk_handling smallint not null, gk_positioning smallint not null,
  marking        smallint not null, tackling    smallint not null, positioning    smallint not null, heading smallint not null,
  passing        smallint not null, vision      smallint not null, technique      smallint not null, stamina smallint not null,
  finishing      smallint not null, off_ball    smallint not null, pace           smallint not null, dribbling smallint not null,
  strength       smallint not null,
  estimated      boolean not null default true,      -- true = estimativa de gameplay (não é dado oficial)
  method         text,
  updated_at     timestamptz not null default now()
);

-- Notas derivadas (atributos x pesos da posição). Recalcule com sim_refresh_ratings().
create table if not exists public.sim_player_pos_ratings (
  player_id text not null references public.sim_players (id) on delete cascade,
  pos       text not null references public.sim_positions (code),
  rating    numeric(5,2) not null,          -- só atributos
  eff       numeric(5,2) not null,          -- atributos x adequação à posição
  primary key (player_id, pos)
);

create or replace function public.sim_refresh_ratings()
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  delete from public.sim_player_pos_ratings;
  insert into public.sim_player_pos_ratings (player_id, pos, rating, eff)
  select p.id, w.pos,
         round(sum(w.weight * (to_jsonb(a) ->> w.attr)::numeric) / sum(w.weight), 2),
         round(sum(w.weight * (to_jsonb(a) ->> w.attr)::numeric) / sum(w.weight)
               * greatest(coalesce(max(f.fit), 0.5), case when w.pos = any (p.secondary_positions) then 0.97 else 0 end), 2)
    from public.sim_players p
    join public.sim_player_attrs a on a.player_id = p.id
    join public.sim_role_weights w on true
    left join public.sim_position_fit f on f.from_pos = p.position and f.to_pos = w.pos
   group by p.id, w.pos, p.secondary_positions;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- B) TEMPORADA: colunas novas nas tabelas existentes
-- ---------------------------------------------------------------------
alter table public.career_seasons add column if not exists mode   text not null default 'player';
alter table public.career_seasons add column if not exists day_no int  not null default 0;
alter table public.career_seasons alter column club_id drop not null;     -- treinador desempregado = sem clube
do $$ begin
  alter table public.career_seasons drop constraint if exists career_seasons_status_check;
  alter table public.career_seasons add constraint career_seasons_status_check check (status in ('active', 'finished', 'archived'));
  alter table public.career_seasons drop constraint if exists career_seasons_mode_check;
  alter table public.career_seasons add constraint career_seasons_mode_check check (mode in ('player', 'coach'));
end $$;
-- só UMA temporada ativa por carreira continua valendo (índice já existe)

alter table public.season_fixtures add column if not exists coach_club text references public.sim_clubs (id);  -- clube que o usuário comandou
alter table public.season_fixtures add column if not exists stats jsonb;                                         -- estatísticas da partida
alter table public.season_fixtures add column if not exists extra_time boolean not null default false;
alter table public.season_fixtures add column if not exists day_no int;

alter table public.season_offers add column if not exists expires_day int;     -- prazo em DIAS do calendário (treinador)
alter table public.season_offers add column if not exists kind text not null default 'player';
alter table public.season_offers add column if not exists context jsonb;       -- posição na tabela, objetivo...

-- ---------------------------------------------------------------------
-- C) CARREIRA DO TREINADOR (por usuário)
-- ---------------------------------------------------------------------
create table if not exists public.mgr_coach (
  career_id        uuid primary key references public.careers (id) on delete cascade,
  status           text not null default 'employed' check (status in ('employed', 'unemployed')),
  club_id          text references public.sim_clubs (id),
  spell_id         uuid,
  reputation       numeric(5,2) not null default 25 check (reputation between 0 and 100),
  board_confidence numeric(5,2) not null default 60 check (board_confidence between 0 and 100),
  fan_mood         numeric(5,2) not null default 60 check (fan_mood between 0 and 100),
  unemployed_day   int,                    -- dia do calendário em que ficou sem clube
  unemployed_season_no int,
  matches  int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0,
  gf       int not null default 0, ga   int not null default 0,
  titles   int not null default 0, fired_count int not null default 0, seasons int not null default 0,
  warned   smallint not null default 0,    -- 0 nada, 1 aviso, 2 ultimato (evita repetir mensagens)
  fan_warned smallint not null default 0,  -- 1 = protesto da torcida já avisado
  started_at timestamptz not null default now()
);

alter table public.mgr_coach add column if not exists fan_warned smallint not null default 0;

-- Passagens por clube (o histórico NÃO depende da temporada: trocar de clube no meio do ano abre outra passagem)
create table if not exists public.mgr_spells (
  id              uuid primary key default gen_random_uuid(),
  career_id       uuid not null references public.careers (id) on delete cascade,
  club_id         text not null references public.sim_clubs (id),
  started_season  int not null,          -- season_no
  started_year    int not null,
  started_day     int not null,
  ended_season    int,
  ended_year      int,
  ended_day       int,
  end_reason      text check (end_reason in ('fired', 'left', 'resigned')),
  matches int not null default 0, wins int not null default 0, draws int not null default 0, losses int not null default 0,
  gf int not null default 0, ga int not null default 0,
  titles jsonb not null default '[]'::jsonb,       -- [{"competition":"brasileirao","year":2026}]
  created_at timestamptz not null default now(),
  ended_at   timestamptz
);
create index if not exists mgr_spells_career_idx on public.mgr_spells (career_id, created_at);

-- Objetivos da diretoria por temporada e clube
create table if not exists public.mgr_objectives (
  id             bigint generated always as identity primary key,
  career_id      uuid not null references public.careers (id) on delete cascade,
  season_id      uuid not null references public.career_seasons (id) on delete cascade,
  spell_id       uuid not null references public.mgr_spells (id) on delete cascade,
  club_id        text not null references public.sim_clubs (id),
  competition_id text not null references public.sim_competitions (id),
  kind           text not null check (kind in ('league_pos', 'reach_stage')),
  target         int  not null,          -- league_pos: posição máxima | reach_stage: rank da fase (1 grupo .. 6 campeão)
  label          text not null,
  priority       smallint not null default 1,
  status         text not null default 'open' check (status in ('open', 'met', 'failed', 'void')),
  unique (season_id, spell_id, competition_id)
);

-- Estado de CADA jogador nesta carreira (o clube aqui pode mudar com transferências futuras)
create table if not exists public.mgr_players (
  career_id      uuid not null references public.careers (id) on delete cascade,
  player_id      text not null references public.sim_players (id) on delete cascade,
  club_id        text references public.sim_clubs (id),
  condition      numeric(5,2) not null default 100 check (condition between 0 and 100),   -- condição física
  rhythm         numeric(5,2) not null default 70  check (rhythm between 0 and 100),      -- ritmo de jogo / entrosamento
  injured_until  int,              -- dia do calendário em que volta
  injury         text,
  susp           jsonb not null default '{}'::jsonb,     -- {"brasileirao":1}: jogos de suspensão a cumprir
  yellows        jsonb not null default '{}'::jsonb,     -- cartões acumulados por competição
  primary key (career_id, player_id)
);
create index if not exists mgr_players_club_idx on public.mgr_players (career_id, club_id);

-- Transferências desta carreira (estrutura pronta para o mercado — etapa futura)
create table if not exists public.mgr_transfers (
  id         bigint generated always as identity primary key,
  career_id  uuid not null references public.careers (id) on delete cascade,
  season_id  uuid references public.career_seasons (id) on delete set null,
  player_id  text not null references public.sim_players (id),
  from_club  text references public.sim_clubs (id),
  to_club    text references public.sim_clubs (id),
  kind       text not null check (kind in ('transfer', 'loan', 'release')),
  fee        int,
  day_no     int,
  created_at timestamptz not null default now()
);

-- Escalação e táticas salvas (do clube do usuário; clubes da IA escalam na hora)
create table if not exists public.mgr_lineups (
  career_id       uuid not null references public.careers (id) on delete cascade,
  club_id         text not null references public.sim_clubs (id),
  formation       text not null references public.sim_formations (id),
  slots           jsonb not null,                -- {"GOL":"player-id", "ZAG1":"...", ...}
  bench           text[] not null default '{}',
  tactics         jsonb not null default '{}'::jsonb,
  formation_games int not null default 0,        -- jogos seguidos nesta formação (entrosamento tático)
  updated_at      timestamptz not null default now(),
  primary key (career_id, club_id)
);

-- Partida (ao vivo ou encerrada) — estado do motor entre as etapas
create table if not exists public.mgr_matches (
  fixture_id  bigint primary key references public.season_fixtures (id) on delete cascade,
  career_id   uuid not null references public.careers (id) on delete cascade,
  season_id   uuid not null references public.career_seasons (id) on delete cascade,
  user_side   char(1) check (user_side in ('h', 'a')),     -- null = partida só da IA
  status      text not null default 'live' check (status in ('live', 'finished')),
  minute      smallint not null default 0,
  state       jsonb not null,
  summary     jsonb,                                         -- resumo pós-jogo (consequências)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists mgr_matches_career_live_idx on public.mgr_matches (career_id) where status = 'live';

-- Jogadores em campo/banco numa partida (a IA usa e apaga ao fim; a do usuário fica para a súmula)
create table if not exists public.mgr_match_players (
  fixture_id  bigint not null references public.season_fixtures (id) on delete cascade,
  player_id   text not null references public.sim_players (id),
  side        char(1) not null check (side in ('h', 'a')),
  club_id     text not null,
  slot        text,                 -- vaga na formação (null no banco)
  pos         text,                 -- posição em que está jogando
  status      text not null check (status in ('on', 'bench', 'off', 'sent_off', 'injured_off')),
  starter     boolean not null default false,
  fit         numeric(4,3) not null default 1,
  cond        numeric(5,2) not null,
  rhythm      numeric(5,2) not null default 70,
  c_att numeric(5,2), c_cre numeric(5,2), c_def numeric(5,2), c_ctl numeric(5,2), c_gk numeric(5,2),
  c_fin numeric(5,2), c_head numeric(5,2), c_pace numeric(5,2), c_stam numeric(5,2), c_tack numeric(5,2), c_str numeric(5,2),
  minutes     smallint not null default 0,
  entered_min smallint,
  left_min    smallint,
  goals smallint not null default 0, assists smallint not null default 0, shots smallint not null default 0,
  sot   smallint not null default 0, saves  smallint not null default 0, fouls  smallint not null default 0,
  yellow smallint not null default 0, red   smallint not null default 0,
  injured boolean not null default false,
  rating numeric(4,2) not null default 6,
  primary key (fixture_id, player_id)
);
create index if not exists mgr_match_players_side_idx on public.mgr_match_players (fixture_id, side, status);

-- Acontecimentos da partida (gols, cartões, lesões, substituições...)
create table if not exists public.mgr_match_events (
  fixture_id  bigint not null references public.season_fixtures (id) on delete cascade,
  seq         int not null,
  minute      smallint not null,
  side        char(1) check (side in ('h', 'a')),
  kind        text not null,       -- goal pen_goal own_goal shot_on shot_off save chance corner foul yellow red second_yellow
                                   -- offside injury sub tactic kickoff ht ft et so_goal so_miss
  player_id   text references public.sim_players (id),
  player2_id  text references public.sim_players (id),
  detail      text,
  primary key (fixture_id, seq)
);

-- Estatísticas dos jogadores na temporada (artilharia, assistências, cartões, nota média)
create table if not exists public.mgr_player_stats (
  season_id      uuid not null references public.career_seasons (id) on delete cascade,
  player_id      text not null references public.sim_players (id) on delete cascade,
  competition_id text not null references public.sim_competitions (id),
  club_id        text not null,
  apps smallint not null default 0, starts smallint not null default 0, minutes int not null default 0,
  goals smallint not null default 0, assists smallint not null default 0,
  yellows smallint not null default 0, reds smallint not null default 0,
  rating_sum numeric(7,2) not null default 0, motm smallint not null default 0,
  primary key (season_id, player_id, competition_id)
);
create index if not exists mgr_player_stats_goals_idx on public.mgr_player_stats (season_id, competition_id, goals desc);

-- Caixa de mensagens (diretoria, torcida, departamento médico, propostas...)
create table if not exists public.mgr_messages (
  id         bigint generated always as identity primary key,
  career_id  uuid not null references public.careers (id) on delete cascade,
  season_id  uuid references public.career_seasons (id) on delete set null,
  day_no     int,
  kind       text not null check (kind in ('board', 'fans', 'medical', 'offer', 'result', 'system', 'press', 'title')),
  title      text not null,
  body       text not null,
  club_id    text,
  read       boolean not null default false,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists mgr_messages_career_idx on public.mgr_messages (career_id, created_at desc);

-- ---------------------------------------------------------------------
-- D) SEGURANÇA: o app só LÊ; toda escrita passa pelas funções (security definer)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['sim_positions', 'sim_position_fit', 'sim_role_weights', 'sim_formations', 'sim_players',
                           'sim_player_attrs', 'sim_player_pos_ratings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'read_' || t, t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', 'read_' || t, t);
  end loop;

  foreach t in array array['mgr_coach', 'mgr_spells', 'mgr_objectives', 'mgr_players', 'mgr_transfers', 'mgr_lineups',
                           'mgr_matches', 'mgr_messages'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'own_' || t, t);
    execute format('create policy %I on public.%I for select to authenticated using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()))', 'own_' || t, t);
  end loop;

  foreach t in array array['mgr_match_players', 'mgr_match_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'own_' || t, t);
    execute format('create policy %I on public.%I for select to authenticated using (exists (select 1 from public.season_fixtures f join public.career_seasons s on s.id = f.season_id join public.careers c on c.id = s.career_id where f.id = fixture_id and c.user_id = auth.uid()))', 'own_' || t, t);
  end loop;

  alter table public.mgr_player_stats enable row level security;
  revoke all on public.mgr_player_stats from anon, authenticated;
  grant select on public.mgr_player_stats to authenticated;
  drop policy if exists own_mgr_player_stats on public.mgr_player_stats;
  create policy own_mgr_player_stats on public.mgr_player_stats for select to authenticated
    using (exists (select 1 from public.career_seasons s join public.careers c on c.id = s.career_id where s.id = season_id and c.user_id = auth.uid()));
end $$;
