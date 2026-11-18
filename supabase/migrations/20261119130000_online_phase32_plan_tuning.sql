-- MODO ONLINE — Fase 32: ajuste fino dos planos de jogo (medido no laboratório scripts/online-lab.mjs).
--
-- O que a rodada anterior (fase 31) deixou fora do ideal, com elencos idênticos e 120 jogos por confronto:
--  • Ataque total levava 65% dos pontos contra Equilibrado (a postura +2 já cria muito; o bônus extra sobrava);
--  • Pressão alta levava 63% contra Pelas pontas sem ter vantagem prevista (jeito de jogar forte demais);
--  • Retranca × Ataque total e Pelas pontas × Posse quase não mostravam a vantagem prevista (52–53%);
--  • o mandante vencia 46% dos jogos (antes da fase 31, 43%).
-- Agora: Ataque total sem bônus de criação, Pressão alta cansa mais e não cria a mais por si só, Pelas pontas finaliza
-- um pouco melhor (cruzamento na área) e a vantagem de casa cai de 1,10 para 1,07.

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
  when 'pressao' then ctl:=0.98;freq:=0.96;qual:=0.00;drain:=1.20;
  when 'contra' then ctl:=0.88;freq:=1.00;qual:=0.09;
  when 'retranca' then ctl:=0.92;freq:=0.76;ofreq:=0.78;oqual:=-0.05;drain:=0.90;
  when 'direto' then ctl:=0.92;freq:=1.12;qual:=0.00;hdr:=0.28;
  when 'pontas' then qual:=0.03;hdr:=0.34;
  when 'total' then freq:=0.95;qual:=0.00;drain:=1.10;
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

do $$ begin
 perform public.on_patch('public.on_engine_run(bigint,integer,text)',
  '(case when v_neut then 1 when s = 1 then 1.10 else 0.97 end)','(case when v_neut then 1 when s = 1 then 1.07 else 0.98 end)');
end $$;

revoke all on function public.on_plan_effect(bigint,int,jsonb,jsonb,numeric,numeric,numeric,numeric) from public,anon,authenticated;
