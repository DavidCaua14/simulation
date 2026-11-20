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
declare v_s smallint;n int;users int;h0 int;early boolean;
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
 -- todo bot com pelo menos 2 goleiros (fase 40)
 if exists(select 1 from public.on_clubs k where k.season_id=v_s and k.user_id is null and (select count(*) from public.on_players p where p.club_id=k.id and p.pos='GOL')<2) then
  raise exception 'bot com menos de 2 goleiros';
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
  -- fase 40: série que termina é paga na hora (antes do fim da temporada)
  if (select status from public.on_seasons where id=v_s)='live' and cardinality((select div_paid from public.on_seasons where id=v_s))>0 then early:=true;end if;
  exit when (select status from public.on_seasons where id=v_s)<>'live';
 end loop;
 if not coalesce(early,false) then raise exception 'nenhuma série foi paga antes do fim da temporada';end if;
 if (select array(select unnest(div_paid) order by 1) from public.on_seasons where id=v_s)<>array['A','B','C','D'] then
  raise exception 'séries pagas: %',(select div_paid from public.on_seasons where id=v_s);
 end if;
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

-- fase 40: prêmios das séries (dinheiro pelo peso, resto pela raiz, acesso e rebaixamento)
do $$
declare a jsonb:=public.on_league_prize('A',1,'champion');d jsonb:=public.on_league_prize('D',1,'champion');
 up jsonb:=public.on_league_prize('D',3,'promoted');down jsonb:=public.on_league_prize('A',20,'relegated');mid jsonb:=public.on_league_prize('B',10,null);
begin
 if (a->>'cash')::bigint<>5000000 or (a->>'bonus')::bigint<>0 then raise exception 'campeão da A: %',a;end if;
 if (d->>'cash')::bigint<>1250000+800000 or (d->>'diamonds')::int<>150 then raise exception 'campeão da D: %',d;end if;
 if (up->>'bonus')::bigint<>800000 then raise exception 'acesso da D: %',up;end if;
 if (down->>'bonus')::bigint<>1250000 then raise exception 'rebaixado da A: %',down;end if;
 if (mid->>'bonus')::bigint<>0 then raise exception 'meio da tabela: %',mid;end if;
 raise notice 'PASS prêmios das séries';
end $$;

-- fase 40: "já vi" por conta e ficha de jogador em leilão
do $$
declare u uuid;l public.on_lots;
begin
 select k.user_id into u from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live' where k.user_id is not null limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);
 if public.ui_seen_bump('t:festa') is not null then raise exception 'primeira vez deveria ser nula';end if;
 if public.ui_seen_bump('t:festa') is distinct from 1 then raise exception 'segunda vez (outro aparelho) deveria ver 1';end if;
 if public.ui_seen_bump('level',7) is not null or public.ui_seen_bump('level',9)<>7 or public.ui_seen_bump('level',8)<>9 then raise exception 'nível não só sobe';end if;
 if public.ui_seen_get(array['level','t:festa','x'])<>'{"level":9,"t:festa":1}'::jsonb then raise exception 'leitura: %',public.ui_seen_get(array['level','t:festa','x']);end if;
 select * into l from public.on_lots where status='open' limit 1;
 if l.id is not null and (public.on_player_sheet(l.player_id)->>'id')<>l.player_id then raise exception 'ficha do leilão';end if;
 raise notice 'PASS já vi por conta e ficha do mercado';
end $$;

