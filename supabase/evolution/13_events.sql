-- =====================================================================
-- EVOLUÇÃO 13 — EVENTOS RECORRENTES, SEQUÊNCIA DIÁRIA E ADMINISTRAÇÃO PROTEGIDA
--
-- * Eventos são DADOS (events + event_objectives + event_rewards): criar um evento novo = preencher um formulário.
--   Objetivos só de TIPOS já implementados (event_objective_kinds) — nada de código livre no banco.
-- * Progresso vem de acontecimentos reais, por gatilhos nas tabelas que só o servidor escreve (partida jogada,
--   caixa aberta, carta nova, venda no mercado, palpite feito). O navegador não envia progresso.
-- * Recorrência diária/semanal com "períodos" no fuso do evento (horários guardados em UTC).
-- * Recompensa: uma por conclusão (chave única evento × carreira × período), resgate travado e idempotente,
--   com prazo configurável depois do fim. Evento encerrado/cancelado não aceita progresso.
-- * Sequência diária (streak) com recompensas progressivas, exige uma atividade real no dia.
-- * Administração: só usuários em `admins`; funções validam tudo (tipos, parâmetros, recompensas, datas).
-- Rode depois de evolution/12. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) ADMINISTRADORES
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- B) CATÁLOGO DE TIPOS DE OBJETIVO (o que o motor sabe medir) — parâmetros permitidos por tipo
-- ---------------------------------------------------------------------
create table if not exists public.event_objective_kinds (
  id          text primary key,
  label       text not null,
  description text not null,
  params      jsonb not null default '[]'::jsonb,    -- nomes de parâmetros aceitos (filtros)
  sort_order  int not null default 0
);
insert into public.event_objective_kinds (id, label, description, params, sort_order) values
  ('match_played',      'Jogar partidas',        'Partidas suas (modo Temporadas) concluídas.',                 '["competition","region","min_opponent_strength"]', 1),
  ('match_won',         'Vencer partidas',       'Vitórias suas em partidas concluídas (pênaltis contam como vitória de quem passou).', '["competition","region","min_opponent_strength"]', 2),
  ('goals_scored',      'Marcar gols',           'Gols do seu time em partidas concluídas.',                   '["competition","region","min_opponent_strength"]', 3),
  ('clean_sheet',       'Não sofrer gols',       'Partidas concluídas sem sofrer gol.',                        '["competition","region"]', 4),
  ('box_opened',        'Abrir caixas',          'Caixas de recompensa abertas.',                              '["tier"]', 5),
  ('card_collected',    'Conseguir cartas novas','Cartas que entram na coleção pela primeira vez.',            '["tier"]', 6),
  ('market_sale',       'Vender no mercado',     'Cartas vendidas no mercado entre jogadores.',                '[]', 7),
  ('prediction_placed', 'Fazer palpites',        'Bilhetes de palpite registrados.',                           '[]', 8)
on conflict (id) do update set label = excluded.label, description = excluded.description, params = excluded.params, sort_order = excluded.sort_order;

-- ---------------------------------------------------------------------
-- C) EVENTOS
-- ---------------------------------------------------------------------
create table if not exists public.events (
  id                 uuid primary key default gen_random_uuid(),
  slug               text not null unique check (slug ~ '^[a-z0-9-]{3,60}$'),
  name               text not null check (length(name) between 3 and 80),
  description        text not null check (length(description) <= 600),
  category           text not null check (category in ('daily', 'weekly', 'themed', 'collection')),
  banner             jsonb not null default '{}'::jsonb,          -- {"css": gradiente, "icon": nome do ícone}
  starts_at          timestamptz not null,                         -- UTC
  ends_at            timestamptz not null,                         -- UTC
  timezone           text not null default 'America/Sao_Paulo',    -- fuso de referência (virada do dia/semana)
  recurrence         text not null default 'none' check (recurrence in ('none', 'daily', 'weekly')),
  min_level          int not null default 1 check (min_level >= 1),
  max_completions    int check (max_completions is null or max_completions >= 1),   -- por usuário, somando períodos
  claim_grace_hours  int not null default 48 check (claim_grace_hours between 0 and 720),
  status             text not null default 'draft' check (status in ('draft', 'published', 'cancelled')),
  sort_order         int not null default 0,
  created_by         uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.event_objectives (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  kind       text not null references public.event_objective_kinds (id),
  target     int  not null check (target between 1 and 100000),
  params     jsonb not null default '{}'::jsonb,
  label      text not null,
  sort_order int not null default 0
);
create index if not exists event_objectives_kind_idx on public.event_objectives (kind);

create table if not exists public.event_rewards (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  kind       text not null check (kind in ('coins', 'diamonds', 'energy', 'box', 'card', 'cosmetic', 'badge')),
  amount     int  not null default 1 check (amount between 1 and 100000),
  ref        text,                 -- raridade da caixa / id da carta / id do cosmético / id da insígnia
  sort_order int not null default 0
);

create table if not exists public.event_progress (
  event_id     uuid not null references public.events (id) on delete cascade,
  career_id    uuid not null references public.careers (id) on delete cascade,
  period_key   text not null,
  objective_id uuid not null references public.event_objectives (id) on delete cascade,
  progress     int  not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (event_id, career_id, period_key, objective_id)
);

create table if not exists public.event_completions (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events (id) on delete cascade,
  career_id    uuid not null references public.careers (id) on delete cascade,
  period_key   text not null,
  completed_at timestamptz not null default now(),
  claim_until  timestamptz not null,
  claimed_at   timestamptz,
  rewards      jsonb,                      -- o que foi entregue (histórico)
  unique (event_id, career_id, period_key)
);
create index if not exists event_completions_career_idx on public.event_completions (career_id, completed_at desc);

-- ---------------------------------------------------------------------
-- D) SEQUÊNCIA DIÁRIA
-- ---------------------------------------------------------------------
create table if not exists public.streak_config (
  id         boolean primary key default true check (id),
  timezone   text not null default 'America/Sao_Paulo',
  cycle_days int not null default 7 check (cycle_days between 2 and 31),
  active     boolean not null default true
);
insert into public.streak_config (id) values (true) on conflict (id) do nothing;

