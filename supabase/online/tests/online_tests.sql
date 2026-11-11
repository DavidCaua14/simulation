-- Testes do modo online (Fase 1). Rodar só em banco descartável: scripts/test-online-db.mjs.
-- Cada bloco levanta exceção se a regra falhar.

insert into public.careers(user_id,nickname) values
 ('00000000-0000-0000-0000-000000000001','Edson'),('00000000-0000-0000-0000-000000000002','Jeff'),
 ('00000000-0000-0000-0000-000000000003','brunomartins'),('00000000-0000-0000-0000-000000000004','davidcaua'),
 ('00000000-0000-0000-0000-000000000005','Dennis'),('00000000-0000-0000-0000-000000000009','novato');

select public.on_season_bootstrap(array['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000005']::uuid[],
 date '2026-11-16');

do $$
declare n int;m int;
begin
 -- clubes e elencos
 select count(*),count(user_id) into n,m from public.on_clubs;
 if n<>12 or m<>5 then raise exception 'clubes: % (% humanos)',n,m;end if;
 if exists(select 1 from public.on_clubs c where (select count(*) from public.on_players p where p.club_id=c.id)<>case when c.user_id is null then 22 else 19 end) then
  raise exception 'tamanho de elenco errado';
 end if;
 if exists(select 1 from public.on_players where level not between 54 and 82 or pot<level or ovr<>level) then raise exception 'nível fora da faixa';end if;
 if (select count(*) from public.on_lineups)<>7 then raise exception 'bots sem escalação';end if;
 if exists(select 1 from public.on_lineups l where (select count(*) from jsonb_object_keys(l.slots))<>11 or cardinality(l.bench)<>11) then
  raise exception 'escalação de bot incompleta';
 end if;

 -- liga: 132 jogos, 22 rodadas, 6 por rodada, cada clube uma vez por rodada
 select count(*) into n from public.on_fixtures;
 if n<>132 then raise exception 'jogos: %',n;end if;
 if exists(select 1 from public.on_fixtures where home=away) then raise exception 'clube contra ele mesmo';end if;
 if exists(select 1 from(select round,count(*) c,count(distinct kickoff) k,count(distinct (kickoff at time zone 'America/Sao_Paulo')::date) d from public.on_fixtures group by round) x
  where x.c<>6 or x.k<>6 or x.d<>1) then raise exception 'rodada sem 6 jogos em 6 horários do mesmo dia';end if;
 if exists(select 1 from(select round,club,count(*) c from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(club) group by 1,2) x where x.c<>1) then
  raise exception 'clube joga mais de uma vez na rodada';
 end if;
 -- cada par se enfrenta duas vezes, uma em casa e uma fora
 if (select count(*) from(select home,away from public.on_fixtures group by 1,2 having count(*)=1) x)<>132 then raise exception 'mando repetido';end if;
 if exists(select 1 from(select club,count(*) filter(where at_home) h from public.on_fixtures f
   cross join lateral(values(f.home,true),(f.away,false)) v(club,at_home) group by 1) x where x.h<>11) then raise exception 'mandos desbalanceados';end if;
 -- um jogo por clube por dia; dias de copa (6, 12, 18, 24) livres; 26 dias de liga
 if exists(select 1 from(select (kickoff at time zone 'America/Sao_Paulo')::date d,club,count(*) c from public.on_fixtures f
   cross join lateral(values(f.home),(f.away)) v(club) group by 1,2) x where x.c<>1) then raise exception 'dois jogos no mesmo dia';end if;
 if exists(select 1 from public.on_fixtures where (kickoff at time zone 'America/Sao_Paulo')::date-date '2026-11-16'+1 in(6,12,18,24)) then
  raise exception 'jogo de liga em dia de copa';
 end if;
 if (select max((kickoff at time zone 'America/Sao_Paulo')::date)-date '2026-11-16'+1 from public.on_fixtures)<>26 then raise exception 'liga não fecha em 26 dias';end if;
 -- o horário de cada clube varia ao longo da temporada
 if exists(select 1 from(select club,count(distinct (kickoff at time zone 'America/Sao_Paulo')::time) k from public.on_fixtures f
   cross join lateral(values(f.home),(f.away)) v(club) group by 1) x where x.k<3) then raise exception 'clube sempre no mesmo horário';end if;
 if (select count(*) from public.on_table)<>12 then raise exception 'tabela incompleta';end if;
 raise notice 'PASS criação da temporada';
end $$;

-- segunda temporada ao vivo é recusada
do $$ begin
 begin perform public.on_season_bootstrap('{}'::uuid[],current_date);
  raise exception 'aceitou duas temporadas ao vivo';
 exception when others then if sqlerrm not like 'Já existe%' then raise;end if;end;
 raise notice 'PASS uma temporada por vez';
end $$;

-- portão: com o modo fechado, só o e-mail de teste entra
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
set request.jwt.claims='{"email":"outro@example.com"}';
set role authenticated;
do $$
declare j jsonb;
begin
 j:=public.on_status();
 if j->>'access'<>'unavailable' or j->'club'<>'null'::jsonb then raise exception 'portão deixou passar: %',j;end if;
 begin perform public.on_squad();raise exception 'conta fora do teste leu elenco';
 exception when others then if sqlerrm not like 'O modo online ainda não%' then raise;end if;end;
 begin perform public.on_draft_pick(0,1);raise exception 'conta fora do teste escolheu craque';
 exception when others then if sqlerrm not like 'O modo online ainda não%' then raise;end if;end;
 begin perform public.on_join_queue();raise exception 'conta fora do teste entrou na fila';
 exception when others then if sqlerrm not like 'O modo online ainda não%' then raise;end if;end;
 begin perform public.on_gate();raise exception 'usuário chamou on_gate';
 exception when insufficient_privilege then null;end;
 raise notice 'PASS portão de testes';
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.on_players p join public.on_clubs c on c.id=p.club_id where p.star and c.user_id is not null) then
  raise exception 'portão fechado gravou craque';
 end if;
end $$;
-- e-mail de teste (maiúsculas e espaços não importam) entra
set request.jwt.claims='{"email":" ContatoDavidCaua@gmail.com "}';
set role authenticated;
do $$ begin
 if public.on_status()->>'access'<>'playing' then raise exception 'e-mail de teste barrado';end if;
end $$;
reset role;
-- o restante dos testes roda com o modo aberto para todos
update public.on_config set public_open=true;

