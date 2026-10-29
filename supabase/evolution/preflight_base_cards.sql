-- Read only; run before 21–23. No personal data in this report.
with held as(
 select u.career_id,c.tier,u.qty from public.user_cards u join public.cards c on c.id=u.card_id where u.qty>0 and c.tier<>'basica'
 union all select l.seller_career,c.tier,1 from public.market_listings l join public.cards c on c.id=l.card_id where l.status='active' and c.tier<>'basica'
),rates(tier,coins,diamonds,energy) as(values('destaque',2300,16,2),('lenda',21600,130,4),('epica',43200,260,6)),
 amounts as(
 select h.career_id,h.qty*r.coins as coins,h.qty*r.diamonds as diamonds,h.qty*r.energy as energy from held h join rates r using(tier)
 union all select b.career_id,t.box_coins_max+t.discard_coins,t.box_diamonds_max+t.discard_diamonds,t.box_energy_max
 from public.reward_boxes b join public.card_tiers t on t.id=b.tier where b.status='pending'
)
select jsonb_build_object(
 'unmapped_owned_base',(select count(*) from public.user_cards u join public.cards c on c.id=u.card_id left join public.sim_players p on p.id=c.player_key where u.qty>0 and c.tier='basica' and p.id is null),
 'unsupported_owned_tier',(select count(*) from held where tier not in('destaque','lenda','epica')),
 'owned_base_quantity',(select coalesce(sum(u.qty),0) from public.user_cards u join public.cards c on c.id=u.card_id where c.tier='basica'),
 'special_quantity_including_escrow',(select coalesce(sum(qty),0) from held),
 'special_by_tier',(select jsonb_object_agg(tier,n) from(select tier,sum(qty) n from held group by tier) x),
 'pending_boxes',(select count(*) from public.reward_boxes where status='pending'),
 'active_listings',(select count(*) from public.market_listings where status='active'),
 'affected_careers',(select count(distinct career_id) from amounts),
 'coins_to_credit',(select coalesce(sum(coins),0) from amounts),
 'diamonds_to_credit',(select coalesce(sum(diamonds),0) from amounts),
 'bonus_energy_to_credit',(select coalesce(sum(energy),0) from amounts)
) as preview;
