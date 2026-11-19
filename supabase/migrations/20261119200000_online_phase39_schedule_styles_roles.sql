-- MODO ONLINE — Fase 39: horários espalhados, bots no nível máximo, seis estilos de jogo, marcação individual,
-- ordem de pênaltis e escanteios por lado.
--
-- 1. HORÁRIOS. Antes os jogos de uma série saíam todos no mesmo minuto (até 47 partidas juntas no turno).
--    Agora cada jogo tem um horário só dele: o turno da manhã vai das 08:00 às 13:22 e o da tarde das 14:00 às 16:55
--    e das 18:40 às 21:08 (nada entre 17:00 e 18:40), um jogo a cada 7 minutos. As vagas das séries se intercalam
--    (A, B, C, D, A, B…) e, no turno da tarde, quem jogou cedo de manhã joga cedo à tarde: o descanso entre os dois
--    jogos do dia fica perto de 6 horas para todo mundo. Os jogos da copa se espalham pelo turno inteiro.
-- 2. BOTS. Todo jogador de clube bot entra no nível máximo da carta (nota = potencial) desde o primeiro jogo.
-- 3. ESTILOS DE JOGO (tactics.plan): Posse de bola, Contra-ataque rápido, Contra-ataque com bolas longas, Pelas pontas,
--    Bola longa e Sobrecarga. Cada um tem jeito de jogar, confrontos (cada estilo leva vantagem sobre dois e
--    desvantagem contra dois) e aderência ao elenco (atributos-chave contra os do adversário). Os planos antigos viram
--    o estilo mais próximo. A instrução "bola parada" sai: quem decide a cobrança é o cobrador.
-- 4. MARCAÇÃO INDIVIDUAL (tactics.marks): até dois pares "meu jogador marca o jogador X" (como no eFootball). O alvo
--    finaliza pior e aparece menos (quanto melhor o marcador em defesa, desarme e velocidade contra o ataque e a
--    velocidade do alvo); o marcador ataca e cria menos e cansa um pouco mais.
-- 5. FUNÇÕES (on_lineups.roles): capitão, ordem dos pênaltis (até 11), faltas, escanteio da direita e da esquerda.
--    Quem sai substituído passa a função (e a marcação) para quem entrou; no pontapé, quem entra no lugar de um
--    titular fora (lesão, suspensão) também herda.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Horários
-- ─────────────────────────────────────────────────────────────────────────────

create index if not exists on_fixtures_season_slot on public.on_fixtures(season_id,slot);

-- Minuto (a partir do começo do turno) da vaga k da série: as 47 vagas (A 10, B 10, C 12, D 15) se intercalam.
create or replace function public.on_lane_min(p_div text,p_k int) returns int
language sql immutable as $$
 select 7*(x.r-1)::int from(
  select l.d,l.k,row_number() over(order by (l.k+0.5)/l.n,l.o) r
  from(select v.d,v.n,v.o,g.k from(values('A',10,0),('B',10,1),('C',12,2),('D',15,3)) v(d,n,o),generate_series(0,v.n-1) g(k)) l) x
 where x.d=p_div and x.k=least(p_k,(select case p_div when 'A' then 9 when 'B' then 9 when 'C' then 11 else 14 end))
$$;

-- Horário de um minuto do turno: manhã a partir das 08:00; tarde a partir das 14:00, pulando 17:00–18:40.
create or replace function public.on_block_time(p_season smallint,p_slot int,p_min int) returns timestamptz
language sql stable security definer set search_path=public as $$
 select ((s.starts_on+(p_slot/2))+case when p_slot%2=0 then time '08:00'+make_interval(mins=>p_min)
   else time '14:00'+make_interval(mins=>p_min+case when p_min>=180 then 100 else 0 end) end)::timestamp at time zone s.tz
 from public.on_seasons s where s.id=p_season
$$;

-- Refaz os horários de um turno (de uma série, ou da copa com p_div='K'). Ordem dos jogos: pelo horário dos clubes
-- no outro turno do mesmo dia (à tarde, pelo jogo da manhã que terminou mais tarde; de manhã, pelo jogo da tarde que
-- começa mais cedo): quem joga cedo num turno joga cedo no outro. Sem isso, uma ordem sorteada pelo jogo.
-- Só mexe em jogo que ainda não começou.
create or replace function public.on_retime(p_season smallint,p_slot int,p_div text,p_partner boolean default true) returns void
language plpgsql security definer set search_path=public as $$
declare r record;i int:=0;n int;v_other int:=case when p_slot%2=0 then p_slot+1 else p_slot-1 end;
begin
 select count(*) into n from public.on_fixtures f where f.season_id=p_season and f.slot=p_slot
  and case when p_div='K' then f.comp='C' else f.comp='L' and f.div=p_div end;
 for r in select f.id,f.status from public.on_fixtures f
   left join lateral(select case when p_slot%2=1 then max(g.kickoff) else min(g.kickoff) end t from public.on_fixtures g where p_partner and g.season_id=f.season_id and g.slot=v_other
     and (g.home in(f.home,f.away) or g.away in(f.home,f.away))) pt on true
  where f.season_id=p_season and f.slot=p_slot and case when p_div='K' then f.comp='C' else f.comp='L' and f.div=p_div end
  order by pt.t nulls last,public.sim_hash01(p_season||':'||p_slot||':'||f.id),f.id loop
  if r.status='sched' then
   update public.on_fixtures set kickoff=public.on_block_time(p_season,p_slot,
     case when p_div='K' then floor((i+0.5)*329.0/greatest(n,1))::int else public.on_lane_min(p_div,i) end)
   where id=r.id and kickoff>now();
  end if;
  i:=i+1;
 end loop;
end $$;

-- Temporada inteira: em cada dia, o turno de liga sai primeiro (ordem sorteada) e o outro segue a ordem dele.
create or replace function public.on_retime_season(p_season smallint) returns void
language plpgsql security definer set search_path=public as $$
declare d int;a int;b int;x text;cup int[]:=array[3,8,13,18,22,27,31,36,40,45,49];
begin
 for d in 0..(select coalesce(max(slot),0)/2 from public.on_fixtures where season_id=p_season) loop
  a:=case when 2*d=any(cup) then 2*d+1 else 2*d end;
  b:=case when a=2*d then 2*d+1 else 2*d end;
  foreach x in array array['A','B','C','D'] loop perform public.on_retime(p_season,a,x,false);end loop;
  if b=any(cup) then perform public.on_retime(p_season,b,'K',true);
  else foreach x in array array['A','B','C','D'] loop perform public.on_retime(p_season,b,x,true);end loop;
  end if;
 end loop;
end $$;

-- Jogo novo (tabela, mata-mata, copa): entra no turno e o turno daquela série (ou da copa) é reordenado.
create or replace function public.on_fx_add(p_season smallint,p_comp text,p_div text,p_round int,p_home int,p_away int,
 p_tphase int,p_grp int,p_tie int,p_legs int,p_stage text,p_adv int) returns void
language plpgsql security definer set search_path=public as $$
declare v_slot int;v_kdiv text;i int;
begin
 for i in 1..p_legs loop
  v_slot:=public.on_round_slot(case when p_comp='C' then 'K' else p_div end,p_round+i-1);
  v_kdiv:=case when p_comp='C' then (select div from public.on_clubs where id=case when i=1 then p_home else p_away end) else p_div end;
  insert into public.on_fixtures(season_id,comp,div,round,stage,home,away,kickoff,tphase,grp,tie,leg,adv,slot)
  values(p_season,p_comp,case when p_comp='L' then p_div end,p_round+i-1,p_stage,
   case when i=1 then p_home else p_away end,case when i=1 then p_away else p_home end,
   public.on_slot_kick(p_season,v_slot,v_kdiv),p_tphase,nullif(p_grp,0),p_tie,case when p_legs=2 then i end,p_adv,v_slot);
  perform public.on_retime(p_season,v_slot,case when p_comp='C' then 'K' else p_div end,true);
 end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Bots no nível máximo
-- ─────────────────────────────────────────────────────────────────────────────
-- A nota sobe pela experiência (g): o que falta até o potencial entra no setor do jogador.
create or replace function public.on_bot_max(p_club int) returns void
language sql security definer set search_path=public as $$
 update public.on_players p set g=x.g,ovr=public.on_ovr(p.level,p.pot,x.g)
 from(select q.id,case when sp.line in('GK','DEF') then array[q.g[1]+n.need,q.g[2],q.g[3],q.g[4]]
   when sp.line='MID' then array[q.g[1],q.g[2]+n.need,q.g[3],q.g[4]] else array[q.g[1],q.g[2],q.g[3]+n.need,q.g[4]] end::smallint[] g
  from public.on_players q join public.sim_positions sp on sp.code=q.pos
  cross join lateral(select greatest(0,ceil(2*(q.pot-q.level))::int-(select coalesce(sum(x),0) from unnest(q.g) x)::int) need) n
  where q.club_id=p_club and n.need>0) x,public.on_clubs k
 where p.id=x.id and k.id=p.club_id and k.user_id is null
