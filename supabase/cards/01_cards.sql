-- =====================================================================
-- CARTAS, CAIXAS E CAIXA DE ENTRADA
-- Rode DEPOIS de supabase/seasons/01..04 (usa careers, season_fixtures e sim_lock_career).
-- Pode ser rodado de novo sem perder dados (create if not exists / or replace / on conflict).
--
-- Ideia central: a COR DA CAIXA é a raridade da carta que vem dentro dela.
--   cinza = básica · azul = destaque · dourada = lenda · roxa = épica
-- O sorteio (qual caixa você ganha, o que vem dentro) é feito 100% aqui no banco;
-- o navegador só pede "abrir" e anima o resultado. Nada fica no localStorage.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0) Diamantes na carreira
-- ---------------------------------------------------------------------
alter table public.careers add column if not exists diamonds int not null default 0 check (diamonds >= 0);

-- ---------------------------------------------------------------------
-- 1) RARIDADES (também definem os prêmios extras de cada caixa e o valor de descarte)
--    Para mudar o equilíbrio do jogo, basta dar UPDATE nesta tabela. Sem mexer em código.
-- ---------------------------------------------------------------------
create table if not exists public.card_tiers (
  id               text primary key,                 -- basica | destaque | lenda | epica
  label            text not null,
  rank             int  not null unique,             -- 1 = mais comum
  box_coins_min    int  not null default 0,
  box_coins_max    int  not null default 0,
  box_energy_min   int  not null default 0,          -- vai para a energia "bônus" (nunca é zerada)
  box_energy_max   int  not null default 0,
  box_diamonds_min int  not null default 0,
  box_diamonds_max int  not null default 0,
  discard_coins    int  not null default 0,          -- por carta repetida descartada
  discard_diamonds int  not null default 0,
  check (box_coins_min <= box_coins_max and box_energy_min <= box_energy_max and box_diamonds_min <= box_diamonds_max)
);

insert into public.card_tiers
  (id, label, rank, box_coins_min, box_coins_max, box_energy_min, box_energy_max, box_diamonds_min, box_diamonds_max, discard_coins, discard_diamonds)
values
  ('basica',   'Básica',   1,   10,   40, 0, 1, 0,  0,   15, 0),
  ('destaque', 'Destaque', 2,   50,  150, 1, 2, 0,  1,   60, 1),
  ('lenda',    'Lenda',    3,  200,  500, 2, 4, 1,  5,  250, 4),
  ('epica',    'Épica',    4,  500, 1000, 4, 6, 5, 15,  600, 10)
on conflict (id) do nothing;   -- não sobrescreve ajustes que você já fez

-- ---------------------------------------------------------------------
-- 2) CATÁLOGO DE CARTAS  (para criar cartas novas: veja supabase/cards/LEIA-ME.md)
-- ---------------------------------------------------------------------
create table if not exists public.cards (
  id         text primary key,                       -- "arrascaeta-92" (também é o nome do arquivo da imagem, sem extensão)
  name       text not null,
  tier       text not null references public.card_tiers(id),
  overall    int  not null check (overall between 1 and 130),
  position   text,                                   -- ATA, MEI, ZAG... (usado na escalação online, no futuro)
  club_id    text,                                  -- id do clube no jogo (opcional)
  player_key text,                                  -- agrupa versões do mesmo jogador (ex.: "arrascaeta")
  image      text not null,                          -- arquivo dentro de public/cards/ (ex.: "arrascaeta-92.webp")
  weight     int  not null default 100 check (weight > 0),   -- chance relativa DENTRO da raridade
  active     boolean not null default true,          -- false = para de cair, mas quem já tem continua tendo
  meta       jsonb not null default '{}'::jsonb,     -- espaço livre (atributos, temporada, etc.)
  created_at timestamptz not null default now()
);
create index if not exists cards_tier_active_idx on public.cards (tier) where active;

-- ---------------------------------------------------------------------
-- 3) INVENTÁRIO (uma linha por carta diferente; qty = quantas cópias)
-- ---------------------------------------------------------------------
create table if not exists public.user_cards (
  career_id         uuid not null references public.careers(id) on delete cascade,
  card_id           text not null references public.cards(id),
  qty               int  not null default 1 check (qty >= 0),
  first_obtained_at timestamptz not null default now(),
  last_obtained_at  timestamptz not null default now(),
  primary key (career_id, card_id)
);

