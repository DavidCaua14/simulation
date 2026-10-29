-- Fictitious data only, disposable local PostgreSQL.
insert into auth.users(id,email) values
 ('31313131-0000-0000-0000-000000000001','base-one@example.test'),
 ('31313131-0000-0000-0000-000000000002','base-two@example.test');
insert into public.careers(id,user_id,nickname,club_id,coins,diamonds,energy,bonus_energy,energy_reset_at,xp) values
 ('31313131-0000-0000-0000-000000000011','31313131-0000-0000-0000-000000000001','BaseOne','flamengo',1234,17,8,3,now(),234),
 ('31313131-0000-0000-0000-000000000022','31313131-0000-0000-0000-000000000002','BaseTwo','arsenal',4321,31,6,5,now(),432);
select public.mgr_ensure(c) from public.careers c where id in('31313131-0000-0000-0000-000000000011','31313131-0000-0000-0000-000000000022');
select public.profile_ensure('31313131-0000-0000-0000-000000000011');
select public.profile_ensure('31313131-0000-0000-0000-000000000022');
create table public._test_base_choice as select c.id,c.player_key from public.cards c join public.sim_players p on p.id=c.player_key
 where c.tier='basica' and p.club_id not in('flamengo','arsenal') order by c.id limit 1;
insert into public.user_cards(career_id,card_id,qty)
 select careers.id,c.id,case when careers.id='31313131-0000-0000-0000-000000000011' then 3 else 1 end
 from public.careers cross join public._test_base_choice c where careers.id in('31313131-0000-0000-0000-000000000011','31313131-0000-0000-0000-000000000022');
insert into public.user_cards(career_id,card_id,qty)
 select '31313131-0000-0000-0000-000000000011',c.id,x.qty from(values('destaque',2),('lenda',3),('epica',4)) x(tier,qty)
 cross join lateral(select id from public.cards where tier=x.tier and active order by id limit 1) c;
insert into public.user_cards(career_id,card_id,qty)
 select '31313131-0000-0000-0000-000000000022',id,1 from public.cards where tier='destaque' order by id limit 1;
-- An escrow copy is not in inventory; it must still be compensated exactly once.
insert into public.market_listings(seller_career,card_id,price,fee_pct,expires_at)
 select '31313131-0000-0000-0000-000000000011',id,1000,5,now()+interval '2days' from public.cards where tier='destaque' order by id limit 1;
insert into public.reward_boxes(career_id,tier,source,ref)
 select '31313131-0000-0000-0000-000000000011',id,'test_pending',id from public.card_tiers;
update public.player_profiles set featured_card=(select id from public.cards where tier='destaque' order by id limit 1),
 avatar_data='data:image/jpeg;base64,AA==',privacy='{"show_collection":false}' where career_id='31313131-0000-0000-0000-000000000011';

create table public._test_base_balances as select id,coins,diamonds,energy,bonus_energy,xp from public.careers;
create table public._test_base_inventory as select * from public.user_cards;
create table public._test_base_expected as
 with owned as (
 select u.career_id,c.tier,u.qty from public.user_cards u join public.cards c on c.id=u.card_id where c.tier<>'basica'
 union all select l.seller_career,c.tier,1 from public.market_listings l join public.cards c on c.id=l.card_id where l.status='active' and c.tier<>'basica'),
 rates(tier,coins,diamonds,energy) as(values('destaque',2300,16,2),('lenda',21600,130,4),('epica',43200,260,6)),
 amounts as(
 select o.career_id,o.qty*r.coins as coins,o.qty*r.diamonds as diamonds,o.qty*r.energy as energy from owned o join rates r using(tier)
 union all select b.career_id,t.box_coins_max+t.discard_coins,t.box_diamonds_max+t.discard_diamonds,t.box_energy_max
 from public.reward_boxes b join public.card_tiers t on t.id=b.tier where b.status='pending')
 select career_id,sum(coins)::int as coins,sum(diamonds)::int as diamonds,sum(energy)::int as energy from amounts group by career_id;
create table public._test_base_protected as
 select 'season_fixtures'::text as name,id::text,to_jsonb(t) as row from public.season_fixtures t
 union all select 'mgr_matches',fixture_id::text,to_jsonb(t) from public.mgr_matches t
 union all select 'mgr_match_players',fixture_id::text||':'||player_id,to_jsonb(t) from public.mgr_match_players t
 union all select 'mgr_players',career_id::text||':'||player_id,to_jsonb(t)-'club_id' from public.mgr_players t;
