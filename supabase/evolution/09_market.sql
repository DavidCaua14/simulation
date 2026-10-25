-- =====================================================================
-- EVOLUÇÃO 09 — MERCADO ENTRE JOGADORES (cartas por moedas)
--
-- * Anunciar: a cópia SAI do inventário (user_cards.qty − 1) e fica guardada no anúncio. Assim ela não pode ser
--   descartada, vendida duas vezes nem usada em outra operação. Cancelar ou expirar devolve a cópia.
-- * Comprar: as DUAS carteiras são travadas em ordem fixa (por id) — sem deadlock quando dois jogadores compram um do
--   outro ao mesmo tempo — e o anúncio é travado (FOR UPDATE): dois compradores ao mesmo tempo → um compra, o outro
--   recebe "já foi vendido". Comprador paga o preço; vendedor recebe o preço menos a taxa (mostrada antes).
-- * Só o servidor decide dono, preço, saldo e taxa. Nada vem do app além de "qual carta/anúncio" e "qual preço pedir".
-- * Tudo registrado: market_listings (estado) + market_events (auditoria) + wallet_ledger (dinheiro).
-- Rode depois de evolution/08. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) CONFIGURAÇÃO
-- ---------------------------------------------------------------------
create table if not exists public.market_config (
  id                  boolean primary key default true check (id),
  fee_pct             numeric(5,2) not null check (fee_pct between 0 and 50),   -- taxa do vendedor (sai da economia)
  listing_hours       int not null check (listing_hours between 1 and 720),     -- validade do anúncio
  max_active_listings int not null check (max_active_listings between 1 and 200),
  active              boolean not null default true
);
insert into public.market_config (id, fee_pct, listing_hours, max_active_listings) values (true, 5, 72, 10)
on conflict (id) do nothing;

-- Limites de preço por raridade (só raridades listadas aqui podem ser vendidas)
create table if not exists public.market_price_limits (
  tier      text primary key references public.card_tiers (id),
  min_price int not null check (min_price >= 1),
  max_price int not null,
  check (max_price >= min_price)
);
insert into public.market_price_limits (tier, min_price, max_price) values
  ('destaque', 200,  20000),
  ('lenda',    1000, 150000),
  ('epica',    2000, 300000)
on conflict (tier) do nothing;

-- ---------------------------------------------------------------------
-- B) ANÚNCIOS E AUDITORIA
-- ---------------------------------------------------------------------
create table if not exists public.market_listings (
  id              uuid primary key default gen_random_uuid(),
  seller_career   uuid not null references public.careers (id) on delete cascade,
  card_id         text not null references public.cards (id),
  price           int  not null check (price > 0),
  fee_pct         numeric(5,2) not null,                 -- taxa vigente quando o anúncio foi criado (não muda depois)
  status          text not null default 'active' check (status in ('active', 'sold', 'cancelled', 'expired')),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  closed_at       timestamptz,
  buyer_career    uuid references public.careers (id) on delete set null,
  fee             int,                                   -- taxa cobrada (na venda)
  seller_received int                                    -- preço − taxa (na venda)
);
-- um anúncio ativo por carta por vendedor (evita anúncio duplicado)
create unique index if not exists market_listings_one_active_uq on public.market_listings (seller_career, card_id) where status = 'active';
create index if not exists market_listings_active_idx on public.market_listings (status, expires_at) where status = 'active';
create index if not exists market_listings_seller_idx on public.market_listings (seller_career, created_at desc);
create index if not exists market_listings_buyer_idx on public.market_listings (buyer_career, closed_at desc);