create table if not exists public.streak_rewards (
  day      int primary key check (day between 1 and 31),
  coins    int not null default 0 check (coins >= 0),
  diamonds int not null default 0 check (diamonds >= 0),
  box_tier text references public.card_tiers (id)
);
insert into public.streak_rewards (day, coins, diamonds, box_tier) values
  (1, 40, 0, null), (2, 60, 0, null), (3, 80, 0, 'basica'), (4, 100, 0, null),
  (5, 120, 1, null), (6, 150, 0, 'basica'), (7, 200, 2, 'destaque')
on conflict (day) do nothing;

create table if not exists public.player_streaks (
  career_id uuid primary key references public.careers (id) on delete cascade,
  current   int not null default 0,
  best      int not null default 0,
  last_day  date
);

-- ---------------------------------------------------------------------
-- E) SEGURANÇA DAS TABELAS
-- ---------------------------------------------------------------------
alter table public.event_objective_kinds enable row level security;
alter table public.events                enable row level security;
alter table public.event_objectives      enable row level security;
alter table public.event_rewards         enable row level security;
alter table public.event_progress        enable row level security;
alter table public.event_completions     enable row level security;
alter table public.streak_config         enable row level security;
alter table public.streak_rewards        enable row level security;
alter table public.player_streaks        enable row level security;
revoke all on public.event_objective_kinds, public.events, public.event_objectives, public.event_rewards, public.event_progress,
  public.event_completions, public.streak_config, public.streak_rewards, public.player_streaks from anon, authenticated;
-- tudo é lido pelas funções abaixo (que aplicam as regras de visibilidade); o app não escreve nada direto

-- ---------------------------------------------------------------------
-- F) PERÍODOS (virada no fuso do evento)
-- ---------------------------------------------------------------------
create or replace function public.event_period(p_ev public.events, p_at timestamptz default now(),
                                               out period_key text, out period_start timestamptz, out period_end timestamptz)
language plpgsql stable set search_path = public as $$
declare d date;
begin
  if p_ev.recurrence = 'daily' then
    d := (p_at at time zone p_ev.timezone)::date;
    period_key := d::text;
    period_start := d::timestamp at time zone p_ev.timezone;
    period_end := (d + 1)::timestamp at time zone p_ev.timezone;
  elsif p_ev.recurrence = 'weekly' then
    d := date_trunc('week', (p_at at time zone p_ev.timezone))::date;        -- semana começa na segunda
    period_key := 'semana-' || d::text;
    period_start := d::timestamp at time zone p_ev.timezone;
    period_end := (d + 7)::timestamp at time zone p_ev.timezone;
  else
    period_key := 'unico';
    period_start := p_ev.starts_at;
    period_end := p_ev.ends_at;
  end if;
  period_start := greatest(period_start, p_ev.starts_at);
  period_end := least(period_end, p_ev.ends_at);
end;
$$;