-- usuário 1: situação, escolha dos craques, escalação
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
set request.jwt.claims='{"email":"outro@example.com"}';
set role authenticated;
do $$
declare j jsonb;k jsonb;n int;first_name text;
begin
 j:=public.on_status();
 if j->>'access'<>'playing' or (j->'club'->>'draft_step')::int<>0 or j->'next' is null or j->'next'->>'id' is null then raise exception 'status: %',j;end if;
 if j->'club'->>'name'<>'FC Edson' then raise exception 'nome do clube: %',j->'club';end if;

 begin perform public.on_lineup_auto();raise exception 'escalou antes dos craques';
 exception when others then if sqlerrm not like 'Escolha seus três%' then raise;end if;end;

 j:=public.on_draft_read();
 if (j->>'step')::int<>0 or j->>'line'<>'DEF' or jsonb_array_length(j->'options')<>3 then raise exception 'draft 0: %',j;end if;
 if exists(select 1 from jsonb_array_elements(j->'options') o where o->>'pos' not in('ZAG','LD','LE') or (o->>'ovr')::int not between 78 and 82) then
  raise exception 'opções de defesa: %',j->'options';
 end if;
 if j<>public.on_draft_read() then raise exception 'opções mudam entre leituras';end if;
 first_name:=j->'options'->1->>'name';

 k:=public.on_draft_pick(0,2);
 if (k->>'step')::int<>1 or k->>'line'<>'MID' or k->'picked'->0->>'name'<>first_name then raise exception 'pick 0: %',k;end if;
 -- duplo clique no mesmo passo não escolhe de novo
 k:=public.on_draft_pick(0,3);
 if (k->>'step')::int<>1 or jsonb_array_length(k->'picked')<>1 then raise exception 'pick repetido avançou: %',k;end if;
 if exists(select 1 from jsonb_array_elements(k->'options') o where o->>'pos' not in('VOL','MC','MEI')) then raise exception 'opções de meio';end if;
 k:=public.on_draft_pick(1,1);
 if k->>'line'<>'ATT' or exists(select 1 from jsonb_array_elements(k->'options') o where o->>'pos' not in('PD','ATA','PE')) then raise exception 'opções de ataque';end if;
 k:=public.on_draft_pick(2,3);
 if not (k->>'done')::boolean or jsonb_array_length(k->'picked')<>3 or jsonb_array_length(k->'options')<>0 then raise exception 'draft final: %',k;end if;
 begin perform public.on_draft_pick(3,1);exception when others then raise exception 'pick depois do fim deu erro: %',sqlerrm;end;

 j:=public.on_squad();
 if jsonb_array_length(j->'players')<>22 then raise exception 'elenco: %',jsonb_array_length(j->'players');end if;
 if (select count(*) from jsonb_object_keys(j->'lineup'->'slots'))<>11 or jsonb_array_length(j->'lineup'->'bench')<>11 then raise exception 'escalação automática';end if;
 -- os três craques entram no time titular
 select count(*) into n from jsonb_array_elements(j->'players') p
  where (p->>'star')::boolean and exists(select 1 from jsonb_each_text(j->'lineup'->'slots') s where s.value=p->>'id');
 if n<>3 then raise exception 'craques titulares: %',n;end if;
 raise notice 'PASS escolha dos craques';
end $$;

do $$
declare j jsonb:=public.on_squad();v_slots jsonb:=j->'lineup'->'slots';v_bench text[];a text;b text;k jsonb;
begin
 select array_agg(x) into v_bench from jsonb_array_elements_text(j->'lineup'->'bench') x;
 -- troca um titular por um reserva e muda a formação para o mesmo conjunto de vagas
 a:=v_slots->>'ATA';b:=v_bench[1];
 k:=public.on_lineup_save('4-3-3',v_slots||jsonb_build_object('ATA',b),array_replace(v_bench,b,a),'{"style":"attacking"}');
 if k->'lineup'->'slots'->>'ATA'<>b or k->'lineup'->'tactics'->>'style'<>'attacking' then raise exception 'salvar escalação: %',k->'lineup';end if;
 -- sem táticas: mantém as salvas
 k:=public.on_lineup_save('4-3-3',v_slots,v_bench);
 if k->'lineup'->'tactics'->>'style'<>'attacking' then raise exception 'perdeu as táticas';end if;

 begin perform public.on_lineup_save('4-3-3',v_slots-'ATA',v_bench);raise exception 'aceitou 10 jogadores';
 exception when others then if sqlerrm not like 'Escalação incompleta%' then raise;end if;end;
 begin perform public.on_lineup_save('4-3-3',v_slots||jsonb_build_object('ATA',v_slots->>'GOL'),v_bench);raise exception 'aceitou repetido';
 exception when others then if sqlerrm not like 'Jogador repetido%' then raise;end if;end;
 begin perform public.on_lineup_save('4-3-3',v_slots||jsonb_build_object('ATA','o999999'),v_bench);raise exception 'aceitou jogador de fora';
 exception when others then if sqlerrm not like 'Jogador fora%' then raise;end if;end;
 begin perform public.on_lineup_save('9-9-9',v_slots,v_bench);raise exception 'aceitou formação inválida';
 exception when others then if sqlerrm not like 'Formação inválida%' then raise;end if;end;
 begin perform public.on_lineup_save('4-4-2',v_slots,v_bench);raise exception 'aceitou vagas de outra formação';
 exception when others then if sqlerrm not like 'Escalação incompleta%' then raise;end if;end;

 k:=public.on_lineup_auto('4-4-2');
 if k->'lineup'->>'formation'<>'4-4-2' or not k->'lineup'->'slots' ? 'ATA2' then raise exception 'auto 4-4-2';end if;
 raise notice 'PASS escalação';
end $$;

do $$
declare j jsonb;
begin
 j:=public.on_calendar();
 if jsonb_array_length(j->'fixtures')<>132 or jsonb_array_length(j->'clubs')<>12 then raise exception 'calendário';end if;
 j:=public.on_standings();
 if jsonb_array_length(j->'rows')<>12 then raise exception 'tabela';end if;
 j:=public.on_club_rename('  Dragões   do Sul ');
 if j->'club'->>'name'<>'Dragões do Sul' or j->'club'->>'short'<>'DRA' then raise exception 'renomear: %',j->'club';end if;
 begin perform public.on_club_rename('ab');raise exception 'aceitou nome curto';
 exception when others then if sqlerrm not like 'O nome do clube%' then raise;end if;end;
 begin perform public.on_club_rename('fc jeff');raise exception 'aceitou nome repetido';
 exception when others then if sqlerrm not like 'Já existe um clube%' then raise;end if;end;
 raise notice 'PASS calendário, tabela e nome do clube';
end $$;