create table if not exists public.market_events (
  id         bigint generated always as identity primary key,
  listing_id uuid not null references public.market_listings (id) on delete cascade,
  event      text not null check (event in ('created', 'cancelled', 'expired', 'sold')),
  actor      uuid references public.careers (id) on delete set null,
  data       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists market_events_listing_idx on public.market_events (listing_id, id);

alter table public.market_config       enable row level security;
alter table public.market_price_limits enable row level security;
alter table public.market_listings     enable row level security;
alter table public.market_events       enable row level security;
revoke all on public.market_config, public.market_price_limits, public.market_listings, public.market_events from anon, authenticated;
grant select on public.market_config, public.market_price_limits to authenticated;
drop policy if exists "read_market_config" on public.market_config;
create policy "read_market_config" on public.market_config for select to authenticated using (true);
drop policy if exists "read_market_price_limits" on public.market_price_limits;
create policy "read_market_price_limits" on public.market_price_limits for select to authenticated using (true);
-- anúncios e auditoria: só pelas funções abaixo (o nome do vendedor vem junto, sem expor a tabela careers)

-- ---------------------------------------------------------------------
-- C) FUNÇÕES INTERNAS
-- ---------------------------------------------------------------------
-- taxa de um preço (arredonda para cima; nunca maior que o preço)
create or replace function public.market_fee(p_price int, p_pct numeric)
returns int language sql immutable as $$ select least(p_price, ceil(p_price * p_pct / 100)::int) $$;

-- devolve ao vendedor a cópia de um anúncio que saiu do ar (cancelado/expirado). Chamar com o anúncio travado.
create or replace function public.market_return_card(p_listing public.market_listings)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.user_cards (career_id, card_id, qty) values (p_listing.seller_career, p_listing.card_id, 1)
  on conflict (career_id, card_id) do update set qty = public.user_cards.qty + 1;
end;
$$;

-- expira anúncios vencidos (devolvendo as cartas). Roda sozinho no começo das funções do mercado.
create or replace function public.market_expire_due(p_limit int default 200)
returns int language plpgsql security definer set search_path = public as $$
declare v_l public.market_listings; v_n int := 0;
begin
  for v_l in
    select * from public.market_listings where status = 'active' and expires_at <= now()
     order by expires_at limit p_limit for update skip locked      -- quem estiver sendo comprado agora fica para depois
  loop
    update public.market_listings set status = 'expired', closed_at = now() where id = v_l.id;
    perform public.market_return_card(v_l);
    insert into public.market_events (listing_id, event, actor, data) values (v_l.id, 'expired', null, '{}');
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function public.market_card_json(p_card public.cards)
returns jsonb language sql stable as $$
  select jsonb_build_object('id', p_card.id, 'name', p_card.name, 'tier', p_card.tier, 'overall', p_card.overall,
                            'position', p_card.position, 'club_id', p_card.club_id, 'player_key', p_card.player_key,
                            'image', p_card.image, 'meta', p_card.meta);
$$;

-- ---------------------------------------------------------------------
-- D) FUNÇÕES DO APP
-- ---------------------------------------------------------------------
-- regras do mercado (para a tela mostrar ANTES de anunciar/comprar)
create or replace function public.market_rules()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('fee_pct', c.fee_pct, 'listing_hours', c.listing_hours, 'max_active_listings', c.max_active_listings,
                            'active', c.active,
                            'limits', (select jsonb_object_agg(tier, jsonb_build_object('min', min_price, 'max', max_price)) from public.market_price_limits))
    from public.market_config c;
$$;