-- ---------------------------------------------------------------------
-- G) MOTOR DE PROGRESSO (chamado só pelos gatilhos)
-- ---------------------------------------------------------------------
create or replace function public.event_track(p_career uuid, p_kind text, p_amount int, p_ctx jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r     record;
  v_per record;
  v_lvl int;
  v_ev  public.events;
begin
  if p_amount is null or p_amount <= 0 or p_career is null then return; end if;
  select level into v_lvl from public.careers where id = p_career;
  for r in
    select o.id as oid, o.target, o.params, e.id as eid
      from public.event_objectives o join public.events e on e.id = o.event_id
     where o.kind = p_kind and e.status = 'published' and now() >= e.starts_at and now() < e.ends_at
       and coalesce(v_lvl, 1) >= e.min_level
       -- filtros do objetivo (só os previstos para o tipo)
       and (o.params ->> 'competition' is null or o.params ->> 'competition' = p_ctx ->> 'competition')
       and (o.params ->> 'region' is null or o.params ->> 'region' = p_ctx ->> 'region')
       and (o.params ->> 'tier' is null or o.params ->> 'tier' = p_ctx ->> 'tier')
       and (o.params ->> 'min_opponent_strength' is null
            or coalesce((p_ctx ->> 'opponent_strength')::int, 0) >= (o.params ->> 'min_opponent_strength')::int)
  loop
    select * into v_ev from public.events where id = r.eid;
    select * into v_per from public.event_period(v_ev);
    -- período já concluído ou limite de conclusões atingido: não conta mais
    continue when exists (select 1 from public.event_completions where event_id = r.eid and career_id = p_career and period_key = v_per.period_key);
    continue when v_ev.max_completions is not null
      and (select count(*) from public.event_completions where event_id = r.eid and career_id = p_career) >= v_ev.max_completions;

    insert into public.event_progress (event_id, career_id, period_key, objective_id, progress)
    values (r.eid, p_career, v_per.period_key, r.oid, least(r.target, p_amount))
    on conflict (event_id, career_id, period_key, objective_id)
    do update set progress = least(r.target, public.event_progress.progress + p_amount), updated_at = now();

    -- todos os objetivos do evento cumpridos neste período? → conclusão (uma só, pela chave única)
    if not exists (
      select 1 from public.event_objectives o2
        left join public.event_progress p2 on p2.objective_id = o2.id and p2.career_id = p_career and p2.period_key = v_per.period_key
       where o2.event_id = r.eid and coalesce(p2.progress, 0) < o2.target) then
      insert into public.event_completions (event_id, career_id, period_key, claim_until)
      values (r.eid, p_career, v_per.period_key, v_per.period_end + make_interval(hours => v_ev.claim_grace_hours))
      on conflict (event_id, career_id, period_key) do nothing;
    end if;
  end loop;
end;
$$;

-- partida do treinador concluída (mesmo critério da caixa de vitória: status vira 'played')
create or replace function public.event_on_fixture()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_cs  record;
  v_my  int; v_opp int; v_oppclub text; v_win boolean; v_ctx jsonb;
begin
  if not (coalesce(new.player_match, false) and new.status = 'played' and old.status is distinct from 'played') then return new; end if;
  select career_id, club_id, region into v_cs from public.career_seasons where id = new.season_id;
  if not found or v_cs.career_id is null then return new; end if;
  if new.home_club = coalesce(new.coach_club, v_cs.club_id) then
    v_my := new.home_goals; v_opp := new.away_goals; v_oppclub := new.away_club;
  else
    v_my := new.away_goals; v_opp := new.home_goals; v_oppclub := new.home_club;
  end if;
  v_win := v_my > v_opp or (v_my = v_opp and new.tie_winner = coalesce(new.coach_club, v_cs.club_id)
                             and (new.home_pens is not null or new.away_pens is not null));
  v_ctx := jsonb_build_object('competition', new.competition_id, 'region', v_cs.region,
                              'opponent_strength', (select strength from public.sim_clubs where id = v_oppclub));
  perform public.event_track(v_cs.career_id, 'match_played', 1, v_ctx);
  if v_win then perform public.event_track(v_cs.career_id, 'match_won', 1, v_ctx); end if;
  if v_my > 0 then perform public.event_track(v_cs.career_id, 'goals_scored', v_my, v_ctx); end if;
  if v_opp = 0 then perform public.event_track(v_cs.career_id, 'clean_sheet', 1, v_ctx); end if;
  return new;
end;
$$;
drop trigger if exists event_on_fixture on public.season_fixtures;
create trigger event_on_fixture after update on public.season_fixtures for each row execute function public.event_on_fixture();

create or replace function public.event_on_box()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'opened' and old.status is distinct from 'opened' then
    perform public.event_track(new.career_id, 'box_opened', 1, jsonb_build_object('tier', new.tier));
  end if;
  return new;
end;
$$;
drop trigger if exists event_on_box on public.reward_boxes;
create trigger event_on_box after update of status on public.reward_boxes for each row execute function public.event_on_box();

create or replace function public.event_on_new_card()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.event_track(new.career_id, 'card_collected', 1, jsonb_build_object('tier', (select tier from public.cards where id = new.card_id)));
  return new;
end;
$$;
drop trigger if exists event_on_new_card on public.user_cards;
create trigger event_on_new_card after insert on public.user_cards for each row execute function public.event_on_new_card();

create or replace function public.event_on_market_sale()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'sold' and old.status is distinct from 'sold' then
    perform public.event_track(new.seller_career, 'market_sale', 1, '{}'::jsonb);
  end if;
  return new;
end;
$$;
drop trigger if exists event_on_market_sale on public.market_listings;
create trigger event_on_market_sale after update of status on public.market_listings for each row execute function public.event_on_market_sale();

create or replace function public.event_on_ticket()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.event_track(new.career_id, 'prediction_placed', 1, '{}'::jsonb);
  return new;
end;
$$;
do $$
begin
  if to_regclass('public.tickets') is not null then
    execute 'drop trigger if exists event_on_ticket on public.tickets';
    execute 'create trigger event_on_ticket after insert on public.tickets for each row execute function public.event_on_ticket()';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- H) TELA DE EVENTOS
-- ---------------------------------------------------------------------
create or replace function public.event_json(p_ev public.events, p_career uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_per record; v_state text; v_comp public.event_completions;
begin
  select * into v_per from public.event_period(p_ev, least(greatest(now(), p_ev.starts_at), p_ev.ends_at - interval '1 second'));
  v_state := case when p_ev.status = 'cancelled' then 'cancelled' when now() < p_ev.starts_at then 'scheduled'
                  when now() >= p_ev.ends_at then 'ended' else 'active' end;
  select * into v_comp from public.event_completions where event_id = p_ev.id and career_id = p_career and period_key = v_per.period_key;
  return jsonb_build_object(
    'id', p_ev.id, 'slug', p_ev.slug, 'name', p_ev.name, 'description', p_ev.description, 'category', p_ev.category,
    'banner', p_ev.banner, 'starts_at', p_ev.starts_at, 'ends_at', p_ev.ends_at, 'timezone', p_ev.timezone,
    'recurrence', p_ev.recurrence, 'min_level', p_ev.min_level, 'max_completions', p_ev.max_completions, 'state', v_state,
    'period_key', v_per.period_key, 'period_end', v_per.period_end,
    'completions_total', (select count(*) from public.event_completions where event_id = p_ev.id and career_id = p_career),
    'completion', case when v_comp.id is not null then jsonb_build_object('id', v_comp.id, 'claimed_at', v_comp.claimed_at,
        'claim_until', v_comp.claim_until, 'claimable', v_comp.claimed_at is null and now() < v_comp.claim_until) end,
    'objectives', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'kind', o.kind, 'label', o.label, 'target', o.target, 'params', o.params,
         'progress', coalesce((select p.progress from public.event_progress p where p.objective_id = o.id and p.career_id = p_career
                                and p.period_key = v_per.period_key), 0)) order by o.sort_order, o.label)
         from public.event_objectives o where o.event_id = p_ev.id), '[]'::jsonb),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('kind', w.kind, 'amount', w.amount, 'ref', w.ref,
         'label', case w.kind when 'cosmetic' then (select label from public.cosmetics where id = w.ref)
                              when 'badge' then (select label from public.badges where id = w.ref)
                              when 'card' then (select name from public.cards where id = w.ref) end) order by w.sort_order)
         from public.event_rewards w where w.event_id = p_ev.id), '[]'::jsonb));