-- fase 41: cópias (uma por clube), quarentena e limite por temporada; bots que compram
do $$
declare s public.on_seasons;a public.on_clubs;b public.on_clubs;k int;v_src text;pid text;lot bigint;r public.on_lots;v bigint;ok boolean;
begin
 select * into s from public.on_seasons where status='live';
 select * into a from public.on_clubs where season_id=s.id and user_id is not null order by id limit 1;
 -- jogador base do catálogo colocado num bot: pode virar nova cópia no mercado
 select * into b from public.on_clubs where season_id=s.id and user_id is null order by id limit 1;
 select q.id into v_src from public.on_pool q where not q.legend and q.rating<81
  and not exists(select 1 from public.on_players o where o.src=q.id) order by q.id limit 1;
 perform public.on_real_insert(v_src,b.id,99,s.id+1);
 if not public.on_src_free(v_src,false,70) then raise exception 'jogador com dono deveria poder ter nova cópia';end if;
 pid:=public.on_real_insert(v_src,null,null,s.id+1);
 if public.on_src_free(v_src,false,70) then raise exception 'duas cópias livres ao mesmo tempo';end if;
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end) values(s.id,pid,500,now(),now()+interval '1 hour',now()+interval '2 hours') returning id into lot;
 -- o dono não dá lance na própria cópia; bot dono também não quer
 begin perform public.on_bid_as(b.id,lot,500,now());raise exception 'clube com o jogador deu lance';
 exception when others then if sqlerrm not like 'Você já tem esse jogador%' and sqlerrm not like 'Caixa livre%' then raise;end if;end;
 if public.on_bot_limit(b.id,lot,pid)<>0 then raise exception 'bot que já tem o jogador quer outra cópia';end if;
 -- técnico compra: vira registro da quarentena (7 dias para base)
 update public.on_clubs set cash=greatest(cash,10000000),reserved=0,debt=0 where id=a.id;
 delete from public.on_players where club_id=a.id and src=v_src;
 perform public.on_bid_as(a.id,lot,1000,now());
 update public.on_lots set ends_at=now()-interval '1 second' where id=lot;
 perform public.on_lot_settle(lot,now());
 if (select club_id from public.on_players where id=pid)<>a.id then raise exception 'cópia não foi para o comprador';end if;
 if not exists(select 1 from public.on_src_log where src=v_src and club_id=a.id) then raise exception 'compra sem registro';end if;
 if exists(select 1 from public.on_players o where o.src=v_src and o.club_id=b.id)=false then raise exception 'cópia do bot sumiu';end if;
 if public.on_src_free(v_src,false,70) then raise exception 'base voltou antes de 7 dias';end if;
 perform set_config('on.now',(now()+interval '7 days 1 minute')::text,true);
 if not public.on_src_free(v_src,false,70) then raise exception 'base não voltou depois de 7 dias';end if;
 if public.on_src_free(v_src,false,85) then raise exception 'destaque voltou antes de 14 dias';end if;
 perform set_config('on.now',(now()+interval '14 days 1 minute')::text,true);
 if not public.on_src_free(v_src,false,85) then raise exception 'destaque não voltou depois de 14 dias';end if;
 -- limite de cópias de lenda por temporada (3)
 insert into public.on_src_log(src,club_id,season_id,at) select 'lg-teste',a.id,s.id,now()-interval '60 days' from generate_series(1,3);
 perform set_config('on.now',(now()+interval '30 days')::text,true);
 if public.on_src_free('lg-teste',true,90) then raise exception 'lenda passou de 3 cópias';end if;
 delete from public.on_src_log where src='lg-teste';
 if not public.on_src_free('lg-teste',true,90) then raise exception 'lenda sem cópias deveria voltar';end if;
 perform set_config('on.now','',true);
 -- montagem de elenco (fora do mercado) continua sem repetir dono
 if public.on_real_pick(null,0,200,'x'||v_src) in(select src from public.on_players where src is not null and club_id is not null) then raise exception 'elenco novo pegou jogador com dono';end if;
 -- destaque: bot rico com teto acima do lance inicial; bot sem caixa fora
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end) values(null,'Destaque Teste','ATA',26,86,86,86,10,s.id+1) returning id into pid;
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured) values(s.id,pid,600000,now(),now()+interval '1 hour',now()+interval '2 hours',9) returning id into lot;
 select bool_or(public.on_bot_limit(c.id,lot,pid)>=public.on_start_price(p)) into ok
  from public.on_clubs c,public.on_players p where p.id=pid and c.season_id=s.id and c.user_id is null and c.cash>=5000000;
 update public.on_clubs set cash=10000000 where id=b.id;
 if exists(select 1 from public.on_clubs c where c.season_id=s.id and c.user_id is null and public.on_bot_limit(c.id,lot,pid)>(c.cash-c.reserved)*.4+1) then raise exception 'bot passou de 40%% do caixa';end if;
 delete from public.on_players where id=pid;
 raise notice 'PASS cópias, quarentena e teto dos bots (destaque com bot interessado: %)',coalesce(ok,false);
end $$;