-- Anunciar uma cópia de uma carta própria
create or replace function public.market_list_card(p_card text, p_price int, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c    public.careers;
  v_prev jsonb;
  v_cfg  public.market_config;
  v_lim  public.market_price_limits;
  v_card public.cards;
  v_qty  int;
  v_id   uuid := gen_random_uuid();
  v_exp  timestamptz;
begin
  v_c := public.sim_lock_career();
  v_prev := public.econ_request_get(v_c.id, p_request, 'market_list');
  if v_prev is not null then return v_prev; end if;
  perform public.market_expire_due();

  select * into v_cfg from public.market_config;
  if not found or not v_cfg.active then raise exception 'O mercado está fechado no momento.'; end if;
  select * into v_card from public.cards where id = p_card;
  if not found then raise exception 'Carta não encontrada.'; end if;
  select * into v_lim from public.market_price_limits where tier = v_card.tier;
  if not found then raise exception 'Cartas desta raridade não podem ser vendidas no mercado.'; end if;
  if p_price is null or p_price < v_lim.min_price or p_price > v_lim.max_price then
    raise exception 'Preço fora do limite para esta raridade: de % a % moedas.',
      to_char(v_lim.min_price, 'FM999G999G999'), to_char(v_lim.max_price, 'FM999G999G999');
  end if;
  if (select count(*) from public.market_listings where seller_career = v_c.id and status = 'active') >= v_cfg.max_active_listings then
    raise exception '%', format('Você já tem %s %s (o máximo). Cancele um ou espere vender.', v_cfg.max_active_listings,
                                case when v_cfg.max_active_listings = 1 then 'anúncio ativo' else 'anúncios ativos' end);
  end if;
  if exists (select 1 from public.market_listings where seller_career = v_c.id and card_id = p_card and status = 'active') then
    raise exception 'Você já tem um anúncio ativo desta carta.';
  end if;

  -- a cópia sai do inventário (se não tiver, nada acontece)
  update public.user_cards set qty = qty - 1 where career_id = v_c.id and card_id = p_card and qty >= 1 returning qty into v_qty;
  if v_qty is null then raise exception 'Você não tem esta carta disponível para vender.'; end if;

  v_exp := now() + make_interval(hours => v_cfg.listing_hours);
  insert into public.market_listings (id, seller_career, card_id, price, fee_pct, expires_at)
  values (v_id, v_c.id, p_card, p_price, v_cfg.fee_pct, v_exp);
  insert into public.market_events (listing_id, event, actor, data)
  values (v_id, 'created', v_c.id, jsonb_build_object('price', p_price, 'fee_pct', v_cfg.fee_pct));

  return public.econ_request_save(v_c.id, p_request, 'market_list', jsonb_build_object(
    'ok', true, 'listing_id', v_id, 'card', public.market_card_json(v_card), 'price', p_price,
    'fee_pct', v_cfg.fee_pct, 'fee', public.market_fee(p_price, v_cfg.fee_pct),
    'seller_receives', p_price - public.market_fee(p_price, v_cfg.fee_pct), 'expires_at', v_exp, 'qty_left', v_qty));
end;
$$;

-- Cancelar um anúncio próprio (a cópia volta). Cancelar de novo devolve o mesmo resultado.
create or replace function public.market_cancel(p_listing uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_l public.market_listings;
begin
  v_c := public.sim_lock_career();
  select * into v_l from public.market_listings where id = p_listing and seller_career = v_c.id for update;
  if not found then raise exception 'Anúncio não encontrado.'; end if;
  if v_l.status = 'cancelled' then return jsonb_build_object('ok', true, 'status', 'cancelled', 'replayed', true); end if;
  if v_l.status = 'sold' then raise exception 'Este anúncio já foi vendido.'; end if;
  if v_l.status = 'expired' then raise exception 'Este anúncio já expirou (a carta voltou para a sua coleção).'; end if;
  if v_l.expires_at <= now() then
    perform public.market_expire_due();
    raise exception 'Este anúncio já expirou (a carta voltou para a sua coleção).';
  end if;
  update public.market_listings set status = 'cancelled', closed_at = now() where id = v_l.id;
  perform public.market_return_card(v_l);
  insert into public.market_events (listing_id, event, actor) values (v_l.id, 'cancelled', v_c.id);
  return jsonb_build_object('ok', true, 'status', 'cancelled', 'card_id', v_l.card_id, 'replayed', false);
end;
$$;

-- Comprar um anúncio
create or replace function public.market_buy(p_listing uuid, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me     uuid;
  v_c      public.careers;
  v_prev   jsonb;
  v_l      public.market_listings;
  v_card   public.cards;
  v_fee    int;
  v_bal    int;
  v_qty    int;
  v_seller text;
  v_sid    uuid;
begin
  select id into v_me from public.careers where user_id = auth.uid() and status = 'active';
  if v_me is null then raise exception 'Carreira ativa não encontrada'; end if;
  select seller_career into v_sid from public.market_listings where id = p_listing;
  if v_sid is null then raise exception 'Anúncio não encontrado.'; end if;
  -- trava as duas carteiras em ordem fixa (evita deadlock entre compras cruzadas)
  perform 1 from public.careers where id in (v_me, v_sid) order by id for update;
  v_c := public.sim_lock_career();

  v_prev := public.econ_request_get(v_c.id, p_request, 'market_buy');
  if v_prev is not null then return v_prev; end if;
  if not (select active from public.market_config) then raise exception 'O mercado está fechado no momento.'; end if;

  select * into v_l from public.market_listings where id = p_listing for update;   -- compradores simultâneos: um de cada vez
  if v_l.seller_career = v_c.id then raise exception 'Você não pode comprar o seu próprio anúncio.'; end if;
  if v_l.status = 'sold' then raise exception 'Este anúncio já foi vendido.'; end if;
  if v_l.status <> 'active' then raise exception 'Este anúncio não está mais disponível.'; end if;
  if v_l.expires_at <= now() then raise exception 'Este anúncio expirou.'; end if;

  v_fee := public.market_fee(v_l.price, v_l.fee_pct);
  v_bal := public.econ_apply(v_c.id, 'coins', -v_l.price, 'market_buy', v_l.id::text);         -- sem saldo: erro, nada muda
  if v_l.price - v_fee > 0 then
    perform public.econ_apply(v_l.seller_career, 'coins', v_l.price - v_fee, 'market_sale', v_l.id::text);
  end if;

  insert into public.user_cards (career_id, card_id) values (v_c.id, v_l.card_id)
  on conflict (career_id, card_id) do update set qty = public.user_cards.qty + 1, last_obtained_at = now()
  returning qty into v_qty;
  update public.market_listings
     set status = 'sold', closed_at = now(), buyer_career = v_c.id, fee = v_fee, seller_received = v_l.price - v_fee
   where id = v_l.id;
  insert into public.market_events (listing_id, event, actor, data)
  values (v_l.id, 'sold', v_c.id, jsonb_build_object('price', v_l.price, 'fee', v_fee, 'seller_received', v_l.price - v_fee));

  select * into v_card from public.cards where id = v_l.card_id;
  select nickname into v_seller from public.careers where id = v_l.seller_career;
  return public.econ_request_save(v_c.id, p_request, 'market_buy', jsonb_build_object(
    'ok', true, 'listing_id', v_l.id, 'card', public.market_card_json(v_card), 'price', v_l.price, 'seller', v_seller,
    'coins', v_bal, 'qty', v_qty, 'new', v_qty = 1));
end;
$$;

-- Vitrine do mercado com filtros: p_q (nome), p_tier, p_min, p_max, p_sort (price_asc|price_desc|newest|overall), p_limit, p_offset
create or replace function public.market_browse(p_q text default null, p_tier text default null, p_min int default null, p_max int default null,
                                                p_sort text default 'newest', p_limit int default 30, p_offset int default 0)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid; v_lim int := least(greatest(coalesce(p_limit, 30), 1), 60);
begin
  select id into v_me from public.careers where user_id = auth.uid() and status = 'active';
  if v_me is null then raise exception 'Carreira ativa não encontrada'; end if;
  perform public.market_expire_due();
  return jsonb_build_object(
    'rules', public.market_rules(),
    'items', coalesce((
      select jsonb_agg(x.j order by x.rn)
        from (
          select jsonb_build_object('id', l.id, 'price', l.price, 'created_at', l.created_at, 'expires_at', l.expires_at,
                                    'seller', s.nickname, 'mine', l.seller_career = v_me, 'card', public.market_card_json(c)) as j,
                 row_number() over (order by
                   case when p_sort = 'price_asc' then l.price end asc,
                   case when p_sort = 'price_desc' then l.price end desc,
                   case when p_sort = 'overall' then c.overall end desc,
                   l.created_at desc, l.id) as rn
            from public.market_listings l
            join public.cards c on c.id = l.card_id
            join public.careers s on s.id = l.seller_career
           where l.status = 'active' and l.expires_at > now()
             and (p_tier is null or c.tier = p_tier)
             and (p_min is null or l.price >= p_min)
             and (p_max is null or l.price <= p_max)
             and (nullif(trim(p_q), '') is null or c.name ilike '%' || replace(replace(trim(p_q), '%', ''), '_', '') || '%')
           order by rn
           limit v_lim offset greatest(coalesce(p_offset, 0), 0)
        ) x), '[]'::jsonb),
    'total', (select count(*) from public.market_listings l join public.cards c on c.id = l.card_id
               where l.status = 'active' and l.expires_at > now()
                 and (p_tier is null or c.tier = p_tier) and (p_min is null or l.price >= p_min) and (p_max is null or l.price <= p_max)
                 and (nullif(trim(p_q), '') is null or c.name ilike '%' || replace(replace(trim(p_q), '%', ''), '_', '') || '%')));
end;
$$;

-- Meus anúncios ativos + histórico de vendas e compras (as duas partes veem a transação)
create or replace function public.market_mine()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid;
begin
  select id into v_me from public.careers where user_id = auth.uid() and status = 'active';
  if v_me is null then raise exception 'Carreira ativa não encontrada'; end if;
  perform public.market_expire_due();
  return jsonb_build_object(
    'rules', public.market_rules(),
    'active', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'price', l.price, 'fee', public.market_fee(l.price, l.fee_pct),
               'seller_receives', l.price - public.market_fee(l.price, l.fee_pct), 'created_at', l.created_at, 'expires_at', l.expires_at,
               'card', public.market_card_json(c)) order by l.created_at desc)
        from public.market_listings l join public.cards c on c.id = l.card_id
       where l.seller_career = v_me and l.status = 'active'), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(h.j order by h.at desc)
        from (
          select jsonb_build_object('id', l.id, 'role', case when l.seller_career = v_me then 'sold' else 'bought' end,
                   'status', l.status, 'price', l.price, 'fee', case when l.seller_career = v_me then l.fee end,
                   'received', case when l.seller_career = v_me then l.seller_received end,
                   'other', case when l.seller_career = v_me then b.nickname else s.nickname end,
                   'at', coalesce(l.closed_at, l.created_at), 'card', public.market_card_json(c)) as j,
                 coalesce(l.closed_at, l.created_at) as at
            from public.market_listings l
            join public.cards c on c.id = l.card_id
            join public.careers s on s.id = l.seller_career
            left join public.careers b on b.id = l.buyer_career
           where (l.seller_career = v_me and l.status <> 'active') or l.buyer_career = v_me
           order by coalesce(l.closed_at, l.created_at) desc
           limit 50) h), '[]'::jsonb));