-- ---------------------------------------------------------------------
-- 4) CAIXA DE ENTRADA
--    `ref` evita caixa duplicada (ex.: a mesma vitória, o mesmo dia).
-- ---------------------------------------------------------------------
create table if not exists public.reward_boxes (
  id         uuid primary key default gen_random_uuid(),
  career_id  uuid not null references public.careers(id) on delete cascade,
  tier       text not null references public.card_tiers(id),
  source     text not null,                          -- welcome | daily | season_win | (futuros: evento, loja...)
  ref        text,
  status     text not null default 'pending' check (status in ('pending', 'opened')),
  created_at timestamptz not null default clock_timestamp(),   -- clock: caixas do mesmo lote mantêm a ordem
  opened_at  timestamptz,
  prize      jsonb                                   -- o que veio (fica como histórico)
);
alter table public.reward_boxes alter column created_at set default clock_timestamp();   -- (para quem já rodou a versão anterior)
create unique index if not exists reward_boxes_ref_uq on public.reward_boxes (career_id, source, ref) where ref is not null;
create index if not exists reward_boxes_pending_idx on public.reward_boxes (career_id, created_at) where status = 'pending';

-- ---------------------------------------------------------------------
-- 5) DE ONDE VÊM AS CAIXAS  (quantas, quais são garantidas e as chances do resto)
--    weights = peso relativo de cada raridade (não precisa somar 100).
-- ---------------------------------------------------------------------
create table if not exists public.box_sources (
  source     text primary key,
  label      text not null,
  draws      int  not null default 1 check (draws >= 0),     -- caixas sorteadas pelos pesos
  guaranteed text[] not null default '{}',                    -- caixas fixas, sempre entregues
  weights    jsonb not null default '{"basica":100}'::jsonb
);

insert into public.box_sources (source, label, draws, guaranteed, weights) values
  -- boas-vindas: 3 caixas fixas (a partir do momento em que chega na tela inicial)
  ('welcome',    'Boas-vindas',  0, '{basica,basica,destaque}', '{"basica":100}'),
  -- diária: 3 caixas por dia; "destaque" é raro, "lenda" quase impossível, "épica" ainda mais
  ('daily',      'Diária',       3, '{}', '{"basica":94.65,"destaque":5,"lenda":0.3,"epica":0.05}'),
  -- cada vitória em Temporadas: 1 caixa (mesmas chances da diária)
  ('season_win', 'Vitória',      1, '{}', '{"basica":94.65,"destaque":5,"lenda":0.3,"epica":0.05}')
on conflict (source) do nothing;

-- Estado por carreira (boas-vindas entregues? último dia da diária)
create table if not exists public.career_card_state (
  career_id    uuid primary key references public.careers(id) on delete cascade,
  welcome_at   timestamptz,
  last_daily   date
);

-- ---------------------------------------------------------------------
-- 6) SEGURANÇA: o navegador só LÊ; toda escrita passa pelas funções abaixo
-- ---------------------------------------------------------------------
alter table public.card_tiers        enable row level security;
alter table public.cards             enable row level security;
alter table public.user_cards        enable row level security;
alter table public.reward_boxes      enable row level security;
alter table public.box_sources       enable row level security;   -- sem policy: as chances não são públicas
alter table public.career_card_state enable row level security;

drop policy if exists "read_card_tiers" on public.card_tiers;
create policy "read_card_tiers" on public.card_tiers for select to authenticated using (true);
drop policy if exists "read_cards" on public.cards;
create policy "read_cards" on public.cards for select to authenticated using (true);
drop policy if exists "own_user_cards" on public.user_cards;
create policy "own_user_cards" on public.user_cards for select to authenticated
  using (exists (select 1 from public.careers c where c.id = user_cards.career_id and c.user_id = auth.uid()));
drop policy if exists "own_reward_boxes" on public.reward_boxes;
create policy "own_reward_boxes" on public.reward_boxes for select to authenticated
  using (exists (select 1 from public.careers c where c.id = reward_boxes.career_id and c.user_id = auth.uid()));

