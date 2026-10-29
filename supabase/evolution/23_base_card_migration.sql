-- Conversão e encerramento dos mecanismos antigos. Somente após backup e prévia.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';

create or replace function public.base_reward_value(p_tier text,p_box boolean)
returns table(coins int,diamonds int,energy int) language sql stable security definer set search_path=public as $$
 select case when p_box then t.discard_coins+t.box_coins_max else r.coins end,
        case when p_box then t.discard_diamonds+t.box_diamonds_max else r.diamonds end,
        case when p_box then t.box_energy_max else r.energy end
 from public.base_card_conversion_rates r join public.card_tiers t on t.id=r.tier where r.tier=p_tier
$$;
create or replace function public.base_compensate(p_career uuid,p_kind text,p_source text,p_tier text,p_qty int)
returns boolean language plpgsql security definer set search_path=public as $$
declare v record;paid public.base_card_compensations;
begin
 if p_qty<1 then return false;end if;
 perform 1 from public.careers where id=p_career for update;
 select * into v from public.base_reward_value(p_tier,p_kind='box');
 if not found then raise exception 'Raridade sem regra de conversão';end if;
 insert into public.base_card_compensations(career_id,source_kind,source_id,tier,qty,coins,diamonds,energy)
 values(p_career,p_kind,p_source,p_tier,p_qty,v.coins*p_qty,v.diamonds*p_qty,v.energy*p_qty)
 on conflict do nothing returning * into paid;
 if paid.career_id is null then return false;end if;
 if paid.coins>0 then perform public.econ_apply(p_career,'coins',paid.coins,'base_cards_compensation',p_kind||':'||p_source);end if;
 if paid.diamonds>0 then perform public.econ_apply(p_career,'diamonds',paid.diamonds,'base_cards_compensation',p_kind||':'||p_source);end if;
 if paid.energy>0 then perform public.econ_apply(p_career,'bonus_energy',paid.energy,'base_cards_compensation',p_kind||':'||p_source);end if;
 return true;
end $$;
revoke all on function public.base_reward_value(text,boolean),public.base_compensate(uuid,text,text,text,int) from public,anon,authenticated,service_role;

-- No progress events may be fabricated by this administrative conversion.
drop trigger if exists event_on_box on public.reward_boxes;
drop trigger if exists event_on_new_card on public.user_cards;
drop trigger if exists event_on_market_sale on public.market_listings;
drop trigger if exists profile_featured_guard on public.user_cards;

-- Original marketplace escrow is an owned copy, even when its advertisement expired by time.
do $$ declare listing public.market_listings;begin
 for listing in select * from public.market_listings where status='active' order by seller_career,id for update loop
  insert into public.user_cards(career_id,card_id,qty) values(listing.seller_career,listing.card_id,1)
   on conflict(career_id,card_id) do update set qty=public.user_cards.qty+1;
  update public.market_listings set status='cancelled',closed_at=now() where id=listing.id;
  insert into public.market_events(listing_id,event,actor,data) values(listing.id,'cancelled',listing.seller_career,'{"reason":"base_cards_migration"}');
 end loop;
end $$;

-- Refuse approximate name matches: no owned base card may be lost.
do $$ begin
 if exists(select 1 from public.user_cards u join public.cards c on c.id=u.card_id left join public.base_card_players p on p.card_id=c.id
 where u.qty>0 and c.tier='basica' and p.card_id is null) then raise exception 'Carta base possuída sem jogador correspondente; revisar mapeamento';end if;
 if exists(select 1 from (values('basica',15,0,0),('destaque',2300,16,2),('lenda',21600,130,4),('epica',43200,260,6)) x(t,c,d,e)
  left join public.base_card_conversion_rates r on r.tier=x.t where row(r.coins,r.diamonds,r.energy) is distinct from row(x.c,x.d,x.e)) then
  raise exception 'Tabela de conversão diverge da versão revisada';end if;
end $$;

do $$ declare r record;begin
 for r in select u.career_id,u.card_id,u.qty,c.tier from public.user_cards u join public.cards c on c.id=u.card_id
   where c.tier<>'basica' and u.qty>0 order by u.career_id,u.card_id loop
  perform public.base_compensate(r.career_id,'card',r.card_id,r.tier,r.qty);
 end loop;
end $$;
delete from public.user_cards u using public.cards c where c.id=u.card_id and c.tier<>'basica';

alter table public.reward_boxes drop constraint if exists reward_boxes_status_check;
alter table public.reward_boxes add constraint reward_boxes_status_check check(status in('pending','opened','retired'));
do $$ declare box public.reward_boxes;begin
 for box in select * from public.reward_boxes where status='pending' order by career_id,id for update loop
  perform public.base_compensate(box.career_id,'box',box.id::text,box.tier,1);
  update public.reward_boxes set status='retired',prize=jsonb_build_object('converted',true,'version',1),opened_at=null where id=box.id;
 end loop;
end $$;

