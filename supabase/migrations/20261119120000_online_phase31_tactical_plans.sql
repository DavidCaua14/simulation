-- MODO ONLINE — Fase 31: planos de jogo (táticas novas) e motor que obedece à tática e aos jogadores.
--
-- Medido no laboratório (scripts/online-lab.mjs, elencos gerados, temporadas inteiras):
--  • táticas antigas mexiam 1 a 5 pontos de vitória entre times iguais, dentro do sorteio: "o time não faz o que mando";
--  • nenhuma tática dependia de verdade do elenco nem da tática do adversário.
--
-- Agora o técnico escolhe um PLANO DE JOGO (tactics.plan). Cada plano tem:
--  • um jeito de jogar fixo (posse, frequência e qualidade das chances, desgaste, quanto expõe a defesa);
--  • confrontos: é forte contra uns planos e fraco contra outros (matriz on_plan_vs, pedra-papel-tesoura);
--  • aderência: rende mais quando o atributo-chave do elenco supera o mesmo atributo do adversário
--    (posse: técnica do meio e ataque; pressão: físico; contra-ataque: velocidade do ataque contra a da defesa;
--     retranca: defesa contra ataque; bola longa: jogo aéreo do centroavante contra o dos zagueiros;
--     pontas: pontas e laterais contra os laterais rivais; ataque total: ataque contra defesa).
-- Instruções que continuam valendo por cima do plano: entrada (tackling), chutes de fora (long_shots),
-- bola parada (set_pieces), gestão do resultado (manage: normal, keep, chase) e marcar o craque (mark).
-- Táticas salvas no formato antigo viram o plano mais próximo (on_tactics_clean).
-- O modo Temporadas não muda: as funções mgr_* continuam como estão.

-- ─────────────────────────────────────────────────────────────────────────────
-- Planos
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_plans() returns text[] language sql immutable as $$
 select array['equilibrado','posse','pressao','contra','retranca','direto','pontas','total'] $$;

