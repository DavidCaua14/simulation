-- =====================================================================
-- EVOLUÇÃO 06 — ECONOMIA (livro de transações + idempotência) E LOJA DE CARTAS
--
-- A carteira continua sendo a MESMA de sempre (careers.coins / diamonds / energy / bonus_energy). Não há moeda paralela.
-- O que muda:
--   A) wallet_ledger ...... TODA alteração de saldo vira uma linha (gatilho na tabela careers — vale também para as
--                           funções antigas). Motivo e referência vêm de econ_apply / econ_tag.
--   B) econ_requests ...... chave de idempotência por compra: repetir o mesmo pedido devolve o MESMO resultado, sem
--                           cobrar de novo (clique duplo, atualizar a página, queda de rede).
--   C) econ_apply() ....... ponto único para debitar/creditar nas compras novas (loja, roleta, mercado, energia...).
--   D) Loja de cartas ..... vitrine rotativa de Destaques e Lendas, preços em tabela (shop_prices), limite por usuário.
--
-- Rode depois de evolution/05. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) LIVRO DE TRANSAÇÕES
-- ---------------------------------------------------------------------
create table if not exists public.wallet_ledger (
  id            bigint generated always as identity primary key,
  career_id     uuid not null references public.careers (id) on delete cascade,
  currency      text not null check (currency in ('coins', 'diamonds', 'energy', 'bonus_energy')),
  delta         int  not null check (delta <> 0),
  balance_after int  not null check (balance_after >= 0),
  reason        text not null,           -- shop_card, box_open, energy_regen, opening_balance, other...
  ref           text,                    -- id da compra / caixa / partida
  created_at    timestamptz not null default clock_timestamp()
);
create index if not exists wallet_ledger_career_idx on public.wallet_ledger (career_id, id desc);

-- Motivo da próxima alteração de saldo nesta transação (lido pelo gatilho). Vale até ser trocado ou a transação acabar.
create or replace function public.econ_tag(p_reason text, p_ref text default null)
returns void language sql volatile set search_path = public as $$
  select set_config('econ.reason', coalesce(p_reason, ''), true), set_config('econ.ref', coalesce(p_ref, ''), true);
$$;

create or replace function public.econ_ledger_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_reason text := nullif(current_setting('econ.reason', true), '');
  v_ref    text := nullif(current_setting('econ.ref', true), '');
  v_cur    text;
  v_old    int;
  v_new    int;
begin
  foreach v_cur in array array['coins', 'diamonds', 'energy', 'bonus_energy'] loop
    v_new := (to_jsonb(new) ->> v_cur)::int;
    v_old := case when tg_op = 'INSERT' then 0 else (to_jsonb(old) ->> v_cur)::int end;
    if v_new is distinct from v_old and coalesce(v_new, 0) - coalesce(v_old, 0) <> 0 then
      insert into public.wallet_ledger (career_id, currency, delta, balance_after, reason, ref)
      values (new.id, v_cur, coalesce(v_new, 0) - coalesce(v_old, 0), coalesce(v_new, 0),
              coalesce(v_reason,
                       case when tg_op = 'INSERT' then 'opening_balance'
                            -- recarga automática de energia (sim_lock_career): só a energia sobe e o relógio anda
                            when v_cur = 'energy' and new.energy_reset_at is distinct from old.energy_reset_at and v_new > v_old then 'energy_regen'
                            else 'other' end),
              v_ref);
    end if;
  end loop;
  return null;
end;
$$;

drop trigger if exists econ_ledger_trg on public.careers;
create trigger econ_ledger_trg
  after insert or update of coins, diamonds, energy, bonus_energy on public.careers
  for each row execute function public.econ_ledger_trg();

