-- MODO ONLINE — Fase 36: disputa de pênaltis lance a lance.
--
-- Antes os pênaltis eram resolvidos todos de uma vez no apito final (o placar aparecia na hora). Agora, quando o jogo
-- decisivo termina empatado (no agregado, na volta), começa a disputa em tempo real:
--   • a cada 18 s uma cobrança: "Fulano ajeita a bola" (so_ready) e, 7 s depois, o resultado — gol (so_goal),
--     defesa do goleiro (so_save) ou para fora / na trave / por cima (so_miss) — com o canto da batida e o pulo do goleiro;
--   • 5 cobranças para cada lado, alternadas (quem começa é sorteado), depois alternadas até alguém errar;
--   • ordem: o cobrador oficial do time primeiro, depois os melhores batedores em campo, goleiro por último.
-- Cada cobrança considera, NAQUELE momento: finalização, controle e nota do batedor, condição física (cansaço),
-- especialidade de pênalti, a pressão da cobrança (decisiva ou não) e, do outro lado, goleiro (nota de goleiro,
-- especialidade de pegar pênalti). Os atributos do motor já trazem a seta de condição do dia (fase 33).
-- Sem ninguém assistindo, a disputa sai inteira de uma vez (o relógio do servidor passa direto).
-- Cada evento tem at_s: segundo (desde o pontapé) em que a tela deve mostrá-lo.

alter table public.on_match_events add column if not exists at_s int;

-- Chance de cada lado de uma cobrança. Devolve {aim: chance de acertar o gol, save: chance de defesa se acertar}.
create or replace function public.on_pen_odds(p_fin numeric,p_ctl numeric,p_ovr numeric,p_cond numeric,p_spec boolean,
 p_gk numeric,p_gk_spec boolean,p_pressure boolean) returns jsonb
language sql immutable as $$
 select jsonb_build_object(
  'aim',round(greatest(.78,least(.97,.90+(t.v-70)*.004-greatest(0,70-coalesce(p_cond,100))*.0025-case when p_pressure then .025 else 0 end))::numeric,3),
  'save',round(greatest(.08,least(.40,.18+(coalesce(p_gk,50)+case when p_gk_spec then 6 else 0 end-t.v)*.007
   +greatest(0,70-coalesce(p_cond,100))*.002))::numeric,3))
 from(select .55*coalesce(p_fin,50)+.20*coalesce(p_ctl,50)+.25*coalesce(p_ovr,60)+case when p_spec then 6 else 0 end v) t
$$;

-- Avança a disputa até p_now. Devolve verdadeiro quando terminou e o resultado já pode aparecer (último lance mostrado).
create or replace function public.on_so_step(p_fixture bigint,p_kickoff timestamptz,p_now timestamptz) returns boolean
language plpgsql security definer set search_path=public as $$
declare m public.on_matches;so jsonb;el int;n int;i int;sd char;od char;k int;taker text;keeper text;t record;g record;
 sc int[];kicks int[];odds jsonb;r float8;res text;det text;ready int;dirs text[]:=array['esquerdo','meio','direito'];aim int;dive int;
 left_h int;left_a int;pressure boolean;miss text;