-- Confronto direto: +1 o plano da linha leva vantagem sobre o da coluna, -1 desvantagem (a matriz é antissimétrica).
create or replace function public.on_plan_vs(p_me text,p_opp text) returns int language sql immutable as $$
 select coalesce((('{
  "posse":   {"contra":1,"direto":1,"pressao":-1,"pontas":-1},
  "pressao": {"posse":1,"retranca":1,"direto":-1,"contra":-1},
  "contra":  {"pressao":1,"total":1,"pontas":1,"posse":-1,"retranca":-1},
  "retranca":{"total":1,"direto":1,"contra":1,"pontas":-1,"pressao":-1},
  "direto":  {"pressao":1,"total":1,"posse":-1,"retranca":-1},
  "pontas":  {"retranca":1,"posse":1,"contra":-1},
  "total":   {"retranca":-1,"contra":-1,"direto":-1}
 }'::jsonb)->p_me->>p_opp)::int,0) $$;

-- Formato antigo (postura, jogo, marcação, ataque por) → plano.
create or replace function public.on_plan_legacy(t jsonb) returns text language sql immutable as $$
 select case
  when t->>'plan'=any(public.on_plans()) then t->>'plan'
  when t->>'style'='counter' then 'contra'
  when t->>'style'='defensive' then 'retranca'
  when t->>'style'='attacking' then 'total'
  when coalesce(t->>'marking',t->>'pressing')='high' then 'pressao'
  when coalesce(t->>'passing',case t->>'build' when 'short' then 'short' when 'direct' then 'long' end)='short' then 'posse'
  when coalesce(t->>'passing',case t->>'build' when 'short' then 'short' when 'direct' then 'long' end)='long' then 'direto'
  when coalesce(t->>'attack',case t->>'width' when 'wide' then 'both' end) in('both','left','right') then 'pontas'
  else 'equilibrado' end $$;

-- Táticas do modo online: plano + instruções. Também devolve os campos antigos que o motor lê
-- (postura, pressão, linha, construção, largura), coerentes com o plano: quem lê o formato antigo vê o mesmo plano.
create or replace function public.on_tactics_clean(p_t jsonb) returns jsonb language plpgsql immutable as $$
declare t jsonb:=coalesce(p_t,'{}'::jsonb);v_plan text:=public.on_plan_legacy(t);v_ment int;
begin
 v_ment:=case v_plan when 'total' then 2 when 'pressao' then 1 when 'retranca' then -1 when 'contra' then -1 else 0 end;
 return jsonb_build_object(
  'plan',v_plan,
  'tackling',case when t->>'tackling' in('light','balanced','heavy') then t->>'tackling'
   else case t->>'tackles' when 'cautious' then 'light' when 'aggressive' then 'heavy' else 'balanced' end end,
  'long_shots',case when t->>'long_shots' in('often','sometimes','rarely') then t->>'long_shots' else 'sometimes' end,
  'set_pieces',case when t->>'set_pieces' in('shoot','cross','short') then t->>'set_pieces' else 'cross' end,
  'manage',case when t->>'manage' in('normal','keep','chase') then t->>'manage' else 'normal' end,
  'mark',case when t->>'mark' ~ '^[A-Za-z0-9_-]{1,40}$' then t->>'mark' end,
  -- campos lidos pelo motor
  'mentality',v_ment,
  'style',case v_plan when 'contra' then 'counter' when 'retranca' then 'defensive' when 'total' then 'attacking' else 'neutral' end,
  'marking',case v_plan when 'pressao' then 'high' when 'retranca' then 'low' when 'contra' then 'low' else 'medium' end,
  'pressing',case v_plan when 'pressao' then 'high' when 'retranca' then 'low' when 'contra' then 'low' else 'medium' end,
  'line',case v_plan when 'pressao' then 'high' when 'total' then 'high' when 'retranca' then 'low' when 'contra' then 'low' else 'medium' end,
  'passing',case v_plan when 'posse' then 'short' when 'direto' then 'long' else 'mixed' end,
  'build','mixed','tempo','normal',
  'attack',case v_plan when 'pontas' then 'both' when 'posse' then 'central' else 'mixed' end,
  'width',case v_plan when 'pontas' then 'wide' else 'mixed' end,
  'crossing',case v_plan when 'pontas' then 'byline' when 'direto' then 'deep' when 'posse' then 'rarely' else 'mixed' end,
  'tackles',case when t->>'tackling'='light' or t->>'tackles'='cautious' then 'cautious'
   when t->>'tackling'='heavy' or t->>'tackles'='aggressive' then 'aggressive' else 'normal' end);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Perfil do time em campo (atributos do motor por setor). Mesmo cálculo para a partida e para a escalação salva.
-- tec: criação e controle do meio e ataque · fis: fôlego (com a condição) e velocidade · vatt/vdef: velocidade do
-- ataque e da defesa · aatt/adef: cabeceio e força do centroavante e dos zagueiros · wide: pontas e laterais
-- (velocidade e criação) · wdef: laterais (defesa e velocidade) · def: defesa e desarme da defesa e volantes ·
-- att: ataque e finalização do ataque.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_profile_rows(p_rows jsonb) returns jsonb language sql immutable as $$
 select jsonb_build_object(
  'tec',coalesce(avg((r.cre+r.ctl)/2) filter(where r.line in('MID','ATT')),50),
  'fis',coalesce(avg((r.stam*r.cond/100+r.pace)/2) filter(where r.line<>'GK'),50),
  'vatt',coalesce(avg(r.pace) filter(where r.line='ATT'),avg(r.pace) filter(where r.pos='MEI'),50),
  'vdef',coalesce(avg(r.pace) filter(where r.line='DEF'),50),
  'aatt',coalesce(avg((r.head+r.str)/2) filter(where r.pos='ATA'),avg((r.head+r.str)/2) filter(where r.line='ATT'),45),
  'adef',coalesce(avg((r.head+r.str)/2) filter(where r.pos='ZAG'),50),
  'wide',coalesce(avg((r.pace+r.cre)/2) filter(where r.pos in('PD','PE','LD','LE')),50),
  'wdef',coalesce(avg((r.def+r.pace)/2) filter(where r.pos in('LD','LE')),avg((r.def+r.pace)/2) filter(where r.line='DEF'),50),
  'def',coalesce(avg((r.def+r.tack)/2) filter(where r.line='DEF' or r.pos='VOL'),50),
  'att',coalesce(avg((r.att+r.fin)/2) filter(where r.line='ATT'),50))
 from jsonb_to_recordset(p_rows) r(pos text,line text,att numeric,cre numeric,def numeric,ctl numeric,fin numeric,head numeric,
  pace numeric,stam numeric,tack numeric,str numeric,cond numeric) $$;

create or replace function public.on_side_profile(p_fixture bigint,p_side char) returns jsonb language sql stable set search_path=public as $$
 select public.on_profile_rows(coalesce(jsonb_agg(jsonb_build_object('pos',mp.pos,'line',sp.line,
  'att',mp.c_att*mp.fit,'cre',mp.c_cre*mp.fit,'def',mp.c_def*mp.fit,'ctl',mp.c_ctl*mp.fit,'fin',mp.c_fin*mp.fit,'head',mp.c_head*mp.fit,
  'pace',mp.c_pace*mp.fit,'stam',mp.c_stam*mp.fit,'tack',mp.c_tack*mp.fit,'str',mp.c_str*mp.fit,'cond',mp.cond)),'[]'))
 from public.on_match_players mp join public.sim_positions sp on sp.code=mp.pos
 where mp.fixture_id=p_fixture and mp.side=p_side and mp.status='on' $$;

create or replace function public.on_club_profile(p_club int) returns jsonb language sql stable set search_path=public as $$
 select public.on_profile_rows(coalesce(jsonb_agg(jsonb_build_object('pos',x.pos,'line',sp.line,
  'att',c[1]*x.fit,'cre',c[2]*x.fit,'def',c[3]*x.fit,'ctl',c[4]*x.fit,'fin',c[6]*x.fit,'head',c[7]*x.fit,
  'pace',c[8]*x.fit,'stam',c[9]*x.fit,'tack',c[10]*x.fit,'str',c[11]*x.fit,'cond',p.cond)),'[]'))
 from public.on_lineups l
 cross join lateral jsonb_array_elements((select f.slots from public.sim_formations f where f.id=l.formation)) s
 join public.on_players p on p.id=l.slots->>(s->>'slot')
 cross join lateral(select s->>'pos' pos,greatest(coalesce((select ft.fit from public.sim_position_fit ft where ft.from_pos=p.pos and ft.to_pos=s->>'pos'),.5),
  case when s->>'pos'=any(p.sec) then .97 else 0 end) fit) x
 join public.sim_positions sp on sp.code=x.pos
 cross join lateral(select public.on_comp(p.id,p.pos,p.level,p.g) c) k
 where l.club_id=p_club $$;

-- Aderência do plano: vantagem do atributo-chave sobre o mesmo atributo do adversário, em unidades de 10 pontos (−1,5 a +1,5).
create or replace function public.on_plan_edge(p_plan text,p_me jsonb,p_opp jsonb) returns numeric language sql immutable as $$
 select greatest(-1.5,least(1.5,coalesce(case p_plan
  when 'posse' then (p_me->>'tec')::numeric-(p_opp->>'tec')::numeric
  when 'pressao' then (p_me->>'fis')::numeric-(p_opp->>'fis')::numeric
  when 'contra' then (p_me->>'vatt')::numeric-(p_opp->>'vdef')::numeric
  when 'retranca' then (p_me->>'def')::numeric-(p_opp->>'att')::numeric
  when 'direto' then (p_me->>'aatt')::numeric-(p_opp->>'adef')::numeric
  when 'pontas' then (p_me->>'wide')::numeric-(p_opp->>'wdef')::numeric
  when 'total' then (p_me->>'att')::numeric-(p_opp->>'def')::numeric
  else 0 end,0)/10)) $$;

-- Efeito do plano para o motor (mesmas chaves de mgr_tactical_effect e mais as que valem para o adversário):
-- control/frequency/quality do meu ataque, ofreq/oqual do ataque rival, drain do meu desgaste, hdr parcela de cabeceios.
create or replace function public.on_plan_effect(p_fixture bigint,p_s int,p_t jsonb,p_opp jsonb,p_skill numeric,p_pace numeric,p_stamina numeric,p_head numeric)
returns jsonb language plpgsql stable set search_path=public as $$
declare me text:=coalesce(p_t->>'plan',public.on_plan_legacy(p_t));op text:=coalesce(p_opp->>'plan',public.on_plan_legacy(p_opp));
 pm jsonb:=public.on_side_profile(p_fixture,case when p_s=1 then 'h' else 'a' end);
 po jsonb:=public.on_side_profile(p_fixture,case when p_s=1 then 'a' else 'h' end);
 vs int:=public.on_plan_vs(me,op);e numeric:=public.on_plan_edge(me,pm,po);
 ctl numeric:=1;freq numeric:=1;qual numeric:=0;ofreq numeric:=1;oqual numeric:=0;drain numeric:=1;hdr numeric;
begin
 -- jeito de jogar
 case me
  when 'posse' then ctl:=1.06;freq:=0.95;qual:=0.02;drain:=0.90;ofreq:=0.97;
  when 'pressao' then ctl:=1.02;freq:=1.02;qual:=0.01;drain:=1.10;
  when 'contra' then ctl:=0.88;freq:=1.00;qual:=0.09;
  when 'retranca' then ctl:=0.92;freq:=0.76;ofreq:=0.78;oqual:=-0.05;drain:=0.90;
  when 'direto' then ctl:=0.92;freq:=1.12;qual:=0.00;hdr:=0.28;
  when 'pontas' then hdr:=0.34;
  when 'total' then freq:=1.10;qual:=0.02;drain:=1.10;
  else null;
 end case;
 -- confronto: quem leva vantagem cria mais e finaliza melhor; quem está em desvantagem, o contrário
 freq:=freq*(1+0.14*vs);qual:=qual+0.05*vs;
 -- aderência: o elenco que executa melhor o plano rende mais (vale também para o confronto)
 if me<>'equilibrado' then
  freq:=freq*(1+0.06*e);qual:=qual+0.04*e;
  if me='posse' then ctl:=ctl*(1+0.05*e);end if;
  if me='retranca' then ofreq:=ofreq*(1-0.05*e);oqual:=oqual-0.02*e;end if;
 end if;
 -- marcação individual no craque rival: tira um pouco da criação do time dele
 if p_t->>'mark' is not null then ofreq:=ofreq*0.97;drain:=drain*1.03;end if;
 return jsonb_build_object('control',ctl,'frequency',freq,'quality',qual,'ofreq',ofreq,'oqual',oqual,'drain',drain,'hdr',hdr,
  'vs',vs,'edge',round(e,2));
end $$;

-- Plano escolhido pela IA (bots e o "auxiliar"): pela diferença de força e pela aderência do elenco.
-- Não olha a tática do adversário (o bot não sabe o que o usuário escolheu).
create or replace function public.on_ai_plan(p_club int,p_opp int,p_diff numeric,p_home boolean) returns jsonb
language plpgsql stable set search_path=public as $$
declare pm jsonb:=public.on_club_profile(p_club);po jsonb:=public.on_club_profile(p_opp);v_plan text;v_best numeric:=-9;p text;v numeric;
begin
 foreach p in array case when p_diff>4 then array['pressao','posse','pontas','equilibrado']
  when p_diff<-5 then array['contra','retranca','direto']
  else array['equilibrado','posse','pontas','direto','pressao','contra'] end loop
  v:=public.on_plan_edge(p,pm,po)+case when p='equilibrado' then 0.3 else 0 end;
  if v>v_best then v_best:=v;v_plan:=p;end if;
 end loop;
 return jsonb_build_object('plan',v_plan,'manage',case when p_diff>4 then 'keep' else 'normal' end);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ligações com o resto do modo online
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 -- motor: o efeito tático passa a ser o do plano (o resto do cálculo continua igual)
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  'v_effect:=public.mgr_tactical_effect(','v_effect:=public.on_plan_effect(p_fixture,s,');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '        v_qual[s]:=v_qual[s]+(v_effect->>''quality'')::float8;',
  '        v_qual[s]:=v_qual[s]+(v_effect->>''quality'')::float8;
        v_freq[3-s]:=v_freq[3-s]*coalesce((v_effect->>''ofreq'')::float8,1);
        v_qual[3-s]:=v_qual[3-s]+coalesce((v_effect->>''oqual'')::float8,0);
        v_drainm[s]:=v_drainm[s]*coalesce((v_effect->>''drain'')::float8,1);
        if v_effect->>''hdr'' is not null then v_hdr[s]:=(v_effect->>''hdr'')::float8; end if;');
 -- marcação individual: o craque marcado finaliza pior
 perform public.on_patch('public.on_engine_run(bigint,integer,text)','  v_rprob float8;','  v_rprob float8;
  v_mark text[];');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '      v_spk := array[coalesce(v_tac->''h''->>''set_pieces'',''cross''), coalesce(v_tac->''a''->>''set_pieces'',''cross'')];',
  '      v_spk := array[coalesce(v_tac->''h''->>''set_pieces'',''cross''), coalesce(v_tac->''a''->>''set_pieces'',''cross'')];
      v_mark := array[v_tac->''a''->>''mark'', v_tac->''h''->>''mark''];');
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '                 - case when v_head then 0.08 else 0 end',
  '                 - case when v_head then 0.08 else 0 end
                 - case when v_p[v_k].pid = v_mark[s] then 0.10 else 0 end');
 -- abertura da partida: táticas limpas no formato novo; bot escolhe o plano
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  'th:=public.mgr_tactics_clean(case when bh then public.mgr_ai_tactics(sh-sa,not v_neut) else lh->''tactics'' end);',
  'th:=public.on_tactics_clean(case when bh then public.on_ai_plan(p_fx.home,p_fx.away,sh-sa,not v_neut) else lh->''tactics'' end);');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  'ta:=public.mgr_tactics_clean(case when ba then public.mgr_ai_tactics(sa-sh,false) else la->''tactics'' end);',
  'ta:=public.on_tactics_clean(case when ba then public.on_ai_plan(p_fx.away,p_fx.home,sa-sh,false) else la->''tactics'' end);');
 -- mudança durante o jogo e escalação salva
 perform public.on_patch('public.on_match_act(bigint,text,jsonb)',
  't:=public.mgr_tactics_clean(coalesce(m.state->''tactics''->sd,''{}''::jsonb)||(p_changes->''tactics''));',
  't:=public.on_tactics_clean(case when p_changes->''tactics'' ? ''plan'' or not (p_changes->''tactics'' ?| array[''style'',''passing'',''marking'',''attack''])
    then coalesce(m.state->''tactics''->sd,''{}''::jsonb)||(p_changes->''tactics'')
    else (coalesce(m.state->''tactics''->sd,''{}''::jsonb)-''plan'')||(p_changes->''tactics'') end);');
 perform public.on_patch('public.on_lineup_save(text,jsonb,text[],jsonb)',
  'public.mgr_tactics_clean(coalesce(p_tactics,''{}''::jsonb))','public.on_tactics_clean(coalesce(p_tactics,''{}''::jsonb))');