-- fase 41: dia de mercado agitado — relâmpago no horário, setores cheios, bots dando lance e anunciando
do $$
declare s public.on_seasons;t timestamptz;n int;day0 timestamptz:=date_trunc('day',now()+interval '3 days')+interval '11 hours';
begin
 select * into s from public.on_seasons where status='live';
 update public.on_config set market_open=8,market_close=18,market_close_min=30,flash_per_day=3;
 for n in 0..62 loop
  t:=day0+n*interval '10 minutes';
  perform public.on_market_buzz(t,false);
 end loop;
 if (select count(*) from public.on_lots where flash_key like to_char(day0 at time zone 'America/Sao_Paulo','YYYYMMDD')||':%')<>3 then
  raise exception 'relâmpagos do dia: %',(select count(*) from public.on_lots where flash_key like to_char(day0 at time zone 'America/Sao_Paulo','YYYYMMDD')||':%');end if;
 if exists(select 1 from public.on_lots l join public.on_players p on p.id=l.player_id where l.featured=7
   and l.start_price>round(public.on_start_price(p)*.7)+1) then raise exception 'relâmpago sem desconto';end if;
 if exists(select 1 from public.on_lots where featured=7 and ends_at-opens_at>interval '30 minutes') then raise exception 'relâmpago longo';end if;
 if not exists(select 1 from public.on_news where text like 'Promoção relâmpago%') then raise exception 'sem aviso do relâmpago';end if;
 if exists(select 1 from(values('{GOL}'::text[],1),('{LD,ZAG,LE}',2),('{VOL,MC,MEI}',2),('{PD,PE,ATA}',2)) g(ps,k)
   where(select count(*) from public.on_lots x join public.on_players q on q.id=x.player_id where x.status='open' and q.pos=any(g.ps))<g.k) then
  raise exception 'setor sem lote';end if;
 if exists(select 1 from public.on_players p join public.on_lots l on l.player_id=p.id and l.status='open' where p.club_id is null
   group by p.src having p.src is not null and count(*)>1) then raise exception 'duas cópias livres no mercado';end if;
 if exists(select club_id,src from public.on_players where club_id is not null and src is not null group by 1,2 having count(*)>1) then raise exception 'clube com duas cópias';end if;
 update public.on_config set market_open=0,market_close=24,market_close_min=0;
 raise notice 'PASS dia agitado (% lances de bots)',(select count(*) from public.on_bids b join public.on_clubs c on c.id=b.club_id where c.user_id is null);
end $$;