-- tabelas e funções internas fechadas para o usuário
do $$ begin
 begin perform 1 from public.on_clubs;raise exception 'leu on_clubs direto';
 exception when insufficient_privilege then null;end;
 begin perform public.on_season_bootstrap('{}'::uuid[],current_date);raise exception 'usuário criou temporada';
 exception when insufficient_privilege then null;end;
 begin perform public.on_auto_lineup(1);raise exception 'usuário chamou função interna';
 exception when insufficient_privilege then null;end;
 raise notice 'PASS permissões';
end $$;

-- usuário novo: sem acesso, entra na fila, não tem clube
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000009';
do $$
declare j jsonb;
begin
 j:=public.on_status();
 if j->>'access'<>'none' or j->'club'<>'null'::jsonb then raise exception 'novato: %',j;end if;
 j:=public.on_join_queue();
 if j->>'access'<>'queued' then raise exception 'fila: %',j;end if;
 j:=public.on_join_queue();
 if j->>'access'<>'queued' then raise exception 'fila repetida: %',j;end if;
 begin perform public.on_squad();raise exception 'novato leu elenco';
 exception when others then if sqlerrm not like 'Você não participa%' then raise;end if;end;
 raise notice 'PASS fila de novos usuários';
end $$;
reset role;

-- sandbox: jogos em sequência curta a partir de um instante
update public.on_seasons set status='closed';
select public.on_season_bootstrap(array['00000000-0000-0000-0000-000000000004']::uuid[],current_date,'sandbox',interval '3 minutes',timestamptz '2026-11-10 12:00+00');
do $$ begin
 if (select min(kickoff) from public.on_fixtures f join public.on_seasons s on s.id=f.season_id and s.status='live')<>timestamptz '2026-11-10 12:03+00' then
  raise exception 'primeiro pontapé do sandbox';
 end if;
 if (select count(distinct kickoff) from public.on_fixtures f join public.on_seasons s on s.id=f.season_id and s.status='live')<>132 then
  raise exception 'sandbox com horários repetidos';
 end if;
 raise notice 'PASS sandbox';
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Fase 2: partida ao vivo
-- ═════════════════════════════════════════════════════════════════════════════
do $$ begin
 if public.on_clock('2026-01-01 20:00','2026-01-01 19:59')<>-1 or public.on_clock('2026-01-01 20:00','2026-01-01 20:00:20')<>2
  or public.on_clock('2026-01-01 20:00','2026-01-01 20:05:20')<>45 or public.on_clock('2026-01-01 20:00','2026-01-01 20:06:40')<>45
  or public.on_clock('2026-01-01 20:00','2026-01-01 20:06:52')<>46 or public.on_clock('2026-01-01 20:00','2026-01-01 20:12:00')<>90
  or public.on_clock('2026-01-01 20:00','2026-01-01 20:30:00')<>90 or public.on_clock('2026-01-01 20:00','2026-01-01 20:12:50',true)<>90
  or public.on_clock('2026-01-01 20:00','2026-01-01 20:13:07',true)<>91 or public.on_clock('2026-01-01 20:00','2026-01-01 20:30:00',true)<>120 then
  raise exception 'relógio';
 end if;
 if exists(select 1 from pg_proc where proname='on_engine_run' and prosrc ~ 'mgr_matches|mgr_match_players|sim_player_attrs|mgr_event\(') then
  raise exception 'motor online ainda cita tabelas do modo Temporadas';
 end if;
 raise notice 'PASS relógio e cópia do motor';
end $$;

-- craques do usuário 4 (sandbox) para ter escalação de humano
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
set role authenticated;
select public.on_draft_pick(0,1),public.on_draft_pick(1,1),public.on_draft_pick(2,1);
reset role;

-- abertura, avanço pelo relógio, intervalo, fim único e volta para o elenco
do $$
declare f public.on_fixtures;m public.on_matches;n int;k timestamptz;t0 timestamptz;pid text;v_round int;
begin
 select x.* into f from public.on_fixtures x join public.on_seasons s on s.id=x.season_id and s.status='live'
  join public.on_clubs c on c.user_id is not null and c.id in(x.home,x.away) order by x.kickoff limit 1;
 k:=f.kickoff;
 -- titular lesionado e suspenso são trocados no pontapé; o resto da escolha fica
 select l.slots->>'ATA' into pid from public.on_lineups l join public.on_clubs c on c.id=l.club_id and c.user_id is not null where l.club_id in(f.home,f.away);
 update public.on_players set inj_until=current_date+3 where id=pid;
 perform public.on_match_open(f);
 select * into m from public.on_matches where fixture_id=f.id;
 if m.status<>'live' or (select status from public.on_fixtures where id=f.id)<>'live' then raise exception 'abertura';end if;
 if (select count(*) from public.on_match_players where fixture_id=f.id and status='on')<>22 then raise exception 'titulares';end if;
 if exists(select 1 from public.on_match_players where fixture_id=f.id and player_id=pid) then raise exception 'lesionado entrou';end if;
 if jsonb_array_length(m.state->'fixes'->(case when (select user_id from public.on_clubs where id=f.home) is not null then 'h' else 'a' end))<>1 then
  raise exception 'troca de titular não registrada: %',m.state->'fixes';
 end if;
 if exists(select 1 from public.on_match_players where fixture_id=f.id and (c_att is null or c_gk is null or fit<=0)) then raise exception 'atributos';end if;
 perform public.on_match_open(f); -- repetir não duplica
 if (select count(*) from public.on_match_players where fixture_id=f.id)>46 then raise exception 'abriu duas vezes';end if;

 t0:=clock_timestamp();
 perform public.on_advance(f.id,k+interval '200 seconds','h');
 if (select minute from public.on_matches where fixture_id=f.id)<>28 then raise exception 'minuto 28';end if;
 perform public.on_advance(f.id,k+interval '350 seconds','h');
 perform public.on_advance(f.id,k+interval '380 seconds','h');
 if (select minute from public.on_matches where fixture_id=f.id)<>45 then raise exception 'intervalo';end if;
 if (select count(*) from public.on_match_events where fixture_id=f.id and kind='ht')<>1 then raise exception 'evento de intervalo';end if;
 raise notice 'primeiro tempo em % ms',round(extract(epoch from clock_timestamp()-t0)*1000);

 -- vermelho forçado vira suspensão na próxima rodada de liga
 select player_id into pid from public.on_match_players where fixture_id=f.id and status='on' and pos<>'GOL' order by player_id limit 1;
 update public.on_match_players set red=1,yellow=0,status='sent_off',slot=null,left_min=45 where fixture_id=f.id and player_id=pid;
 perform public.on_advance(f.id,k+interval '900 seconds',null);
 select * into m from public.on_matches where fixture_id=f.id;
 if m.status<>'finished' or m.summary is null then raise exception 'não terminou: % %',m.status,m.minute;end if;
 select count(*) into n from public.on_table t where t.club_id in(f.home,f.away) and t.p=1;
 if n<>2 then raise exception 'classificação';end if;
 if (select sum(pts) from public.on_table t where t.club_id in(f.home,f.away)) not in(2,3) then raise exception 'pontos';end if;
 perform public.on_match_finish(f.id);
 update public.on_matches set summary=null where fixture_id=f.id; -- força o caminho de fim repetido
 perform public.on_match_finish(f.id);
 if (select sum(p) from public.on_table t where t.club_id in(f.home,f.away))<>2 then raise exception 'fim repetido somou de novo';end if;
 select min(o.round) into v_round from public.on_fixtures o where o.season_id=f.season_id and o.comp='L' and o.kickoff>f.kickoff
  and (select club_id from public.on_match_players where fixture_id=f.id and player_id=pid) in(o.home,o.away);
 if (select susp_round from public.on_players where id=pid) is distinct from v_round then raise exception 'suspensão';end if;
 if exists(select 1 from public.on_players p join public.on_match_players mp on mp.player_id=p.id and mp.fixture_id=f.id
  where mp.status<>'bench' and p.cond<>round(mp.cond)) then raise exception 'condição não voltou ao elenco';end if;
 if (select hg from public.on_fixtures where id=f.id)<>(m.state->'score'->>0)::int then raise exception 'placar';end if;
 raise notice 'PASS partida: abertura, relógio, fim e elenco';
