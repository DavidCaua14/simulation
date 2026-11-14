-- Evolução 71: recusa de proposta pelo jogador do técnico com o texto certo.
-- Quando o técnico recusava a proposta de outro clube por um atleta dele, a caixa de entrada dizia
-- "Coritiba recusa a proposta por X", como se o comprador tivesse desistido. Agora: "A pedido do técnico, o
-- Fortaleza recusou a proposta do Coritiba por X". Se o técnico é o comprador e encerra a negociação: "A pedido do
-- técnico, o Fortaleza encerrou a negociação por X". Os demais textos não mudam.
CREATE OR REPLACE FUNCTION public.cw_neg_inbox_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare own text;who text;pl text;buyer text;seller text;t text;b text;fee text;mine_buy boolean;
begin
 select club_id into own from public.mgr_coach where career_id=new.career_id and status='employed';
 if own is null or own not in(coalesce(new.buyer_club,''),coalesce(new.seller_club,'')) then return null;end if;
 if tg_op='UPDATE' and new.status is not distinct from old.status then return null;end if;
 pl:=public.mgr_player_name(new.player_id);buyer:=public.mgr_club_name(new.buyer_club);seller:=coalesce(public.mgr_club_name(new.seller_club),'o clube');
 fee:=public.cw_money_label(new.fee);mine_buy:=new.buyer_club=own;
 if tg_op='INSERT' then
  if new.initiator='ai' and new.seller_club=own and new.status='seller_review' then
   t:=buyer||' faz proposta por '||pl;b:='Oferta de '||fee||'. Aceite, recuse ou faça uma contraproposta até '||to_char(new.expires_on,'DD/MM')||'.';
  elsif new.initiator='ai' and new.seller_club=own and new.status='precontract' then
   t:=pl||' assina pré-contrato com '||buyer;b:='Sem renovação, o atleta deixa o clube de graça em '||to_char(new.register_on,'DD/MM/YYYY')||'.';
  else return null;end if;
 elsif new.status='club_counter' and mine_buy then t:=seller||' faz contraproposta por '||pl;b:='O clube pede '||fee||'. Responda até '||to_char(new.expires_on,'DD/MM')||'.';
 elsif new.status='player_counter' and mine_buy and old.status='club_pending' then t:=seller||' aceita negociar '||pl;b:='Clubes de acordo. Agora negocie o contrato: salário por mês e duração (até 5 anos).';
 elsif new.status='player_counter' and mine_buy and old.status='player_pending' then t:=pl||' pede melhores condições';b:=coalesce(new.response,'O atleta quer um contrato melhor.')||' Pedido: '||public.cw_money_label(public.cw_weekly(new.monthly_salary))||' por mês.';
 elsif new.status='player_accepted' and mine_buy then t:=pl||' aceita sua oferta';b:=coalesce(new.response,'Confirme o negócio para concluir.');
 elsif new.status in('agreed','precontract') and mine_buy then
  t:=case when new.initiator='renewal' then pl||' aceita renovar' else 'Acordo fechado com '||pl end;
  b:=case when new.register_on>(select today from public.cw_world where career_id=new.career_id) then 'Registro em '||to_char(new.register_on,'DD/MM/YYYY')||'.' else 'Contrato registrado.' end;
 elsif new.status='completed' and new.initiator<>'renewal' then
  t:=case when mine_buy then pl||' é reforço do '||buyer else pl||' é vendido ao '||buyer end;
  b:=case when new.fee>0 then 'Valor: '||fee||'. ' else 'Transferência sem custo. ' end||'Contrato de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='completed' and new.initiator='renewal' then t:=pl||' renova contrato';b:='Novo vínculo de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='rejected' then
  who:=case when old.status='player_pending' then pl when mine_buy then seller else buyer end;
  -- Recusa feita pelo técnico (cw_neg_action 'reject'): quem encerrou foi o clube dele, não o outro clube.
  t:=case when new.response='Proposta recusada pelo treinador.' and not mine_buy then 'A pedido do técnico, o '||seller||' recusou a proposta do '||buyer||' por '||pl
   when new.response='Proposta recusada pelo treinador.' then 'A pedido do técnico, o '||buyer||' encerrou a negociação por '||pl
   when not mine_buy and old.status='player_pending' then pl||' recusa ir para o '||buyer when new.initiator='renewal' then pl||' recusa a renovação' else who||' recusa a proposta por '||pl end;
  b:=coalesce(new.response,'Negociação encerrada.');
 elsif new.status='expired' then t:='Proposta por '||pl||' expirou';b:='O prazo terminou sem acordo.';
 elsif new.status='failed_funds' then t:='Negócio por '||pl||' cancelado';b:=coalesce(new.response,'Orçamento insuficiente para concluir.');
 elsif new.status='cancelled' and old.status in('agreed','precontract','club_pending','player_pending') then t:='Negociação por '||pl||' cancelada';b:=coalesce(new.response,'');
 else return null;end if;
 perform public.cw_inbox_add(new.career_id,'neg:'||new.id||':'||new.status||':'||coalesce(new.round_no,0),'transfer','market',t,b,
  case when new.buyer_club=own then coalesce(new.seller_club,own) else new.buyer_club end,new.player_id,new.id,'open_negotiations');
 return null;
end $function$;

-- Corrige os e-mails já enviados com o texto antigo.
update public.mgr_messages m set title=case when n.initiator='user'
  then 'A pedido do técnico, o '||public.mgr_club_name(n.buyer_club)||' encerrou a negociação por '||public.mgr_player_name(n.player_id)
  else 'A pedido do técnico, o '||coalesce(public.mgr_club_name(n.seller_club),'clube')||' recusou a proposta do '||public.mgr_club_name(n.buyer_club)||' por '||public.mgr_player_name(n.player_id) end
 from public.cw_negotiations n
 where m.negotiation_id=n.id and n.response='Proposta recusada pelo treinador.' and n.status='rejected'
   and m.title like '% recusa a proposta por %';