-- fase 42: Big Time — cadastro no painel, caixa sem reposição, carta vermelha no elenco
do $$
declare s public.on_seasons;u uuid;c public.on_clubs;bt jsonb;bt2 jsonb;pk jsonb;r jsonb;n int;p public.on_players;d0 int;sk numeric[];
begin
 select * into s from public.on_seasons where status='live';
 select * into c from public.on_clubs where season_id=s.id and user_id is not null order by id limit 1;
 u:=c.user_id;
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform set_config('request.jwt.claims','{"email":"contatodavidcaua@gmail.com"}',true);
 insert into public.admins(user_id) values(u) on conflict do nothing;
 if not exists(select 1 from public.careers where user_id=u) then insert into public.careers(user_id,nickname) values(u,'bt-'||left(u::text,8));end if;
 update public.careers set diamonds=5000 where user_id=u;
 -- painel
 begin perform public.admin_bt_save('{"name":"Fraco","pos":"ATA","rating":104,"match_date":"2005-11-19","opponent":"X"}');raise exception 'overall 104 aceito';
 exception when others then if sqlerrm not like 'Overall máximo entre%' then raise;end if;end;
 bt:=public.admin_bt_save(jsonb_build_object('name','Ronaldinho','pos','PE','sec',jsonb_build_array('MEI','PD'),'rating',108,'age',25,
  'match_date','2005-11-19','opponent','Real Madrid','team','Barcelona','competition','La Liga','score','3 x 0',
  'story','Aplaudido de pé no Bernabéu.','photo','https://exemplo/r10.jpg','traits',jsonb_build_array('drible','finalizacao'),'style_off','x'));
 bt2:=public.admin_bt_save(jsonb_build_object('name','Romário','pos','ATA','rating',107,'age',27,'match_date','1993-09-19','opponent','Uruguai','team','Brasil'));
 if (bt->>'year')::int<>2005 or bt->'skills'->>0 is null then raise exception 'carta: %',bt;end if;
 pk:=public.admin_pack_save(jsonb_build_object('title','Big Time da semana','price',100,'starts_at',now()-interval '1 hour','ends_at',now()+interval '7 days',
  'items',jsonb_build_array(jsonb_build_object('kind','bigtime','ref',bt->>'id'),jsonb_build_object('kind','bigtime','ref',bt2->>'id'),
   jsonb_build_object('kind','player','src',(select q.id from public.on_pool q where not q.legend and q.rating<75
     and not exists(select 1 from public.on_players o where o.src=q.id and o.club_id=c.id) order by q.id limit 1)),
   jsonb_build_object('kind','energy','qty',5,'balls',2),jsonb_build_object('kind','coins','qty',300,'balls',1))));
 if (pk->>'total')::int<>6 then raise exception 'caixa: %',pk;end if;
 if (select count(*) from public.on_players where club_id=c.id)<28 then
  insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end) select c.id,'Extra '||g,'MC',25,60,60,60,10,s.id+1 from generate_series(1,30-(select count(*)::int from public.on_players where club_id=c.id)) g;
 end if;
 -- loja
 r:=public.online_packs();
 if not (r->>'enabled')::boolean or jsonb_array_length(r->'packs')<1 then raise exception 'loja: %',r;end if;
 -- o técnico vê quantos itens existem (energia, moedas...), mas não o total da caixa nem as chances das cartas
 if (r->'packs'->0->>'total') is not null or r::text not like '%"balls": 2%'
  or exists(select 1 from jsonb_array_elements(r->'packs'->0->'items') x where x->>'kind' in('bigtime','player') and x->>'balls' is not null)
  then raise exception 'loja mostra quantidades: %',r;end if;
 d0:=(select diamonds from public.careers where user_id=u order by created_at desc limit 1);
 for n in 1..6 loop r:=public.online_pack_draw((pk->>'id')::bigint);end loop; -- elenco com 30+: sem limite
 if (select diamonds from public.careers where user_id=u order by created_at desc limit 1)<>d0-600 then raise exception 'diamantes cobrados errado';end if;
 if not (r->'store'->'packs'->0->>'empty')::boolean then raise exception 'caixa deveria estar vazia';end if;
 begin perform public.online_pack_draw((pk->>'id')::bigint);raise exception 'caixa vazia deu prêmio';
 exception when others then if sqlerrm not like 'Você já tirou tudo%' then raise;end if;end;
 -- as duas cartas estão no elenco, vermelhas, regularidade B, atributos acima de 99
 if (select count(*) from public.on_players where club_id=c.id and tier='bigtime')<>2 then raise exception 'cartas no elenco';end if;
 select * into p from public.on_players where club_id=c.id and src=bt->>'id';
 -- chega no overall inicial (máximo − 10) e treina até o máximo
 if p.form<>'B' or p.ovr<>98 or p.pot<>108 or p.legend or not ('drible'=any(p.traits)) then raise exception 'carta no elenco: % % % %',p.form,p.ovr,p.pot,p.traits;end if;
 if (select max(x) from unnest(public.on_comp_skill(p)) x)>99 then raise exception 'carta sem treino passou de 99';end if;
 update public.on_players set g='{6,6,6,6}',ovr=public.on_ovr(level,pot,'{6,6,6,6}') where id=p.id returning * into p;
 if p.ovr<>108 then raise exception 'treino não leva ao máximo: %',p.ovr;end if;
 sk:=public.on_comp_skill(p);
 if (select max(x) from unnest(sk) x)<=99 or (select max(x) from unnest(sk) x)>99+(108-99)*.7+.01 then raise exception 'atributos: %',sk;end if;
 if (public.on_sheet(p)->'attrs'->0->>'value')::int is null or not exists(select 1 from jsonb_array_elements(public.on_sheet(p)->'attrs') a where (a->>'value')::int>99) then raise exception 'ficha sem valor acima de 99';end if;
 if (select x->'bt'->>'opponent' from jsonb_array_elements(public.on_squad()->'players') x where x->>'id'=p.id)<>'Real Madrid' then raise exception 'elenco sem dados da atuação';end if;
 if public.on_player_sheet(p.id)->'bt'->>'team'<>'Barcelona' then raise exception 'ficha sem a atuação';end if;
 -- não sai do clube
 begin perform public.on_sell(p.id);raise exception 'vendeu Big Time';exception when others then if sqlerrm not like 'Cartas Big Time%' and sqlerrm not like 'Elenco com 16%' then raise;end if;end;
 begin perform public.on_lot_create(p.id,1000000);raise exception 'leiloou Big Time';exception when others then if sqlerrm not like 'Cartas Big Time%' and sqlerrm not like 'Mercado fechado%' and sqlerrm not like 'Elenco com 16%' then raise;end if;end;
 if public.on_bot_limit((select id from public.on_clubs where season_id=s.id and user_id is null limit 1),0,p.id)<>0 then raise exception 'bot quer Big Time';end if;
 -- nova caixa com a mesma carta: quem já tem não tira de novo
 pk:=public.admin_pack_save(jsonb_build_object('title','Repeteco','price',50,'starts_at',now()-interval '30 minutes','ends_at',now()+interval '1 day',
  'items',jsonb_build_array(jsonb_build_object('kind','bigtime','ref',bt->>'id'),jsonb_build_object('kind','cash','qty',1000))));
 r:=public.online_packs();
 if not exists(select 1 from jsonb_array_elements(r->'packs') x,jsonb_array_elements(x->'items') i where x->>'id'=pk->>'id' and i->>'kind'='bigtime' and (i->>'got')::boolean) then raise exception 'carta já tirada não aparece como sua';end if;
 -- a caixa nova tirou a anterior da loja
 if jsonb_array_length(r->'packs')<>1 then raise exception 'caixa anterior continua na loja';end if;
 r:=public.online_pack_draw((pk->>'id')::bigint);
 if r->'prize'->>'kind'<>'cash' then raise exception 'tirou repetida: %',r->'prize';end if;
 -- edição no painel chega na carta entregue
 perform public.admin_bt_save(bt||jsonb_build_object('rating',110,'traits',jsonb_build_array('drible')));
 if (select pot from public.on_players where id=p.id)<>110 then raise exception 'edição não chegou ao elenco';end if;
 -- aviso de caixa nova (uma vez, com o nome do técnico)
 perform public.on_pack_notify(now(),false);
 perform public.on_pack_notify(now(),false);
 if (select count(*) from public.player_notices x join public.careers k on k.id=x.career_id where k.user_id=u and x.title like 'Big Time%')<>1 then raise exception 'aviso da caixa';end if;
 if not exists(select 1 from public.player_notices x join public.careers k on k.id=x.career_id where k.user_id=u and x.body like k.nickname||',%') then raise exception 'aviso sem nome';end if;
 if jsonb_array_length(public.admin_pool_pick(5,70,80))<>5 then raise exception 'sorteio de cartas base';end if;
 -- sem admin: painel fechado
 perform set_config('request.jwt.claims','{"email":"outro@x.com"}',true);
 begin perform public.admin_bt_list();raise exception 'painel aberto';exception when others then if sqlerrm not like 'Acesso restrito%' then raise;end if;end;
 perform set_config('request.jwt.claims','',true);
 raise notice 'PASS Big Time e caixas';