end $$;

-- poll e mudanças do técnico (duplo clique ignorado), espectador sem lado
do $$
declare f public.on_fixtures;c public.on_clubs;
begin
 select x.* into c from public.on_clubs x join public.on_seasons s on s.id=x.season_id and s.status='live' where x.user_id='00000000-0000-0000-0000-000000000004';
 select x.* into f from public.on_fixtures x where x.status='sched' and c.id in(x.home,x.away) order by x.kickoff limit 1;
 update public.on_fixtures set kickoff=kickoff+interval '30 days' where status='sched' and season_id=c.season_id;
 update public.on_fixtures set kickoff=now()-interval '100 seconds' where id=f.id;
end $$;
set role authenticated;
do $$
declare j jsonb;k jsonb;s text;pout text;pin text;
begin
 j:=public.on_match_poll();
 s:=j->>'my_side';
 if j->>'status'<>'live' or s not in('h','a') or (j->>'minute')::int<>14 then raise exception 'poll: % %',j->>'status',j->>'minute';end if;
 if not (j->'present'->>s)::boolean then raise exception 'presença';end if;
 select p->>'id' into pout from jsonb_array_elements(j->'players') p where p->>'side'=s and p->>'status'='on' and p->>'pos'<>'GOL' limit 1;
 select p->>'id' into pin from jsonb_array_elements(j->'players') p where p->>'side'=s and p->>'status'='bench' limit 1;
 k:=public.on_match_act((j->>'fixture_id')::bigint,'req-0001',jsonb_build_object('subs',jsonb_build_array(jsonb_build_object('out',pout,'in',pin)),'tactics','{"style":"attacking"}'::jsonb));
 if (k->>'applied_at')::int<>14 or (k->'subs'->s->>'used')::int<>1 then raise exception 'act: %',k->'subs';end if;
 k:=public.on_match_act((j->>'fixture_id')::bigint,'req-0001',jsonb_build_object('subs',jsonb_build_array(jsonb_build_object('out',pout,'in',pin))));
 if not (k->>'repeated')::boolean or (k->'subs'->s->>'used')::int<>1 then raise exception 'duplo clique gastou duas substituições';end if;
 if (select count(*) from jsonb_array_elements(public.on_match_poll((j->>'fixture_id')::bigint,1000)->'events'))<>0 then raise exception 'eventos antigos voltaram';end if;
 begin perform public.on_match_act((j->>'fixture_id')::bigint,'xx',null);raise exception 'aceitou envio sem id';
 exception when others then if sqlerrm not like 'Envio sem%' then raise;end if;end;
 raise notice 'PASS poll e mudanças do técnico';
end $$;
reset role;