end $$;

-- escalações salvas passam para o formato novo (o plano mais próximo do que o técnico tinha escolhido)
update public.on_lineups set tactics=public.on_tactics_clean(tactics) where not tactics ? 'plan';

-- ─────────────────────────────────────────────────────────────────────────────
-- Força e craques pesam mais; bot sem vantagem escondida
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 -- diferença de força entre os times decide mais (expoente 0,65 → 1,20)
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '/ greatest(v_def[d] * v_dmult[d], 1) / 0.86, 0.65)','/ greatest(v_def[d] * v_dmult[d], 1) / 0.86, 1.20)');
 -- vantagem de jogar em casa um pouco menor (com o expoente maior ela crescia junto)
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '(case when v_neut then 1 when s = 1 then 1.16 else 0.96 end)','(case when v_neut then 1 when s = 1 then 1.10 else 0.97 end)');
 -- o atacante bom contra a defesa fraca finaliza melhor (0,0025 → 0,0055 por ponto de atributo)
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  'v_q := 0.30 + 0.0025 * ((case when v_head','v_q := 0.30 + 0.0055 * ((case when v_head');
 -- bot e usuário ausente jogam com as mesmas regras: durante o jogo a IA só substitui; a postura muda pela
 -- "gestão do resultado" (segurar/buscar), que o motor já aplica para os dois
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  if v_human then v_ment := coalesce((v_m.state -> ''tactics'' -> p_side ->> ''mentality'')::int, v_base);',
  '  if true then v_ment := coalesce((v_m.state -> ''tactics'' -> p_side ->> ''mentality'')::int, v_base); -- fase 31: igual para bot e usuário');
 perform public.on_patch('public.on_ai_manage(bigint,character,integer)',
  '  if p_minute>=60 and not v_human then','  if false and p_minute>=60 and not v_human then -- fase 31: bot não muda a tática no meio do jogo');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Tela: aderência de cada plano do meu time contra o adversário (próximo jogo ou partida ao vivo)
