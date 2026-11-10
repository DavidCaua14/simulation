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
