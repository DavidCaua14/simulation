-- =====================================================================
-- EVOLUÇÃO 08 — ROLETA DE CARTAS POR DIAMANTES
--
-- * Cada giro custa diamantes (wheel_config.cost_diamonds = 10), cobrados por econ_apply (livro + idempotência).
-- * Prêmios: só Lendas e Épicas, em FATIAS com probabilidades próprias (wheel_segments). As fatias ativas precisam
--   somar exatamente 100% — conferido pelo banco no fim de cada alteração e de novo antes de cada giro.
-- * Proteção contra azar (configurável e mostrada ANTES do giro): sem Épica em (pity_threshold − 1) giros seguidos,
--   o giro seguinte é Épica garantida. O contador zera sempre que sair uma Épica.
-- * O sorteio acontece AQUI no servidor; o app só anima até a fatia sorteada.
-- * Repetidas: mesma regra do resto do jogo (a cópia extra entra na coleção e pode ser descartada).
-- Rode depois de evolution/07. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) CONFIGURAÇÃO
-- ---------------------------------------------------------------------
create table if not exists public.wheel_config (
  id             boolean primary key default true check (id),     -- uma linha só
  cost_diamonds  int     not null check (cost_diamonds > 0),
  pity_enabled   boolean not null default true,
  pity_threshold int     not null check (pity_threshold between 2 and 500),   -- no máximo N giros até uma Épica
  pity_segment   text    not null,                                             -- fatia entregue pela garantia
  active         boolean not null default true
);

create table if not exists public.wheel_segments (
  id          text primary key,
  label       text not null,
  tier        text not null references public.card_tiers (id),
  min_overall int,
  max_overall int,
  probability numeric(6,3) not null check (probability > 0 and probability <= 100),   -- em %
  color       text not null default '#fbbf24',
  sort_order  int  not null default 0,
  active      boolean not null default true,
  check (tier in ('lenda', 'epica')),
  check (min_overall is null or max_overall is null or min_overall <= max_overall)
);

-- Fatias (as notas de Lenda são as mesmas em qualquer banco: 85–99). Épicas são raras de propósito:
-- 3% por giro ≈ 1 a cada 33 giros, e a garantia limita a sequência de azar a 40 giros.
insert into public.wheel_segments (id, label, tier, min_overall, max_overall, probability, color, sort_order) values
  ('lenda_classica', 'Lenda clássica', 'lenda', null, 89, 70.000, '#d4a017', 1),
  ('lenda_estrela',  'Lenda estrela',  'lenda',   90, 93, 22.000, '#f5c542', 2),
  ('lenda_imortal',  'Lenda imortal',  'lenda',   94, null, 5.000, '#ffe08a', 3),
  ('epica',          'Épica',          'epica', null, null, 3.000, '#c084fc', 4)
on conflict (id) do nothing;

insert into public.wheel_config (id, cost_diamonds, pity_enabled, pity_threshold, pity_segment)
values (true, 10, true, 40, 'epica')
on conflict (id) do nothing;

-- soma = 100% (conferida no COMMIT de qualquer alteração nas fatias)
create or replace function public.wheel_check_sum()
returns trigger language plpgsql set search_path = public as $$
declare v_sum numeric;
begin
  select coalesce(sum(probability), 0) into v_sum from public.wheel_segments where active;
  if v_sum <> 100 then
    raise exception '%', format('As probabilidades ativas da roleta somam %s%% (precisam somar 100%%).', trim(to_char(v_sum, 'FM990D099')));
  end if;
  return null;
end;
$$;
drop trigger if exists wheel_segments_sum on public.wheel_segments;
create constraint trigger wheel_segments_sum after insert or update or delete on public.wheel_segments
  deferrable initially deferred for each row execute function public.wheel_check_sum();

-- ---------------------------------------------------------------------
-- B) ESTADO E HISTÓRICO
-- ---------------------------------------------------------------------
create table if not exists public.wheel_state (
  career_id        uuid primary key references public.careers (id) on delete cascade,
  spins_total      int not null default 0,
  spins_since_epic int not null default 0     -- giros seguidos sem Épica (a garantia olha para isto)
);