-- saldo de abertura das carreiras que já existiam (uma vez só: só se a carreira ainda não tem linha no livro)
insert into public.wallet_ledger (career_id, currency, delta, balance_after, reason)
select c.id, x.cur, x.val, x.val, 'opening_balance'
  from public.careers c
  cross join lateral (values ('coins', c.coins), ('diamonds', c.diamonds), ('energy', c.energy), ('bonus_energy', c.bonus_energy)) x(cur, val)
 where x.val > 0 and not exists (select 1 from public.wallet_ledger l where l.career_id = c.id);

-- ---------------------------------------------------------------------
-- B) IDEMPOTÊNCIA
-- ---------------------------------------------------------------------
create table if not exists public.econ_requests (
  career_id  uuid not null references public.careers (id) on delete cascade,
  request_id uuid not null,
  action     text not null,
  response   jsonb not null,
  created_at timestamptz not null default now(),
  primary key (career_id, request_id)
);

-- Devolve a resposta já gravada para este pedido (null = pedido novo). Chamar DEPOIS de travar a carreira.
create or replace function public.econ_request_get(p_career uuid, p_request uuid, p_action text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_r public.econ_requests;
begin
  if p_request is null then raise exception 'Pedido sem identificador.'; end if;
  select * into v_r from public.econ_requests where career_id = p_career and request_id = p_request;
  if not found then return null; end if;
  if v_r.action <> p_action then raise exception 'Identificador de pedido já usado em outra operação.'; end if;
  return v_r.response || jsonb_build_object('replayed', true);
end;
$$;

create or replace function public.econ_request_save(p_career uuid, p_request uuid, p_action text, p_response jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  insert into public.econ_requests (career_id, request_id, action, response) values (p_career, p_request, p_action, p_response);
  return p_response || jsonb_build_object('replayed', false);
end;
$$;

-- ---------------------------------------------------------------------
-- C) DÉBITO/CRÉDITO CENTRAL (usado pelas compras novas). Saldo insuficiente = erro, nada muda.
-- ---------------------------------------------------------------------
create or replace function public.econ_apply(p_career uuid, p_currency text, p_delta int, p_reason text, p_ref text default null)
returns int language plpgsql security definer set search_path = public as $$
declare v_bal int;
begin
  if p_currency not in ('coins', 'diamonds', 'energy', 'bonus_energy') then raise exception 'Moeda inválida.'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'Valor inválido.'; end if;
  execute format('select %I from public.careers where id = $1 for update', p_currency) into v_bal using p_career;
  if v_bal is null then raise exception 'Carreira não encontrada.'; end if;
  if v_bal + p_delta < 0 then
    raise exception using errcode = 'P0402',
      message = case p_currency when 'coins' then 'Moedas insuficientes.' when 'diamonds' then 'Diamantes insuficientes.'
                                else 'Energia insuficiente.' end,
      detail = format('saldo=%s, necessário=%s', v_bal, -p_delta);
  end if;
  perform public.econ_tag(p_reason, p_ref);
  execute format('update public.careers set %I = %I + $1 where id = $2 returning %I', p_currency, p_currency, p_currency)
    into v_bal using p_delta, p_career;
  perform public.econ_tag(null, null);
  return v_bal;
end;
$$;

-- histórico da carteira (para o app)
create or replace function public.wallet_history(p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_car uuid;
begin
  select id into v_car from public.careers where user_id = auth.uid() and status = 'active';
  if v_car is null then raise exception 'Carreira ativa não encontrada'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', l.id, 'currency', l.currency, 'delta', l.delta, 'balance', l.balance_after,
                                        'reason', l.reason, 'ref', l.ref, 'at', l.created_at) order by l.id desc)
      from (select * from public.wallet_ledger where career_id = v_car order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) l
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- D) LOJA DE CARTAS — configuração centralizada
-- ---------------------------------------------------------------------
-- Seções da vitrine: quais raridades aparecem, quantas cartas por rodízio, de quanto em quanto tempo troca (UTC)
-- e quantas cópias de cada carta o mesmo usuário pode comprar por rodízio.
create table if not exists public.shop_sections (
  tier           text primary key references public.card_tiers (id),
  label          text not null,
  description    text not null,
  slots          int  not null check (slots between 1 and 30),
  rotation_hours int  not null default 24 check (rotation_hours between 1 and 168),
  per_user_limit int  not null default 1 check (per_user_limit between 1 and 10),
  sort_order     int  not null default 0,
  active         boolean not null default true
);