end;
$$;

create or replace function public.events_overview()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_cfg public.streak_config;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  select * into v_cfg from public.streak_config;
  return jsonb_build_object(
    'now', now(), 'is_admin', public.is_admin(),
    'active', coalesce((select jsonb_agg(public.event_json(e, v_c.id) order by e.category = 'daily' desc, e.category = 'weekly' desc, e.sort_order, e.ends_at)
                          from public.events e where e.status = 'published' and now() >= e.starts_at and now() < e.ends_at), '[]'::jsonb),
    'upcoming', coalesce((select jsonb_agg(public.event_json(e, v_c.id) order by e.starts_at)
                            from public.events e where e.status = 'published' and e.starts_at > now() and e.starts_at < now() + interval '30 days'), '[]'::jsonb),
    -- encerrados nos últimos 7 dias (com recompensa ainda resgatável ou só para consulta)
    'ended', coalesce((select jsonb_agg(public.event_json(e, v_c.id) order by e.ends_at desc)
                         from public.events e where e.status = 'published' and e.ends_at <= now() and e.ends_at > now() - interval '7 days'), '[]'::jsonb),
    'claimable', (select count(*) from public.event_completions c join public.events e on e.id = c.event_id
                   where c.career_id = v_c.id and c.claimed_at is null and now() < c.claim_until and e.status <> 'cancelled'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('event', e.name, 'period', c.period_key, 'claimed_at', c.claimed_at, 'rewards', c.rewards)
                                          order by c.claimed_at desc)
                           from (select * from public.event_completions where career_id = v_c.id and claimed_at is not null order by claimed_at desc limit 30) c
                           join public.events e on e.id = c.event_id), '[]'::jsonb),
    'streak', public.streak_status_for(v_c.id));
end;
$$;

