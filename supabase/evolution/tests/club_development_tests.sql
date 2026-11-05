-- Evolução 58 (desenvolvimento do clube). Banco descartável local; tudo é revertido no final.
do $$ begin if current_database() not like 'simulation_validation_%' then raise exception 'Disposable local database required';end if;end $$;
begin;
insert into auth.users(id,email) values('58580000-0000-0000-0000-000000000001','club-dev@example.test');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins,level,xp)
 values('58580000-0000-0000-0000-000000000011','58580000-0000-0000-0000-000000000001','ClubDevTest','sport','1',30,15000,3,250);
select set_config('request.jwt.claim.sub','58580000-0000-0000-0000-000000000001',true);
select public.career_runtime_initialize() is not null;
do $test$
#variable_conflict use_column
declare cid uuid:='58580000-0000-0000-0000-000000000011';d date:='2026-01-05';young text;old text;star text;loanee text;parent text;other text;
 r jsonb;req uuid;before_strength numeric;before_value bigint;v numeric;n int;fx bigint;st jsonb;lid uuid;cash0 bigint;lvl int;detail jsonb;
 base_list jsonb;patched jsonb;
begin
 update public.cw_world set today=d,needs_sync=false where career_id=cid;
 update public.cw_clubs set debt=0,financial_risk=0 where career_id=cid;
 perform public.mgr_lock();

 -- 1) Preservação: sem evolução registrada, as listas e notas são idênticas às anteriores.
 base_list:=public.cw_patch_players_before_v58(cid,(public.mgr_squad_before_v32('sport'))->'players',true);
 patched:=public.cw_patch_players(cid,(public.mgr_squad_before_v32('sport'))->'players',true);
 if (select count(*) from jsonb_array_elements(base_list) b join jsonb_array_elements(patched) p on p->>'id'=b->>'id'
     where (p->>'overall')::numeric is distinct from (b->>'overall')::numeric or p->'attrs' is distinct from b->'attrs')>0 then
  raise exception 'Lista do elenco mudou sem evolução registrada';
 end if;
 raise notice 'PASS preservação: elenco igual sem evolução';

 select mp.player_id into young from public.mgr_players mp join public.cw_players cp using(career_id,player_id)
  join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  join public.cw_world w on w.career_id=mp.career_id
  where mp.career_id=cid and mp.club_id='sport' and cp.age_at_start+floor((w.today-w.started_on)/365.25)<=22 and cp.potential>=pr.rating+6 and sp.position<>'GOL'
  order by mp.player_id limit 1;
 if young is null then
  select mp.player_id into young from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id where mp.career_id=cid and mp.club_id='sport' and sp.position<>'GOL' order by mp.player_id limit 1;
  update public.cw_players cp set age_at_start=19,potential=least(99,(select round(pr.rating)+12 from public.sim_player_pos_ratings pr join public.sim_players sp on sp.id=pr.player_id and pr.pos=sp.position where pr.player_id=young))
  where career_id=cid and player_id=young;
 end if;
 select mp.player_id into old from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id where mp.career_id=cid and mp.club_id='sport' and mp.player_id<>young and sp.position<>'GOL' order by mp.player_id desc limit 1;
 update public.cw_players set age_at_start=33 where career_id=cid and player_id=old;
 before_value:=public.cw_player_value(cid,young);

 -- 2) Evolução mensal: jovem cresce sem passar do potencial; veterano cai; mês repetido não soma de novo.
 for n in 1..6 loop perform public.cw_dev_month(cid,(date '2026-01-01'+make_interval(months=>n))::date);end loop;
 select d_rating into v from public.cw_player_dev where career_id=cid and player_id=young;
 if coalesce(v,0)<=0.5 then raise exception 'Jovem não evoluiu: %',v;end if;
 if public.cw_rating_now(cid,young)>(select potential from public.cw_players where career_id=cid and player_id=young)+0.01 then raise exception 'Passou do potencial';end if;
 if (select d_rating from public.cw_player_dev where career_id=cid and player_id=old)>=0 then raise exception 'Veterano não declinou';end if;
 if public.cw_player_value(cid,young)<=before_value then raise exception 'Valor de mercado ignorou a evolução';end if;
 perform public.cw_dev_month(cid,'2026-07-01');
 if (select d_rating from public.cw_player_dev where career_id=cid and player_id=young)<>v then raise exception 'Mês repetido alterou a evolução';end if;
 if (select count(*) from jsonb_object_keys((select pos from public.cw_player_dev where career_id=cid and player_id=young)))<>10 then raise exception 'Notas por posição não recalculadas';end if;
 if jsonb_array_length((select history from public.cw_player_dev where career_id=cid and player_id=young))<6 then raise exception 'Histórico mensal incompleto';end if;
 raise notice 'PASS evolução: jovem +%, veterano %, mês idempotente',round(v,2),(select round(d_rating,2) from public.cw_player_dev where career_id=cid and player_id=old);

 -- 3) Treino e aprendizado de posição
 r:=public.career_training_set('physical','hard');
 if (select focus from public.cw_training where career_id=cid and club_id='sport')<>'physical' then raise exception 'Treino não salvo';end if;
 r:=public.career_player_learn(young,case when (select position from public.sim_players where id=young)='ATA' then 'PD' else 'ATA' end);
 update public.cw_player_dev set learning_progress=95 where career_id=cid and player_id=young;
 perform public.cw_dev_month(cid,'2026-08-01');
 if cardinality((select learned from public.cw_player_dev where career_id=cid and player_id=young))<>1 then raise exception 'Posição não aprendida';end if;
 if not exists(select 1 from public.cw_player_dev d cross join unnest(d.learned) lp
   where d.career_id=cid and d.player_id=young and (d.pos->lp->>1)::numeric>0) then raise exception 'Posição aprendida sem ganho de adequação';end if;
 raise notice 'PASS treino e nova posição';

 -- 4) Instalações: diretoria aprova com caixa, recusa com motivo, obra demora e conclui.
 update public.cw_clubs set cash=500000,infrastructure=1000 where career_id=cid and club_id='sport';
 lvl:=public.cw_fac_level(cid,'sport','training');
 req:=gen_random_uuid();r:=public.career_facility_upgrade('training',req);
 if not (r->>'approved')::boolean then raise exception 'Obra recusada com caixa: %',r;end if;
 if (public.career_facility_upgrade('training',req)-'replayed')<>(r-'replayed') then raise exception 'Pedido repetido não devolveu o mesmo recibo';end if;
 if (select infrastructure from public.cw_clubs where career_id=cid and club_id='sport')<>0 then raise exception 'Fundo de infraestrutura não usado primeiro';end if;
 if public.cw_fac_level(cid,'sport','training')<>lvl then raise exception 'Nível subiu antes da obra terminar';end if;
 update public.cw_world set today=(select building_until from public.cw_facilities where career_id=cid and club_id='sport' and kind='training') where career_id=cid;
 perform public.cw_dev_daily(cid);
 if public.cw_fac_level(cid,'sport','training')<>lvl+1 then raise exception 'Obra não concluída';end if;
 update public.cw_world set today=d where career_id=cid;
 update public.cw_clubs set cash=10,financial_risk=0 where career_id=cid and club_id='sport';
 r:=public.career_facility_upgrade('stadium',gen_random_uuid());
 if (r->>'approved')::boolean or r->>'reason' not like '%Como melhorar%' then raise exception 'Recusa sem motivo/orientação: %',r;end if;
 raise notice 'PASS instalações: aprovação, recibo, prazo, recusa explicada';

 -- 5) Comissão técnica: contratação cobra salário mensal; nível original não custa nada.
 update public.cw_clubs set cash=900000 where career_id=cid and club_id='sport';
 lvl:=public.cw_staff_level(cid,'sport','scout');
 r:=public.career_staff_hire('scout',least(5,lvl+1),gen_random_uuid());
 if lvl<5 and not (r->>'approved')::boolean then raise exception 'Contratação recusada: %',r;end if;
 cash0:=(select cash from public.cw_clubs where career_id=cid and club_id='sport');
 perform public.cw_dev_month(cid,'2026-09-01');
 if lvl<5 and not exists(select 1 from public.cw_finance where career_id=cid and club_id='sport' and kind='staff' and reference='2026-09') then raise exception 'Salário da comissão não cobrado';end if;
 raise notice 'PASS comissão técnica';

 -- 6) Observação: atleta de outro clube aparece aproximado até o relatório ficar pronto.
 select mp.player_id,mp.club_id into other,parent from public.mgr_players mp where mp.career_id=cid and mp.club_id<>'sport' and mp.club_id is not null order by mp.player_id limit 1;
 detail:=public.mgr_player_detail(other);
 if not coalesce((detail->>'attrs_estimated')::boolean,false) then raise exception 'Atleta não observado mostrou atributos exatos';end if;
 r:=public.career_scout_request(other);
 update public.cw_world set today=(r->>'ready_on')::date where career_id=cid;
 detail:=public.mgr_player_detail(other);
 if detail ? 'attrs_estimated' then raise exception 'Relatório pronto não revelou atributos';end if;
 update public.cw_world set today=d where career_id=cid;
 raise notice 'PASS névoa e relatório do olheiro';

 -- 7) Empréstimo: clube cede reserva com salário pago; atleta volta ao fim; bloqueia outras negociações.
 update public.cw_clubs set cash=900000 where career_id=cid and club_id='sport';
 select x.player_id,x.club_id into loanee,parent from(select mp.player_id,mp.club_id,public.cw_squad_rank(cid,mp.club_id,mp.player_id) rk
   from public.mgr_players mp join public.cw_contracts ct on ct.career_id=mp.career_id and ct.player_id=mp.player_id and ct.club_id=mp.club_id and ct.status='active'
   where mp.career_id=cid and mp.club_id<>'sport' and mp.club_id in(select public.cw_domestic_clubs(cid))) x
  where x.rk>20 and public.cw_project_reason(cid,x.player_id,'sport') is null order by x.player_id limit 1;
 if loanee is null then raise exception 'Sem atleta para emprestar';end if;
 r:=public.career_loan_request(loanee,1,'starter',gen_random_uuid());
 if not (r->>'approved')::boolean then raise exception 'Empréstimo recusado: %',r;end if;
 lid:=(r->>'loan_id')::uuid;
 if (select club_id from public.mgr_players where career_id=cid and player_id=loanee)<>'sport' then raise exception 'Atleta não chegou';end if;
 if (select count(*) from public.cw_contracts where career_id=cid and player_id=loanee and status='active')<>1 then raise exception 'Dois contratos ativos';end if;
 if public.cw_project_reason(cid,loanee,'flamengo') not like '%emprestado%' then raise exception 'Atleta emprestado aceitou negociar';end if;
 update public.cw_world set today=(select ends_on from public.cw_loans where id=lid) where career_id=cid;
 perform public.cw_dev_daily(cid);
 if (select club_id from public.mgr_players where career_id=cid and player_id=loanee)<>parent then raise exception 'Atleta não voltou ao clube de origem';end if;
 if (select status from public.cw_loans where id=lid)<>'returned' then raise exception 'Empréstimo não encerrado';end if;
 update public.cw_world set today=d where career_id=cid;
 raise notice 'PASS empréstimo de ida e volta';

 -- 8) Veto da diretoria: principal atleta do elenco não é liberado.
 select mp.player_id into star from public.mgr_players mp where mp.career_id=cid and mp.club_id='sport' order by public.cw_squad_rank(cid,'sport',mp.player_id) limit 1;
 begin
  perform public.career_player_release(star,gen_random_uuid());
  raise exception 'Diretoria liberou o principal atleta';
 exception when others then if sqlerrm not like '%diretoria%' then raise;end if;end;
 raise notice 'PASS veto da diretoria';

 -- 9) Partida: cobrador escolhido, atributos evoluídos e motor com bola parada.
 update public.cw_player_dev set d='{"finishing":10}' where career_id=cid and player_id=young;
 r:=public.career_set_pieces_set(young,null,null);
 select f.id into fx from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
  where s.career_id=cid and f.status<>'played' and 'sport' in(f.home_club,f.away_club) and not exists(select 1 from public.mgr_matches m where m.fixture_id=f.id) order by f.id limit 1;
 if fx is not null then
  begin
   perform public.mgr_match_create(fx,cid,null,null);
   select state into st from public.mgr_matches where fixture_id=fx;
   if not coalesce((st->>'dev58')::boolean,false) then raise exception 'Partida sem preparação 58';end if;
   if exists(select 1 from public.mgr_match_players where fixture_id=fx and player_id=young)
    and (select c_fin from public.mgr_match_players where fixture_id=fx and player_id=young)
     <>(select least(99,a.finishing+10) from public.sim_player_attrs a where a.player_id=young) then raise exception 'Atributo evoluído não chegou ao motor';end if;
   raise exception using errcode='P5801',message='rollback match';
  exception when sqlstate 'P5801' then null;end;
 end if;
 if not exists(select 1 from pg_proc where proname='mgr_engine_run_v2' and prosrc like '%v_pentaker%') then raise exception 'Motor sem cobrador de pênalti';end if;
 raise notice 'PASS partida: atributos evoluídos e cobrador';

 -- 10) Base e aposentadoria no início da temporada brasileira.
 update public.cw_players set age_at_start=41 where career_id=cid and player_id=old;
 perform public.cw_dev_month(cid,'2027-01-01');
 if not exists(select 1 from public.sim_players p join public.mgr_players mp on mp.player_id=p.id and mp.career_id=cid
   where p.career_id=cid and mp.club_id='sport' and p.club_id is null) then raise exception 'Base não revelou jogador';end if;
 if not exists(select 1 from public.cw_contracts ct join public.sim_players p on p.id=ct.player_id where ct.career_id=cid and p.career_id=cid and ct.status='active' and ct.role='prospect') then raise exception 'Jovem sem contrato';end if;
 if (select retired_on from public.cw_players where career_id=cid and player_id=old) is null then raise exception 'Veterano de 41 anos não se aposentou';end if;
 if public.cw_ai_recovery_club(cid,old) is not null then raise exception 'Aposentado pode ser recontratado';end if;
 n:=(select count(*) from public.sim_players where career_id=cid);
 delete from public.cw_dev_months where career_id=cid and month='2027-01-01';
 perform public.cw_dev_month(cid,'2027-01-01');
 if (select count(*) from public.sim_players where career_id=cid)<>n then raise exception 'Ciclo anual da base repetido';end if;
 raise notice 'PASS base (jogador fictício marcado) e aposentadoria';

 -- 11) Dificuldade escolhida pelo treinador
 r:=public.career_difficulty_set('hard');
 if (public.mgr_difficulty(cid)).dev_mult<>0.85 then raise exception 'Dificuldade Difícil não aplicada';end if;
 begin perform public.career_difficulty_set('accessible');raise exception 'Aceitou dificuldade restrita';
 exception when others then if sqlerrm not like '%inválida%' then raise;end if;end;
 raise notice 'PASS dificuldade escolhida';

 if exists(select 1 from public.cw_dev_errors where career_id=cid) then raise exception 'Erros registrados: %',(select string_agg(stage||': '||message,' | ') from public.cw_dev_errors where career_id=cid);end if;
end $test$;
rollback;