-- Preço pela faixa de notas da raridade: a carta mais fraca da raridade custa `base`, a mais forte custa `top` e as
-- demais ficam proporcionais à nota (funciona com qualquer catálogo). Uma linha por raridade × moeda.
create table if not exists public.shop_prices (
  tier        text not null references public.card_tiers (id),
  currency    text not null check (currency in ('coins', 'diamonds')),
  base        int  not null check (base > 0),
  top         int  not null,
  round_to    int  not null default 1 check (round_to >= 1),
  min_price   int  not null default 1 check (min_price >= 1),
  active      boolean not null default true,
  primary key (tier, currency),
  constraint shop_prices_top_check check (top >= base)
);

-- Balanceamento (outubro/2026, medido em produção): ~24 moedas por partida + ~40 por caixa; diamantes saem quase só
-- de caixas raras e descarte (0–1 por semana). Destaque ≈ 1–2 temporadas de moedas; Lenda ≈ várias temporadas.
insert into public.shop_sections (tier, label, description, slots, rotation_hours, per_user_limit, sort_order) values
  ('destaque', 'Destaques', 'Os destaques da temporada atual. A vitrine troca todo dia às 00:00 UTC.', 6, 24, 1, 1),
  ('lenda',    'Lendas',    'Ídolos de todos os tempos. Poucas por dia e caras: junte moedas ao longo da carreira.', 3, 24, 1, 2)
on conflict (tier) do nothing;   -- não sobrescreve ajustes feitos no painel

insert into public.shop_prices (tier, currency, base, top, round_to, min_price) values
  ('destaque', 'coins',     1500,  2300,  50, 1000),
  ('destaque', 'diamonds',    12,    16,   1,    8),
  ('lenda',    'coins',     9000, 21600, 100, 6000),
  ('lenda',    'diamonds',    60,   130,   1,   40)
on conflict (tier, currency) do nothing;

create table if not exists public.shop_purchases (
  id         uuid primary key default gen_random_uuid(),
  career_id  uuid not null references public.careers (id) on delete cascade,
  card_id    text not null references public.cards (id),
  currency   text not null check (currency in ('coins', 'diamonds')),
  price      int  not null check (price > 0),
  period_key text not null,                 -- rodízio da vitrine em que a compra aconteceu
  request_id uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists shop_purchases_career_idx on public.shop_purchases (career_id, period_key);

alter table public.wallet_ledger  enable row level security;
alter table public.econ_requests  enable row level security;
alter table public.shop_sections  enable row level security;
alter table public.shop_prices    enable row level security;
alter table public.shop_purchases enable row level security;
revoke all on public.wallet_ledger, public.econ_requests, public.shop_sections, public.shop_prices, public.shop_purchases
  from anon, authenticated;
grant select on public.wallet_ledger, public.shop_sections, public.shop_prices, public.shop_purchases to authenticated;
drop policy if exists "own_wallet_ledger" on public.wallet_ledger;
create policy "own_wallet_ledger" on public.wallet_ledger for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));
drop policy if exists "own_shop_purchases" on public.shop_purchases;
create policy "own_shop_purchases" on public.shop_purchases for select to authenticated
  using (exists (select 1 from public.careers c where c.id = career_id and c.user_id = auth.uid()));
drop policy if exists "read_shop_sections" on public.shop_sections;
create policy "read_shop_sections" on public.shop_sections for select to authenticated using (active);
drop policy if exists "read_shop_prices" on public.shop_prices;
create policy "read_shop_prices" on public.shop_prices for select to authenticated using (active);

