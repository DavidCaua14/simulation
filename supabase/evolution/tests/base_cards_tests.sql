begin;
do $test$
declare r record;c1 uuid:='31313131-0000-0000-0000-000000000011';c2 uuid:='31313131-0000-0000-0000-000000000022';pid text;v int;before_bonus int;before_coins int;fixture public.season_fixtures;won boolean;
begin
 if exists(select 1 from public._test_base_balances b left join public._test_base_expected e on e.career_id=b.id join public.careers c on c.id=b.id
  where row(c.coins,c.diamonds,c.bonus_energy,c.energy,c.xp) is distinct from row(b.coins+coalesce(e.coins,0),b.diamonds+coalesce(e.diamonds,0),b.bonus_energy+coalesce(e.energy,0),b.energy,b.xp)) then raise exception 'Compensação divergente ou saldo/progresso regravado';end if;
 if exists(select 1 from public._test_base_inventory b join public.cards c on c.id=b.card_id left join public.user_cards u using(career_id,card_id) where c.tier='basica' and to_jsonb(u) is distinct from to_jsonb(b)) then raise exception 'Inventário base alterado';end if;
 if exists(select 1 from public.user_cards u join public.cards c on c.id=u.card_id where c.tier<>'basica') then raise exception 'Carta especial restante';end if;
 if exists(select 1 from public.market_listings where status='active') or exists(select 1 from public.reward_boxes where status='pending') then raise exception 'Aquisição antiga restante';end if;
 if exists(select 1 from public.event_rewards where kind in('box','card')) or exists(select 1 from public.streak_rewards where box_tier is not null) then raise exception 'Recompensa indireta restante';end if;
 if exists(select 1 from public._test_base_protected b where b.name='season_fixtures' and b.row is distinct from(select to_jsonb(f) from public.season_fixtures f where f.id=b.id::bigint)) then raise exception 'Partida existente alterada';end if;
 if exists(select 1 from public._test_base_protected b where b.name='mgr_matches' and b.row is distinct from(select to_jsonb(m) from public.mgr_matches m where m.fixture_id=b.id::bigint)) then raise exception 'Partida em andamento alterada';end if;
 if exists(select 1 from public._test_base_protected b where b.name='mgr_players' and b.row is distinct from(select to_jsonb(m)-'club_id' from public.mgr_players m where m.career_id=split_part(b.id,':',1)::uuid and m.player_id=split_part(b.id,':',2))) then raise exception 'Condição/progresso dos atletas alterado';end if;
 select player_key into pid from public._test_base_choice;
 if (select club_id from public.mgr_players where career_id=c1 and player_id=pid)<>'flamengo' or
 (select club_id from public.mgr_players where career_id=c2 and player_id=pid)<>'arsenal' then raise exception 'Carta base não está no clube individual correto';end if;
 if (select club_id from public.sim_players where id=pid) in('flamengo','arsenal') then raise exception 'Catálogo global foi alterado';end if;
 if (select count(*) from public.base_card_roster where player_id=pid and career_id in(c1,c2))<>2 then raise exception 'Vínculo duplicado ou ausente';end if;
 if not exists(select 1 from public.player_profiles where career_id=c1 and avatar_data='data:image/jpeg;base64,AA==' and privacy='{"show_collection":false}' and featured_card is null) then raise exception 'Perfil/privacidade alterado';end if;
 for r in select p.oid::regprocedure as signature from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and(p.proname like 'shop\_%' escape '\' or p.proname like 'wheel\_%' escape '\' or p.proname like 'market\_%' escape '\' or p.proname in('box_open','card_claim_daily','card_grant_box','card_grant_source','profile_set_featured')) loop
  if has_function_privilege('authenticated',r.signature,'execute') or has_function_privilege('anon',r.signature,'execute') or has_function_privilege('service_role',r.signature,'execute') then raise exception 'RPC antiga acessível: %',r.signature;end if;
 end loop;
 begin
  insert into public.user_cards(career_id,card_id) select c1,id from public.cards where tier='lenda' limit 1;
  raise exception 'FAILED special inventory accepted';
 exception when others then if sqlerrm='FAILED special inventory accepted' then raise;end if;end;
 begin
  insert into public.reward_boxes(career_id,tier,source) values(c1,'basica','test');
  raise exception 'FAILED box accepted';
 exception when others then if sqlerrm='FAILED box accepted' then raise;end if;end;
 -- A new victory: coins + exactly one persistent energy, even on a repeated internal call.
 select * into fixture from public.season_fixtures where season_id in(select id from public.career_seasons where career_id=c1 and status='active')
  and (home_club='flamengo' or away_club='flamengo') and status='pending' order by id limit 1;
 select bonus_energy,coins into before_bonus,before_coins from public.careers where id=c1;
 update public.season_fixtures set home_goals=case when home_club='flamengo' then 2 else 0 end,away_goals=case when away_club='flamengo' then 2 else 0 end,
 status='played',played_at=now(),player_match=true,coach_club='flamengo' where id=fixture.id;
 perform public.base_award_match(fixture.id);perform public.base_award_match(fixture.id);
 if (select bonus_energy from public.careers where id=c1)<>before_bonus+1 or (select count(*) from public.base_match_rewards where fixture_id=fixture.id)<>1 then raise exception 'Prêmio de vitória duplicado ou ausente';end if;
 if (select coins from public.careers where id=c1)<>before_coins+(select coins from public.base_match_rewards where fixture_id=fixture.id) then raise exception 'Moedas duplicadas';end if;
 if (select bonus_energy from public.careers where id=c2)<>(select b.bonus_energy+coalesce(e.energy,0) from public._test_base_balances b left join public._test_base_expected e on e.career_id=b.id where b.id=c2) then raise exception 'Recompensa vazou para outra carreira';end if;
 -- Draw, defeat and penalty victory.
 for r in select f.* from public.season_fixtures f where f.season_id in(select id from public.career_seasons where career_id=c1 and status='active') and(f.home_club='flamengo' or f.away_club='flamengo') and f.status='pending' order by f.id limit 3 loop
  select bonus_energy into before_bonus from public.careers where id=c1;
  v:=coalesce(v,0)+1;
  update public.season_fixtures set home_goals=case when v=2 and home_club<>'flamengo' then 1 else 0 end,
   away_goals=case when v=2 and away_club<>'flamengo' then 1 else 0 end,
   home_pens=case when v=3 then case when home_club='flamengo' then 5 else 4 end end,
   away_pens=case when v=3 then case when away_club='flamengo' then 5 else 4 end end,
   status='played',played_at=now(),player_match=true,coach_club='flamengo' where id=r.id;
  if (select bonus_energy from public.careers where id=c1)<>(before_bonus+case when v=3 then 1 else 0 end) then raise exception 'Energia incorreta em empate/derrota/pênaltis';end if;
 end loop;
 if v<>3 then raise exception 'Casos de resultado incompletos';end if;
 -- Ownership follows a change of club without resetting athlete condition.
 update public.mgr_players set condition=47,rhythm=63 where career_id=c1 and player_id=pid;
 update public.mgr_coach set club_id='botafogo' where career_id=c1;
 perform public.mgr_sync_base_cards(c1);
 if not exists(select 1 from public.mgr_players where career_id=c1 and player_id=pid and club_id='botafogo' and condition=47 and rhythm=63) then raise exception 'Mudança de clube perdeu estado individual';end if;
 raise notice 'PASS cartas: compensação por raridade/quantidade, escrow, caixas, base, preservação, RPCs e prêmios idempotentes';
end $test$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"31313131-0000-0000-0000-000000000001","role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.cards where tier<>'basica') then raise exception 'Catálogo especial exposto';end if;
 if exists(select 1 from public.user_cards where career_id<>'31313131-0000-0000-0000-000000000011') then raise exception 'Inventário de outro usuário exposto';end if;
 if exists(select 1 from public.base_card_compensations where career_id<>'31313131-0000-0000-0000-000000000011') then raise exception 'Compensação de outro usuário exposta';end if;
 raise notice 'PASS RLS cartas e compensações';
end $$;
rollback;