-- cron: partida que ninguém assiste termina depois do relógio, em dois blocos de 45 minutos
do $$
declare f public.on_fixtures;n int;
begin
 perform public.on_advance(x.id,now()+interval '1 day',null) from public.on_fixtures x where x.status='live';
 select x.* into f from public.on_fixtures x join public.on_seasons s on s.id=x.season_id and s.status='live' where x.status='sched' order by x.kickoff limit 1;
 if public.on_tick(f.kickoff+interval '1 minute')<>0 then raise exception 'tick terminou jogo em andamento';end if;
 if (select status from public.on_matches where fixture_id=f.id)<>'live' then raise exception 'tick não abriu o jogo';end if;
 perform public.on_tick(f.kickoff+interval '13 minutes');
 if (select minute from public.on_matches where fixture_id=f.id)<>45 then raise exception 'primeiro bloco';end if;
 perform public.on_tick(f.kickoff+interval '14 minutes');
 if (select status from public.on_fixtures where id=f.id)<>'done' then raise exception 'tick não terminou';end if;
 -- recuperação diária uma vez só
 update public.on_players set cond=50 where id in(select player_id from public.on_match_players where fixture_id=f.id);
 update public.on_seasons set last_recovery=null where status='live';
 perform public.on_tick(f.kickoff+interval '15 minutes');
 perform public.on_tick(f.kickoff+interval '16 minutes');
 select max(cond) into n from public.on_players where id in(select player_id from public.on_match_players where fixture_id=f.id);
 if n<>85 then raise exception 'recuperação diária: %',n;end if;
 raise notice 'PASS cron';
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Fase 3: mercado de leilões
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare s public.on_seasons;n int;l public.on_lots;a public.on_clubs;b public.on_clubs;bot public.on_clubs;pid text;v bigint;ids text[];
begin
 select * into s from public.on_seasons where status='live';
 update public.on_lots set status='cancelled' where status='open';
 -- destaques: um por faixa, os mesmos para todos, até a virada da hora; fora do horário não abre
 perform public.on_market_tick(timestamptz '2026-11-12 05:00+00',false);
 if exists(select 1 from public.on_lots where season_id=s.id and status='open' and featured>0) then raise exception 'destaque de madrugada';end if;
 perform public.on_market_tick(timestamptz '2026-11-12 13:20+00',false);
 perform public.on_market_tick(timestamptz '2026-11-12 13:21+00',false);
 select count(*) into n from public.on_lots where season_id=s.id and seller is null and status='open' and featured>0;
 if n<>3 then raise exception 'destaques: %',n;end if;
 if (select count(distinct featured) from public.on_lots where status='open' and featured>0)<>3 then raise exception 'faixas repetidas';end if;
 if exists(select 1 from public.on_lots where status='open' and featured>0 and ends_at<>timestamptz '2026-11-12 14:00+00') then raise exception 'destaque não fecha na virada da hora';end if;
 if (select min(p.ovr) from public.on_lots x join public.on_players p on p.id=x.player_id where x.status='open' and x.featured=1)<77 then raise exception 'faixa 1 fraca';end if;
 -- sem lances: sai (jogador apagado) e entra outro
 select array_agg(player_id) into ids from public.on_lots where status='open' and featured>0;
 perform public.on_market_tick(timestamptz '2026-11-12 14:00+00',false);
 if exists(select 1 from public.on_players where id=any(ids)) then raise exception 'destaque sem lance ficou no banco';end if;
 if (select count(*) from public.on_lots where status='open' and featured>0 and ends_at=timestamptz '2026-11-12 15:00+00')<>3 then raise exception 'destaque não foi trocado';end if;

 select * into l from public.on_lots where status='open' and seller is null order by opens_at limit 1;
 select * into a from public.on_clubs where season_id=s.id and user_id is not null order by id limit 1;
 select * into b from public.on_clubs where season_id=s.id and user_id is null order by id limit 1;
 update public.on_clubs set cash=100000,reserved=0,debt=0 where id in(a.id,b.id);
 -- antes de abrir: recusa
 begin perform public.on_bid_as(a.id,l.id,l.start_price,l.opens_at-interval '1 minute');raise exception 'lance antes de abrir';
 exception when others then if sqlerrm not like 'Leilão encerrado%' then raise;end if;end;
 -- lance abaixo do mínimo: recusa
 begin perform public.on_bid_as(a.id,l.id,l.start_price-1,l.opens_at);raise exception 'lance baixo';
 exception when others then if sqlerrm not like 'O lance mínimo%' then raise;end if;end;
 perform public.on_bid_as(a.id,l.id,l.start_price,l.opens_at+interval '10 seconds');
 if (select reserved from public.on_clubs where id=a.id)<>l.start_price then raise exception 'reserva do lance';end if;
 -- cobertura libera a reserva do anterior
 v:=public.on_min_bid((select x from public.on_lots x where x.id=l.id));
 perform public.on_bid_as(b.id,l.id,v,l.ends_at-interval '5 seconds');
 if (select reserved from public.on_clubs where id=a.id)<>0 or (select reserved from public.on_clubs where id=b.id)<>v then raise exception 'reserva liberada';end if;
 -- lance no fim garante mais 5 minutos
 if (select ends_at from public.on_lots where id=l.id)<>l.ends_at-interval '5 seconds'+interval '5 minutes' then raise exception 'prorrogação de 5 min';end if;
 -- mesmo clube cobrindo o próprio lance só reserva a diferença
 v:=public.on_min_bid((select x from public.on_lots x where x.id=l.id));
 perform public.on_bid_as(b.id,l.id,v,l.ends_at+interval '1 minute');
 if (select reserved from public.on_clubs where id=b.id)<>v then raise exception 'reserva própria';end if;
 -- prorrogação tem teto
 update public.on_clubs set cash=100000000 where id in(a.id,b.id);
 for n in 1..200 loop
  select * into l from public.on_lots where id=l.id;
  exit when l.ends_at>=l.hard_end;
  perform public.on_bid_as(case when l.best_club=a.id then b.id else a.id end,l.id,public.on_min_bid(l),l.ends_at-interval '1 second');
 end loop;
 select * into l from public.on_lots where id=l.id;
 if l.ends_at>l.hard_end then raise exception 'passou do teto';end if;
 -- fechamento: dinheiro e jogador mudam de mãos uma vez só
 select cash into v from public.on_clubs where id=l.best_club;
 perform public.on_lot_settle(l.id,l.hard_end+interval '1 second');
 perform public.on_lot_settle(l.id,l.hard_end+interval '2 second');
 if (select club_id from public.on_players where id=l.player_id)<>l.best_club then raise exception 'jogador não entregue';end if;
 if (select cash from public.on_clubs where id=l.best_club)<>v-l.best_bid or (select reserved from public.on_clubs where id=l.best_club)<>0 then raise exception 'pagamento';end if;
 if (select count(*) from public.on_ledger where club_id=l.best_club and kind='buy')<>1 then raise exception 'extrato';end if;
 if exists(select 1 from public.on_lineups x where x.club_id=l.best_club and (x.slots::text like '%"'||l.player_id||'"%' or l.player_id=any(x.bench))) then
  raise exception 'comprado entrou na escalação';end if;

 -- venda de jogador do humano: sai da escalação salva, vaga preenchida, vendedor recebe
 select l2.slots->>'ATA' into pid from public.on_lineups l2 where l2.club_id=a.id;
 update public.on_clubs set cash=10000 where id=a.id;
 set local request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
 select * into a from public.on_clubs where id=a.id;
 if a.user_id<>'00000000-0000-0000-0000-000000000004' then raise exception 'teste espera o usuário 4';end if;
 perform public.on_lot_create(pid,greatest(500,round(public.on_value((select ovr from public.on_players where id=pid),(select age from public.on_players where id=pid),(select pot from public.on_players where id=pid))*.5))::bigint);
 select * into l from public.on_lots where player_id=pid and status='open';
 perform public.on_bid_as(b.id,l.id,l.start_price,now());
 perform public.on_lot_settle(l.id,l.hard_end+interval '1 second');
 if (select club_id from public.on_players where id=pid)<>b.id then raise exception 'venda não entregue';end if;
 if (select cash from public.on_clubs where id=a.id)<>10000+l.start_price then raise exception 'vendedor não recebeu';end if;
 if exists(select 1 from public.on_lineups x where x.club_id=a.id and x.slots::text like '%"'||pid||'"%') then raise exception 'vendido continua escalado';end if;
 if (select count(*) from jsonb_object_keys((select slots from public.on_lineups where club_id=a.id)))<>11 then raise exception 'vaga não preenchida';end if;
 if not exists(select 1 from public.on_news where club_id=a.id and text like '%vendido%') then raise exception 'técnico não avisado';end if;

 -- sem interessados: bot compra por 60% a 75% do valor
 select l2.bench[1] into pid from public.on_lineups l2 where l2.club_id=a.id;
 perform public.on_lot_create(pid,greatest(500,round(public.on_value((select ovr from public.on_players where id=pid),(select age from public.on_players where id=pid),(select pot from public.on_players where id=pid))*.5))::bigint);
 select * into l from public.on_lots where player_id=pid and status='open';
 perform public.on_lot_settle(l.id,l.hard_end+interval '1 second');
 select * into bot from public.on_clubs where id=(select club_id from public.on_players where id=pid);
 if bot.user_id is not null then raise exception 'bot não comprou';end if;
 v:=(select best_bid from public.on_lots where id=l.id);
 if v<round(public.on_value((select ovr from public.on_players where id=pid),(select age from public.on_players where id=pid),(select pot from public.on_players where id=pid))*.59) then raise exception 'bot pagou pouco: %',v;end if;

 -- limite de elenco: 16 não vende; dívida bloqueia lance
 delete from public.on_players where club_id=a.id and id not in(select id from public.on_players where club_id=a.id order by ovr desc limit 16);
 perform public.on_lineup_repair(a.id);
 begin perform public.on_lot_create((select id from public.on_players where club_id=a.id limit 1),100000);raise exception 'vendeu com 16';
 exception when others then if sqlerrm not like 'Elenco com 16%' then raise;end if;end;
 update public.on_clubs set debt=5 where id=a.id;
 select * into l from public.on_lots where status='open' and seller is null order by opens_at limit 1;
 begin perform public.on_bid_as(a.id,l.id,l.start_price,l.opens_at);raise exception 'lance com dívida';
 exception when others then if sqlerrm not like 'Clube com dívida%' then raise;end if;end;
 perform public.on_money(a.id,100,'test');
 if (select debt from public.on_clubs where id=a.id)<>0 then raise exception 'entrada não pagou dívida';end if;
 raise notice 'PASS mercado';
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Fase 4: treino, estrutura, contratos, finanças e moedas
-- ═════════════════════════════════════════════════════════════════════════════
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
set role authenticated;
do $$
declare j jsonb;k jsonb;ids text[];sid bigint;
begin
 j:=public.on_club();
 if (j->'train'->>'max')::int<>3 or j->'levels'->>'stadium'<>'0' then raise exception 'on_club: %',j;end if;
 -- treino: condição cai, limite diário, resultado limitado a 0..1, ganho só uma vez
 ids:=array(select p->>'id' from jsonb_array_elements(public.on_squad()->'players') p where not (p->>'injured')::boolean order by (p->>'ovr')::numeric limit 3);
 k:=public.on_train_start('aim',ids);
 sid:=(k->>'session')::bigint;
 begin perform public.on_train_finish(sid,1);raise exception 'treino curto aceito';
 exception when others then if sqlerrm not like 'Treino curto%' then raise;end if;end;
 raise notice 'PASS treino recusa sessão curta';
