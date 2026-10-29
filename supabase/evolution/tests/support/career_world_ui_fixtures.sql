begin;
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111');
insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','Coach UI','palmeiras','BR',30,10);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
create temp table world_ui as select public.mgr_hub() as hub;
select public.cw_news_add('22222222-2222-4222-8222-222222222222','ui:signing','transfer','Contratação internacional anunciada','Atleta apresentado para os testes da interface.',98,'palmeiras',
 (select id from public.sim_players where club_id='palmeiras' order by id limit 1),null,
 (select jsonb_build_object('big_signing',true,'fee',180000,'from_club','arsenal','to_club','palmeiras','overall',round(r.rating),'position',p.position) from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.club_id='palmeiras' order by p.id limit 1));
insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,valuation,created_on,reply_on,expires_on,response)
 select '22222222-2222-4222-8222-222222222222',id,'arsenal','palmeiras','user','player_counter',80000,70000,'2026-01-01','2026-01-01','2026-01-08','Clube aprovou. Apresente o contrato ao atleta.' from public.sim_players where club_id='arsenal' order by id limit 1;
select jsonb_build_object('worldHub',(select hub from world_ui),'worldMarket',public.career_player_search(),'worldContracts',public.career_player_search('','','','mine'),'worldNews',public.career_news(),'worldFinance',public.career_finance_history(),'worldDeals',public.career_negotiations());
rollback;
