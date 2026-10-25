-- =====================================================================
-- EVOLUÇÃO 07 — PREÇO DA LOJA PELA FAIXA DE NOTAS DA RARIDADE
--
-- A PRIMEIRA versão da 06 (a aplicada em produção em 25/10/2026) calculava o preço a partir de uma nota fixa de referência. Só que o catálogo de cartas de cada banco é gerado
-- com os elencos do momento (em produção os Destaques têm nota 75–80; num banco novo, 86–90), então a nota fixa dava
-- preço mínimo para todo mundo. Agora o preço é relativo à raridade:
--   carta mais fraca da raridade = base · carta mais forte = top · as demais, proporcional à nota.
-- Funciona com qualquer catálogo. A 06 atual já nasce assim; esta migração só converte bancos com a 06 antiga.
-- Rode depois da 06. Idempotente (num banco novo não muda nada).
-- =====================================================================
alter table public.shop_prices add column if not exists top int;
update public.shop_prices set top = v.top, base = v.base
  from (values ('destaque', 'coins', 1500, 2300), ('destaque', 'diamonds', 12, 16),
               ('lenda', 'coins', 9000, 21600), ('lenda', 'diamonds', 60, 130)) v(tier, currency, base, top)
 where shop_prices.tier = v.tier and shop_prices.currency = v.currency and shop_prices.top is null;
update public.shop_prices set top = base where top is null;
alter table public.shop_prices alter column top set not null;
alter table public.shop_prices drop constraint if exists shop_prices_top_check;
alter table public.shop_prices add constraint shop_prices_top_check check (top >= base);
alter table public.shop_prices drop column if exists ref_overall;
alter table public.shop_prices drop column if exists per_point;

create or replace function public.shop_price(p_card public.cards, p_currency text)
returns int language sql stable set search_path = public as $$
  select greatest(p.min_price,
           (round((p.base + (p.top - p.base) * coalesce((p_card.overall - r.lo)::numeric / nullif(r.hi - r.lo, 0), 0))
                  / p.round_to) * p.round_to)::int)
    from public.shop_prices p
    cross join lateral (select min(c.overall) as lo, max(c.overall) as hi from public.cards c where c.tier = p_card.tier and c.active) r
   where p.tier = p_card.tier and p.currency = p_currency and p.active;
$$;
revoke all on function public.shop_price(public.cards, text) from public, anon, authenticated;