$$;

do $$ begin
 perform public.on_patch('public.on_bot_squad(integer,text)',
  ' update public.on_players p set number=x.rn from(',
  ' perform public.on_bot_max(p_club); -- fase 39: bot no nível máximo da carta
 update public.on_players p set number=x.rn from(');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Estilos de jogo
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_plans() returns text[] language sql immutable as $$
 select array['posse','contra','contra_longo','pontas','direto','sobrecarga'] $$;

-- Confrontos (antissimétrico; cada estilo vence dois, perde para dois e empata com um):
--  posse > pontas, bola longa     · contra-ataque rápido > posse, sobrecarga
--  contra longo > posse, rápido   · pontas > contra longo, sobrecarga
--  bola longa > rápido, pontas    · sobrecarga > contra longo, bola longa
create or replace function public.on_plan_vs(p_me text,p_opp text) returns int language sql immutable as $$
 select coalesce((('{
  "posse":       {"pontas":1,"direto":1,"contra":-1,"contra_longo":-1},
  "contra":      {"posse":1,"sobrecarga":1,"direto":-1,"contra_longo":-1},
  "contra_longo":{"posse":1,"contra":1,"pontas":-1,"sobrecarga":-1},
  "pontas":      {"contra_longo":1,"sobrecarga":1,"posse":-1,"direto":-1},
  "direto":      {"contra":1,"pontas":1,"posse":-1,"sobrecarga":-1},
  "sobrecarga":  {"contra_longo":1,"direto":1,"contra":-1,"pontas":-1}
 }'::jsonb)->p_me->>p_opp)::int,0) $$;

-- Planos antigos e formato antigo → estilo.
create or replace function public.on_plan_legacy(t jsonb) returns text language sql immutable as $$
 select case
  when t->>'plan'=any(public.on_plans()) then t->>'plan'
  when t->>'plan'='equilibrado' then 'posse'
  when t->>'plan'='pressao' then 'contra'
  when t->>'plan'='retranca' then 'contra_longo'
  when t->>'plan'='total' then 'sobrecarga'
  when t->>'style'='counter' then 'contra'
  when t->>'style'='defensive' then 'contra_longo'
  when t->>'style'='attacking' then 'sobrecarga'
  when coalesce(t->>'marking',t->>'pressing')='high' then 'contra'
  when coalesce(t->>'passing',case t->>'build' when 'short' then 'short' when 'direct' then 'long' end)='long' then 'direto'
  when coalesce(t->>'attack',case t->>'width' when 'wide' then 'both' end) in('both','left','right') then 'pontas'
  else 'posse' end $$;

-- Marcações válidas: até 2 pares {by, on} com ids de jogador, sem repetir marcador nem alvo.
create or replace function public.on_marks_clean(p jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('by',x.b,'on',x.o) order by x.i),'[]'::jsonb) from(
  select e->>'by' b,e->>'on' o,i,row_number() over(partition by e->>'by' order by i) rb,row_number() over(partition by e->>'on' order by i) ro
  from jsonb_array_elements(case when jsonb_typeof(p)='array' then p else '[]'::jsonb end) with ordinality a(e,i)
  where jsonb_typeof(e)='object' and e->>'by' ~ '^[A-Za-z0-9_-]{1,40}$' and e->>'on' ~ '^[A-Za-z0-9_-]{1,40}$') x
 where x.rb=1 and x.ro=1 and x.i<=4 $$;

create or replace function public.on_tactics_clean(p_t jsonb) returns jsonb language plpgsql immutable as $$
declare t jsonb:=coalesce(p_t,'{}'::jsonb);v_plan text:=public.on_plan_legacy(t);v_marks jsonb:=public.on_marks_clean(t->'marks');
begin
 if jsonb_array_length(v_marks)>2 then v_marks:=jsonb_path_query_array(v_marks,'$[0 to 1]');end if;
 return jsonb_build_object(
  'plan',v_plan,
  'tackling',case when t->>'tackling' in('light','balanced','heavy') then t->>'tackling'
   else case t->>'tackles' when 'cautious' then 'light' when 'aggressive' then 'heavy' else 'balanced' end end,
  'long_shots',case when t->>'long_shots' in('often','sometimes','rarely') then t->>'long_shots' else 'sometimes' end,
  'manage',case when t->>'manage' in('normal','keep','chase') then t->>'manage' else 'normal' end,
  'marks',v_marks,
  -- campos lidos pelo motor (coerentes com o estilo; on_plan_legacy deles volta ao mesmo estilo)
  'mentality',case v_plan when 'sobrecarga' then 1 when 'contra_longo' then -1 else 0 end,
  'style',case v_plan when 'contra' then 'counter' when 'contra_longo' then 'defensive' when 'sobrecarga' then 'attacking' else 'neutral' end,
  'marking',case v_plan when 'contra' then 'high' when 'sobrecarga' then 'high' when 'contra_longo' then 'low' else 'medium' end,
  'pressing',case v_plan when 'contra' then 'high' when 'sobrecarga' then 'high' when 'contra_longo' then 'low' else 'medium' end,
  'line',case v_plan when 'contra' then 'high' when 'sobrecarga' then 'high' when 'contra_longo' then 'low' else 'medium' end,
  'passing',case v_plan when 'posse' then 'short' when 'sobrecarga' then 'short' when 'direto' then 'long' when 'contra_longo' then 'long' else 'mixed' end,
  'build','mixed','tempo',case v_plan when 'contra' then 'fast' else 'normal' end,
  'attack',case v_plan when 'pontas' then 'both' when 'posse' then 'central' when 'sobrecarga' then 'central' else 'mixed' end,
  'width',case v_plan when 'pontas' then 'wide' else 'mixed' end,
  'crossing',case v_plan when 'pontas' then 'byline' when 'direto' then 'deep' when 'posse' then 'rarely' else 'mixed' end,
  'tackles',case when t->>'tackling'='light' or t->>'tackles'='cautious' then 'cautious'
   when t->>'tackling'='heavy' or t->>'tackles'='aggressive' then 'aggressive' else 'normal' end);
end $$;

-- Aderência: atributos-chave do estilo contra os do adversário (unidades de 10 pontos, −1,5 a +1,5).
--  posse: técnica do meio e do ataque · rápido: fôlego/velocidade e velocidade do ataque contra a da defesa ·
--  bolas longas: defesa contra ataque e velocidade do ataque contra a da defesa · pontas: pontas e laterais contra
--  os laterais · bola longa: jogo aéreo e força do centroavante contra os zagueiros · sobrecarga: técnica e fôlego.
create or replace function public.on_plan_edge(p_plan text,p_me jsonb,p_opp jsonb) returns numeric language sql immutable as $$
 select greatest(-1.5,least(1.5,coalesce(case p_plan
  when 'posse' then (p_me->>'tec')::numeric-(p_opp->>'tec')::numeric
  when 'contra' then ((p_me->>'fis')::numeric-(p_opp->>'fis')::numeric+(p_me->>'vatt')::numeric-(p_opp->>'vdef')::numeric)/2
  when 'contra_longo' then ((p_me->>'def')::numeric-(p_opp->>'att')::numeric+(p_me->>'vatt')::numeric-(p_opp->>'vdef')::numeric)/2
  when 'pontas' then (p_me->>'wide')::numeric-(p_opp->>'wdef')::numeric
  when 'direto' then (p_me->>'aatt')::numeric-(p_opp->>'adef')::numeric
  when 'sobrecarga' then ((p_me->>'tec')::numeric-(p_opp->>'tec')::numeric+(p_me->>'fis')::numeric-(p_opp->>'fis')::numeric)/2
  else 0 end,0)/10)) $$;

-- Estilos de jogador (on_styles.plans) passam para os nomes novos.
update public.on_styles set plans=array(select distinct case x when 'pressao' then 'contra' when 'retranca' then 'contra_longo' when 'total' then 'sobrecarga' else x end
 from unnest(plans) x where x<>'equilibrado') where plans && array['pressao','retranca','total','equilibrado'];
update public.on_styles set plans=array(select distinct x from unnest(plans||array['contra_longo']) x)
 where code in('goal_poacher','attack_outlet','gk_def') and not 'contra_longo'=any(plans);
update public.on_styles set plans=array(select distinct x from unnest(plans||array['sobrecarga']) x)
 where code in('orchestrator','creative','classic10','box_to_box') and not 'sobrecarga'=any(plans);

-- Efeito do estilo no motor (mesmas chaves de antes). Jeito de jogar + confronto + aderência + estilos dos titulares.
create or replace function public.on_plan_effect(p_fixture bigint,p_s int,p_t jsonb,p_opp jsonb,p_skill numeric,p_pace numeric,p_stamina numeric,p_head numeric)
returns jsonb language plpgsql stable set search_path=public as $$
declare me text:=public.on_plan_legacy(p_t);op text:=public.on_plan_legacy(p_opp);
 pm jsonb:=public.on_side_profile(p_fixture,case when p_s=1 then 'h' else 'a' end);
 po jsonb:=public.on_side_profile(p_fixture,case when p_s=1 then 'a' else 'h' end);
 vs int:=public.on_plan_vs(me,op);e numeric:=public.on_plan_edge(me,pm,po);sy numeric;
 ctl numeric:=1;freq numeric:=1;qual numeric:=0;ofreq numeric:=1;oqual numeric:=0;drain numeric:=1;hdr numeric;
begin
 -- jeito de jogar (somado ao que a pressão, a linha e a postura do estilo já fazem no motor)
 case me
  when 'posse' then ctl:=1.07;freq:=0.95;qual:=0.03;drain:=0.90;ofreq:=0.96;
  when 'contra' then ctl:=0.98;freq:=0.98;qual:=0.02;drain:=0.92;
  when 'contra_longo' then ctl:=0.86;freq:=0.98;qual:=0.08;ofreq:=0.86;oqual:=-0.03;drain:=0.95;
  when 'pontas' then qual:=0.03;hdr:=0.34;
  when 'direto' then ctl:=0.92;freq:=1.10;qual:=0.00;hdr:=0.30;
  when 'sobrecarga' then ctl:=1.03;freq:=0.94;qual:=0.01;drain:=0.95;oqual:=0.02;
  else null;
 end case;
 -- confronto
 freq:=freq*(1+0.14*vs);qual:=qual+0.05*vs;
 -- estilos dos titulares que combinam com o estilo do time
 sy:=public.on_style_synergy(p_fixture,case when p_s=1 then 'h' else 'a' end,me);
 freq:=freq*(1+0.09*sy);qual:=qual+0.05*sy;
 if me='contra_longo' then ofreq:=ofreq*(1-0.08*sy);oqual:=oqual-0.03*sy;end if;
 -- aderência do elenco
 freq:=freq*(1+0.06*e);qual:=qual+0.04*e;
 if me in('posse','sobrecarga') then ctl:=ctl*(1+0.05*e);end if;
 if me='contra_longo' then ofreq:=ofreq*(1-0.05*e);oqual:=oqual-0.02*e;end if;
 if me='direto' then qual:=qual+0.03*sy;end if;
 -- marcação individual pedida: um jogador a menos no apoio
 if jsonb_array_length(coalesce(p_t->'marks','[]'::jsonb))>0 then ofreq:=ofreq*(1-0.01*jsonb_array_length(p_t->'marks'));end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',qual,'ofreq',ofreq,'oqual',oqual,'drain',drain,'hdr',hdr,
  'vs',vs,'edge',round(e,2));
end $$;

-- Estilo escolhido pela IA (bots e auxiliar): pela força e pela aderência do elenco; não vê o estilo do adversário.
create or replace function public.on_ai_plan(p_club int,p_opp int,p_diff numeric,p_home boolean) returns jsonb
language plpgsql stable set search_path=public as $$
declare pm jsonb:=public.on_club_profile(p_club);po jsonb:=public.on_club_profile(p_opp);v_plan text;v_best numeric:=-9;p text;v numeric;
begin
 foreach p in array case when p_diff>4 then array['posse','sobrecarga','pontas','contra']
  when p_diff<-5 then array['contra_longo','direto','contra']
  else public.on_plans() end loop
  v:=public.on_plan_edge(p,pm,po)+public.on_club_synergy(p_club,p)*0.5+case when p='posse' then 0.15 else 0 end;
  if v>v_best then v_best:=v;v_plan:=p;end if;
 end loop;
 return jsonb_build_object('plan',v_plan,'manage',case when p_diff>4 then 'keep' else 'normal' end);
end $$;

-- Tela: aderência de cada estilo e o provável time do adversário (para a marcação individual).
-- O estilo do adversário NUNCA é revelado.
create or replace function public.on_plan_fit(p_fixture bigint default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);f public.on_fixtures;sd char;o int;pm jsonb;po jsonb;v_live boolean:=false;
begin
 if p_fixture is not null then
  select * into f from public.on_fixtures where id=p_fixture and season_id=c.season_id;
 else
  f:=public.on_next_fixture(c.id);
 end if;
 if f.id is null then return jsonb_build_object('plans',null,'mark','[]'::jsonb);end if;
 sd:=public.on_side_of(f,c.id);
 if sd is null then raise exception 'Você não joga esta partida';end if;
 o:=case when sd='h' then f.away else f.home end;
 if exists(select 1 from public.on_matches m where m.fixture_id=f.id and m.status='live') then
  v_live:=true;
  pm:=public.on_side_profile(f.id,sd);po:=public.on_side_profile(f.id,case when sd='h' then 'a' else 'h' end);
 else
  if not exists(select 1 from public.on_lineups where club_id=o) then perform public.on_auto_lineup(o);end if;
  pm:=public.on_club_profile(c.id);po:=public.on_club_profile(o);
 end if;
 return jsonb_build_object('fixture',f.id,'live',v_live,
  'opponent',(select jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors) from public.on_clubs k where k.id=o),
  'plans',(select jsonb_object_agg(p,jsonb_build_object('edge',round(public.on_plan_edge(p,pm,po),2))) from unnest(public.on_plans()) p),
  -- titulares do adversário (em campo, se o jogo já começou; senão a escalação salva dele)
  'mark',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'ovr',p.ovr,'number',p.number) order by p.ovr desc,p.id)
   from public.on_players p where p.club_id=o and p.pos<>'GOL' and (
    (v_live and exists(select 1 from public.on_match_players mp where mp.fixture_id=f.id and mp.player_id=p.id and mp.status='on'))
    or (not v_live and p.id in(select e.value from public.on_lineups l,jsonb_each_text(l.slots) e where l.club_id=o)))),'[]'::jsonb));