begin
 select * into m from public.on_matches where fixture_id=p_fixture for update;
 so:=m.state->'so';
 el:=extract(epoch from p_now-p_kickoff)::int;
 if so is null then
  -- começo: ordem dos batedores (cobrador oficial, depois os melhores em campo; goleiro por último) e quem começa
  so:=jsonb_build_object('start',case when coalesce((m.state->>'et')::boolean,false) then 990 else 720 end,
   'first',case when random()<.5 then 'h' else 'a' end,'n',0,'sc',jsonb_build_array(0,0),'kicks',jsonb_build_array(0,0),'done',false,
   'order',jsonb_build_object(
    'h',(select jsonb_agg(x.player_id order by x.o,x.v desc,x.player_id) from(
      select mp.player_id,case when mp.player_id=m.state->'pen_taker'->>'h' then 0 when mp.pos='GOL' then 2 else 1 end o,
       .55*mp.c_fin+.20*mp.c_ctl+.25*mp.ovr+case when 'penalti'=any(coalesce(p.traits,'{}')) then 6 else 0 end v
      from public.on_match_players mp left join public.on_players p on p.id=mp.player_id
      where mp.fixture_id=p_fixture and mp.side='h' and mp.status='on') x),
    'a',(select jsonb_agg(x.player_id order by x.o,x.v desc,x.player_id) from(
      select mp.player_id,case when mp.player_id=m.state->'pen_taker'->>'a' then 0 when mp.pos='GOL' then 2 else 1 end o,
       .55*mp.c_fin+.20*mp.c_ctl+.25*mp.ovr+case when 'penalti'=any(coalesce(p.traits,'{}')) then 6 else 0 end v
      from public.on_match_players mp left join public.on_players p on p.id=mp.player_id
      where mp.fixture_id=p_fixture and mp.side='a' and mp.status='on') x)));
  update public.on_matches set state=state||jsonb_build_object('so',so) where fixture_id=p_fixture;
  perform public.on_event(p_fixture,m.minute,null,'so_start',null,null,so->>'first');
  update public.on_match_events set at_s=(so->>'start')::int+8 where fixture_id=p_fixture and seq=(select max(seq) from public.on_match_events where fixture_id=p_fixture);
 end if;

 loop
  exit when (so->>'done')::boolean;
  n:=(so->>'n')::int;
  ready:=(so->>'start')::int+25+n*18;
  exit when el<ready;
  sd:=case when n%2=0 then so->>'first' else case when so->>'first'='h' then 'a' else 'h' end end;
  od:=case when sd='h' then 'a' else 'h' end;
  i:=case when sd='h' then 0 else 1 end;
  sc:=array[(so->'sc'->>0)::int,(so->'sc'->>1)::int];
  kicks:=array[(so->'kicks'->>0)::int,(so->'kicks'->>1)::int];
  k:=kicks[i+1];
  taker:=so->'order'->sd->>(k%greatest(1,jsonb_array_length(so->'order'->sd)));
  select mp.c_fin,mp.c_ctl,mp.ovr,mp.cond,'penalti'=any(coalesce(p.traits,'{}')) spec into t
   from public.on_match_players mp left join public.on_players p on p.id=mp.player_id where mp.fixture_id=p_fixture and mp.player_id=taker;
  select mp.player_id,mp.c_gk,'defesa_penalti'=any(coalesce(p.traits,'{}')) spec into g
   from public.on_match_players mp left join public.on_players p on p.id=mp.player_id
   where mp.fixture_id=p_fixture and mp.side=od and mp.status='on' order by (mp.pos='GOL') desc,mp.c_gk desc limit 1;
  keeper:=g.player_id;
  -- pressão: cobrança que pode decidir (empata ou define) ou já nas alternadas
  left_h:=greatest(0,5-kicks[1]);left_a:=greatest(0,5-kicks[2]);
  pressure:=k>=4 or abs(sc[1]-sc[2])>=least(left_h,left_a);
  odds:=public.on_pen_odds(t.c_fin,t.c_ctl,t.ovr,t.cond,coalesce(t.spec,false),g.c_gk,coalesce(g.spec,false),pressure);
  aim:=1+floor(random()*3)::int;
  dive:=case when random()<.42 then aim else 1+floor(random()*3)::int end;
  r:=random();
  if r>(odds->>'aim')::numeric then
   res:='so_miss';miss:=(array['fora','trave','por cima'])[1+floor(random()*3)::int];
   det:=format('%s|%s|%s',miss,dirs[aim],dirs[dive]);
  elsif random()<((odds->>'save')::numeric*(case when dive=aim then 1.6 else .35 end)) then
   res:='so_save';det:=format('defesa|%s|%s',dirs[aim],dirs[aim]);
  else
   res:='so_goal';det:=format('gol|%s|%s',dirs[aim],dirs[dive]);
   sc[i+1]:=sc[i+1]+1;
  end if;
  kicks[i+1]:=kicks[i+1]+1;
  perform public.on_event(p_fixture,m.minute,sd,'so_ready',taker,keeper,format('%s|%s',kicks[i+1],round(t.cond)));
  update public.on_match_events set at_s=ready where fixture_id=p_fixture and seq=(select max(seq) from public.on_match_events where fixture_id=p_fixture);
  perform public.on_event(p_fixture,m.minute,sd,res,taker,keeper,det);
  update public.on_match_events set at_s=ready+7 where fixture_id=p_fixture and seq=(select max(seq) from public.on_match_events where fixture_id=p_fixture);
  if res='so_save' then update public.on_match_players set saves=saves+1 where fixture_id=p_fixture and player_id=keeper;end if;
  -- fim: alguém não alcança mais nas 5; depois das 5, cada par alternado decide
  so:=so||jsonb_build_object('n',n+1,'sc',to_jsonb(sc),'kicks',to_jsonb(kicks),
   'done',(kicks[1]<=5 and kicks[2]<=5 and (sc[1]+greatest(0,5-kicks[1])<sc[2] or sc[2]+greatest(0,5-kicks[2])<sc[1]))
    or (kicks[1]>=5 and kicks[1]=kicks[2] and sc[1]<>sc[2]),
   'end_at',ready+7);
  update public.on_matches set state=state||jsonb_build_object('so',so) where fixture_id=p_fixture;
 end loop;
 -- o resultado sai 6 s depois do último lance (a tela mostra a última cobrança antes do apito)
 return (so->>'done')::boolean and el>=(so->>'end_at')::int+6;