-- ---------------------------------------------------------------------
-- I) RESGATE (uma vez por conclusão; travado; idempotente)
-- ---------------------------------------------------------------------
create or replace function public.event_grant(p_career uuid, p_reward public.event_rewards, p_ref text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare i int;
begin
  case p_reward.kind
    when 'coins' then perform public.econ_apply(p_career, 'coins', p_reward.amount, 'event_reward', p_ref);
    when 'diamonds' then perform public.econ_apply(p_career, 'diamonds', p_reward.amount, 'event_reward', p_ref);
    when 'energy' then perform public.econ_apply(p_career, 'bonus_energy', p_reward.amount, 'event_reward', p_ref);
    when 'box' then
      for i in 1 .. p_reward.amount loop
        perform public.card_grant_box(p_career, p_reward.ref, 'event', p_ref || '#' || p_reward.id || '#' || i);
      end loop;
    when 'card' then
      insert into public.user_cards (career_id, card_id, qty) values (p_career, p_reward.ref, p_reward.amount)
      on conflict (career_id, card_id) do update set qty = public.user_cards.qty + excluded.qty, last_obtained_at = now();
    when 'cosmetic' then
      insert into public.player_cosmetics (career_id, cosmetic_id, source) values (p_career, p_reward.ref, 'event') on conflict do nothing;
    when 'badge' then
      insert into public.player_badges (career_id, badge_id, value) values (p_career, p_reward.ref, 1) on conflict do nothing;
  end case;
  return jsonb_build_object('kind', p_reward.kind, 'amount', p_reward.amount, 'ref', p_reward.ref);
end;
$$;

create or replace function public.event_claim(p_completion uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_comp public.event_completions; v_ev public.events; w public.event_rewards; v_out jsonb := '[]';
begin
  v_c := public.sim_lock_career();
  select * into v_comp from public.event_completions where id = p_completion and career_id = v_c.id for update;
  if not found then raise exception 'Recompensa não encontrada.'; end if;
  if v_comp.claimed_at is not null then
    return jsonb_build_object('ok', true, 'replayed', true, 'rewards', v_comp.rewards);   -- clique duplo / atualizar a página
  end if;
  select * into v_ev from public.events where id = v_comp.event_id;
  if v_ev.status = 'cancelled' then raise exception 'Este evento foi cancelado.'; end if;
  if now() >= v_comp.claim_until then raise exception 'O prazo para resgatar esta recompensa terminou.'; end if;
  for w in select * from public.event_rewards where event_id = v_ev.id order by sort_order, id loop
    v_out := v_out || public.event_grant(v_c.id, w, v_comp.id::text);
  end loop;
  update public.event_completions set claimed_at = now(), rewards = v_out where id = v_comp.id;
  return jsonb_build_object('ok', true, 'replayed', false, 'event', v_ev.name, 'rewards', v_out);
end;
$$;

-- ---------------------------------------------------------------------
-- J) SEQUÊNCIA DIÁRIA: exige atividade real no dia (partida concluída ou palpite)
-- ---------------------------------------------------------------------
create or replace function public.streak_active_today(p_career uuid, p_tz text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare d date := (now() at time zone p_tz)::date; v boolean;
begin
  select exists (select 1 from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
                  where s.career_id = p_career and f.player_match and f.status = 'played' and (f.played_at at time zone p_tz)::date = d) into v;
  if not v and to_regclass('public.tickets') is not null then
    execute 'select exists (select 1 from public.tickets where career_id = $1 and (created_at at time zone $2)::date = $3)' into v using p_career, p_tz, d;
  end if;
  return coalesce(v, false);
end;
$$;

create or replace function public.streak_status_for(p_career uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cfg public.streak_config; v_s public.player_streaks; d date; v_next int; v_claimed boolean;
begin
  select * into v_cfg from public.streak_config;
  select * into v_s from public.player_streaks where career_id = p_career;
  d := (now() at time zone v_cfg.timezone)::date;
  v_claimed := v_s.last_day = d;
  v_next := case when v_claimed then v_s.current when v_s.last_day = d - 1 then v_s.current + 1 else 1 end;
  return jsonb_build_object(
    'active', v_cfg.active, 'current', case when v_claimed or v_s.last_day = d - 1 then coalesce(v_s.current, 0) else 0 end,
    'best', coalesce(v_s.best, 0), 'claimed_today', coalesce(v_claimed, false),
    'today_day', ((v_next - 1) % v_cfg.cycle_days) + 1, 'cycle_days', v_cfg.cycle_days,
    'eligible_today', public.streak_active_today(p_career, v_cfg.timezone),
    'resets_at', (d + 1)::timestamp at time zone v_cfg.timezone,
    'rewards', (select jsonb_agg(jsonb_build_object('day', day, 'coins', coins, 'diamonds', diamonds, 'box_tier', box_tier) order by day)
                  from public.streak_rewards where day <= v_cfg.cycle_days));
end;
$$;

create or replace function public.streak_claim()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_cfg public.streak_config; v_s public.player_streaks; d date; v_cur int; v_day int; v_r public.streak_rewards; v_ref text;
begin
  v_c := public.sim_lock_career();
  select * into v_cfg from public.streak_config;
  if not v_cfg.active then raise exception 'A sequência diária está desligada.'; end if;
  d := (now() at time zone v_cfg.timezone)::date;
  insert into public.player_streaks (career_id) values (v_c.id) on conflict do nothing;
  select * into v_s from public.player_streaks where career_id = v_c.id for update;
  if v_s.last_day = d then return jsonb_build_object('ok', true, 'replayed', true, 'current', v_s.current); end if;
  if not public.streak_active_today(v_c.id, v_cfg.timezone) then
    raise exception 'Jogue uma partida ou faça um palpite hoje para liberar a recompensa do dia.';
  end if;
  v_cur := case when v_s.last_day = d - 1 then v_s.current + 1 else 1 end;
  v_day := ((v_cur - 1) % v_cfg.cycle_days) + 1;
  select * into v_r from public.streak_rewards where day = v_day;
  v_ref := 'streak:' || d::text;
  if v_r.coins > 0 then perform public.econ_apply(v_c.id, 'coins', v_r.coins, 'daily_streak', v_ref); end if;
  if v_r.diamonds > 0 then perform public.econ_apply(v_c.id, 'diamonds', v_r.diamonds, 'daily_streak', v_ref); end if;
  if v_r.box_tier is not null then perform public.card_grant_box(v_c.id, v_r.box_tier, 'streak', d::text); end if;
  update public.player_streaks set current = v_cur, best = greatest(best, v_cur), last_day = d where career_id = v_c.id;
  return jsonb_build_object('ok', true, 'replayed', false, 'current', v_cur, 'day', v_day,
                            'coins', v_r.coins, 'diamonds', v_r.diamonds, 'box_tier', v_r.box_tier);
end;
$$;

-- ---------------------------------------------------------------------
-- K) INSÍGNIAS DE EVENTOS (estende a regra da evolução 11)
-- ---------------------------------------------------------------------
insert into public.badges (id, label, description, icon, tier, kind, threshold, sort_order) values
  ('evento_1',  'Participante',  'Conclua e resgate um evento.',   'calendar', 'bronze', 'events_completed', 1, 80),
  ('evento_10', 'Frequentador',  'Conclua e resgate 10 eventos.',  'calendar', 'prata',  'events_completed', 10, 81),
  ('sequencia_diaria_7', 'Semana completa', 'Chegue a 7 dias seguidos na sequência diária.', 'flame', 'prata', 'daily_streak', 7, 82)
on conflict (id) do nothing;

create or replace function public.badge_metric(p_career uuid, p_kind text, p_threshold numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v numeric;
begin
  case p_kind
    when 'titles' then
      select coalesce(sum(jsonb_array_length(coalesce(titles, '[]'::jsonb))), 0) into v from public.mgr_spells where career_id = p_career;
    when 'level' then select level into v from public.careers where id = p_career;
    when 'coach_matches' then select matches into v from public.mgr_coach where career_id = p_career;
    when 'seasons_done' then select seasons into v from public.mgr_coach where career_id = p_career;
    when 'collection' then select count(*) into v from public.user_cards where career_id = p_career;
    when 'own_epica' then
      select count(*) into v from public.user_cards uc join public.cards c on c.id = uc.card_id where uc.career_id = p_career and c.tier = 'epica';
    when 'market_sales' then select count(*) into v from public.market_listings where seller_career = p_career and status = 'sold';
    when 'season_year' then
      select case when exists (select 1 from public.career_seasons where career_id = p_career and mode = 'coach' and status = 'finished'
                                and year = p_threshold::int) then p_threshold else 0 end into v;
    when 'win_streak' then
      select coalesce(max(n), 0) into v from (
        select count(*) as n from (
          select w, sum(case when w then 0 else 1 end) over (order by played_at, id) as grp
            from (select f.id, f.played_at,
                         case when f.home_club = f.coach_club then f.home_goals > f.away_goals else f.away_goals > f.home_goals end as w
                    from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
                   where s.career_id = p_career and f.player_match and f.status = 'played' and f.coach_club is not null) x
        ) y where w group by grp) z;
    -- evolução 13
    when 'events_completed' then select count(*) into v from public.event_completions where career_id = p_career and claimed_at is not null;
    when 'daily_streak' then select best into v from public.player_streaks where career_id = p_career;
    else v := 0;
  end case;
  return coalesce(v, 0);
end;
$$;

-- ---------------------------------------------------------------------
-- L) ADMINISTRAÇÃO (só `admins`). Tudo validado: tipos de objetivo e seus parâmetros, recompensas, datas.
-- ---------------------------------------------------------------------
create or replace function public.admin_assert()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception using errcode = '42501', message = 'Apenas administradores.'; end if;
end;
$$;

-- p_event: {id?, slug, name, description, category, banner, starts_at, ends_at, timezone, recurrence, min_level,
--           max_completions, claim_grace_hours, sort_order,
--           objectives: [{kind, target, params, label}], rewards: [{kind, amount, ref}]}
-- Salva como RASCUNHO (ou mantém o estado atual). Publicar é outra ação.
create or replace function public.admin_event_save(p_event jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := nullif(p_event ->> 'id', '')::uuid;
  v_ev public.events;
  o jsonb; w jsonb; k text; v_kind public.event_objective_kinds; i int := 0;
begin
  perform public.admin_assert();
  if v_id is not null then
    select * into v_ev from public.events where id = v_id for update;
    if not found then raise exception 'Evento não encontrado.'; end if;
    if v_ev.status = 'published' and now() >= v_ev.starts_at then
      raise exception 'Evento já começou: não dá para alterar objetivos/recompensas. Cancele e crie outro.';
    end if;
  end if;
  if coalesce(p_event ->> 'timezone', 'America/Sao_Paulo') not in (select name from pg_timezone_names) then raise exception 'Fuso horário inválido.'; end if;
  if jsonb_typeof(p_event -> 'objectives') <> 'array' or jsonb_array_length(p_event -> 'objectives') = 0 then raise exception 'O evento precisa de pelo menos um objetivo.'; end if;
  if jsonb_typeof(p_event -> 'rewards') <> 'array' or jsonb_array_length(p_event -> 'rewards') = 0 then raise exception 'O evento precisa de pelo menos uma recompensa.'; end if;

  -- objetivos: só tipos do catálogo e só os parâmetros previstos para cada tipo
  for o in select * from jsonb_array_elements(p_event -> 'objectives') loop
    select * into v_kind from public.event_objective_kinds where id = o ->> 'kind';
    if not found then raise exception 'Tipo de objetivo inválido: %', o ->> 'kind'; end if;
    if o ? 'params' and jsonb_typeof(o -> 'params') not in ('object', 'null') then raise exception 'Parâmetros do objetivo % precisam ser um objeto.', v_kind.label; end if;
    if coalesce((o ->> 'target')::int, 0) < 1 then raise exception 'Meta inválida no objetivo %.', v_kind.label; end if;
    for k in select jsonb_object_keys(coalesce(nullif(o -> 'params', 'null'::jsonb), '{}'::jsonb)) loop
      if not (v_kind.params ? k) then raise exception 'Parâmetro "%" não é permitido em "%".', k, v_kind.label; end if;
    end loop;
    if o -> 'params' ? 'competition' and not exists (select 1 from public.sim_competitions where id = o -> 'params' ->> 'competition') then
      raise exception 'Competição inexistente: %', o -> 'params' ->> 'competition'; end if;
    if o -> 'params' ? 'tier' and not exists (select 1 from public.card_tiers where id = o -> 'params' ->> 'tier') then
      raise exception 'Raridade inexistente: %', o -> 'params' ->> 'tier'; end if;
    if o -> 'params' ? 'region' and o -> 'params' ->> 'region' not in ('BRA', 'ENG') then raise exception 'Região inválida.'; end if;
    if o -> 'params' ? 'min_opponent_strength' and coalesce((o -> 'params' ->> 'min_opponent_strength')::int, -1) not between 1 and 99 then
      raise exception 'Força mínima do adversário deve ficar entre 1 e 99.'; end if;
  end loop;
  -- recompensas: tipos conhecidos e referências que existem (nada de diamante obrigatório para completar)
  for w in select * from jsonb_array_elements(p_event -> 'rewards') loop
    if w ->> 'kind' not in ('coins', 'diamonds', 'energy', 'box', 'card', 'cosmetic', 'badge') then raise exception 'Recompensa inválida: %', w ->> 'kind'; end if;
    if coalesce((w ->> 'amount')::int, 1) not between 1 and 100000 then raise exception 'Quantidade inválida na recompensa.'; end if;
    if w ->> 'kind' = 'box' and not exists (select 1 from public.card_tiers where id = w ->> 'ref') then raise exception 'Caixa de raridade inexistente.'; end if;
    if w ->> 'kind' = 'card' and not exists (select 1 from public.cards where id = w ->> 'ref') then raise exception 'Carta inexistente.'; end if;
    if w ->> 'kind' = 'cosmetic' and not exists (select 1 from public.cosmetics where id = w ->> 'ref') then raise exception 'Cosmético inexistente.'; end if;
    if w ->> 'kind' = 'badge' and not exists (select 1 from public.badges where id = w ->> 'ref') then raise exception 'Insígnia inexistente.'; end if;
  end loop;

  if v_id is null then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, timezone, recurrence, min_level,
                               max_completions, claim_grace_hours, sort_order, created_by)
    values (p_event ->> 'slug', p_event ->> 'name', coalesce(p_event ->> 'description', ''), p_event ->> 'category',
            coalesce(p_event -> 'banner', '{}'::jsonb), (p_event ->> 'starts_at')::timestamptz, (p_event ->> 'ends_at')::timestamptz,
            coalesce(p_event ->> 'timezone', 'America/Sao_Paulo'), coalesce(p_event ->> 'recurrence', 'none'),
            coalesce((p_event ->> 'min_level')::int, 1), (p_event ->> 'max_completions')::int,
            coalesce((p_event ->> 'claim_grace_hours')::int, 48), coalesce((p_event ->> 'sort_order')::int, 0), auth.uid())
    returning * into v_ev;
  else
    update public.events set slug = p_event ->> 'slug', name = p_event ->> 'name', description = coalesce(p_event ->> 'description', ''),
           category = p_event ->> 'category', banner = coalesce(p_event -> 'banner', '{}'::jsonb),
           starts_at = (p_event ->> 'starts_at')::timestamptz, ends_at = (p_event ->> 'ends_at')::timestamptz,
           timezone = coalesce(p_event ->> 'timezone', 'America/Sao_Paulo'), recurrence = coalesce(p_event ->> 'recurrence', 'none'),
           min_level = coalesce((p_event ->> 'min_level')::int, 1), max_completions = (p_event ->> 'max_completions')::int,
           claim_grace_hours = coalesce((p_event ->> 'claim_grace_hours')::int, 48), sort_order = coalesce((p_event ->> 'sort_order')::int, 0),
           updated_at = now()
     where id = v_id returning * into v_ev;
    delete from public.event_objectives where event_id = v_id;
    delete from public.event_rewards where event_id = v_id;
  end if;
  for o in select * from jsonb_array_elements(p_event -> 'objectives') loop
    i := i + 1;
    insert into public.event_objectives (event_id, kind, target, params, label, sort_order)
    values (v_ev.id, o ->> 'kind', (o ->> 'target')::int, coalesce(nullif(o -> 'params', 'null'::jsonb), '{}'::jsonb),
            coalesce(nullif(o ->> 'label', ''), (select label from public.event_objective_kinds where id = o ->> 'kind')), i);
  end loop;
  i := 0;
  for w in select * from jsonb_array_elements(p_event -> 'rewards') loop
    i := i + 1;
    insert into public.event_rewards (event_id, kind, amount, ref, sort_order)
    values (v_ev.id, w ->> 'kind', coalesce((w ->> 'amount')::int, 1), nullif(w ->> 'ref', ''), i);
  end loop;
  return jsonb_build_object('ok', true, 'id', v_ev.id, 'status', v_ev.status);
end;
$$;

create or replace function public.admin_event_set_status(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ev public.events;
begin
  perform public.admin_assert();
  if p_status not in ('draft', 'published', 'cancelled') then raise exception 'Estado inválido.'; end if;
  select * into v_ev from public.events where id = p_id for update;
  if not found then raise exception 'Evento não encontrado.'; end if;
  if p_status = 'draft' and v_ev.status = 'published' and now() >= v_ev.starts_at then raise exception 'Evento já começou: cancele em vez de voltar a rascunho.'; end if;
  if p_status = 'published' and v_ev.ends_at <= now() then raise exception 'O fim do evento já passou.'; end if;
  update public.events set status = p_status, updated_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

create or replace function public.admin_events_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_assert();
  return jsonb_build_object(
    'kinds', (select jsonb_agg(to_jsonb(k) order by k.sort_order) from public.event_objective_kinds k),
    'events', coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object(
                 'objectives', (select coalesce(jsonb_agg(to_jsonb(o) order by o.sort_order), '[]') from public.event_objectives o where o.event_id = e.id),
                 'rewards', (select coalesce(jsonb_agg(to_jsonb(w) order by w.sort_order), '[]') from public.event_rewards w where w.event_id = e.id),
                 'completions', (select count(*) from public.event_completions c where c.event_id = e.id))
               order by e.starts_at desc) from public.events e), '[]'::jsonb),
    'options', jsonb_build_object(
      'competitions', (select jsonb_agg(jsonb_build_object('id', id, 'name', name) order by sort_order) from public.sim_competitions where active),
      'tiers', (select jsonb_agg(id order by rank) from public.card_tiers),
      'cosmetics', (select jsonb_agg(jsonb_build_object('id', id, 'label', label, 'kind', kind) order by kind, sort_order) from public.cosmetics where active),
      'badges', (select jsonb_agg(jsonb_build_object('id', id, 'label', label) order by sort_order) from public.badges where active)));
