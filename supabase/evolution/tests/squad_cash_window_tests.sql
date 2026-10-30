-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 39 (elenco, caixa, janela e banco menor). Transação com ROLLBACK.
begin;
select set_config('request.jwt.claim.sub','31313131-0000-0000-0000-000000000001',true);
select public.mgr_hub() is not null;
do $test$
#variable_conflict use_column
declare car uuid:='31313131-0000-0000-0000-000000000011';own text;r jsonb;listed int;d date;pid text;nid uuid;i int;fx bigint;
begin
 select club_id into own from public.mgr_coach where career_id=car;
 update public.cw_world set needs_sync=false where career_id=car;

 -- 1) contagem do elenco = atletas 21+ da lista exibida; limite 40
 r:=public.mgr_squad(null);
 select count(*) into listed from jsonb_array_elements(r->'players') e where coalesce((e->>'age')::int,99)>=21;
 if (r->'squad'->>'count')::int<>listed or (r->'squad'->>'limit')::int<>40 then raise exception 'Contagem %/% diferente da lista (%)',r->'squad'->>'count',r->'squad'->>'limit',listed;end if;
 raise notice 'PASS contagem do elenco igual à lista (%/40)',listed;

 -- 2) caixa do seu clube não vira patrimônio no fechamento do mês
 update public.cw_clubs set cash=initial_budget*20,debt=0 where career_id=car and club_id=own;
 select date_trunc('month',today)::date into d from public.cw_world where career_id=car;
 delete from public.cw_settled_months where career_id=car and month=d;
 perform public.cw_settle_month(car,d);
 if exists(select 1 from public.cw_finance where career_id=car and club_id=own and kind='infrastructure' and reference=to_char(d,'YYYY-MM')) then raise exception 'Caixa do seu clube foi recolhido';end if;
 raise notice 'PASS caixa do seu clube não vai para patrimônio';

 -- 3) atleta livre: acordo fora da janela só é registrado na abertura
 select today into d from public.cw_world where career_id=car;
 update public.cw_world set today=make_date(extract(year from d)::int,5,15) where career_id=car;
 select today into d from public.cw_world where career_id=car;
 if public.cw_window_open(public.cw_region(own),d) then raise exception 'Data de teste dentro da janela';end if;
 update public.mgr_players set club_id=null where career_id=car and player_id=(select player_id from public.mgr_players where career_id=car and club_id<>own and club_id is not null order by player_id limit 1) returning player_id into pid;
 update public.cw_contracts set status='ended',ended_on=d-1 where career_id=car and player_id=pid and status='active';
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,register_on,valuation,role)
 values(car,pid,null,own,'user','agreed',0,100,2,d,d,d+30,d,1000,'rotation') returning id into nid;
 if public.cw_register_transfer(nid) then raise exception 'Livre registrado fora da janela';end if;
 if (select register_on from public.cw_negotiations where id=nid)<>public.cw_next_window(public.cw_region(own),d) then raise exception 'Registro não ficou para a abertura da janela';end if;
 update public.cw_world set today=public.cw_next_window(public.cw_region(own),d) where career_id=car;
 if not public.cw_register_transfer(nid) or (select club_id from public.mgr_players where career_id=car and player_id=pid)<>own then raise exception 'Livre não registrado com a janela aberta';end if;
 raise notice 'PASS atleta livre só é registrado com a janela aberta';

 -- 4) no máximo 6 contratações por janela
 select today into d from public.cw_world where career_id=car;
 insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,created_on,reply_on,expires_on,register_on,valuation,role)
 select car,mp.player_id,mp.club_id,own,'user','completed',0,100,2,d,d,d,d,1000,'rotation' from public.mgr_players mp
 where mp.career_id=car and mp.club_id is not null and mp.club_id<>own and mp.player_id<>pid order by mp.player_id limit 5;
 begin perform public.career_transfer_bid((select player_id from public.mgr_players where career_id=car and club_id is not null and club_id<>own order by player_id desc limit 1),1000,1,0,false,gen_random_uuid());
  raise exception 'Passou do limite de contratações';
 exception when raise_exception then if sqlerrm not like 'Limite de 6 contratações por janela%' then raise;end if;end;
 raise notice 'PASS limite de 6 contratações por janela';

 -- 5) banco menor: partida antiga da IA sai, mas o relatório continua (placar e gols)
 select f.id into fx from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id
  where fd.career_id=car and f.status='pending' and own not in(f.home_club,f.away_club) order by fd.due_on limit 1;
 perform public.mgr_match_create(fx,car,null,null);
 update public.mgr_matches set status='finished',user_side=null where fixture_id=fx;
 update public.season_fixtures set home_goals=1,away_goals=0,status='played',played_at=now() where id=fx;
 update public.cw_fixture_dates set due_on=(select today from public.cw_world where career_id=car)-40 where fixture_id=fx;
 perform public.cw_prune_career(car);
 if exists(select 1 from public.mgr_matches where fixture_id=fx) then raise exception 'Partida antiga da IA não foi apagada';end if;
 r:=public.mgr_match_report(fx);
 if r->'score'->>0<>'1' then raise exception 'Relatório da partida antiga quebrou: %',r;end if;
 raise notice 'PASS partida antiga da IA apagada, relatório preservado';
end $test$;
rollback;
