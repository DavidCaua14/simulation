-- Evolução 73: contratos vencendo no elenco do técnico geram um só aviso.
-- No fim de temporada, cada contrato que vencia na semana parava o calendário com um e-mail próprio: o técnico do Remo
-- precisou dispensar 12 avisos seguidos para virar o ano. Agora os contratos da semana formam um único aviso; ele
-- volta se a lista mudar ou quando o primeiro vencimento estiver a um dia.
CREATE OR REPLACE FUNCTION public.cw_attention(p_career uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date;own text;a jsonb;k text;ack text;
begin
 select w.today,c.club_id,r.attention_ack into d,own,ack from public.cw_world w
 join public.mgr_coach c using(career_id) left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 select j into a from(
 select o.created_at ts,jsonb_build_object('id',o.id,'kind','job','expires_on',o.expires_on,'action','offers',
 'key','job:'||o.id||':'||o.negotiation_round||case when o.expires_on<=d+1 then ':deadline' else '' end) j
 from public.season_offers o where o.career_id=p_career and o.kind='coach' and o.status='pending' and o.expires_on>=d
 union all
 select n.created_on::timestamptz,jsonb_build_object('id',n.id,'kind','negotiation','expires_on',n.expires_on,'action','deals',
 'key','neg:'||n.id||':'||n.status||':'||n.round_no||case when n.expires_on<=d+1 then ':deadline' else '' end)
 from public.cw_negotiations n where n.career_id=p_career and n.expires_on>=d
 and (n.status in('seller_review','club_counter','player_counter')
  -- contratação aceita pelo atleta aguarda o clique em confirmar: o calendário para até o treinador decidir
  or (n.status='player_accepted' and n.buyer_club=own))
 and (n.initiator in('user','renewal') or n.seller_club=own)
 union all
 select w.today::timestamptz,jsonb_build_object('id',cc.career_id,'kind','coach_contract','expires_on',cc.contract_until,'action','contract',
 'key','contract:'||cc.contract_until||case when cc.contract_until<=d+1 then ':deadline' else '' end)
 from public.cw_coach cc join public.cw_world w using(career_id)
 where cc.career_id=p_career and own is not null and cc.contract_until between d and d+7
 union all
 -- Evolução 73: todos os contratos do elenco que vencem na semana viram um único aviso (antes, um por atleta).
 select min(ct.starts_on)::timestamptz,jsonb_build_object('id',min(ct.id::text),'kind','player_contract','count',count(*),'expires_on',min(ct.expires_on),'action','contracts',
 'key','player-contracts:'||md5(string_agg(ct.id::text||':'||ct.expires_on,',' order by ct.id))||case when min(ct.expires_on)<=d+1 then ':deadline' else '' end)
 from public.cw_contracts ct where ct.career_id=p_career and ct.club_id=own and ct.status='active' and ct.expires_on between d and d+7
 and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=ct.player_id and n.status in('agreed','precontract'))
 having count(*)>0
 )x where not exists(select 1 from public.cw_attention_acks a where a.career_id=p_career and a.decision_key=x.j->>'key') order by ts limit 1;
 if a is null then return null;end if;
 return a;
end $function$;