end $$;

-- fase 42: elenco sem limite — lance aceito com mais de 28 jogadores
do $$
declare s public.on_seasons;c public.on_clubs;l public.on_lots;pid text;
begin
 select * into s from public.on_seasons where status='live';
 select * into c from public.on_clubs where season_id=s.id and user_id is not null order by id limit 1;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end)
  select c.id,'Sem limite '||g,'MC',25,60,60,60,10,s.id+1 from generate_series(1,greatest(0,32-(select count(*)::int from public.on_players where club_id=c.id))) g;
 update public.on_clubs set cash=100000000,reserved=0,debt=0 where id=c.id;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end) values(null,'Alvo Sem Limite','MC',25,70,70,70,10,s.id+1) returning id into pid;
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end) values(s.id,pid,500,now(),now()+interval '1 hour',now()+interval '2 hours') returning * into l;
 perform public.on_bid_as(c.id,l.id,500,now());
 raise notice 'PASS elenco sem limite (% jogadores)',(select count(*) from public.on_players where club_id=c.id);
end $$;

-- fase 44: tipo fixo da carta, teto por tipo, mercado por série e reinício do clube do técnico
do $$
declare s public.on_seasons;c public.on_clubs;b public.on_clubs;l public.on_lots;pid text;r jsonb;
begin
 select * into s from public.on_seasons where status='live';
 select * into c from public.on_clubs where season_id=s.id and user_id is not null order by id limit 1;
 select * into b from public.on_clubs where season_id=s.id and user_id is null order by id limit 1;
 -- base: promessa com potencial 92 fica em 84 e continua base mesmo treinada
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end) values(c.id,'Promessa T44','MC',19,70,92,70,10,s.id+1) returning id into pid;
 if (select tier from public.on_players where id=pid)<>'base' or (select pot from public.on_players where id=pid)<>84 then raise exception 'teto da base';end if;
 update public.on_players set level=88,ovr=90 where id=pid;
 if (select ovr from public.on_players where id=pid)<>84 or (select tier from public.on_players where id=pid)<>'base' then raise exception 'base virou outra carta';end if;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,star) values(null,'Destaque T44','MC',24,82,99,82,10,s.id+1,true) returning id into pid;
 if (select tier from public.on_players where id=pid)<>'destaque' or (select pot from public.on_players where id=pid)<>94 then raise exception 'teto do destaque';end if;
 -- mercado: Série D não contrata destaque; o leilão mostra o motivo
 update public.on_clubs set div='D',cash=100000000,reserved=0,debt=0 where id=c.id;
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end) values(s.id,pid,500,now(),now()+interval '1 hour',now()+interval '2 hours') returning * into l;
 begin perform public.on_bid_as(c.id,l.id,500,now());raise exception 'Série D contratou destaque';
 exception when others then if sqlerrm not like 'Na Série D só cartas base%' then raise;end if;end;
 if public.on_lot_json(l,c.id)->>'locked' is null or public.on_lot_json(l,c.id)->'player'->>'tier'<>'destaque' then raise exception 'leilão sem o motivo do bloqueio';end if;
 update public.on_clubs set div='D',cash=100000000,reserved=0,debt=0 where id=b.id;
 if public.on_bot_limit(b.id,l.id,pid)<>0 then raise exception 'bot da Série D quer destaque';end if;
 -- Série B contrata destaque, mas não épica
 update public.on_clubs set div='B' where id=c.id;
 perform public.on_bid_as(c.id,l.id,500,now());
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,legend) values(null,'Épica T44','MC',30,92,110,92,10,s.id+1,true) returning id into pid;
 if (select tier from public.on_players where id=pid)<>'epica' or (select pot from public.on_players where id=pid)<>104 then raise exception 'teto da épica';end if;
 insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end) values(s.id,pid,500,now(),now()+interval '1 hour',now()+interval '2 hours') returning * into l;
 begin perform public.on_bid_as(c.id,l.id,500,now());raise exception 'Série B contratou épica';
 exception when others then if sqlerrm not like 'Cartas Épicas só%' then raise;end if;end;
 update public.on_clubs set div='A' where id=c.id;
 perform public.on_bid_as(c.id,l.id,500,now());
 -- reinício: elenco base da Série D, $ 1 milhão, lances desfeitos
 r:=public.on_restart_club(c.id,'t44');
 if (select cash from public.on_clubs where id=c.id)<>1000000 or (select reserved from public.on_clubs where id=c.id)<>0 then raise exception 'caixa do reinício: %',r;end if;
 if (r->>'players')::int<18 or exists(select 1 from public.on_players where club_id=c.id and (tier not in('base','bigtime') or name like '%T44' or name like 'Sem limite%')) then raise exception 'elenco do reinício: %',r;end if;
 if (r->>'kept')::int<>(select count(*) from public.on_pack_draws d where d.club_id=c.id and d.player_id is not null) then raise exception 'cartas da caixa sumiram: %',r;end if;
 if (select avg(ovr) from(select ovr from public.on_players where club_id=c.id and tier='base' and id not in(select player_id from public.on_pack_draws where player_id is not null) order by ovr desc limit 11) x) not between 54 and 66 then raise exception 'elenco fora do nível da Série D: %',r;end if;
 if exists(select 1 from public.on_lots where status='open' and best_club=c.id) then raise exception 'lance ficou depois do reinício';end if;
 update public.on_clubs set div=null where id in(c.id,b.id);
 raise notice 'PASS tipos de carta, mercado por série e reinício (%)',r;
end $$;