end;
$$;

-- Cartas que eu posso anunciar (com cópia disponível e raridade permitida)
create or replace function public.market_sellable()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me uuid;
begin
  select id into v_me from public.careers where user_id = auth.uid() and status = 'active';
  if v_me is null then raise exception 'Carreira ativa não encontrada'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('card', public.market_card_json(c), 'qty', uc.qty,
             'listed', exists (select 1 from public.market_listings l where l.seller_career = v_me and l.card_id = c.id and l.status = 'active'),
             'min', lim.min_price, 'max', lim.max_price)
           order by ct.rank desc, c.overall desc, c.name)
      from public.user_cards uc
      join public.cards c on c.id = uc.card_id
      join public.card_tiers ct on ct.id = c.tier
      join public.market_price_limits lim on lim.tier = c.tier
     where uc.career_id = v_me and uc.qty >= 1), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- E) PERMISSÕES
-- ---------------------------------------------------------------------
revoke all on function public.market_fee(int, numeric), public.market_return_card(public.market_listings),
  public.market_expire_due(int), public.market_card_json(public.cards) from public, anon, authenticated;
revoke all on function public.market_rules(), public.market_list_card(text, int, uuid), public.market_cancel(uuid),
  public.market_buy(uuid, uuid), public.market_browse(text, text, int, int, text, int, int), public.market_mine(),
  public.market_sellable() from public, anon;
grant execute on function public.market_rules(), public.market_list_card(text, int, uuid), public.market_cancel(uuid),
  public.market_buy(uuid, uuid), public.market_browse(text, text, int, int, text, int, int), public.market_mine(),
  public.market_sellable() to authenticated;