-- Convert future event benefits; claimed history is never credited again.
do $$ declare r public.event_rewards;v record;tier text;inserted uuid;begin
 for r in select * from public.event_rewards where kind in('box','card') order by id for update loop
  insert into public.base_event_reward_migrations(reward_id,original) values(r.id,to_jsonb(r)) on conflict do nothing returning reward_id into inserted;
  if inserted is null then continue;end if;
  tier:=case when r.kind='box' then r.ref else(select c.tier from public.cards c where c.id=r.ref) end;
  select * into v from public.base_reward_value(tier,r.kind='box');
  if not found then raise exception 'Recompensa antiga sem regra de conversão';end if;
  update public.event_rewards set kind='coins',amount=v.coins*r.amount,ref=null where id=r.id;
  if v.diamonds>0 then insert into public.event_rewards(event_id,kind,amount,sort_order) values(r.event_id,'diamonds',v.diamonds*r.amount,r.sort_order);end if;
  if v.energy>0 then insert into public.event_rewards(event_id,kind,amount,sort_order) values(r.event_id,'energy',v.energy*r.amount,r.sort_order);end if;
 end loop;
end $$;
alter table public.event_rewards drop constraint if exists event_rewards_kind_check;
alter table public.event_rewards add constraint event_rewards_kind_check check(kind in('coins','diamonds','energy','cosmetic','badge'));

-- Pay already completed, still claimable retired challenges before closing them.
do $$ declare c public.event_completions;w public.event_rewards;v_rewards jsonb;begin
 for c in select ec.* from public.event_completions ec join public.events e on e.id=ec.event_id
 where ec.claimed_at is null and ec.claim_until>now() and e.status<>'cancelled'
 and exists(select 1 from public.event_objectives o where o.event_id=e.id and o.kind in('box_opened','card_collected','market_sale'))
 order by ec.career_id,ec.id for update of ec loop
  v_rewards:='[]';
  for w in select * from public.event_rewards where event_id=c.event_id order by sort_order,id loop
   v_rewards:=v_rewards||public.event_grant(c.career_id,w,c.id::text);
  end loop;
  update public.event_completions set claimed_at=now(),rewards=v_rewards where id=c.id;
 end loop;
end $$;
update public.events e set status='cancelled' where status<>'cancelled' and exists
 (select 1 from public.event_objectives o where o.event_id=e.id and o.kind in('box_opened','card_collected','market_sale'));

do $$ declare r public.streak_rewards;v record;begin
 for r in select * from public.streak_rewards where box_tier is not null for update loop
  select * into v from public.base_reward_value(r.box_tier,true);
  update public.streak_rewards set coins=coins+v.coins,diamonds=diamonds+v.diamonds,energy=energy+v.energy,box_tier=null where day=r.day;
 end loop;
end $$;

update public.cards set active=false where tier<>'basica' and active;
update public.box_sources set draws=0,guaranteed='{}',weights='{}';
update public.shop_sections set active=false where active;
update public.shop_prices set active=false where active;
update public.wheel_config set active=false where active;
update public.market_config set active=false where active;
update public.player_profiles set featured_card=null where featured_card is not null;
alter table public.player_profiles drop constraint if exists profile_no_featured_card;
alter table public.player_profiles add constraint profile_no_featured_card check(featured_card is null);
update public.badges set active=false where kind in('collection','own_epica','market_sales') and active;

-- Positive base inventory quantities and all individual athlete state are retained.
do $$ declare c record;begin
 for c in select id from public.careers where exists(select 1 from public.mgr_coach m where m.career_id=careers.id) order by id loop
  perform public.mgr_sync_base_cards(c.id);
 end loop;
end $$;

create or replace function public.base_inventory_guard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.cards where id=new.card_id and tier='basica') then raise exception 'Somente cartas base são permitidas';end if;
 return new;
end $$;
create or replace function public.base_boxes_disabled()
returns trigger language plpgsql security definer set search_path=public as $$
begin raise exception 'Caixas de cartas foram removidas';end $$;
drop trigger if exists base_inventory_guard on public.user_cards;
create trigger base_inventory_guard before insert or update on public.user_cards for each row execute function public.base_inventory_guard();
drop trigger if exists base_boxes_disabled on public.reward_boxes;
create trigger base_boxes_disabled before insert on public.reward_boxes for each row execute function public.base_boxes_disabled();
revoke all on function public.base_inventory_guard(),public.base_boxes_disabled() from public,anon,authenticated,service_role;

grant select on public.user_cards,public.card_tiers to authenticated;
drop policy if exists read_cards on public.cards;
create policy read_cards on public.cards for select to authenticated using(tier='basica');
drop policy if exists read_card_tiers on public.card_tiers;
create policy read_card_tiers on public.card_tiers for select to authenticated using(id='basica');
revoke all on public.reward_boxes,public.box_sources,public.career_card_state,
 public.shop_sections,public.shop_prices,public.shop_purchases,public.wheel_config,public.wheel_segments,public.wheel_state,public.wheel_spins,
 public.market_config,public.market_price_limits,public.market_listings,public.market_events from anon,authenticated;

-- Consistent wallet labels; historical transactions and their references stay intact.
insert into public.econ_reason_map(fn,reason,label) values
 ('base_compensate','base_cards_compensation','Conversão de cartas especiais'),('base_award_match','match_reward','Prêmio de partida')
on conflict(fn) do update set reason=excluded.reason,label=excluded.label;
notify pgrst,'reload schema';
commit;