end $$;

-- Apito final de jogo decisivo empatado: primeiro a disputa, lance a lance; só depois o fim.
do $$ begin
 perform public.on_patch('public.on_advance(bigint,timestamp with time zone,text)',
  '    perform public.on_event(p_fixture,m.minute,null,''ft'');',
  '    if coalesce((m.state->>''decisive'')::boolean,false)
     and (m.state->''score''->>0)::int+coalesce((m.state->''agg''->>0)::int,0)=(m.state->''score''->>1)::int+coalesce((m.state->''agg''->>1)::int,0)
     and not public.on_so_step(p_fixture,k,p_now) then exit;end if;
    perform public.on_event(p_fixture,m.minute,null,''ft'');');
 -- o placar da disputa já está pronto: on_match_finish usa o que aconteceu em campo
 perform public.on_patch('public.on_shootout(bigint,integer)',
  'begin
 select array_agg(player_id order by c_fin desc,player_id) into th',
  'begin
 if (select (state->''so''->>''done'')::boolean from public.on_matches where fixture_id=p_fixture) then
  return (select array[(state->''so''->''sc''->>0)::int,(state->''so''->''sc''->>1)::int] from public.on_matches where fixture_id=p_fixture);
 end if;
 select array_agg(player_id order by c_fin desc,player_id) into th');
 -- a tela recebe o segundo de cada lance da disputa e o placar dela
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''player2_name'',p2.name,''detail'',e.detail) order by e.seq)',
  '''player2_name'',p2.name,''detail'',e.detail,''at_s'',e.at_s) order by e.seq)');
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''pens'',m.state->''pens'',',
  '''pens'',m.state->''pens'',''so'',case when m.state ? ''so'' then jsonb_build_object(''first'',m.state->''so''->''first'',''start'',m.state->''so''->''start'') end,');
end $$;

revoke all on function public.on_pen_odds(numeric,numeric,numeric,numeric,boolean,numeric,boolean,boolean),
 public.on_so_step(bigint,timestamptz,timestamptz) from public,anon,authenticated;