create table if not exists public.wheel_spins (
  id         uuid primary key default gen_random_uuid(),
  career_id  uuid not null references public.careers (id) on delete cascade,
  request_id uuid not null,
  segment_id text not null references public.wheel_segments (id),
  card_id    text not null references public.cards (id),
  cost       int  not null,
  pity       boolean not null default false,   -- true = veio pela garantia
  roll       numeric(8,5),                      -- número sorteado (0–100); null quando foi garantia
  created_at timestamptz not null default now()
);
create index if not exists wheel_spins_career_idx on public.wheel_spins (career_id, created_at desc);

alter table public.wheel_config   enable row level security;
alter table public.wheel_segments enable row level security;
alter table public.wheel_state    enable row level security;
alter table public.wheel_spins    enable row level security;
revoke all on public.wheel_config, public.wheel_segments, public.wheel_state, public.wheel_spins from anon, authenticated;
grant select on public.wheel_config, public.wheel_segments, public.wheel_state, public.wheel_spins to authenticated;
drop policy if exists "read_wheel_config" on public.wheel_config;
create policy "read_wheel_config" on public.wheel_config for select to authenticated using (true);
drop policy if exists "read_wheel_segments" on public.wheel_segments;
create policy "read_wheel_segments" on public.wheel_segments for select to authenticated using (active);
drop policy if exists "own_wheel_state" on public.wheel_state;
create policy "own_wheel_state" on public.wheel_state for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));
drop policy if exists "own_wheel_spins" on public.wheel_spins;
create policy "own_wheel_spins" on public.wheel_spins for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));

-- ---------------------------------------------------------------------
-- C) FUNÇÕES
-- ---------------------------------------------------------------------
-- cartas que podem sair numa fatia
create or replace function public.wheel_segment_cards(p_seg public.wheel_segments)
returns setof public.cards language sql stable security definer set search_path = public as $$
  select c.* from public.cards c
   where c.active and c.tier = p_seg.tier
     and (p_seg.min_overall is null or c.overall >= p_seg.min_overall)
     and (p_seg.max_overall is null or c.overall <= p_seg.max_overall);
$$;

-- tudo o que a tela precisa ANTES do giro: custo, fatias e chances, regra da garantia, saldo e últimos giros
create or replace function public.wheel_catalog()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_car public.careers;
  v_cfg public.wheel_config;
  v_st  public.wheel_state;
begin
  select * into v_car from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  select * into v_cfg from public.wheel_config;
  select * into v_st from public.wheel_state where career_id = v_car.id;
  return jsonb_build_object(
    'active', coalesce(v_cfg.active, false),
    'cost', v_cfg.cost_diamonds,
    'diamonds', v_car.diamonds,
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'tier', s.tier, 'probability', s.probability,
               'color', s.color, 'min_overall', s.min_overall, 'max_overall', s.max_overall,
               'cards', (select count(*) from public.wheel_segment_cards(s)))
             order by s.sort_order, s.id)
        from public.wheel_segments s where s.active), '[]'::jsonb),
    'probability_sum', (select sum(probability) from public.wheel_segments where active),
    'pity', jsonb_build_object(
      'enabled', v_cfg.pity_enabled, 'threshold', v_cfg.pity_threshold,
      'segment', v_cfg.pity_segment, 'segment_label', (select label from public.wheel_segments where id = v_cfg.pity_segment),
      'since', coalesce(v_st.spins_since_epic, 0),
      'remaining', case when v_cfg.pity_enabled then greatest(1, v_cfg.pity_threshold - coalesce(v_st.spins_since_epic, 0)) end),
    'spins_total', coalesce(v_st.spins_total, 0),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('id', w.id, 'at', w.created_at, 'segment', w.segment_id, 'pity', w.pity,
               'card', jsonb_build_object('id', c.id, 'name', c.name, 'tier', c.tier, 'overall', c.overall)) order by w.created_at desc)
        from (select * from public.wheel_spins where career_id = v_car.id order by created_at desc limit 10) w
        join public.cards c on c.id = w.card_id), '[]'::jsonb));
end;
$$;

