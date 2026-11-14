-- Evolução 75: renovação em andamento não deixa o atleta sair de graça.
--
-- Antes: o contrato vencia no dia seguinte ao fim do vínculo mesmo com uma renovação aberta. Se o técnico propunha a
-- renovação perto do vencimento (o atleta responde em alguns dias) ou se o atleta fazia contraproposta, avançar o
-- calendário encerrava o contrato e o jogador saía de graça.
-- Agora:
--  • enquanto houver renovação em andamento (aguardando o atleta, contraproposta ou aceite a confirmar), o contrato
--    não vence; o vínculo segue (e continua válido para concluir a renovação) até a negociação terminar. A
--    contraproposta do atleta já para o calendário (aviso);
--  • o aviso "contratos vencendo" deixa de listar quem já está em renovação.
CREATE OR REPLACE FUNCTION public.cw_finance_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;coach public.mgr_coach;ct public.cw_contracts;
begin
 perform public.cw_prepare_club_economy(p_career);
 perform public.cw_ai_contracts_tick(p_career);
 select * into w from public.cw_world where career_id=p_career;
 if extract(day from w.today)=1 then perform public.cw_settle_month(p_career,(date_trunc('month',w.today)-interval '1month')::date);end if;
 select * into coach from public.mgr_coach where career_id=p_career;
 for ct in select * from public.cw_contracts where career_id=p_career and status='active' and expires_on<w.today
  and(not public.cw_runtime_enabled(p_career) or club_id=coach.club_id or club_id in(select public.cw_domestic_clubs(p_career))
   or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id and n.status='precontract'))
  -- Evolução 75: renovação em andamento segura o vínculo até a negociação terminar (aceita, recusada ou vencida).
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cw_contracts.player_id
   and n.initiator='renewal' and n.buyer_club=cw_contracts.club_id
   and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','player_accepted','agreed')) loop
  update public.cw_contracts set status='expired',ended_on=expires_on where id=ct.id and career_id=ct.career_id;
  update public.mgr_players set club_id=null where career_id=p_career and player_id=ct.player_id and club_id=ct.club_id;
  perform public.cw_prune_lineups(p_career,ct.player_id);
  perform public.cw_news_add(p_career,'expiry:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' encerra seu contrato',
   'O atleta está livre após o encerramento do vínculo com '||public.mgr_club_name(ct.club_id)||'.',case when ct.club_id=coach.club_id then 85 else 30 end,ct.club_id,ct.player_id);
 end loop;
end $function$;

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
 -- quem já está em renovação (ou com acordo) sai do aviso: o andamento aparece como negociação
 and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=ct.player_id
  and (n.status in('agreed','precontract') or (n.initiator='renewal' and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','player_accepted','agreed'))))
 having count(*)>0
 )x where not exists(select 1 from public.cw_attention_acks a where a.career_id=p_career and a.decision_key=x.j->>'key') order by ts limit 1;
 if a is null then return null;end if;
 return a;
end $function$;

-- O vínculo segurado pela renovação continua válido para a negociação ser concluída depois da data original.
CREATE OR REPLACE FUNCTION public.cw_valid_renewal(p_career uuid, p_player text, p_club text, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from public.mgr_players mp join public.cw_contracts ct
  on ct.career_id=mp.career_id and ct.player_id=mp.player_id and ct.club_id=mp.club_id
  where mp.career_id=p_career and mp.player_id=p_player and mp.club_id=p_club
   and ct.status='active' and ct.starts_on<=p_date
   and (ct.expires_on>=p_date or exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=p_player
    and n.initiator='renewal' and n.buyer_club=p_club
    and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','player_accepted','agreed'))))
$function$;
