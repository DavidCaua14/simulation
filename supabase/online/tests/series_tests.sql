-- Testes das séries (fase 35). Rodam depois de online_tests.sql, que deixa uma temporada de liga única com técnicos,
-- títulos e elencos (mesmo caminho da migração). Os resultados são marcados direto (sem o motor) para passar por todas
-- as fases em segundos; o motor de verdade fica no laboratório scripts/series-lab.mjs.

update public.on_config set tick_hooks='{}';

-- resultado de mentira: placar pelo hash, tabela como em on_match_finish e o gancho das séries
create or replace function public.t_fake(p_fx bigint) returns void language plpgsql as $$
declare f public.on_fixtures;vh int;va int;v_agg int[];
begin
 select * into f from public.on_fixtures where id=p_fx;
 vh:=floor(public.sim_hash01('h'||p_fx)*4);va:=floor(public.sim_hash01('a'||p_fx)*3);
 update public.on_fixtures set status='done',hg=vh,ag=va where id=p_fx;
 -- pênaltis: copa empatada (no agregado, na volta)
 if f.comp='C' and coalesce(f.leg,2)=2 then
  select array[coalesce(sum(case when x.home=f.home then x.hg else x.ag end),0),coalesce(sum(case when x.home=f.home then x.ag else x.hg end),0)] into v_agg
   from public.on_fixtures x where x.season_id=f.season_id and x.comp='C' and x.tie=f.tie and x.id<>f.id;
  if vh+v_agg[1]=va+v_agg[2] then update public.on_fixtures set pens='[5,4]' where id=p_fx;end if;
 end if;
 if f.comp='L' and f.tphase is not null then
  update public.on_table t set p=t.p+1,w=t.w+(x.gf>x.ga)::int,d=t.d+(x.gf=x.ga)::int,l=t.l+(x.gf<x.ga)::int,gf=t.gf+x.gf,ga=t.ga+x.ga,
   pts=t.pts+case when x.gf>x.ga then 3 when x.gf=x.ga then 1 else 0 end
  from(values(f.home,vh,va),(f.away,va,vh)) x(club,gf,ga) where t.season_id=f.season_id and t.club_id=x.club and t.phase=f.tphase;
 end if;
 perform public.on_series_hook(p_fx);
end $$;

create or replace function public.t_sizes(p smallint) returns text language sql as $$
 select string_agg(x.div||x.n,',' order by x.div) from(select div,count(*) n from public.on_clubs where season_id=p group by div) x $$;

