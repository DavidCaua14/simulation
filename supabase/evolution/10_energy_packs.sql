-- =====================================================================
-- EVOLUÇÃO 10 — PACOTES DE ENERGIA (diamantes → energia bônus)
--
-- Energia do jogo (inalterada): `energy` volta a 10 a cada 5 h (sim_lock_career) e `bonus_energy` nunca é zerada.
-- Pacotes e a troca 1 💎 = 2 ⚡ (que já existia) creditam energia BÔNUS, até um limite configurável:
-- se a compra passaria do limite, ela é RECUSADA antes de cobrar (regra 'block', mostrada na tela antes da compra).
-- Cobrança e crédito na mesma transação, com idempotência e livro de transações.
-- Rode depois de evolution/09. Idempotente.
-- =====================================================================
create table if not exists public.energy_config (
  id            boolean primary key default true check (id),
  regular_max   int  not null default 10,                 -- informativo (a recarga é feita por sim_lock_career)
  regen_hours   int  not null default 5,                  -- informativo
  bonus_cap     int  not null check (bonus_cap between 1 and 100000),
  overflow_rule text not null default 'block' check (overflow_rule in ('block')),
  exchange_rate int  not null default 2 check (exchange_rate between 1 and 100)   -- troca avulsa: 1 diamante = N de energia
);
insert into public.energy_config (id, bonus_cap) values (true, 200) on conflict (id) do nothing;

create table if not exists public.energy_packs (
  id             text primary key,
  label          text not null,
  description    text not null,
  energy         int  not null check (energy > 0),
  price_diamonds int  not null check (price_diamonds > 0),
  sort_order     int  not null default 0,
  active         boolean not null default true
);
-- Mesma base da troca avulsa (1 💎 = 2 ⚡) com bônus progressivo nos pacotes maiores
insert into public.energy_packs (id, label, description, energy, price_diamonds, sort_order) values
  ('folego',        'Fôlego',        'Para mais algumas partidas hoje.',          10,  5, 1),
  ('treino_extra',  'Treino extra',  'Rende 10% a mais que a troca avulsa.',      22, 10, 2),
  ('pre_temporada', 'Pré-temporada', 'Rende 25% a mais que a troca avulsa.',      50, 20, 3)
on conflict (id) do nothing;

alter table public.energy_config enable row level security;
alter table public.energy_packs  enable row level security;
revoke all on public.energy_config, public.energy_packs from anon, authenticated;
grant select on public.energy_config, public.energy_packs to authenticated;
drop policy if exists "read_energy_config" on public.energy_config;
create policy "read_energy_config" on public.energy_config for select to authenticated using (true);
drop policy if exists "read_energy_packs" on public.energy_packs;
create policy "read_energy_packs" on public.energy_packs for select to authenticated using (active);

create or replace function public.energy_catalog()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers; v_cfg public.energy_config;
begin
  v_c := public.sim_lock_career();        -- aplica a recarga das 5 h antes de mostrar
  select * into v_cfg from public.energy_config;
  return jsonb_build_object(
    'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy, 'diamonds', v_c.diamonds,
    'regular_max', v_cfg.regular_max, 'regen_hours', v_cfg.regen_hours, 'next_reset_at', v_c.energy_reset_at + make_interval(hours => v_cfg.regen_hours),
    'bonus_cap', v_cfg.bonus_cap, 'overflow_rule', v_cfg.overflow_rule, 'exchange_rate', v_cfg.exchange_rate,
    'packs', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'label', p.label, 'description', p.description,
                                                            'energy', p.energy, 'price', p.price_diamonds,
                                                            'fits', v_c.bonus_energy + p.energy <= v_cfg.bonus_cap) order by p.sort_order)
                         from public.energy_packs p where p.active), '[]'::jsonb));
end;
$$;

create or replace function public.energy_buy(p_pack text, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c    public.careers;
  v_prev jsonb;
  v_cfg  public.energy_config;
  v_p    public.energy_packs;
  v_dia  int;
  v_bon  int;
  v_ref  text := gen_random_uuid()::text;
begin
  v_c := public.sim_lock_career();
  v_prev := public.econ_request_get(v_c.id, p_request, 'energy_pack');
  if v_prev is not null then return v_prev; end if;
  select * into v_cfg from public.energy_config;
  select * into v_p from public.energy_packs where id = p_pack and active;
  if not found then raise exception 'Pacote de energia não encontrado.'; end if;
  if v_c.bonus_energy + v_p.energy > v_cfg.bonus_cap then
    raise exception '%', format('Este pacote passaria do limite de energia bônus (%s). Você tem %s; use um pouco antes de comprar.',
                                v_cfg.bonus_cap, v_c.bonus_energy);
  end if;
  v_dia := public.econ_apply(v_c.id, 'diamonds', -v_p.price_diamonds, 'energy_pack', v_ref);   -- sem diamantes: erro, nada muda
  v_bon := public.econ_apply(v_c.id, 'bonus_energy', v_p.energy, 'energy_pack', v_ref);
  return public.econ_request_save(v_c.id, p_request, 'energy_pack', jsonb_build_object(
    'ok', true, 'pack', v_p.id, 'label', v_p.label, 'energy_added', v_p.energy, 'price', v_p.price_diamonds,
    'diamonds', v_dia, 'bonus_energy', v_bon, 'energy', v_c.energy));
end;
$$;

-- A troca avulsa que já existia (Cartas → trocar diamantes) passa a respeitar o mesmo limite e a entrar no livro.
create or replace function public.diamonds_exchange_energy(p_diamonds int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c   public.careers;
  v_cfg public.energy_config;
  v_ref text := gen_random_uuid()::text;
begin
  v_c := public.sim_lock_career();
  select * into v_cfg from public.energy_config;
  if p_diamonds is null or p_diamonds < 1 or p_diamonds > 1000 then raise exception 'Quantidade inválida.'; end if;
  if v_c.diamonds < p_diamonds then raise exception 'Diamantes insuficientes.'; end if;
  if v_c.bonus_energy + p_diamonds * v_cfg.exchange_rate > v_cfg.bonus_cap then
    raise exception '%', format('Passaria do limite de energia bônus (%s). Você tem %s.', v_cfg.bonus_cap, v_c.bonus_energy);
  end if;
  perform public.econ_apply(v_c.id, 'diamonds', -p_diamonds, 'energy_exchange', v_ref);
  perform public.econ_apply(v_c.id, 'bonus_energy', p_diamonds * v_cfg.exchange_rate, 'energy_exchange', v_ref);
  return jsonb_build_object('diamonds_spent', p_diamonds, 'energy_gained', p_diamonds * v_cfg.exchange_rate);
end;
$$;

revoke all on function public.energy_catalog(), public.energy_buy(text, uuid), public.diamonds_exchange_energy(int) from public, anon;
grant execute on function public.energy_catalog(), public.energy_buy(text, uuid), public.diamonds_exchange_energy(int) to authenticated;