-- ---------------------------------------------------------------------
-- E) LOJA — funções
-- ---------------------------------------------------------------------
-- Rodízio atual de uma seção: chave e fim (UTC)
create or replace function public.shop_period(p_hours int, p_at timestamptz default now())
returns table (period_key text, ends_at timestamptz) language sql stable as $$
  select (floor(extract(epoch from p_at) / (p_hours * 3600)))::bigint::text || 'h' || p_hours,
         to_timestamp(((floor(extract(epoch from p_at) / (p_hours * 3600)))::bigint + 1) * p_hours * 3600);
$$;

create or replace function public.shop_price(p_card public.cards, p_currency text)
returns int language sql stable set search_path = public as $$
  select greatest(p.min_price,
           (round((p.base + (p.top - p.base) * coalesce((p_card.overall - r.lo)::numeric / nullif(r.hi - r.lo, 0), 0))
                  / p.round_to) * p.round_to)::int)
    from public.shop_prices p
    cross join lateral (select min(c.overall) as lo, max(c.overall) as hi from public.cards c where c.tier = p_card.tier and c.active) r
   where p.tier = p_card.tier and p.currency = p_currency and p.active;
$$;

-- Vitrine (a mesma para todos os usuários no mesmo rodízio; sorteio determinístico pela chave do rodízio)
create or replace function public.shop_showcase_cards(p_tier text)
returns setof public.cards language sql stable security definer set search_path = public as $$
  select c.* from public.shop_sections s
    cross join lateral public.shop_period(s.rotation_hours) per
    join public.cards c on c.tier = s.tier and c.active
   where s.tier = p_tier and s.active
   order by md5(c.id || ':' || per.period_key), c.id
   limit (select slots from public.shop_sections where tier = p_tier);
$$;

create or replace function public.shop_catalog()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_car public.careers;
begin
  select * into v_car from public.careers where user_id = auth.uid() and status = 'active';
  if not found then raise exception 'Carreira ativa não encontrada'; end if;
  return jsonb_build_object(
    'wallet', jsonb_build_object('coins', v_car.coins, 'diamonds', v_car.diamonds, 'energy', v_car.energy, 'bonus_energy', v_car.bonus_energy),
    'sections', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tier', s.tier, 'label', s.label, 'description', s.description, 'per_user_limit', s.per_user_limit,
               'period_key', per.period_key, 'ends_at', per.ends_at,
               'items', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'card', jsonb_build_object('id', c.id, 'name', c.name, 'tier', c.tier, 'overall', c.overall, 'position', c.position,
                                                     'club_id', c.club_id, 'player_key', c.player_key, 'image', c.image, 'meta', c.meta),
                          'prices', jsonb_strip_nulls(jsonb_build_object('coins', public.shop_price(c, 'coins'), 'diamonds', public.shop_price(c, 'diamonds'))),
                          'owned', coalesce((select uc.qty from public.user_cards uc where uc.career_id = v_car.id and uc.card_id = c.id), 0),
                          'bought', (select count(*) from public.shop_purchases sp where sp.career_id = v_car.id and sp.card_id = c.id and sp.period_key = per.period_key),
                          'available', greatest(0, s.per_user_limit - (select count(*) from public.shop_purchases sp
                                                                       where sp.career_id = v_car.id and sp.card_id = c.id and sp.period_key = per.period_key)))
                        order by c.overall desc, c.id)
                   from public.shop_showcase_cards(s.tier) c), '[]'::jsonb))
             order by s.sort_order)
        from public.shop_sections s cross join lateral public.shop_period(s.rotation_hours) per
       where s.active), '[]'::jsonb),
    -- compra de diamantes com dinheiro real: ainda NÃO existe (sem provedor de pagamento configurado)
    'diamond_store', jsonb_build_object('available', false, 'label', 'EM BREVE'));