end $$;

-- escalações e partidas salvas no formato antigo passam para os estilos novos
update public.on_lineups set tactics=public.on_tactics_clean(tactics) where not coalesce(tactics->>'plan','')=any(public.on_plans()) or tactics ? 'set_pieces' or tactics ? 'mark';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Funções
-- ─────────────────────────────────────────────────────────────────────────────
-- Formato: {captain, pen:[ordem], fk, ck_r, ck_l}. O formato antigo (pen e ck únicos) é convertido.
create or replace function public.on_roles_norm(r jsonb) returns jsonb language sql immutable as $$
 select jsonb_strip_nulls(jsonb_build_object(
  'captain',r->>'captain',
  'pen',case when jsonb_typeof(r->'pen')='array' then r->'pen' when r->>'pen' is not null then jsonb_build_array(r->>'pen') else '[]'::jsonb end,
  'fk',r->>'fk','ck_r',coalesce(r->>'ck_r',r->>'ck'),'ck_l',coalesce(r->>'ck_l',r->>'ck')))
 from(select coalesce(r,'{}'::jsonb) r) x(r) $$;

-- Troca um jogador por outro em todas as funções (pontapé com titular fora ou substituição).
create or replace function public.on_roles_swap(r jsonb,p_out text,p_in text) returns jsonb language sql immutable as $$
 select case when p_out is null or p_in is null then r else
  (select coalesce(jsonb_object_agg(k,case when jsonb_typeof(v)='array'
     then (select coalesce(jsonb_agg(case when x=p_out then to_jsonb(p_in) else to_jsonb(x) end order by i),'[]'::jsonb) from jsonb_array_elements_text(v) with ordinality a(x,i))
     when v #>> '{}'=p_out then to_jsonb(p_in) else v end),'{}'::jsonb) from jsonb_each(r) e(k,v)) end $$;

create or replace function public.on_roles_remap(r jsonb,p_fixes jsonb) returns jsonb language plpgsql immutable as $$
declare f jsonb;
begin
 for f in select e from jsonb_array_elements(coalesce(p_fixes,'[]'::jsonb)) e loop
  r:=public.on_roles_swap(r,f->>'out',f->>'in');
 end loop;
 return r;
end $$;

-- Substituição: quem entra herda as funções e a marcação de quem saiu (e quem marcava quem saiu passa a marcar quem entrou).
create or replace function public.on_roles_inherit(st jsonb,p_side text,p_out text,p_in text) returns jsonb language plpgsql immutable as $$
declare k text;os text:=case when p_side='h' then 'a' else 'h' end;
begin
 foreach k in array array['pen_taker','fk_taker','ck_taker','ck_r','ck_l','captain'] loop
  if st->k->>p_side=p_out then st:=jsonb_set(st,array[k,p_side],to_jsonb(p_in));end if;
 end loop;
 if jsonb_typeof(st->'pen_order'->p_side)='array' then
  st:=jsonb_set(st,array['pen_order',p_side],(select coalesce(jsonb_agg(case when x=p_out then to_jsonb(p_in) else to_jsonb(x) end order by i),'[]'::jsonb)
   from jsonb_array_elements_text(st->'pen_order'->p_side) with ordinality a(x,i)));
 end if;
 if jsonb_typeof(st->'tactics'->p_side->'marks')='array' then
  st:=jsonb_set(st,array['tactics',p_side,'marks'],(select coalesce(jsonb_agg(case when e->>'by'=p_out then jsonb_set(e,'{by}',to_jsonb(p_in)) else e end order by i),'[]'::jsonb)
   from jsonb_array_elements(st->'tactics'->p_side->'marks') with ordinality a(e,i)));
 end if;
 if jsonb_typeof(st->'tactics'->os->'marks')='array' then
  st:=jsonb_set(st,array['tactics',os,'marks'],(select coalesce(jsonb_agg(case when e->>'on'=p_out then jsonb_set(e,'{on}',to_jsonb(p_in)) else e end order by i),'[]'::jsonb)
   from jsonb_array_elements(st->'tactics'->os->'marks') with ordinality a(e,i)));
 end if;
 return st;
end $$;

create or replace function public.on_roles_save(p_roles jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v jsonb:=public.on_roles_norm(p_roles);x text;
begin
 if jsonb_array_length(v->'pen')>11 then raise exception 'A ordem dos pênaltis aceita até 11 jogadores';end if;
 if jsonb_array_length(v->'pen')<>(select count(distinct e) from jsonb_array_elements_text(v->'pen') e) then raise exception 'Jogador repetido na ordem dos pênaltis';end if;
 for x in select e from jsonb_array_elements_text(v->'pen') e union all
  select v->>r.key from unnest(array['captain','fk','ck_r','ck_l']) r(key) where v->>r.key is not null loop
  if not exists(select 1 from public.on_players where id=x and club_id=c.id) then raise exception 'Jogador fora do seu elenco';end if;
 end loop;
 update public.on_lineups set roles=v,updated_at=now() where club_id=c.id;
 return public.on_squad();
end $$;

update public.on_lineups set roles=public.on_roles_norm(roles) where roles ? 'ck' or jsonb_typeof(roles->'pen')='string';

do $$ begin
 -- elenco devolve as funções no formato novo
 perform public.on_patch('public.on_squad()','''roles'',l.roles)','''roles'',public.on_roles_norm(l.roles))');
 -- pontapé: quem entra no lugar de um titular fora herda a função dele
 perform public.on_patch('public.on_kickoff_lineup(integer,public.on_fixtures)','''roles'',l.roles,','''roles'',public.on_roles_remap(public.on_roles_norm(l.roles),fixes),');
 -- abertura: ordem dos pênaltis e escanteio de cada lado
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  '''pen_taker'',jsonb_build_object(''h'',lh->''roles''->>''pen'',''a'',la->''roles''->>''pen''),',
  '''pen_taker'',jsonb_build_object(''h'',lh->''roles''->''pen''->>0,''a'',la->''roles''->''pen''->>0),
  ''pen_order'',jsonb_build_object(''h'',coalesce(lh->''roles''->''pen'',''[]''),''a'',coalesce(la->''roles''->''pen'',''[]'')),');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  '''ck_taker'',jsonb_build_object(''h'',lh->''roles''->>''ck'',''a'',la->''roles''->>''ck''),',
  '''ck_taker'',jsonb_build_object(''h'',lh->''roles''->>''ck_r'',''a'',la->''roles''->>''ck_r''),
  ''ck_r'',jsonb_build_object(''h'',lh->''roles''->>''ck_r'',''a'',la->''roles''->>''ck_r''),
  ''ck_l'',jsonb_build_object(''h'',lh->''roles''->>''ck_l'',''a'',la->''roles''->>''ck_l''),');
 -- substituição: herança das funções e da marcação
 perform public.on_patch('public.on_do_sub(bigint,character,text,text,integer,boolean,text)',
  'perform public.on_event(p_fixture, p_minute, p_side, ''sub'', p_in, p_out, p_detail);',
  'perform public.on_event(p_fixture, p_minute, p_side, ''sub'', p_in, p_out, p_detail);
update public.on_matches set state = public.on_roles_inherit(state, p_side, p_out, p_in) where fixture_id = p_fixture;');
 -- disputa de pênaltis: a ordem do técnico (quem está em campo), depois os melhores, goleiro por último
 perform public.on_patch('public.on_so_step(bigint,timestamp with time zone,timestamp with time zone)',
  'case when mp.player_id=m.state->''pen_taker''->>''h'' then 0 when mp.pos=''GOL'' then 2 else 1 end o,',
  'case when mp.pos=''GOL'' then 1000 else coalesce((select q.i from jsonb_array_elements_text(coalesce(m.state->''pen_order''->''h'',''[]'')) with ordinality q(id,i) where q.id=mp.player_id),case when mp.player_id=m.state->''pen_taker''->>''h'' then 0 else 500 end) end o,');
 perform public.on_patch('public.on_so_step(bigint,timestamp with time zone,timestamp with time zone)',
  'case when mp.player_id=m.state->''pen_taker''->>''a'' then 0 when mp.pos=''GOL'' then 2 else 1 end o,',
  'case when mp.pos=''GOL'' then 1000 else coalesce((select q.i from jsonb_array_elements_text(coalesce(m.state->''pen_order''->''a'',''[]'')) with ordinality q(id,i) where q.id=mp.player_id),case when mp.player_id=m.state->''pen_taker''->>''a'' then 0 else 500 end) end o,');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Motor (on_engine_run): marcação individual, cobrador de pênalti pela ordem, bola parada decidida pelo cobrador
-- (falta: chute direto ou cruzamento; escanteio: batedor do lado), assistência do cobrador no gol de cabeça.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.on_engine_run(p_fixture bigint, p_to integer, p_interactive text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lsh float8[];
  v_ldist boolean;
  v_spk text[];
  v_cprev int[];
  v_fk int[];
  v_fktaker text[];
  v_cktaker text[];
  v_sp64 int;
  v_spq float8;
  v_pentaker text[];
  v_spb float8[];
  v_m      public.on_matches;
  v_p      public.mgr_ep[];
  v_n      int;
  v_min    int;
  v_end    int;
  v_stop   text := 'segment';
  i        int;
  j        int;
  s        int;
  d        int;
  v_e      float8;
  v_att    float8[];
  v_def    float8[];
  v_ctl    float8[];
  v_gkr    float8[];
  v_gki    int[];
  v_defav  float8[];
  v_paceav float8[];
  v_non    int[];
  v_tac    jsonb;
  v_ment   int[];
  v_amult  float8[];
  v_dmult  float8[];
  v_freq   float8[];
  v_qual   float8[];
  v_drainm float8[];
  v_foulm  float8[];
  v_offm   float8[];
  v_hdr    float8[];
  v_sc     int[];
  v_agg    int[];
  v_poss   int[];
  v_corn   int[];
  v_offs   int[];
  v_ph     float8;
  v_r      float8;
  v_pa     float8;
  v_q      float8;
  v_w      float8[];
  v_k      int;
  v_a      int;
  v_gkidx  int;
  v_head   boolean;
  v_reload boolean;
  v_neut   boolean;
  v_et     boolean;
  v_side   char;
  v_oside  char;
  v_dsec   char;
  v_inj_stop boolean;
  v_lead   int;
  v_detail text;
  v_form   float8[];
  v_tpress text[];
  v_tline  text[];
  v_ttempo text[];
  v_tbuild text[];
  v_tmanage text[];
  v_tment  int[];
  v_ctlm   float8[];
  v_dws    float8[];
  v_dirty  boolean := true;
  v_profiles jsonb;
  v_card jsonb;
  v_ref float8;
  v_tackles text[];
  v_effect jsonb;
  v_skill record;
  v_yprob float8;
  v_rprob float8;
  v_mark text[];
  v_markq  jsonb := '{}';
  v_ckr    text[];
  v_ckl    text[];
  v_tk     int;
  v_x      int;
  v_mk     jsonb;
begin
  select * into v_m from public.on_matches where fixture_id = p_fixture for update;
  if v_m.status <> 'live' then return 'ft'; end if;
  select jsonb_object_agg(mp.player_id,jsonb_build_array(mp.agg,mp.disc)) into v_profiles
   from public.on_match_players mp where mp.fixture_id=p_fixture;
  v_ref:=coalesce((v_m.state->>'referee')::float8,1);
  v_form := array[coalesce((v_m.state -> 'form' ->> 0)::numeric, 1), coalesce((v_m.state -> 'form' ->> 1)::numeric, 1)];
  v_min := v_m.minute;
  v_et  := coalesce((v_m.state ->> 'et')::boolean, false);
  v_end := least(p_to, case when v_et then 120 else 90 end);
  v_neut := coalesce((v_m.state ->> 'neutral')::boolean, false);
  v_poss := array[(v_m.state -> 'poss' ->> 0)::int, (v_m.state -> 'poss' ->> 1)::int];
  v_corn := array[(v_m.state -> 'corners' ->> 0)::int, (v_m.state -> 'corners' ->> 1)::int];
  v_offs := array[(v_m.state -> 'offsides' ->> 0)::int, (v_m.state -> 'offsides' ->> 1)::int];
  v_sc   := array[(v_m.state -> 'score' ->> 0)::int, (v_m.state -> 'score' ->> 1)::int];
  v_agg  := array[(v_m.state -> 'agg' ->> 0)::int, (v_m.state -> 'agg' ->> 1)::int];
  v_cprev := array[v_corn[1], v_corn[2]]; v_fk := array[0, 0];
  v_fktaker := array[v_m.state->'fk_taker'->>'h', v_m.state->'fk_taker'->>'a'];
  v_cktaker := array[v_m.state->'ck_taker'->>'h', v_m.state->'ck_taker'->>'a'];
  v_ckr := array[coalesce(v_m.state->'ck_r'->>'h', v_cktaker[1]), coalesce(v_m.state->'ck_r'->>'a', v_cktaker[2])];
  v_ckl := array[coalesce(v_m.state->'ck_l'->>'h', v_cktaker[1]), coalesce(v_m.state->'ck_l'->>'a', v_cktaker[2])];
  v_reload := true;
  v_pentaker := array[v_m.state->'pen_taker'->>'h', v_m.state->'pen_taker'->>'a'];
  v_spb := array[coalesce((v_m.state->'sp_bonus'->>0)::float8,0), coalesce((v_m.state->'sp_bonus'->>1)::float8,0)];

  while v_min < v_end loop
    v_min := v_min + 1;

    -- a IA (e o auxiliar, no modo automático) mexe nos intervalos e marcos do jogo
    if v_min in (46, 61, 71, 81, 91, 106) then
      if v_p is not null then   -- grava antes: a IA decide olhando a condição e o placar atuais
        update public.on_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
        update public.on_matches
           set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
         where fixture_id = p_fixture;
        v_p := null;
      end if;
      if strpos(coalesce(p_interactive,''),'h')=0 then perform public.on_ai_manage(p_fixture, 'h', v_min - 1); end if;
      if strpos(coalesce(p_interactive,''),'a')=0 then perform public.on_ai_manage(p_fixture, 'a', v_min - 1); end if;
      v_reload := true;
    end if;

    if v_reload then
      if v_p is not null then
        update public.on_match_players m
           set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
               fouls = x.fouls, yellow = x.yel, red = x.red,
               minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
          from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
      end if;
      select * into v_m from public.on_matches where fixture_id = p_fixture;
      select array_agg(row(mp.player_id, case when mp.side = 'h' then 1 else 2 end, mp.slot, mp.pos,
                           (sp.w_att * mp.s_aw)::float8, (sp.w_def * mp.s_dw)::float8, (sp.w_ctl * mp.s_cw)::float8, (sp.drain * mp.s_dr)::float8,
                           mp.c_att::float8, mp.c_cre::float8, mp.c_def::float8, mp.c_ctl::float8, mp.c_gk::float8, mp.c_fin::float8,
                           mp.c_head::float8, mp.c_pace::float8, mp.c_stam::float8, mp.c_tack::float8, mp.c_str::float8,
                           mp.fit::float8, mp.cond::float8, mp.rhythm::float8, mp.goals, mp.assists, mp.shots, mp.sot, mp.saves, mp.fouls, mp.yellow, mp.red,
                           false, true, mp.minutes)::public.mgr_ep order by mp.side, mp.slot)
        into v_p
        from public.on_match_players mp join public.sim_positions sp on sp.code = mp.pos
       where mp.fixture_id = p_fixture and mp.status = 'on';
      v_n := coalesce(array_length(v_p, 1), 0);
      v_tac := v_m.state -> 'tactics';
      v_reload := false;
      v_dirty := true;
      -- parâmetros táticos fixos até a próxima mudança
      v_tackles:=array[coalesce(v_tac->'h'->>'tackles','normal'),coalesce(v_tac->'a'->>'tackles','normal')];
      v_tpress := array[v_tac -> 'h' ->> 'pressing', v_tac -> 'a' ->> 'pressing'];
      v_tline  := array[v_tac -> 'h' ->> 'line', v_tac -> 'a' ->> 'line'];
      v_ttempo := array[v_tac -> 'h' ->> 'tempo', v_tac -> 'a' ->> 'tempo'];
      v_tbuild := array[v_tac -> 'h' ->> 'build', v_tac -> 'a' ->> 'build'];
      v_tmanage := array[v_tac -> 'h' ->> 'manage', v_tac -> 'a' ->> 'manage'];
      v_tment  := array[coalesce((v_tac -> 'h' ->> 'mentality')::int, 0), coalesce((v_tac -> 'a' ->> 'mentality')::int, 0)];
      v_freq := array[1, 1]; v_qual := array[0, 0]; v_drainm := array[1, 1]; v_foulm := array[1, 1]; v_offm := array[1, 1];
      v_hdr := array[0.2, 0.2]; v_ctlm := array[1, 1];
      v_lsh := array[0.18, 0.18];
      -- cobradores (a substituição passa a função para quem entrou: on_roles_inherit)
      v_fktaker := array[v_m.state->'fk_taker'->>'h', v_m.state->'fk_taker'->>'a'];
      v_ckr := array[coalesce(v_m.state->'ck_r'->>'h', v_m.state->'ck_taker'->>'h'), coalesce(v_m.state->'ck_r'->>'a', v_m.state->'ck_taker'->>'a')];
      v_ckl := array[coalesce(v_m.state->'ck_l'->>'h', v_m.state->'ck_taker'->>'h'), coalesce(v_m.state->'ck_l'->>'a', v_m.state->'ck_taker'->>'a')];
      -- pênalti: o primeiro da ordem que está em campo
      for s in 1 .. 2 loop
        v_side := case when s = 1 then 'h' else 'a' end;
        v_pentaker[s] := null;
        for v_x in 0 .. coalesce(jsonb_array_length(v_m.state->'pen_order'->v_side), 0) - 1 loop
          exit when v_pentaker[s] is not null;
          for i in 1 .. v_n loop
            if v_p[i].sd = s and v_p[i].on_field and v_p[i].pid = v_m.state->'pen_order'->v_side->>v_x then v_pentaker[s] := v_p[i].pid; end if;
          end loop;
        end loop;
        if v_pentaker[s] is null then v_pentaker[s] := v_m.state->'pen_taker'->>v_side; end if;
      end loop;
      -- marcação individual: o marcador gruda no alvo (alvo finaliza pior e aparece menos; marcador ataca e cria menos)
      v_markq := '{}';
      for s in 1 .. 2 loop
        v_side := case when s = 1 then 'h' else 'a' end;
        for v_mk in select e from jsonb_array_elements(coalesce(v_tac->v_side->'marks', '[]'::jsonb)) e loop
          v_k := 0; v_a := 0;
          for i in 1 .. v_n loop
            if v_p[i].sd = s and v_p[i].pos <> 'GOL' and v_p[i].pid = v_mk->>'by' then v_k := i; end if;
            if v_p[i].sd = 3 - s and v_p[i].pid = v_mk->>'on' then v_a := i; end if;
          end loop;
          continue when v_k = 0 or v_a = 0 or v_markq ? v_p[v_a].pid;
          v_markq := v_markq || jsonb_build_object(v_p[v_a].pid, greatest(0.03, least(0.16,
            0.08 + 0.004 * ((v_p[v_k].def + v_p[v_k].tack + v_p[v_k].pace) / 3 - (v_p[v_a].att + v_p[v_a].pace) / 2))));
          v_p[v_k].aw := v_p[v_k].aw * 0.60; v_p[v_k].cw := v_p[v_k].cw * 0.85; v_p[v_k].drain := v_p[v_k].drain * 1.08;
        end loop;
      end loop;
      for s in 1 .. 2 loop
        d := 3 - s;
        if v_tpress[s] = 'high' then v_freq[s] := v_freq[s] * 1.06; v_drainm[s] := 1.30; v_foulm[s] := 1.25; v_ctlm[d] := v_ctlm[d] * 0.93;
        elsif v_tpress[s] = 'low' then v_drainm[s] := 0.85; v_foulm[s] := 0.85; v_ctlm[d] := v_ctlm[d] * 1.04; end if;
        if v_ttempo[s] = 'fast' then v_freq[s] := v_freq[s] * 1.10; v_drainm[s] := v_drainm[s] * 1.18; v_ctlm[s] := v_ctlm[s] * 0.97;
        elsif v_ttempo[s] = 'slow' then v_freq[s] := v_freq[s] * 0.90; v_drainm[s] := v_drainm[s] * 0.90; v_ctlm[s] := v_ctlm[s] * 1.04; end if;
        if v_tbuild[s] = 'short' then v_freq[s] := v_freq[s] * 0.95; v_qual[s] := v_qual[s] + 0.04; v_ctlm[s] := v_ctlm[s] * 1.05;
        elsif v_tbuild[s] = 'direct' then v_freq[s] := v_freq[s] * 1.08; v_qual[s] := v_qual[s] - 0.03; v_offm[s] := 1.25; v_ctlm[s] := v_ctlm[s] * 0.94; end if;
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'width' when 'wide' then 0.30 when 'center' then 0.10 else 0.20 end;
        if v_hdr[s] = 0.10 then v_qual[s] := v_qual[s] + 0.02; end if;
        -- CM17: cruzamento define a parcela de cabeceios; chutes longos trocam volume por qualidade
        v_hdr[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'crossing' when 'byline' then 0.32 when 'deep' then 0.24 when 'rarely' then 0.06 else v_hdr[s] end;
        v_lsh[s] := case v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'long_shots' when 'often' then 0.35 when 'rarely' then 0.06 else 0.18 end;
        if v_lsh[s] >= 0.35 then v_freq[s] := v_freq[s] * 1.04; elsif v_lsh[s] <= 0.06 then v_freq[s] := v_freq[s] * 0.97; v_qual[s] := v_qual[s] + 0.01; end if;
        if v_tac -> (case when s = 1 then 'h' else 'a' end) ->> 'style' = 'counter' then v_freq[s] := v_freq[s] * 1.06; v_qual[s] := v_qual[s] + 0.02; v_ctlm[s] := v_ctlm[s] * 0.95; end if;
        -- linha defensiva do ADVERSÁRIO muda a frequência de ataque e os impedimentos
        if v_tline[d] = 'high' then v_freq[s] := v_freq[s] * 0.95; v_offm[s] := v_offm[s] * 1.7;
        elsif v_tline[d] = 'low' then v_freq[s] := v_freq[s] * 1.06; v_offm[s] := v_offm[s] * 0.6; end if;
      end loop;
      for s in 1..2 loop
        select avg(c_cre) as skill,avg(c_pace) as pace,avg(c_stam * cond/100) as stamina,avg(c_head) as heading into v_skill
        from public.on_match_players where fixture_id=p_fixture and side=case when s=1 then 'h' else 'a' end and status='on' and pos<>'GOL';
        v_effect:=public.on_plan_effect(p_fixture,s,v_tac->(case when s=1 then 'h' else 'a' end),v_tac->(case when s=1 then 'a' else 'h' end),
                  v_skill.skill,v_skill.pace,v_skill.stamina,v_skill.heading);
        v_ctlm[s]:=v_ctlm[s]*(v_effect->>'control')::float8;
        v_freq[s]:=v_freq[s]*(v_effect->>'frequency')::float8;
        v_qual[s]:=v_qual[s]+(v_effect->>'quality')::float8;
        v_freq[3-s]:=v_freq[3-s]*coalesce((v_effect->>'ofreq')::float8,1);
        v_qual[3-s]:=v_qual[3-s]+coalesce((v_effect->>'oqual')::float8,0);
        v_drainm[s]:=v_drainm[s]*coalesce((v_effect->>'drain')::float8,1);
        if v_effect->>'hdr' is not null then v_hdr[s]:=(v_effect->>'hdr')::float8; end if;
        v_foulm[s]:=v_foulm[s]*case v_tackles[s] when 'aggressive' then 1.22 when 'cautious' then 0.78 else 1 end;
      end loop;
      if not v_neut then v_ctlm[1] := v_ctlm[1] * 1.05; end if;
    end if;

    -- ---- força dos times (recalculada a cada 3 minutos ou quando alguém sai/entra) ----
    if v_dirty or v_min % 3 = 1 then
      v_dirty := false;
      v_att := array[0, 0]; v_def := array[0, 0]; v_ctl := array[0, 0]; v_gkr := array[30, 30]; v_gki := array[0, 0];
      v_defav := array[0, 0]; v_paceav := array[0, 0]; v_non := array[0, 0]; v_dws := array[0, 0];
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_e := v_p[i].fit * (0.60 + 0.004 * v_p[i].cond) * (case when v_p[i].cond < 50 then 0.88 + 0.0024 * v_p[i].cond else 1 end)
               * (0.94 + 0.0006 * v_p[i].rhy);
        v_att[s] := v_att[s] + v_p[i].aw * (0.62 * v_p[i].att + 0.38 * v_p[i].cre) * v_e;
        v_def[s] := v_def[s] + v_p[i].dw * v_p[i].def * v_e;
        v_ctl[s] := v_ctl[s] + v_p[i].cw * v_p[i].ctl * v_e;
        v_non[s] := v_non[s] + 1;
        if v_p[i].pos = 'GOL' then v_gkr[s] := v_p[i].gk * v_e; v_gki[s] := i;
        else
          v_defav[s] := v_defav[s] + v_p[i].dw * v_p[i].def * v_e;
          v_paceav[s] := v_paceav[s] + v_p[i].dw * v_p[i].pace * v_e;
          v_dws[s] := v_dws[s] + v_p[i].dw;
        end if;
      end loop;
      for s in 1 .. 2 loop
        v_defav[s] := case when v_dws[s] > 0 then v_defav[s] / v_dws[s] else 40 end;
        v_paceav[s] := case when v_dws[s] > 0 then v_paceav[s] / v_dws[s] else 50 end;
      end loop;
    end if;

    -- ---- postura (muda com o placar conforme a "gestão do jogo") ----
    for s in 1 .. 2 loop
      d := 3 - s;
      v_ment[s] := v_tment[s];
      v_lead := (v_sc[s] + v_agg[s]) - (v_sc[d] + v_agg[d]);
      if v_tmanage[s] = 'keep' and v_lead > 0 and v_min >= 70 then v_ment[s] := greatest(-2, v_ment[s] - 1); end if;
      if v_tmanage[s] = 'push' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if; if v_tmanage[s] = 'chase' and v_lead <= 0 then v_ment[s] := least(2, v_ment[s] + case when v_lead < 0 and v_min >= 70 then 2 else 1 end); end if;
      v_amult[s] := (array[0.80, 0.90, 1.00, 1.10, 1.20])[v_ment[s] + 3];
      v_dmult[s] := (array[1.15, 1.07, 1.00, 0.94, 0.86])[v_ment[s] + 3] * case when v_tpress[s] = 'low' then 1.03 else 1 end;
    end loop;

    -- ---- posse ----
    v_r := v_ctl[1] * v_ctlm[1];
    v_q := v_ctl[2] * v_ctlm[2];
    v_ph := greatest(0.25, least(0.75, 0.5 + 1.15 * (v_r / greatest(v_r + v_q, 1) - 0.5)));
    s := case when random() < v_ph then 1 else 2 end;
    d := 3 - s;
    v_side := case when s = 1 then 'h' else 'a' end;
    v_oside := case when d = 1 then 'h' else 'a' end;
    v_poss[s] := v_poss[s] + 1;

    -- ---- jogada de ataque? ----
    v_pa := 0.285 * (v_form[s] / v_form[d]) * power(greatest(v_att[s] * v_amult[s] * (case when v_neut then 1 when s = 1 then 1.07 else 0.98 end), 1)
                          / greatest(v_def[d] * v_dmult[d], 1) / 0.86, 1.20)
                  * v_freq[s] * (1 + 0.05 * greatest(0, v_ment[d]));
    v_pa := greatest(0.05, least(0.55, v_pa));

    if random() < v_pa then
      v_r := random();
      if v_r < 0.07 * v_offm[s] then
        -- impedimento
        v_offs[s] := v_offs[s] + 1;
        if p_interactive is not null then
          v_w := '{}';
          for i in 1 .. v_n loop v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s then v_p[i].aw * v_p[i].pace else 0 end; end loop;
          v_k := public.mgr_pick(v_w);
          if v_k > 0 then perform public.on_event(p_fixture, v_min, v_side, 'offside', v_p[v_k].pid); end if;
        end if;
      elsif v_r < 0.07 + 0.10 then
        -- falta do defensor na jogada (pode virar pênalti ou cartão)
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = d and v_p[i].pos <> 'GOL' then v_p[i].dw * (1 + (100 - v_p[i].tack) / 100) else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].fouls := v_p[v_k].fouls + 1;
          v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
            v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[d],v_ref::numeric,1.20);
          v_r:=random();
          if v_r<(v_card->>'red')::float8 then
            v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
            perform public.on_event(p_fixture,v_min,v_oside,'red',v_p[v_k].pid,null,'Entrada temerária');
            update public.on_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
            
          elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
            if v_p[v_k].yel>=1 then
              v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
              perform public.on_event(p_fixture,v_min,v_oside,'second_yellow',v_p[v_k].pid);
              update public.on_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
              
            else
              v_p[v_k].yel:=1;perform public.on_event(p_fixture,v_min,v_oside,'yellow',v_p[v_k].pid);
            end if;
          end if;
          if random() < 0.22 then v_fk[s] := v_fk[s] + 1; end if;           -- falta perigosa (bola parada)
          if random() < 0.11 then                                         -- pênalti
            v_a := 0; v_e := -1;
            for i in 1 .. v_n loop
              if v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and (v_p[i].fin + (case when v_p[i].pid = v_pentaker[s] then 500 else 0 end)) > v_e then v_e := v_p[i].fin + (case when v_p[i].pid = v_pentaker[s] then 500 else 0 end); v_a := i; end if;
            end loop;
            if v_a > 0 then
              v_p[v_a].shots := v_p[v_a].shots + 1;
              v_gkidx := v_gki[d];
              if random() < greatest(0.55, least(0.88, 0.70 + v_spb[s] + 0.004 * (v_p[v_a].fin - v_gkr[d]))) then
                v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_a].goals := v_p[v_a].goals + 1; v_sc[s] := v_sc[s] + 1;
                perform public.on_event(p_fixture, v_min, v_side, 'pen_goal', v_p[v_a].pid);
              else
                if random() < 0.6 and v_gkidx > 0 then
                  v_p[v_a].sot := v_p[v_a].sot + 1; v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1;
                  perform public.on_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, v_p[v_gkidx].pid, 'defendido');
                else
                  perform public.on_event(p_fixture, v_min, v_side, 'pen_miss', v_p[v_a].pid, null, 'para fora');
                end if;
              end if;
            end if;
          end if;
        end if;
      elsif v_r < 0.17 + 0.12 then
        if random() < 0.45 then v_corn[s] := v_corn[s] + 1; end if;  -- cruzamento cortado / jogada desarmada
      else
        -- ---- finalização ----
        v_head := random() < v_hdr[s];
        v_ldist := not v_head and random() < v_lsh[s];
        v_w := '{}';
        for i in 1 .. v_n loop
          v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' then
                   case when v_head then (v_p[i].aw + 0.25) * power(v_p[i].head / 60, 3)
                        else power(v_p[i].aw + 0.05 + case when v_ldist then 0.35 * v_p[i].cw else 0 end, 1.6) * power(v_p[i].fin / 60, 2) * (0.70 + 0.003 * v_p[i].cond) end
                   * case when v_markq ? v_p[i].pid then 0.75 else 1 end
                 else 0 end;
        end loop;
        v_k := public.mgr_pick(v_w);
        if v_k > 0 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          v_q := 0.30 + 0.0055 * ((case when v_head then v_p[v_k].head else v_p[v_k].att end) - v_defav[d])
                 + case when s = 1 and not v_neut then 0.02 else 0 end
                 + v_qual[s] + 0.5 * (v_form[s] / v_form[d] - 1) + random() * 0.35
                 + 0.03 * greatest(0, v_ment[d]) + case when v_tpress[d] = 'high' and v_tline[d] = 'high' then 0.02 else 0 end
                 + case v_tline[d] when 'high' then 0.003 * (v_p[v_k].pace - v_paceav[d]) when 'low' then -0.04 else 0 end
                 - case when v_head then 0.08 else 0 end
                 - coalesce((v_markq->>v_p[v_k].pid)::float8, 0)
                 - case when v_ldist then 0.13 - 0.002 * (v_p[v_k].fin - 65) else 0 end;
          v_q := greatest(0.05, least(0.95, v_q * (0.85 + 0.15*v_p[v_k].fit)));
          v_gkidx := v_gki[d];
          v_r := random();
          if v_r < (0.20 + case when v_ldist then 0.08 else 0 end) then
            -- bloqueada
            if random() < 0.60 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then perform public.on_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, 'bloqueado'); end if;
          elsif random() < greatest(0.10, least(0.75, 0.26 + 0.32 * v_q + 0.0020 * (v_p[v_k].fin - 65))) then
            v_p[v_k].sot := v_p[v_k].sot + 1;
            if random() < greatest(0.05, least(0.70, 0.11 + 0.36 * v_q + 0.0015 * (v_p[v_k].fin - v_gkr[d]))) then
              -- GOL
              v_p[v_k].goals := v_p[v_k].goals + 1;
              v_sc[s] := v_sc[s] + 1;
              v_a := 0;
              if random() < 0.78 then
                v_w := '{}';
                for i in 1 .. v_n loop
                  v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and i <> v_k and v_p[i].pos <> 'GOL'
                                     then (v_p[i].aw + 0.6 * v_p[i].cw) * power(v_p[i].cre / 60, 2) else 0 end;
                end loop;
                v_a := public.mgr_pick(v_w);
                if v_a > 0 then v_p[v_a].assists := v_p[v_a].assists + 1; end if;
              end if;
              perform public.on_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid,
                                       case when v_a > 0 then v_p[v_a].pid end, case when v_head then 'de cabeça' when v_ldist then 'de fora da área' end);
            else
              if v_gkidx > 0 then v_p[v_gkidx].saves := v_p[v_gkidx].saves + 1; end if;
              if random() < 0.40 then v_corn[s] := v_corn[s] + 1; end if;
              if p_interactive is not null or v_q > 0.62 then
                perform public.on_event(p_fixture, v_min, v_side, 'save', v_p[v_k].pid,
                                         case when v_gkidx > 0 then v_p[v_gkidx].pid end, case when v_q > 0.62 then 'grande chance' end);
              end if;
            end if;
          else
            if random() < 0.18 then v_corn[s] := v_corn[s] + 1; end if;
            if p_interactive is not null then
              perform public.on_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_q > 0.62 then 'grande chance' end);
            end if;
          end if;
        end if;
      end if;
    end if;

    -- ---- bolas paradas: o cobrador decide. Falta perigosa: o batedor de faltas chuta direto (mais vezes quanto
    -- melhor for a finalização e a técnica dele) ou cruza; escanteio: o batedor daquele lado cruza para o cabeceio.
    -- Sem batedor definido em campo, cobra quem cruza/chuta melhor.
    for s in 1 .. 2 loop
      d := 3 - s;
      v_sp64 := greatest(0, v_corn[s] - v_cprev[s]) + v_fk[s];
      while v_sp64 > 0 loop
        v_sp64 := v_sp64 - 1;
        v_side := case when s = 1 then 'h' else 'a' end;
        if v_fk[s] > 0 then v_fk[s] := v_fk[s] - 1; v_detail := 'fk'; else v_detail := case when random() < 0.5 then 'r' else 'l' end; end if;
        v_tk := 0; v_e := -1;
        for i in 1 .. v_n loop
          continue when not v_p[i].on_field or v_p[i].sd <> s or v_p[i].pos = 'GOL';
          v_q := case when v_detail = 'fk' then (v_p[i].fin + v_p[i].cre) / 2 else v_p[i].cre end
                 + case when v_p[i].pid = case v_detail when 'fk' then v_fktaker[s] when 'r' then v_ckr[s] else v_ckl[s] end then 1000 else 0 end;
          if v_q > v_e then v_e := v_q; v_tk := i; end if;
        end loop;
        continue when v_tk = 0;
        v_ldist := v_detail = 'fk' and random() < greatest(0.15, least(0.65, 0.35 + 0.02 * ((v_p[v_tk].fin + v_p[v_tk].cre) / 2 - 68)));
        v_head := not v_ldist;
        if v_ldist then v_k := v_tk;
        else
          v_w := '{}';
          for i in 1 .. v_n loop
            v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL' and i <> v_tk then
              (v_p[i].aw + 0.5 * v_p[i].dw + 0.2) * power(v_p[i].head / 60, 3) * case when v_markq ? v_p[i].pid then 0.75 else 1 end else 0 end;
          end loop;
          v_k := public.mgr_pick(v_w);
          continue when v_k = 0;
        end if;
        v_spq := case when v_ldist then 0.034 + 0.0018 * (v_p[v_k].fin - 65) + 0.0012 * (v_p[v_k].cre - 65)
                      else 0.018 + 0.0010 * (v_p[v_k].head - v_defav[d]) + 0.0009 * (v_p[v_tk].cre - 65)
                           - 0.5 * coalesce((v_markq->>v_p[v_k].pid)::float8, 0) end + 0.5 * v_spb[s];
        v_spq := greatest(0.005, least(0.15, v_spq));
        if random() < 0.55 then
          v_p[v_k].shots := v_p[v_k].shots + 1;
          if random() < v_spq / 0.55 then
            v_p[v_k].sot := v_p[v_k].sot + 1; v_p[v_k].goals := v_p[v_k].goals + 1; v_sc[s] := v_sc[s] + 1;
            if v_head then v_p[v_tk].assists := v_p[v_tk].assists + 1; end if;
            perform public.on_event(p_fixture, v_min, v_side, 'goal', v_p[v_k].pid, case when v_head then v_p[v_tk].pid end,
              case when v_ldist then 'cobrança de falta' when v_detail = 'fk' then 'falta cruzada, de cabeça' else 'escanteio, de cabeça' end);
          elsif p_interactive is not null and random() < 0.5 then
            perform public.on_event(p_fixture, v_min, v_side, 'shot_off', v_p[v_k].pid, null, case when v_ldist then 'cobrança de falta' else 'bola parada' end);
          end if;
        end if;
      end loop;
    end loop;
    v_cprev := array[v_corn[1], v_corn[2]];
    v_fk := array[0, 0];

    -- ---- faltas no meio-campo e cartões (os dois times) ----
    for s in 1 .. 2 loop
      continue when random() >= 0.125 * v_foulm[s] * (case when v_min > 75 then 1.15 else 1 end);
      v_side := case when s = 1 then 'h' else 'a' end;
      v_w := '{}';
      for i in 1 .. v_n loop
        v_w := v_w || case when v_p[i].on_field and v_p[i].sd = s and v_p[i].pos <> 'GOL'
                           then (v_p[i].dw + 0.3) * (1 + (100 - v_p[i].tack) / 100) * case when v_p[i].yel > 0 then 0.45 else 1 end else 0 end;
      end loop;
      v_k := public.mgr_pick(v_w);
      continue when v_k = 0;
      v_p[v_k].fouls := v_p[v_k].fouls + 1;
      v_card:=public.mgr_card_chances((v_profiles->v_p[v_k].pid->>0)::numeric,(v_profiles->v_p[v_k].pid->>1)::numeric,
        v_p[v_k].tack::numeric,v_p[v_k].cond::numeric,v_p[v_k].fouls,v_p[v_k].yel>0,v_tackles[s],v_ref::numeric,case when v_min>75 and abs(v_sc[1]-v_sc[2])<=1 then 1.10 else 1.0 end);
      v_r:=random();
      if v_r<(v_card->>'red')::float8 then
        v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
        perform public.on_event(p_fixture,v_min,v_side,'red',v_p[v_k].pid,null,'Entrada temerária');
        update public.on_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
        
      elsif v_r<(v_card->>'red')::float8+(v_card->>'yellow')::float8 then
        if v_p[v_k].yel>=1 then
          v_p[v_k].yel:=2;v_p[v_k].red:=1;v_p[v_k].on_field:=false;v_dirty:=true;
          perform public.on_event(p_fixture,v_min,v_side,'second_yellow',v_p[v_k].pid);
          update public.on_match_players set status='sent_off',left_min=v_min,slot=null where fixture_id=p_fixture and player_id=v_p[v_k].pid;
          
        else
          v_p[v_k].yel:=1;perform public.on_event(p_fixture,v_min,v_side,'yellow',v_p[v_k].pid);
        end if;
      end if;
    end loop;

    -- ---- desgaste, lesões e minutos jogados ----
    v_inj_stop := false;
    if v_min % 3 = 0 then
      for i in 1 .. v_n loop
        continue when not v_p[i].on_field;
        s := v_p[i].sd;
        v_side := case when s = 1 then 'h' else 'a' end;
        v_p[i].cond := greatest(0, v_p[i].cond - 3 * 0.21 * v_p[i].drain * (1.32 - v_p[i].stam / 100 * 0.62) * v_drainm[s]
                                   * case when v_et then 1.15 else 1 end);
        if random() < 3 * 0.00005 * (1 + greatest(0, 70 - v_p[i].cond) / 25) * (case when v_tpress[s] = 'high' then 1.15 else 1 end) then
          v_p[i].inj := true; v_p[i].on_field := false; v_dirty := true;
          perform public.on_event(p_fixture, v_min, v_side, 'injury', v_p[i].pid);
          update public.on_match_players set status = 'injured_off', injured = true, left_min = v_min where fixture_id = p_fixture and player_id = v_p[i].pid;
          if strpos(coalesce(p_interactive,''),v_side)>0 then null;
          else
            -- a IA troca na hora (se ainda tiver substituição)
            v_detail := public.on_do_sub(p_fixture, v_side, v_p[i].pid, public.on_best_bench(p_fixture, v_side, v_p[i].pos), v_min, true);
            v_reload := true;
          end if;
        end if;
      end loop;
    end if;
    if v_inj_stop then v_stop := 'injury'; end if;

    if v_reload then  -- grava o estado antes de recarregar a lista de quem está em campo
      update public.on_matches
         set state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
       where fixture_id = p_fixture;
    end if;

    exit when v_stop in ('red', 'injury');
    if v_min = 45 and not v_et then v_stop := 'ht'; exit; end if;
    if v_min = 105 and v_et then v_stop := 'et_ht'; exit; end if;
  end loop;

  -- grava tudo
  if v_p is not null then
    update public.on_match_players m
       set cond = round(x.cond::numeric, 2), goals = x.goals, assists = x.assists, shots = x.shots, sot = x.sot, saves = x.saves,
           fouls = x.fouls, yellow = x.yel, red = x.red,
           minutes = greatest(0, coalesce(m.left_min, v_min) - coalesce(m.entered_min, 0))
      from unnest(v_p) x where m.fixture_id = p_fixture and m.player_id = x.pid;
  end if;
  update public.on_matches
     set minute = v_min, updated_at = now(),
         state = state || jsonb_build_object('score', to_jsonb(v_sc), 'poss', to_jsonb(v_poss), 'corners', to_jsonb(v_corn), 'offsides', to_jsonb(v_offs))
   where fixture_id = p_fixture;

  if v_min >= (case when v_et then 120 else 90 end) then v_stop := 'ft'; end if;
  if v_stop = 'segment' and v_min = 45 then v_stop := 'ht'; end if;
  return v_stop;
end;
$function$;

-- temporada de séries em andamento: horários novos e bots no nível máximo
do $$ declare v smallint;k int;
begin
 for v in select id from public.on_seasons where status='live' and series loop perform public.on_retime_season(v);end loop;
 for k in select c.id from public.on_clubs c join public.on_seasons s on s.id=c.season_id and s.status='live' where c.user_id is null loop
  perform public.on_bot_max(k);
 end loop;
end $$;

revoke all on function public.on_lane_min(text,int),public.on_block_time(smallint,int,int),public.on_retime(smallint,int,text,boolean),
 public.on_retime_season(smallint),public.on_fx_add(smallint,text,text,int,int,int,int,int,int,int,text,int),public.on_bot_max(int),
 public.on_plans(),public.on_plan_vs(text,text),public.on_plan_legacy(jsonb),public.on_marks_clean(jsonb),public.on_tactics_clean(jsonb),
 public.on_plan_edge(text,jsonb,jsonb),public.on_plan_effect(bigint,int,jsonb,jsonb,numeric,numeric,numeric,numeric),public.on_ai_plan(int,int,numeric,boolean),
 public.on_roles_norm(jsonb),public.on_roles_swap(jsonb,text,text),public.on_roles_remap(jsonb,jsonb),public.on_roles_inherit(jsonb,text,text,text)
 from public,anon,authenticated;
revoke all on function public.on_plan_fit(bigint),public.on_roles_save(jsonb) from public,anon;
grant execute on function public.on_plan_fit(bigint),public.on_roles_save(jsonb) to authenticated;