-- ─────────────────────────────────────────────────────────────────────────────
-- O plano do adversário NUNCA é revelado (nem antes nem durante o jogo): só a aderência, que compara os jogadores.
create or replace function public.on_plan_fit(p_fixture bigint default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);f public.on_fixtures;sd char;o int;pm jsonb;po jsonb;v_live boolean:=false;
begin
 if p_fixture is not null then
  select * into f from public.on_fixtures where id=p_fixture and season_id=c.season_id;
 else
  f:=public.on_next_fixture(c.id);
 end if;
 if f.id is null then return jsonb_build_object('plans',null);end if;
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
  'plans',(select jsonb_object_agg(p,jsonb_build_object('edge',round(public.on_plan_edge(p,pm,po),2))) from unnest(public.on_plans()) p),
  'mark',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'ovr',p.ovr) order by p.ovr desc)
   from(select q.* from public.on_players q where q.club_id=o
    and (not v_live or exists(select 1 from public.on_match_players mp where mp.fixture_id=f.id and mp.player_id=q.id and mp.status='on'))
    order by q.ovr desc,q.id limit 4) p),'[]'::jsonb));
end $$;


revoke all on function public.on_plans(),public.on_plan_vs(text,text),public.on_plan_legacy(jsonb),public.on_tactics_clean(jsonb),
 public.on_profile_rows(jsonb),public.on_side_profile(bigint,char),public.on_club_profile(int),public.on_plan_edge(text,jsonb,jsonb),
 public.on_plan_effect(bigint,int,jsonb,jsonb,numeric,numeric,numeric,numeric),public.on_ai_plan(int,int,numeric,boolean) from public,anon,authenticated;
revoke all on function public.on_plan_fit(bigint) from public,anon;
grant execute on function public.on_plan_fit(bigint) to authenticated;
