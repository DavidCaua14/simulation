-- All actions are against fictitious careers and rolled back.
begin;
select set_config('request.jwt.claims','{"sub":"31313131-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
do $test$
declare c uuid:='31313131-0000-0000-0000-000000000011';p jsonb;again jsonb;h jsonb;summary jsonb;energy_before int;coins_before int;xp_before int;count_before int;pid text;lineup public.mgr_lineups;slot text;ev uuid;completion uuid;claim jsonb;r public.event_rewards;
begin
 h:=public.mgr_hub();
 select player_key into pid from public._test_base_choice;
 if public.mgr_player_detail(pid)->>'id' is distinct from pid then raise exception 'Ficha base incorreta';end if;
 begin
  perform public.mgr_player_detail(pid,(select min(f.id) from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id where cs.career_id<>c));
  raise exception 'FAILED foreign player detail accepted';
 exception when others then if sqlerrm<>'Jogador ou partida fora desta carreira' then raise;end if;end;
 perform public.mgr_lineup_auto(null);
 select * into lineup from public.mgr_lineups where career_id=c and club_id='flamengo';
 select key into slot from jsonb_each_text(lineup.slots) limit 1;
 lineup.slots:=jsonb_set(lineup.slots,array[slot],to_jsonb(pid));
 lineup.bench:=array_remove(lineup.bench,pid);
 perform public.mgr_lineup_save(lineup.formation,lineup.slots,to_jsonb(lineup.bench),lineup.tactics);
 if not exists(select 1 from public.mgr_lineups where career_id=c and slots->>slot=pid) then raise exception 'Carta base importada não pôde ser escalada';end if;
 select coins,bonus_energy,xp into coins_before,energy_before,xp_before from public.careers where id=c;
 p:=public.mgr_match_start();
 if (p->>'engine_version')::int<>2 then raise exception 'Partida nova não usou motor v2';end if;
 for attempt in 1..12 loop
  p:=public.mgr_match_step((p->>'fixture_id')::bigint,(p->>'minute')::int,120,null,true,0);
  exit when p->>'status'='finished';
 end loop;
 if p->>'status'<>'finished' then raise exception 'Partida não terminou';end if;
 summary:=p->'summary';
 if (summary->'rewards'->>'xp')::int<>0 then raise exception 'Partida concedeu XP';end if;
 if not exists(select 1 from public.base_match_rewards where fixture_id=(p->>'fixture_id')::bigint and coins=(summary->'rewards'->>'coins')::int and energy=(summary->'rewards'->>'energy')::int) then raise exception 'Resumo diverge do pagamento';end if;
 if exists(select 1 from public.reward_boxes where status='pending') then raise exception 'Partida gerou caixa';end if;
 select coins,bonus_energy into coins_before,energy_before from public.careers where id=c;
 again:=public.mgr_match_step((p->>'fixture_id')::bigint,(p->>'minute')::int,120,null,true,0);
 if (select coins from public.careers where id=c)<>coins_before or(select bonus_energy from public.careers where id=c)<>energy_before then raise exception 'Repetir finalização duplicou prêmio';end if;
 -- Resource-only events keep idempotent claims and reject obsolete reward kinds.
 insert into public.events(slug,name,description,category,status,starts_at,ends_at) values('base-test-claim','Teste base','Teste','daily','published',now()-interval '1hour',now()+interval '1hour') returning id into ev;
 insert into public.event_rewards(event_id,kind,amount) values(ev,'coins',77),(ev,'energy',2);
 insert into public.event_completions(event_id,career_id,period_key,claim_until) values(ev,c,'test',now()+interval '1hour') returning id into completion;
 select coins,bonus_energy into coins_before,energy_before from public.careers where id=c;
 claim:=public.event_claim(completion);again:=public.event_claim(completion);
 if not(again->>'replayed')::boolean or(select coins from public.careers where id=c)<>coins_before+77 or(select bonus_energy from public.careers where id=c)<>energy_before+2 then raise exception 'Evento duplicou ou perdeu recompensa';end if;
 begin
  insert into public.event_rewards(event_id,kind,amount,ref) values(ev,'box',1,'basica');
  raise exception 'FAILED event accepted box';
 exception when check_violation then null;end;
 -- Streak has no boxes, preserves its resources and does not pay twice.
 select coins,bonus_energy into coins_before,energy_before from public.careers where id=c;
 claim:=public.streak_claim();again:=public.streak_claim();
 if not(again->>'replayed')::boolean then raise exception 'Sequência não é idempotente';end if;
 if (select coins from public.careers where id=c)<>coins_before+(claim->>'coins')::int or(select bonus_energy from public.careers where id=c)<>energy_before+(claim->>'energy')::int then raise exception 'Sequência perdeu ou duplicou recursos';end if;
 raise notice 'PASS fluxo integrado: carta base escalada, partida v2 concluída/repetida, eventos e sequência sem caixas';
end $test$;
rollback;