do $$
declare v_s smallint;n int;users int;h0 int;
begin
 h0:=(select count(*) from public.on_honors);
 users:=(select count(*) from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live' where k.user_id is not null);
 v_s:=public.on_series_bootstrap(date '2026-12-01');
 if public.t_sizes(v_s)<>'A20,B20,C24,D30' then
  raise exception 'tamanhos: %',public.t_sizes(v_s);
 end if;
 if (select count(*) from public.on_clubs where season_id=v_s and div='D' and user_id is not null)<>users then raise exception 'técnicos fora da D';end if;
 if (select count(*) from public.on_fixtures where season_id=v_s)<>380+380+276+420+30 then raise exception 'jogos: %',(select count(*) from public.on_fixtures where season_id=v_s);end if;
 -- fase 39: cada jogo num horário só dele, das 08:00 às 21:30 e nunca entre 17:00 e 18:40
 if exists(select 1 from public.on_fixtures where season_id=v_s and ((kickoff at time zone 'America/Sao_Paulo')::time<'08:00' or (kickoff at time zone 'America/Sao_Paulo')::time>'21:30'
   or (kickoff at time zone 'America/Sao_Paulo')::time>='17:00' and (kickoff at time zone 'America/Sao_Paulo')::time<'18:40')) then
  raise exception 'jogo fora da janela 08:00–21:30 (ou entre 17:00 e 18:40)';
 end if;
 if exists(select 1 from public.on_fixtures where season_id=v_s group by kickoff having count(*)>1) then
  raise exception 'dois jogos no mesmo horário: %',(select kickoff from public.on_fixtures where season_id=v_s group by kickoff having count(*)>1 limit 1);
 end if;
 -- manhã antes das 14:00, tarde depois; descanso entre os dois jogos do dia de pelo menos 3 horas para todo clube
 if exists(select 1 from public.on_fixtures where season_id=v_s and (slot%2=0)<>((kickoff at time zone 'America/Sao_Paulo')::time<'14:00')) then raise exception 'jogo no turno errado';end if;
 if (select min(b.kickoff-a.kickoff) from public.on_fixtures a join public.on_fixtures b on b.season_id=a.season_id and b.slot=a.slot+1 and a.slot%2=0
   and (b.home in(a.home,a.away) or b.away in(a.home,a.away)) where a.season_id=v_s)<interval '3 hours' then
  raise exception 'descanso curto entre jogos do dia: %',(select min(b.kickoff-a.kickoff) from public.on_fixtures a join public.on_fixtures b on b.season_id=a.season_id and b.slot=a.slot+1 and a.slot%2=0
   and (b.home in(a.home,a.away) or b.away in(a.home,a.away)) where a.season_id=v_s);
 end if;
 -- Série A em cartas de destaque
 if not exists(select 1 from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=v_s and k.div='A' and k.user_id is null and p.tier='destaque')
  or exists(select 1 from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=v_s and k.div<>'A' and k.user_id is null and p.tier='destaque') then
  raise exception 'cartas de destaque fora da Série A (ou faltando nela)';
 end if;
 -- bots no nível máximo da carta
 if exists(select 1 from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=v_s and k.user_id is null and p.ovr<greatest(p.pot,p.level)) then
  raise exception 'bot abaixo do nível máximo';
 end if;
 if exists(select 1 from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(c) where season_id=v_s group by v.c,f.slot having count(*)>1) then
  raise exception 'clube duas vezes no mesmo turno';
 end if;
 -- segunda chamada do sorteio da copa não duplica
 if public.on_cup_draw(v_s,1,'{}')<>0 then raise exception 'copa sorteada de novo';end if;
 -- elencos reais da C e da D (fase 37): clube com elenco na fonte entra com os jogadores dela
 if exists(select 1 from public.on_clubs k where k.season_id=v_s and k.user_id is null and k.real_key in(select club_key from public.on_lower_players) and k.sq<>'real') then
  raise exception 'clube com elenco real ficou com cartas geradas';
 end if;
 if (select count(*) from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=v_s and k.sq='real'
   and p.name in(select l.name from public.on_lower_players l where l.club_key=k.real_key))<18*(select count(*) from public.on_clubs where season_id=v_s and sq='real') then
  raise exception 'elenco real incompleto';
 end if;
 raise notice 'PASS séries: estrutura e calendário';

 -- temporada inteira com resultados de mentira (as fases seguintes nascem no gancho)
 for n in 1..4000 loop
  perform public.t_fake(f.id) from(select id from public.on_fixtures where season_id=v_s and status<>'done' order by kickoff,id limit 1) f;
  exit when (select status from public.on_seasons where id=v_s)<>'live';
 end loop;
 if (select status from public.on_seasons where id=v_s)<>'closed' then raise exception 'temporada não fechou (% jogos abertos)',(select count(*) from public.on_fixtures where season_id=v_s and status<>'done');end if;
 -- fases: B playoff (4 jogos), C quadrangulares (24) e final (2), D quartas (8), semi (4), final (2); copa 30+32+16+16+8+4+2
 if (select count(*) from public.on_fixtures where season_id=v_s and div='B' and stage='po')<>4 then raise exception 'playoff da B';end if;
 if (select count(*) from public.on_fixtures where season_id=v_s and div='C' and tphase=2)<>24 then raise exception 'quadrangulares da C';end if;
 if (select count(*) from public.on_fixtures where season_id=v_s and div='C' and stage='final')<>2 then raise exception 'final da C';end if;
 if (select string_agg(x.stage||x.n,',' order by x.stage) from(select stage,count(*) n from public.on_fixtures where season_id=v_s and div='D' and tie is not null group by stage) x)
  is distinct from 'final2,qf8,sf4' then raise exception 'mata-mata da D';end if;
 if (select count(*) from public.on_fixtures where season_id=v_s and comp='C')<>30+32+16+16+8+4+2 then
  raise exception 'copa: %',(select string_agg(x.stage||x.n,',') from(select stage,count(*) n from public.on_fixtures where season_id=v_s and comp='C' group by stage) x);
 end if;
 if (select count(*) from public.on_history where season_id=v_s and cup='champion')<>1 then raise exception 'campeão da copa';end if;
 -- acesso e rebaixamento
 if (select count(*) from public.on_history where season_id=v_s and result='relegated')<>12 then raise exception 'rebaixados';end if;
 if (select count(*) from public.on_history where season_id=v_s and result in('promoted','champion') and div<>'A')<>12 then raise exception 'promovidos';end if;
 if (select count(*) from public.on_history where season_id=v_s and result='champion')<>4 then raise exception 'campeões';end if;
 if (select count(*) from public.on_history where season_id=v_s and div='D' and result in('promoted','champion'))<>4 then raise exception 'acesso da D';end if;
 -- insígnias só para técnicos campeões; bots não ganham
 if exists(select 1 from public.on_honors h join public.on_clubs k on k.id=h.club_id where k.user_id is null) then raise exception 'bot com insígnia';end if;
 if (select count(*) from public.on_honors)<h0 then raise exception 'insígnias antigas sumiram';end if;
 raise notice 'PASS séries: temporada inteira, fases, copa, acesso e rebaixamento';

 -- virada: tamanhos mantidos, 24 clubes trocaram de série, bots com o elenco da série nova, copa sorteada
 select id into v_s from public.on_seasons where status='live';
 if public.t_sizes(v_s)<>'A20,B20,C24,D30' then raise exception 'tamanhos da nova temporada';end if;
 if (select count(*) from public.on_clubs k join public.on_history h on h.club_id=k.id and h.season_id=v_s-1 where k.season_id=v_s and k.div<>h.div)<>24 then
  raise exception 'clubes que mudaram de série';
 end if;
 if exists(select 1 from public.on_clubs where season_id=v_s and user_id is null and sq='star' and div<>'A') then raise exception 'destaque fora da A';end if;
 if (select count(*) from public.on_fixtures where season_id=v_s and comp='C')<>30 then raise exception 'copa nova';end if;
 if exists(select 1 from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=v_s and (p.susp<>'{}' or p.ylw<>'{}')) then raise exception 'suspensão não zerou';end if;
 raise notice 'PASS séries: virada da temporada';
end $$;

-- suspensão por competição: vermelho tira 1 jogo; 2 amarelos acumulados também; quem cumpriu desconta
do $$
declare s public.on_seasons;f public.on_fixtures;k int;p1 text;p2 text;p3 text;
begin
 select * into s from public.on_seasons where status='live';
 select * into f from public.on_fixtures where season_id=s.id and comp='L' and status='sched' order by kickoff limit 1;
 k:=f.home;
 perform public.on_match_open(f);
 select player_id into p1 from public.on_match_players where fixture_id=f.id and club_id=k and status='on' and pos<>'GOL' order by player_id limit 1;
 select player_id into p2 from public.on_match_players where fixture_id=f.id and club_id=k and status='on' and pos<>'GOL' and player_id<>p1 order by player_id limit 1;
 update public.on_players set ylw='{"L":1}' where id=p2;
 update public.on_match_players set red=1,status='sent_off',slot=null,left_min=30 where fixture_id=f.id and player_id=p1;
 update public.on_match_players set yellow=1 where fixture_id=f.id and player_id=p2;
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 if (select status from public.on_fixtures where id=f.id)<>'done' then raise exception 'jogo não terminou';end if;
 if (select (susp->>'L')::int from public.on_players where id=p1)<>1 then raise exception 'vermelho não suspendeu';end if;
 if (select (susp->>'L')::int from public.on_players where id=p2)<>1 or (select (ylw->>'L')::int from public.on_players where id=p2)<>0 then
  raise exception '2º amarelo não suspendeu: %',(select susp||ylw from public.on_players where id=p2);
 end if;
 if exists(select 1 from public.on_players where id=p1 and coalesce((susp->>'C')::int,0)>0) then raise exception 'suspensão vazou para a copa';end if;
 -- próximo jogo de liga do clube: os dois ficam fora e depois voltam
 select * into f from public.on_fixtures where season_id=s.id and comp='L' and status='sched' and k in(home,away) order by kickoff limit 1;
 if public.on_can_play((select p from public.on_players p where id=p1),k,f) then raise exception 'suspenso pode jogar';end if;
 perform public.on_match_open(f);
 if exists(select 1 from public.on_match_players where fixture_id=f.id and player_id in(p1,p2)) then raise exception 'suspenso relacionado';end if;
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 if (select (susp->>'L')::int from public.on_players where id=p1)<>0 or (select (susp->>'L')::int from public.on_players where id=p2)<>0 then raise exception 'suspensão não foi cumprida';end if;
 raise notice 'PASS séries: suspensão por competição';
end $$;

-- pênaltis lance a lance (fase 36): jogo de copa empatado no apito final
do $$
declare f public.on_fixtures;m public.on_matches;n int;
begin
 select * into f from public.on_fixtures x where x.season_id=(select id from public.on_seasons where status='live') and x.comp='C' and x.leg is null and x.status='sched' order by kickoff limit 1;
 perform public.on_match_open(f);
 perform public.on_advance(f.id,f.kickoff+interval '700 seconds','h');
 update public.on_matches set state=jsonb_set(state,'{score}',jsonb_build_array(1,1)) where fixture_id=f.id;
 perform public.on_advance(f.id,f.kickoff+interval '730 seconds','h');
 select * into m from public.on_matches where fixture_id=f.id;
 if m.status<>'live' or m.state->'so' is null then raise exception 'disputa não começou: % %',m.status,m.state->'so';end if;
 if exists(select 1 from public.on_match_events where fixture_id=f.id and kind in('ft','so_ready')) then raise exception 'pênaltis saíram de uma vez';end if;
 perform public.on_advance(f.id,f.kickoff+interval '790 seconds','h');
 select count(*) into n from public.on_match_events where fixture_id=f.id and kind='so_ready';
 if n<>3 then raise exception 'cobranças até 790 s: %',n;end if;
 if exists(select 1 from public.on_match_events where fixture_id=f.id and kind like 'so_%' and kind<>'so_start' and at_s is null) then raise exception 'lance sem segundo';end if;
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 select * into m from public.on_matches where fixture_id=f.id;
 select * into f from public.on_fixtures where id=f.id;
 if m.status<>'finished' or f.pens is null then raise exception 'disputa não terminou';end if;
 if (f.pens->>0)::int=(f.pens->>1)::int then raise exception 'pênaltis empatados';end if;
 if (f.pens->>0)::int<>(select count(*) from public.on_match_events where fixture_id=f.id and kind='so_goal' and side='h') then raise exception 'placar dos pênaltis não bate com os lances';end if;
 if (select count(*) from public.on_match_events where fixture_id=f.id and kind='so_ready')<>(select count(*) from public.on_match_events where fixture_id=f.id and kind in('so_goal','so_save','so_miss')) then
  raise exception 'cobrança sem resultado';
 end if;
 raise notice 'PASS pênaltis lance a lance (% x %)',f.pens->>0,f.pens->>1;
end $$;

-- taxa de conversão do modelo: batedor 70 contra goleiro 70, descansado, sem pressão ≈ 72% a 78%
do $$
declare o jsonb:=public.on_pen_odds(70,70,70,100,false,70,false,false);v numeric;
begin
 v:=(o->>'aim')::numeric*(1-(o->>'save')::numeric*1.11);
 if v not between .72 and .80 then raise exception 'conversão média fora do real: %',v;end if;
 if (public.on_pen_odds(70,70,70,45,false,70,false,true)->>'aim')::numeric>=(o->>'aim')::numeric then raise exception 'cansaço e pressão não pesam';end if;
 if (public.on_pen_odds(70,70,70,100,false,85,true,false)->>'save')::numeric<=(o->>'save')::numeric then raise exception 'goleiro bom não pesa';end if;
 raise notice 'PASS chances da cobrança (média %)',round(v,3);
end $$;

-- escudos oficiais (fase 38): todo bot de clube real tem escudo; clube de técnico não
do $$ begin
 if exists(select 1 from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live'
  where k.user_id is null and k.real_key is not null and k.colors->>'crest' is null) then raise exception 'bot sem escudo oficial';end if;
 if exists(select 1 from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live'
  where k.user_id is not null and k.colors ? 'crest') then raise exception 'clube de técnico com escudo oficial';end if;
 raise notice 'PASS escudos oficiais';
end $$;

-- leituras do app como técnico (pega nome de variável que colide com coluna, ex.: "d" de empates)
do $$
declare u uuid;x text;
begin
 select k.user_id into u from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live' where k.user_id is not null limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);
 foreach x in array array['A','B','C','D'] loop
  perform public.on_standings(x);perform public.on_standings(x);perform public.on_round(x,null);perform public.on_round(x,1);
 end loop;
 perform public.on_standings(null);perform public.on_calendar();perform public.on_cup();perform public.on_status();
 raise notice 'PASS leituras do app';
end $$;

-- fase 39: funções (ordem de pênaltis, escanteio por lado) e herança na substituição
do $$
declare st jsonb;r jsonb;u uuid;k public.on_clubs;ids text[];
begin
 r:=public.on_roles_norm('{"pen":"p1","ck":"p2","captain":"p3"}');
 if r->'pen'<>'["p1"]' or r->>'ck_r'<>'p2' or r->>'ck_l'<>'p2' or r ? 'ck' then raise exception 'funções antigas: %',r;end if;
 if public.on_roles_remap('{"pen":["a","b"],"fk":"a","ck_r":"c"}','[{"slot":"ATA","out":"a","in":"z"}]')<>'{"pen":["z","b"],"fk":"z","ck_r":"c"}' then
  raise exception 'pontapé não passou a função: %',public.on_roles_remap('{"pen":["a","b"],"fk":"a","ck_r":"c"}','[{"slot":"ATA","out":"a","in":"z"}]');
 end if;
 st:=public.on_roles_inherit('{"pen_taker":{"h":"a"},"pen_order":{"h":["a","b"],"a":["a2"]},"ck_r":{"h":"a","a":"x"},"ck_l":{"h":"b"},"captain":{"h":"a"},
   "fk_taker":{"h":"c"},"tactics":{"h":{"marks":[{"by":"a","on":"o1"}]},"a":{"marks":[{"by":"o2","on":"a"}]}}}','h','a','n');
 if st->'pen_order'->'h'<>'["n","b"]' or st->'pen_taker'->>'h'<>'n' or st->'ck_r'->>'h'<>'n' or st->'ck_l'->>'h'<>'b' or st->'captain'->>'h'<>'n'
  or st->'fk_taker'->>'h'<>'c' or st->'tactics'->'h'->'marks'->0->>'by'<>'n' or st->'tactics'->'a'->'marks'->0->>'on'<>'n' or st->'pen_order'->'a'<>'["a2"]' then
  raise exception 'herança na substituição: %',st;
 end if;
 -- salvar: ordem com repetido ou jogador de fora é recusada
 select c.* into k from public.on_clubs c join public.on_seasons s on s.id=c.season_id and s.status='live' where c.user_id is not null
  and exists(select 1 from public.on_lineups l where l.club_id=c.id) order by (select count(*) from public.on_players p where p.club_id=c.id) desc,c.id limit 1;
 perform set_config('request.jwt.claim.sub',k.user_id::text,true);
 ids:=array(select id from public.on_players where club_id=k.id order by ovr desc limit 3);
 perform public.on_roles_save(jsonb_build_object('pen',to_jsonb(ids),'ck_r',ids[1],'ck_l',ids[2],'fk',ids[3]));
 if (select roles->'pen' from public.on_lineups where club_id=k.id)<>to_jsonb(ids) then raise exception 'ordem dos pênaltis não salva';end if;
 begin perform public.on_roles_save(jsonb_build_object('pen',jsonb_build_array(ids[1],ids[1])));raise exception 'aceitou repetido';
 exception when others then if sqlerrm='aceitou repetido' then raise;end if;end;
 begin perform public.on_roles_save('{"ck_r":"nao-existe"}');raise exception 'aceitou de fora';
 exception when others then if sqlerrm='aceitou de fora' then raise;end if;end;
 raise notice 'PASS funções e herança';
end $$;

-- fase 39: elenco curto no pontapé — suspenso nunca entra (o time joga com menos gente)
do $$
declare k int;f public.on_fixtures;j jsonb;
begin
 select c.id into k from public.on_clubs c join public.on_seasons s on s.id=c.season_id and s.status='live' where c.user_id is null order by c.id limit 1;
 select * into f from public.on_fixtures where comp='L' and k in(home,away) and status<>'done' order by kickoff limit 1;
 update public.on_players set susp=jsonb_build_object('L',1) where club_id=k and id not in(select id from public.on_players where club_id=k order by ovr desc limit 8);
 j:=public.on_kickoff_lineup(k,f);
 if exists(select 1 from jsonb_each_text(j->'slots') e join public.on_players p on p.id=e.value where (p.susp->>'L')::int>0) then raise exception 'suspenso escalado: %',j->'slots';end if;
 if (select count(*) from jsonb_object_keys(j->'slots'))<>8 then raise exception 'esperava 8 titulares: %',j->'slots';end if;
 update public.on_players set susp='{}' where club_id=k;
 raise notice 'PASS suspenso fora mesmo com elenco curto';
end $$;