end $$;
reset role;
do $$
declare c int;t public.on_train;j jsonb;
begin
 select * into t from public.on_train order by id desc limit 1;
 perform set_config('test.sid',t.id::text,false);
 perform set_config('test.ids',array_to_string(t.players,','),false);
 update public.on_train set started_at=now()-interval '30 seconds' where id=t.id;
 if exists(select 1 from public.on_players where id=any(t.players) and cond>94) then raise exception 'treino não gastou condição';end if;
 update public.on_players set xp='{0,0,90,0}',g='{0,0,0,0}',pot=ovr+10,age=20 where id=any(t.players);
end $$;
set role authenticated;
do $$
declare j jsonb;sid bigint:=current_setting('test.sid')::bigint;ids text[]:=string_to_array(current_setting('test.ids'),',');
begin
 j:=public.on_train_finish(sid,7.5); -- resultado fora da faixa vira 1
 if (j->>'score')::numeric<>1 or jsonb_array_length(j->'players')<>3 then raise exception 'fim do treino: %',j;end if;
 begin perform public.on_train_finish(sid,1);raise exception 'treino terminou duas vezes';
 exception when others then if sqlerrm not like 'Esse treino já%' then raise;end if;end;
 perform public.on_train_start('timing',ids);
 perform public.on_train_start('reaction',ids);
 begin perform public.on_train_start('passing',ids);raise exception 'passou do limite diário';
 exception when others then if sqlerrm not like 'Limite de%' then raise;end if;end;
 raise notice 'PASS treino';
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.on_players where id=any(string_to_array(current_setting('test.ids'),',')) and (g[3]<>1 or ovr<>level+.5)) then
  raise exception 'grupo/nota não subiram';
 end if;
end $$;
do $$
declare c public.on_clubs;f public.on_fixtures;v bigint;w bigint;
begin
 select * into c from public.on_clubs where user_id='00000000-0000-0000-0000-000000000004' and season_id=(select id from public.on_seasons where status='live');
 -- potencial e idade freiam o ganho
 if public.on_train_gain(1,20,70,70,0)<>0 or public.on_train_gain(1,33,60,80,0)>=public.on_train_gain(1,20,60,80,0) then raise exception 'limite de evolução';end if;
 -- salários na virada do dia; sem dinheiro vira dívida
 update public.on_clubs set cash=1000,reserved=0,debt=0 where id=c.id;
 select coalesce(sum(wage),0) into w from public.on_players where club_id=c.id;
 perform public.on_club_tick(now(),true);
 select * into c from public.on_clubs where id=c.id;
 if c.cash<>0 or c.debt<>w-1000 then raise exception 'salários: caixa % dívida % (salários %)',c.cash,c.debt,w;end if;
 -- bilheteria do jogo em casa paga a dívida primeiro
 select * into f from public.on_fixtures where home=c.id and status='done' limit 1;
 if f.id is null then select * into f from public.on_fixtures where home=c.id limit 1;end if;
 perform public.on_gate_income(f.id);
 select * into c from public.on_clubs where id=c.id;
 if c.debt<>greatest(0,w-1000-8000) or c.cash<>greatest(0,8000-(w-1000)) then raise exception 'bilheteria: caixa % dívida %',c.cash,c.debt;end if;
 update public.on_clubs set cash=200000,debt=0 where id=c.id;
 raise notice 'PASS salários e bilheteria';