end;
$$;

-- ---------------------------------------------------------------------
-- M) EVENTOS INICIAIS (dados reais: rastreados pelo motor desde a publicação)
-- ---------------------------------------------------------------------
insert into public.badges (id, label, description, icon, tier, kind, threshold, sort_order) values
  ('evento_gigantes_2026', 'Mata-gigantes 2026', 'Recompensa do evento "Desafio dos Gigantes" (novembro de 2026).', 'trophy', 'ouro', 'event_reward', 1, 90)
on conflict (id) do nothing;

do $$
declare v uuid;
begin
  if not exists (select 1 from public.events where slug = 'diario-entre-em-campo') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, sort_order, claim_grace_hours)
    values ('diario-entre-em-campo', 'Entre em campo', 'Jogue uma partida no modo Temporadas hoje.', 'daily',
            '{"css":"linear-gradient(135deg,#0b4a2a,#1f9d55)","icon":"activity"}', '2026-10-25 03:00+00', '2027-12-31 03:00+00', 'daily', 1, 24)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, label) values (v, 'match_played', 1, 'Jogue 1 partida');
    insert into public.event_rewards (event_id, kind, amount, sort_order) values (v, 'coins', 60, 1);
    update public.events set status = 'published' where id = v;
  end if;
  if not exists (select 1 from public.events where slug = 'diario-vitoria') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, sort_order, claim_grace_hours)
    values ('diario-vitoria', 'Vitória do dia', 'Vença uma partida hoje.', 'daily',
            '{"css":"linear-gradient(135deg,#6b4a06,#e0a82e)","icon":"trophy"}', '2026-10-25 03:00+00', '2027-12-31 03:00+00', 'daily', 2, 24)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, label) values (v, 'match_won', 1, 'Vença 1 partida');
    insert into public.event_rewards (event_id, kind, amount, ref, sort_order) values (v, 'coins', 100, null, 1), (v, 'box', 1, 'basica', 2);
    update public.events set status = 'published' where id = v;
  end if;
  if not exists (select 1 from public.events where slug = 'diario-ataque') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, sort_order, claim_grace_hours)
    values ('diario-ataque', 'Ataque afiado', 'Marque 3 gols hoje, somando suas partidas.', 'daily',
            '{"css":"linear-gradient(135deg,#4d0a12,#d6283a)","icon":"flame"}', '2026-10-25 03:00+00', '2027-12-31 03:00+00', 'daily', 3, 24)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, label) values (v, 'goals_scored', 3, 'Marque 3 gols');
    insert into public.event_rewards (event_id, kind, amount, sort_order) values (v, 'coins', 80, 1);
    update public.events set status = 'published' where id = v;
  end if;
  if not exists (select 1 from public.events where slug = 'semanal-vencedora') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, sort_order)
    values ('semanal-vencedora', 'Semana vencedora', 'Acumule 5 vitórias e 10 partidas nesta semana (de segunda a domingo).', 'weekly',
            '{"css":"linear-gradient(135deg,#0a1633,#2447a8)","icon":"star"}', '2026-10-25 03:00+00', '2027-12-31 03:00+00', 'weekly', 1)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, label, sort_order) values
      (v, 'match_won', 5, 'Vença 5 partidas', 1), (v, 'match_played', 10, 'Jogue 10 partidas', 2);
    insert into public.event_rewards (event_id, kind, amount, ref, sort_order) values (v, 'box', 1, 'destaque', 1), (v, 'diamonds', 3, null, 2);
    update public.events set status = 'published' where id = v;
  end if;
  if not exists (select 1 from public.events where slug = 'semanal-colecionador') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, sort_order)
    values ('semanal-colecionador', 'Colecionador da semana', 'Abra 10 caixas e consiga 3 cartas novas nesta semana.', 'weekly',
            '{"css":"linear-gradient(135deg,#2a1055,#7a3df0)","icon":"layers"}', '2026-10-25 03:00+00', '2027-12-31 03:00+00', 'weekly', 2)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, label, sort_order) values
      (v, 'box_opened', 10, 'Abra 10 caixas', 1), (v, 'card_collected', 3, 'Consiga 3 cartas novas', 2);
    insert into public.event_rewards (event_id, kind, amount, sort_order) values (v, 'coins', 150, 1), (v, 'diamonds', 1, 2);
    update public.events set status = 'published' where id = v;
  end if;
  -- temático, com data marcada: semana de 2 a 9 de novembro de 2026 (horário de Brasília)
  if not exists (select 1 from public.events where slug = 'desafio-dos-gigantes-2026') then
    insert into public.events (slug, name, description, category, banner, starts_at, ends_at, recurrence, max_completions, sort_order)
    values ('desafio-dos-gigantes-2026', 'Desafio dos Gigantes',
            'Uma semana para derrubar os grandes: vença 2 partidas contra clubes de força 80 ou mais e marque 6 gols contra eles.',
            'themed', '{"css":"linear-gradient(135deg,#1b1f27,#d97706)","icon":"crown"}',
            '2026-11-02 03:00+00', '2026-11-09 03:00+00', 'none', 1, 1)
    returning id into v;
    insert into public.event_objectives (event_id, kind, target, params, label, sort_order) values
      (v, 'match_won', 2, '{"min_opponent_strength": 80}', 'Vença 2 gigantes (força 80+)', 1),
      (v, 'goals_scored', 6, '{"min_opponent_strength": 80}', 'Marque 6 gols contra gigantes', 2);
    insert into public.event_rewards (event_id, kind, amount, ref, sort_order) values
      (v, 'cosmetic', 1, 'emb_chama', 1), (v, 'badge', 1, 'evento_gigantes_2026', 2), (v, 'coins', 500, null, 3);
    update public.events set status = 'published' where id = v;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- N) PERMISSÕES
-- ---------------------------------------------------------------------
revoke all on function public.event_period(public.events, timestamptz), public.event_track(uuid, text, int, jsonb),
  public.event_on_fixture(), public.event_on_box(), public.event_on_new_card(), public.event_on_market_sale(), public.event_on_ticket(),
  public.event_json(public.events, uuid), public.event_grant(uuid, public.event_rewards, text),
  public.streak_active_today(uuid, text), public.streak_status_for(uuid), public.admin_assert()
  from public, anon, authenticated;
revoke all on function public.is_admin(), public.events_overview(), public.event_claim(uuid), public.streak_claim(),
  public.admin_event_save(jsonb), public.admin_event_set_status(uuid, text), public.admin_events_list() from public, anon;
grant execute on function public.is_admin(), public.events_overview(), public.event_claim(uuid), public.streak_claim(),
  public.admin_event_save(jsonb), public.admin_event_set_status(uuid, text), public.admin_events_list() to authenticated;