-- UM giro. p_request: identificador gerado pelo app antes de girar (o mesmo em novas tentativas).
create or replace function public.wheel_spin(p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_prev  jsonb;
  v_cfg   public.wheel_config;
  v_st    public.wheel_state;
  v_seg   public.wheel_segments;
  v_card  public.cards;
  v_roll  numeric;
  v_acc   numeric := 0;
  v_pity  boolean := false;
  v_bal   int;
  v_qty   int;
  v_id    uuid := gen_random_uuid();
  r       public.wheel_segments;
begin
  v_c := public.sim_lock_career();                                     -- giros do mesmo usuário em fila
  v_prev := public.econ_request_get(v_c.id, p_request, 'wheel_spin');
  if v_prev is not null then return v_prev; end if;                    -- mesmo pedido = mesmo giro, sem cobrar de novo

  select * into v_cfg from public.wheel_config;
  if not found or not v_cfg.active then raise exception 'A roleta está fechada no momento.'; end if;
  if (select sum(probability) from public.wheel_segments where active) is distinct from 100 then
    raise exception 'A roleta está em manutenção (probabilidades inválidas).';
  end if;

  insert into public.wheel_state (career_id) values (v_c.id) on conflict do nothing;
  select * into v_st from public.wheel_state where career_id = v_c.id for update;

  -- cobra primeiro: sem saldo, nada acontece
  v_bal := public.econ_apply(v_c.id, 'diamonds', -v_cfg.cost_diamonds, 'wheel_spin', v_id::text);

  -- garantia: este é o N-ésimo giro seguido sem Épica
  if v_cfg.pity_enabled and v_st.spins_since_epic + 1 >= v_cfg.pity_threshold then
    select * into v_seg from public.wheel_segments where id = v_cfg.pity_segment and active;
    v_pity := found;
  end if;
  if not v_pity then
    v_roll := round((random() * 100)::numeric, 5);
    for r in select * from public.wheel_segments where active order by sort_order, id loop
      v_acc := v_acc + r.probability;
      v_seg := r;
      exit when v_roll < v_acc;
    end loop;
  end if;

  -- carta da fatia (peso = cards.weight, igual às caixas)
  select c.* into v_card from public.wheel_segment_cards(v_seg) c order by -ln(1 - random()) / c.weight limit 1;
  if v_card.id is null then raise exception 'A fatia % está sem cartas. Avise o suporte.', v_seg.label; end if;

  insert into public.user_cards (career_id, card_id) values (v_c.id, v_card.id)
  on conflict (career_id, card_id) do update set qty = public.user_cards.qty + 1, last_obtained_at = now()
  returning qty into v_qty;
  insert into public.wheel_spins (id, career_id, request_id, segment_id, card_id, cost, pity, roll)
  values (v_id, v_c.id, p_request, v_seg.id, v_card.id, v_cfg.cost_diamonds, v_pity, v_roll);
  update public.wheel_state
     set spins_total = spins_total + 1,
         spins_since_epic = case when v_seg.tier = 'epica' then 0 else spins_since_epic + 1 end
   where career_id = v_c.id
  returning * into v_st;

  return public.econ_request_save(v_c.id, p_request, 'wheel_spin', jsonb_build_object(
    'ok', true, 'spin_id', v_id, 'segment', v_seg.id, 'segment_label', v_seg.label, 'tier', v_seg.tier, 'pity', v_pity,
    'cost', v_cfg.cost_diamonds, 'diamonds', v_bal,
    'card', jsonb_build_object('id', v_card.id, 'name', v_card.name, 'tier', v_card.tier, 'overall', v_card.overall,
                               'position', v_card.position, 'club_id', v_card.club_id, 'player_key', v_card.player_key,
                               'image', v_card.image, 'meta', v_card.meta),
    'qty', v_qty, 'new', v_qty = 1,
    'pity_since', v_st.spins_since_epic,
    'pity_remaining', case when v_cfg.pity_enabled then greatest(1, v_cfg.pity_threshold - v_st.spins_since_epic) end));
end;
$$;

revoke all on function public.wheel_check_sum(), public.wheel_segment_cards(public.wheel_segments) from public, anon, authenticated;
revoke all on function public.wheel_catalog(), public.wheel_spin(uuid) from public, anon;
grant execute on function public.wheel_catalog(), public.wheel_spin(uuid) to authenticated;
