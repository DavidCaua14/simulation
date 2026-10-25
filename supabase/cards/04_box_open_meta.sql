-- Cartas automáticas: a caixa aberta passa a devolver também player_key e meta (número, clube, país)
-- para o app desenhar a carta. Rode depois de 01_cards.sql (já incluído nele para instalações novas).
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