end $$;
set role authenticated;
do $$
declare j jsonb;pid text;
begin
 -- obra: custo na hora, uma por vez
 j:=public.on_build('stadium');
 if j->'build'->>'kind'<>'stadium' or (j->>'cash')::bigint<>200000-25000 then raise exception 'obra: %',j;end if;
 begin perform public.on_build('medical');raise exception 'duas obras';
 exception when others then if sqlerrm not like 'Já existe uma obra%' then raise;end if;end;
 -- renovação
 select p->>'id' into pid from jsonb_array_elements(public.on_squad()->'players') p limit 1;
 j:=public.on_renew(pid,2);
 if (select (p->>'contract_end')::int from jsonb_array_elements(j->'players') p where p->>'id'=pid)<(j->'club'->>'id')::int*0+2 then raise exception 'renovação';end if;
 if not exists(select 1 from jsonb_array_elements(public.on_finance()->'ledger') x where x->>'kind'='renew') then raise exception 'luva no extrato';end if;
 -- moedas: saem da carteira, entram no caixa, com teto
 j:=public.online_coins_convert(100);
 if (j->'coins'->>'converted')::int<>100 then raise exception 'conversão: %',j->'coins';end if;
 begin perform public.online_coins_convert(901);raise exception 'passou do teto';
 exception when others then if sqlerrm not like 'Teto da temporada%' then raise;end if;end;
 raise notice 'PASS obra, renovação e moedas';
end $$;
reset role;
do $$ begin
 if (select coins from public.careers where user_id='00000000-0000-0000-0000-000000000004')<>900 then raise exception 'carteira';end if;
 update public.on_clubs set build_until=now()-interval '1 second' where build_kind='stadium';
 perform public.on_club_tick(now(),false);
 if exists(select 1 from public.on_clubs where build_kind is not null) or not exists(select 1 from public.on_clubs where (lv->>'stadium')::int=1) then raise exception 'obra não concluiu';end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Fase 6: identidade, carta, lance com moedas e resultado do leilão
-- ═════════════════════════════════════════════════════════════════════════════
do $$
declare s public.on_seasons;c public.on_clubs;o public.on_clubs;pid text;l bigint;
begin
 select * into s from public.on_seasons where status='live';
 select * into c from public.on_clubs where season_id=s.id and user_id='00000000-0000-0000-0000-000000000004';
 -- rival humano: se a temporada só tem um técnico, um bot vira técnico durante o teste
 select * into o from public.on_clubs where season_id=s.id and id<>c.id order by (user_id is null),id limit 1;
 perform set_config('test.rival_bot',(o.user_id is null)::text,false);
 update public.on_clubs set user_id='00000000-0000-0000-0000-0000000000f6' where id=o.id and user_id is null;
 update public.on_clubs set cash=1000,reserved=0,debt=0 where id=c.id;
 update public.on_clubs set cash=500000,reserved=0,debt=0 where id=o.id;
 update public.careers set coins=1000 where user_id='00000000-0000-0000-0000-000000000004';
 pid:=public.on_gen_featured('teste-fase6',1);
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
 values(s.id,pid,13000,now()-interval '1 minute',now()+interval '10 minutes',now()+interval '6 hours',0) returning id into l;
 perform public.on_bid_as(o.id,l,13000);
 perform set_config('test.lot',l::text,false);
 perform set_config('test.rival',o.id::text,false);
 if public.on_train_group('tackle')<>1 or public.on_train_group('dribble')<>4 or public.on_train_scale(1)<=public.on_train_scale(4)
  or public.on_train_scale(11)>=public.on_train_scale(4) then raise exception 'treinos novos';end if;
end $$;
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000004';
set role authenticated;
do $$
declare j jsonb;l bigint:=current_setting('test.lot')::bigint;v bigint;
begin
 -- identidade do clube
 j:=public.on_club_identity('{"name":"Trovão Azul","short":"tz-a","a":"#112233","pattern":"hoops","shape":"round","stadium":"Arena do Trovão"}');
 if j->'club'->>'name'<>'Trovão Azul' or j->'club'->>'short'<>'TZA' or j->'club'->'colors'->>'stadium'<>'Arena do Trovão'
  or j->'club'->'colors'->>'pattern'<>'hoops' or j->'club'->'colors'->>'a'<>'#112233' or j->'club'->'colors'->>'b' is null then raise exception 'identidade: %',j->'club';end if;
 begin perform public.on_club_identity('{"a":"red"}');raise exception 'cor inválida aceita';
 exception when others then if sqlerrm not like 'Cor inválida%' then raise;end if;end;
 begin perform public.on_club_identity('{"pattern":"xadrez"}');raise exception 'desenho inválido aceito';
 exception when others then if sqlerrm not like 'Desenho inválido%' then raise;end if;end;
 if not(j ? 'standing' and j ? 'bids' and j ? 'results' and j ? 'featured' and j ? 'form' and j ? 'coins') then raise exception 'status incompleto';end if;
 -- carta: seis atributos em todos os jogadores
 if exists(select 1 from jsonb_array_elements(public.on_squad()->'players') p cross join lateral(values('pac'),('sho'),('pas'),('dri'),('def'),('phy')) k(k)
  where coalesce((p->'card'->>k.k)::int,0) not between 20 and 99) then raise exception 'carta incompleta';end if;
 -- lance sem caixa: recusa; com moedas: cobre a diferença a 600 por moeda
 v:=(public.on_market()->'lots'->0->>'min_bid')::bigint;
 select (x->>'min_bid')::bigint into v from jsonb_array_elements(public.on_market()->'lots') x where (x->>'id')::bigint=l;
 begin perform public.on_bid(l,v);raise exception 'lance sem caixa aceito';
 exception when others then if sqlerrm not like 'Caixa livre insuficiente%' then raise;end if;end;
 j:=public.on_bid(l,v,true);
 if (j->'coins'->>'wallet')::int<>1000-ceil((v-1000)/600.0)::int then raise exception 'moedas do lance: % (lance %)',j->'coins',v;end if;
 if not exists(select 1 from jsonb_array_elements(j->'lots') x where (x->>'id')::bigint=l and (x->>'leading')::boolean and (x->>'bidding')::boolean and jsonb_array_length(x->'history')=2) then
  raise exception 'lote depois do lance';end if;
 if jsonb_array_length(public.on_status()->'bids')<1 then raise exception 'leilão em andamento fora da tela inicial';end if;
end $$;
reset role;
do $$
declare l bigint:=current_setting('test.lot')::bigint;o int:=current_setting('test.rival')::int;
begin
 if public.on_lot_settle(l,now()+interval '7 hours')<>'sold' then raise exception 'lote não fechou';end if;
 -- quem perdeu também é avisado, com o vencedor
 if not exists(select 1 from public.on_news n where n.club_id=o and n.kind='auction' and not (n.data->>'won')::boolean and n.data->'winner'->>'name'='Trovão Azul') then
  raise exception 'perdedor não avisado';end if;