end;
$$;

-- Compra UMA carta da vitrine. p_request: identificador gerado pelo app ao abrir a confirmação (o mesmo em novas tentativas).
create or replace function public.shop_buy_card(p_card text, p_currency text, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_prev  jsonb;
  v_card  public.cards;
  v_sec   public.shop_sections;
  v_per   record;
  v_price int;
  v_n     int;
  v_bal   int;
  v_qty   int;
  v_pid   uuid := gen_random_uuid();
begin
  v_c := public.sim_lock_career();                                   -- trava a carreira: compras do mesmo usuário em fila
  v_prev := public.econ_request_get(v_c.id, p_request, 'shop_card');
  if v_prev is not null then return v_prev; end if;                  -- mesmo pedido: mesmo resultado, nada é cobrado de novo

  if p_currency not in ('coins', 'diamonds') then raise exception 'Moeda inválida.'; end if;
  select * into v_card from public.cards where id = p_card and active;
  if not found then raise exception 'Carta não encontrada.'; end if;
  select * into v_sec from public.shop_sections where tier = v_card.tier and active;
  if not found then raise exception 'Esta raridade não está à venda.'; end if;
  select * into v_per from public.shop_period(v_sec.rotation_hours);
  if not exists (select 1 from public.shop_showcase_cards(v_card.tier) s where s.id = v_card.id) then
    raise exception 'Esta carta não está mais na vitrine (a loja trocou). Atualize a loja.';
  end if;
  v_price := public.shop_price(v_card, p_currency);
  if v_price is null then raise exception 'Esta carta não está à venda nesta moeda.'; end if;

  select count(*) into v_n from public.shop_purchases where career_id = v_c.id and card_id = v_card.id and period_key = v_per.period_key;
  if v_n >= v_sec.per_user_limit then raise exception 'Você já comprou esta carta hoje. Volte no próximo rodízio da loja.'; end if;

  v_bal := public.econ_apply(v_c.id, p_currency, -v_price, 'shop_card', v_pid::text);   -- saldo insuficiente = erro, nada muda

  insert into public.shop_purchases (id, career_id, card_id, currency, price, period_key, request_id)
  values (v_pid, v_c.id, v_card.id, p_currency, v_price, v_per.period_key, p_request);
  insert into public.user_cards (career_id, card_id) values (v_c.id, v_card.id)
  on conflict (career_id, card_id) do update set qty = public.user_cards.qty + 1, last_obtained_at = now()
  returning qty into v_qty;

  return public.econ_request_save(v_c.id, p_request, 'shop_card', jsonb_build_object(
    'ok', true, 'purchase_id', v_pid, 'currency', p_currency, 'price', v_price, 'balance', v_bal,
    'card', jsonb_build_object('id', v_card.id, 'name', v_card.name, 'tier', v_card.tier, 'overall', v_card.overall,
                               'position', v_card.position, 'club_id', v_card.club_id, 'player_key', v_card.player_key,
                               'image', v_card.image, 'meta', v_card.meta),
    'qty', v_qty, 'new', v_qty = 1));
end;
$$;

-- ---------------------------------------------------------------------
-- F) PERMISSÕES
-- ---------------------------------------------------------------------
revoke all on function public.econ_tag(text, text), public.econ_ledger_trg(), public.econ_request_get(uuid, uuid, text),
  public.econ_request_save(uuid, uuid, text, jsonb), public.econ_apply(uuid, text, int, text, text),
  public.shop_showcase_cards(text), public.shop_price(public.cards, text), public.shop_period(int, timestamptz)
  from public, anon, authenticated;
revoke all on function public.shop_catalog(), public.shop_buy_card(text, text, uuid), public.wallet_history(int) from public, anon;
grant execute on function public.shop_catalog(), public.shop_buy_card(text, text, uuid), public.wallet_history(int) to authenticated;