revoke insert, update, delete on public.card_tiers, public.cards, public.user_cards, public.reward_boxes,
  public.box_sources, public.career_card_state from anon, authenticated;
revoke all on public.box_sources, public.career_card_state from anon, authenticated;

-- O catálogo é público para o app, MENOS a coluna "weight" (a chance de cada carta não aparece no navegador).
-- O app deve listar as colunas explicitamente (nunca select *): veja cardsApi.js.
revoke select on public.cards from anon, authenticated;
grant select (id, name, tier, overall, position, club_id, player_key, image, active, meta, created_at)
  on public.cards to authenticated;

-- ---------------------------------------------------------------------
-- 7) FUNÇÕES INTERNAS (sorteio e entrega) — não são chamadas pelo navegador
-- ---------------------------------------------------------------------
-- Sorteia uma raridade pelos pesos. Raridades que não existem na tabela são ignoradas.
create or replace function public.card_pick_tier(p_weights jsonb)
returns text language plpgsql volatile set search_path = public as $$
declare
  r       record;
  v_total double precision := 0;
  v_roll  double precision;
  v_acc   double precision := 0;
  v_last  text;
begin
  for r in select t.id, greatest(coalesce((p_weights ->> t.id)::double precision, 0), 0) as w
             from public.card_tiers t order by t.rank
  loop
    v_total := v_total + r.w;
  end loop;
  if v_total <= 0 then return 'basica'; end if;
  v_roll := random() * v_total;
  for r in select t.id, greatest(coalesce((p_weights ->> t.id)::double precision, 0), 0) as w
             from public.card_tiers t order by t.rank
  loop
    if r.w > 0 then
      v_last := r.id;
      v_acc := v_acc + r.w;
      if v_roll < v_acc then return r.id; end if;
    end if;
  end loop;
  return coalesce(v_last, 'basica');
end;
$$;

-- Coloca UMA caixa na caixa de entrada. Devolve o id (ou null se essa `ref` já tinha sido entregue).
create or replace function public.card_grant_box(p_career uuid, p_tier text, p_source text, p_ref text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.reward_boxes (career_id, tier, source, ref)
  values (p_career, p_tier, p_source, p_ref)
  on conflict (career_id, source, ref) where ref is not null do nothing
  returning id into v_id;
  return v_id;
end;
$$;

-- Entrega todas as caixas de uma "fonte" (garantidas + sorteadas). Devolve quantas foram criadas.
create or replace function public.card_grant_source(p_career uuid, p_source text, p_ref text)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_s     public.box_sources;
  v_tier  text;
  v_i     int := 0;
  v_n     int := 0;
begin
  select * into v_s from public.box_sources where source = p_source;
  if not found then return 0; end if;

  foreach v_tier in array v_s.guaranteed loop
    v_i := v_i + 1;
    if public.card_grant_box(p_career, v_tier, p_source, p_ref || '#' || v_i) is not null then v_n := v_n + 1; end if;
  end loop;
  for v_i in 1 .. v_s.draws loop
    v_tier := public.card_pick_tier(v_s.weights);
    if public.card_grant_box(p_career, v_tier, p_source, p_ref || '#d' || v_i) is not null then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------
-- 8) FUNÇÕES PÚBLICAS (o app chama estas)
-- ---------------------------------------------------------------------
-- Chamada ao entrar na tela inicial. Entrega as caixas de boas-vindas (uma única vez na vida)
-- e as caixas do dia (uma vez por dia, no horário de Brasília). Repetir a chamada é seguro.
create or replace function public.card_claim_daily()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c       public.careers;
  v_st      public.career_card_state;
  v_today   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_welcome int := 0;
  v_daily   int := 0;