end $$;
set role authenticated;
do $$
declare j jsonb;
begin
 j:=public.on_status();
 if jsonb_array_length(j->'results')<1 or not (j->'results'->0->'data'->>'won')::boolean then raise exception 'resultado do leilão: %',j->'results';end if;
 perform public.on_news_seen(array(select (x->>'id')::bigint from jsonb_array_elements(j->'results') x));
 if jsonb_array_length(public.on_status()->'results')<>0 then raise exception 'resultado não some depois de visto';end if;
 raise notice 'PASS fase 6';
end $$;
reset role;
update public.on_clubs set cash=200000 where user_id='00000000-0000-0000-0000-000000000004';
update public.on_clubs set user_id=null where user_id='00000000-0000-0000-0000-0000000000f6' and current_setting('test.rival_bot')::boolean;

-- ═════════════════════════════════════════════════════════════════════════════
-- Fase 5: copa, fim de temporada e novos técnicos (temporada sandbox inteira)
-- ═════════════════════════════════════════════════════════════════════════════
update public.on_seasons set status='closed' where status='live';
select public.on_season_bootstrap(array['00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001']::uuid[],current_date,'sandbox',interval '20 minutes',now()-interval '200 days');
do $$
declare s public.on_seasons;f public.on_fixtures;n int:=0;v_new smallint;top int[];r1 int[];coins0 int;h record;
begin
 select * into s from public.on_seasons where status='live';
 update public.on_lineups l set slots=l.slots where false;
 select coins into coins0 from public.careers where user_id='00000000-0000-0000-0000-000000000004';
 loop
  select x.* into f from public.on_fixtures x where x.season_id=s.id and x.status<>'done' order by x.kickoff,x.id limit 1;
  exit when f.id is null;
  n:=n+1;
  if n>200 then raise exception 'temporada não termina';end if;
  perform public.on_match_open(f);
  perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
  -- primeira fase da copa logo depois da rodada 5: só do 5º ao 12º
  if f.comp='L' and f.round=5 and r1 is null and exists(select 1 from public.on_fixtures where season_id=s.id and comp='C') then
   top:=array(select club_id from public.on_rank(s.id) where pos<=4);
   r1:=array(select unnest(array[home,away]) from public.on_fixtures where season_id=s.id and comp='C' and round=1);
   if cardinality(r1)<>8 or r1&&top then raise exception 'primeira fase da copa: % (top %)',r1,top;end if;
  end if;
 end loop;
 if r1 is null then raise exception 'copa não foi sorteada';end if;
 if (select count(*) from public.on_fixtures where season_id=s.id and comp='C')<>4+4+2+1 then raise exception 'jogos de copa: %',(select array_agg(round||':'||status) from public.on_fixtures where season_id=s.id and comp='C');end if;
 if exists(select 1 from public.on_fixtures where season_id=s.id and comp='C' and round=2 and (home=any(top) or away=any(top))) is not true then raise exception 'folgados fora das quartas';end if;
 if exists(select 1 from public.on_fixtures x join public.on_fixtures y on y.season_id=x.season_id and y.id<>x.id and y.kickoff=x.kickoff where x.season_id=s.id) then
  raise exception 'dois jogos no mesmo horário no sandbox';
 end if;
 -- copa: todo jogo terminou com vencedor
 if exists(select 1 from public.on_fixtures where season_id=s.id and comp='C' and hg=ag and pens is null) then raise exception 'empate sem pênaltis na copa';end if;

 -- fim da temporada
 select * into s from public.on_seasons where id=s.id;
 if s.status<>'closed' or s.champion is null or s.cup_champion is null then raise exception 'temporada não fechou: %',s;end if;
 select id into v_new from public.on_seasons where status='live';
 if v_new is null or v_new=s.id then raise exception 'nova temporada';end if;
 if (select count(*) from public.on_history where season_id=s.id)<>12 then raise exception 'histórico';end if;
 if (select count(*) from public.on_ledger where kind='prize')<12 then raise exception 'prêmios';end if;
 if (select coins from public.careers where user_id='00000000-0000-0000-0000-000000000004')<=coins0 then raise exception 'recompensa na conta';end if;
 if (select count(*) from public.on_clubs where season_id=v_new)<>12 or exists(select 1 from public.on_table where season_id=v_new and (p<>0 or pts<>0)) then
  raise exception 'tabela da nova temporada';end if;
 if (select count(*) from public.on_fixtures where season_id=v_new)<>132 then raise exception 'calendário novo';end if;
 -- fila: o usuário 9 assume o bot pior colocado, com elenco novo e escolha dos craques
 select hh.* into h from public.on_history hh join public.on_clubs k on k.id=hh.club_id where hh.season_id=s.id and k.user_id='00000000-0000-0000-0000-000000000009';
 if h.club_id is null then raise exception 'fila não entrou';end if;
 if h.user_id is not null or h.pos<>(select max(x.pos) from public.on_history x where x.season_id=s.id and x.user_id is null) then raise exception 'não ficou com o pior bot';end if;
 if (select draft_step from public.on_clubs where id=h.club_id)<>0 or (select count(*) from public.on_players where club_id=h.club_id)<>19 then raise exception 'elenco novo';end if;
 if (select state from public.on_access where user_id='00000000-0000-0000-0000-000000000009')<>'allowed' then raise exception 'acesso';end if;
 if exists(select 1 from public.on_match_events e join public.on_fixtures x on x.id=e.fixture_id where x.season_id=s.id) then raise exception 'eventos antigos';end if;
 if exists(select 1 from public.on_players p join public.on_clubs k on k.id=p.club_id and k.season_id=v_new where p.contract_end<=s.id) then raise exception 'contrato vencido ficou';end if;
 raise notice 'PASS copa e virada de temporada';
exception when others then
 declare ctx text;begin get stacked diagnostics ctx=pg_exception_context;raise exception '% | %',sqlerrm,ctx;end;
end $$;
-- quem ficou eliminado: sem erro, só "sem jogo hoje"
set request.jwt.claim.sub='00000000-0000-0000-0000-000000000009';
set role authenticated;
do $$ declare j jsonb;
begin
 j:=public.on_status();
 if j->>'access'<>'playing' or (j->'club'->>'draft_step')::int<>0 then raise exception 'novo técnico: %',j;end if;
 j:=public.on_cup();
 if jsonb_array_length(j->'history')<1 then raise exception 'histórico na copa';end if;
end $$;
reset role;
