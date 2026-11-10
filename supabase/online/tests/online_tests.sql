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
declare s public.on_seasons;n int;l public.on_lots;a public.on_clubs;b public.on_clubs;bot public.on_clubs;pid text;v bigint;
begin
 select * into s from public.on_seasons where status='live';
 update public.on_lots set status='cancelled' where status='open';
 -- novo dia: 24 lotes do sistema, das 08:00 às 23:30
 perform public.on_market_tick(timestamptz '2026-11-12 03:00+00',true);
 select count(*) into n from public.on_lots where season_id=s.id and seller is null and status='open';
 if n<>24 then raise exception 'lotes do dia: %',n;end if;
 if exists(select 1 from public.on_lots where status='open' and seller is null and (ends_at-opens_at not between interval '5 minutes' and interval '10 minutes')) then
  raise exception 'duração dos lotes';end if;
 if (select count(distinct opens_at) from public.on_lots where status='open' and seller is null)<>24 then raise exception 'fins não escalonados';end if;

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
 -- lance no fim estende para pelo menos 30 s
 if (select ends_at from public.on_lots where id=l.id)<>l.ends_at-interval '5 seconds'+interval '30 seconds' then raise exception 'prorrogação de 30 s';end if;
 -- mesmo clube cobrindo o próprio lance só reserva a diferença
 perform public.on_bid_as(b.id,l.id,v+1000,l.ends_at);
 if (select reserved from public.on_clubs where id=b.id)<>v+1000 then raise exception 'reserva própria';end if;
 -- prorrogação tem teto
 for n in 1..40 loop
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