begin
  v_c := public.sim_lock_career();     -- identifica o usuário e trava a carreira (evita entrega em dobro)

  insert into public.career_card_state (career_id) values (v_c.id) on conflict do nothing;
  select * into v_st from public.career_card_state where career_id = v_c.id for update;

  if v_st.welcome_at is null then
    v_welcome := public.card_grant_source(v_c.id, 'welcome', 'welcome');
    update public.career_card_state set welcome_at = now(), last_daily = v_today where career_id = v_c.id;
    -- no dia em que ganhou as boas-vindas não ganha a diária também (evita 7 caixas de uma vez)
  elsif v_st.last_daily is null or v_st.last_daily < v_today then
    v_daily := public.card_grant_source(v_c.id, 'daily', v_today::text);
    update public.career_card_state set last_daily = v_today where career_id = v_c.id;
  end if;

  return jsonb_build_object(
    'welcome', v_welcome, 'daily', v_daily, 'granted', v_welcome + v_daily,
    'pending', (select count(*) from public.reward_boxes where career_id = v_c.id and status = 'pending'));
end;
$$;

-- Abre UMA caixa: sorteia a carta e os prêmios, credita tudo e marca a caixa como aberta (atômico).
create or replace function public.box_open(p_box uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_b     public.reward_boxes;
  v_t     public.card_tiers;
  v_card  public.cards;
  v_coins int;
  v_en    int;
  v_dia   int;
  v_qty   int;
  v_new   boolean := false;
  v_prize jsonb;
begin
  v_c := public.sim_lock_career();
  select * into v_b from public.reward_boxes where id = p_box and career_id = v_c.id for update;
  if not found then raise exception 'Caixa não encontrada.'; end if;
  if v_b.status <> 'pending' then raise exception 'Esta caixa já foi aberta.'; end if;

  select * into v_t from public.card_tiers where id = v_b.tier;

  v_coins := v_t.box_coins_min    + floor(random() * (v_t.box_coins_max    - v_t.box_coins_min    + 1))::int;
  v_en    := v_t.box_energy_min   + floor(random() * (v_t.box_energy_max   - v_t.box_energy_min   + 1))::int;
  v_dia   := v_t.box_diamonds_min + floor(random() * (v_t.box_diamonds_max - v_t.box_diamonds_min + 1))::int;

  -- carta: sorteia entre as cartas ATIVAS da raridade da caixa (peso = cards.weight).
  -- Se a raridade ainda não tem nenhuma carta cadastrada, desce para a raridade logo abaixo.
  select c.* into v_card
    from public.cards c
    join public.card_tiers ct on ct.id = c.tier
   where c.active and ct.rank <= v_t.rank
   order by ct.rank desc, -ln(1 - random()) / c.weight       -- (rank maior primeiro; dentro dele, sorteio ponderado)
   limit 1;

  if v_card.id is not null then
    insert into public.user_cards (career_id, card_id) values (v_c.id, v_card.id)
    on conflict (career_id, card_id) do update set qty = public.user_cards.qty + 1, last_obtained_at = now()
    returning qty into v_qty;
    v_new := (v_qty = 1);
  end if;

  update public.careers
     set coins = coins + v_coins, bonus_energy = bonus_energy + v_en, diamonds = diamonds + v_dia
   where id = v_c.id;

  v_prize := jsonb_build_object(
    'coins', v_coins, 'energy', v_en, 'diamonds', v_dia,
    'card', case when v_card.id is null then null else jsonb_build_object(
        'id', v_card.id, 'name', v_card.name, 'tier', v_card.tier, 'overall', v_card.overall,
        'position', v_card.position, 'club_id', v_card.club_id, 'image', v_card.image,
        'player_key', v_card.player_key, 'meta', v_card.meta) end,
    'card_new', v_new, 'card_qty', v_qty);

  update public.reward_boxes set status = 'opened', opened_at = now(), prize = v_prize where id = v_b.id;

  return v_prize || jsonb_build_object('box_id', v_b.id, 'tier', v_b.tier, 'source', v_b.source);
end;
$$;

-- Descarta cartas REPETIDAS (sempre fica 1 cópia). Devolve moedas/diamantes conforme a raridade.
create or replace function public.card_discard(p_card text, p_qty int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c    public.careers;
  v_uc   public.user_cards;
  v_t    public.card_tiers;
  v_coin int;
  v_dia  int;
begin
  v_c := public.sim_lock_career();
  if p_qty is null or p_qty < 1 then raise exception 'Quantidade inválida.'; end if;

  select * into v_uc from public.user_cards where career_id = v_c.id and card_id = p_card for update;
  if not found then raise exception 'Você não tem esta carta.'; end if;
  if v_uc.qty - p_qty < 1 then raise exception 'Você só pode descartar cartas repetidas (uma cópia sempre fica).'; end if;

  select t.* into v_t from public.cards c join public.card_tiers t on t.id = c.tier where c.id = p_card;
  v_coin := v_t.discard_coins * p_qty;
  v_dia  := v_t.discard_diamonds * p_qty;

  update public.user_cards set qty = qty - p_qty where career_id = v_c.id and card_id = p_card;
  update public.careers set coins = coins + v_coin, diamonds = diamonds + v_dia where id = v_c.id;

  return jsonb_build_object('coins', v_coin, 'diamonds', v_dia, 'qty_left', v_uc.qty - p_qty);
end;
$$;

-- Troca diamantes por energia "bônus" (a que nunca é zerada). 1 diamante = 2 de energia.
create or replace function public.diamonds_exchange_energy(p_diamonds int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  c_rate constant int := 2;
begin
  v_c := public.sim_lock_career();
  if p_diamonds is null or p_diamonds < 1 or p_diamonds > 1000 then raise exception 'Quantidade inválida.'; end if;
  if v_c.diamonds < p_diamonds then raise exception 'Diamantes insuficientes.'; end if;
  update public.careers set diamonds = diamonds - p_diamonds, bonus_energy = bonus_energy + p_diamonds * c_rate
   where id = v_c.id;
  return jsonb_build_object('diamonds_spent', p_diamonds, 'energy_gained', p_diamonds * c_rate);
end;
$$;

-- Carteira do topo do app: agora com diamantes e nº de caixas esperando
create or replace function public.refresh_wallet()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  return jsonb_build_object(
    'coins', v_c.coins, 'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy,
    'diamonds', v_c.diamonds,
    'pending_boxes', (select count(*) from public.reward_boxes where career_id = v_c.id and status = 'pending'),
    'next_reset_at', v_c.energy_reset_at + interval '5 hours');
end;
$$;

-- ---------------------------------------------------------------------
-- 9) CADA VITÓRIA EM TEMPORADAS = 1 CAIXA
--    Gatilho no jogo do usuário: assim funciona sem mexer em season_play e vale também
--    para qualquer modo futuro que grave partidas em season_fixtures.
-- ---------------------------------------------------------------------
create or replace function public.card_on_fixture_played()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_cs   record;
  v_my   int;
  v_opp  int;
begin
  if not (coalesce(new.player_match, false) and new.status = 'played' and old.status is distinct from 'played') then
    return new;
  end if;
  select career_id, club_id into v_cs from public.career_seasons where id = new.season_id;
  if not found then return new; end if;
  if new.home_club = v_cs.club_id then v_my := new.home_goals; v_opp := new.away_goals;
  else v_my := new.away_goals; v_opp := new.home_goals; end if;
  if v_my > v_opp then
    perform public.card_grant_source(v_cs.career_id, 'season_win', new.id::text);
  end if;
  return new;
end;
$$;

drop trigger if exists card_on_fixture_played on public.season_fixtures;
create trigger card_on_fixture_played
  after update on public.season_fixtures
  for each row execute function public.card_on_fixture_played();

-- ---------------------------------------------------------------------
-- 10) PERMISSÕES
-- ---------------------------------------------------------------------
revoke all on function public.card_pick_tier(jsonb)                  from public, anon, authenticated;
revoke all on function public.card_grant_box(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.card_grant_source(uuid, text, text)    from public, anon, authenticated;
revoke all on function public.card_on_fixture_played()               from public, anon, authenticated;

revoke all on function public.card_claim_daily()                     from public, anon;
revoke all on function public.box_open(uuid)                         from public, anon;
revoke all on function public.card_discard(text, int)                from public, anon;
revoke all on function public.diamonds_exchange_energy(int)          from public, anon;
revoke all on function public.refresh_wallet()                       from public, anon;
grant execute on function public.card_claim_daily()                  to authenticated;
grant execute on function public.box_open(uuid)                      to authenticated;
grant execute on function public.card_discard(text, int)             to authenticated;
grant execute on function public.diamonds_exchange_energy(int)       to authenticated;
grant execute on function public.refresh_wallet()                    to authenticated;
