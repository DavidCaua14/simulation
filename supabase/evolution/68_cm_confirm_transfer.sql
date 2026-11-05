-- Evolução 68 — confirmação final do negócio, como no Championship Manager 17.
-- Quando o atleta aceita o contrato que você ofereceu (contratação ou renovação), ele responde por e-mail:
-- "Aceito sua oferta de X por semana por N anos. Se estiver de acordo, confirme." O registro só acontece depois do
-- CONFIRMAR; você também pode desistir. Sem resposta até o prazo, a proposta expira e a verba reservada volta.
-- Negócios já fechados antes desta evolução seguem como estão.
begin;

-- novo estado: atleta aceitou, aguardando a confirmação do treinador
do $$ declare c text;begin
 for c in select conname from pg_constraint where conrelid='public.cw_negotiations'::regclass and contype='c' and pg_get_constraintdef(oid) like '%seller_review%' loop
  if (select pg_get_constraintdef(oid) from pg_constraint where conname=c and conrelid='public.cw_negotiations'::regclass) like '%player_accepted%' then continue;end if;
  execute format('alter table public.cw_negotiations drop constraint %I',c);
 end loop;
 if not exists(select 1 from pg_constraint where conrelid='public.cw_negotiations'::regclass and contype='c' and pg_get_constraintdef(oid) like '%player_accepted%') then
  alter table public.cw_negotiations add constraint cw_negotiations_status_check check(status in('seller_review','club_pending','club_counter','player_pending','player_counter',
   'player_accepted','agreed','precontract','completed','rejected','expired','cancelled','failed_funds'));
 end if;
end $$;
drop index if exists public.cw_negotiation_buyer_uq;
create unique index cw_negotiation_buyer_uq on public.cw_negotiations(career_id,player_id,buyer_club)
 where status in('seller_review','club_pending','club_counter','player_pending','player_counter','player_accepted','agreed','precontract');

-- No mercado diário: o aceite do atleta para o SEU clube vira pedido de confirmação; confirmações vencidas expiram.
do $$ declare src text;old1 text;new1 text;old2 text;new2 text;begin
 select pg_get_functiondef('public.cw_market_tick_before_v37(uuid)'::regprocedure) into src;
 if src like '%player_accepted%' then return;end if;
 old1:=E'    begin\n     perform public.cw_reserve_offer(n.id);\n     update public.cw_negotiations set status=case when n.register_on is not null then ''precontract'' else ''agreed'' end';
 new1:=E'    if n.buyer_club=own and n.initiator in(''user'',''renewal'') then\n'
  ||E'     update public.cw_negotiations set status=''player_accepted'',expires_on=public.cw_deadline(d),\n'
  ||E'      response=format(''Aceito sua oferta de %s por semana por %s ano(s). Se estiver de acordo, confirme e meu agente cuida da papelada.'',public.cw_money_label(public.cw_weekly(n.monthly_salary)),n.contract_years) where id=n.id;\n'
  ||E'     perform public.cw_neg_history(n.id,''player'',''O atleta aceitou; aguardando a confirmação do treinador.'');\n'
  ||E'     continue;\n'
  ||E'    end if;\n'||old1;
 old2:=' select club_id into own from public.mgr_coach where career_id=p_career;';
 new2:=old2||E'\n for id in select x.id from public.cw_negotiations x where x.career_id=p_career and x.status=''player_accepted'' and x.expires_on<d loop\n'
  ||E'  perform public.cw_neg_close(id,''expired'',''O prazo para confirmar terminou e o atleta seguiu outro caminho.'');\n end loop;';
 if (length(src)-length(replace(src,old1,'')))/length(old1)<>1 or (length(src)-length(replace(src,old2,'')))/length(old2)<>1 then
  raise exception 'cw_market_tick_before_v37 diferente do esperado';
 end if;
 execute replace(replace(src,old1,new1),old2,new2);
end $$;

-- Confirmar ou desistir do negócio aceito pelo atleta
create or replace function public.career_transfer_confirm(p_id uuid,p_accept boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;n public.cw_negotiations;own text;d date;prev jsonb;
begin
 car:=public.mgr_lock();
 prev:=public.econ_request_get(car.id,p_request,'transfer_confirm');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select today into d from public.cw_world where career_id=car.id;
 select * into n from public.cw_negotiations where id=p_id and career_id=car.id and buyer_club=own for update;
 if not found or n.status<>'player_accepted' then raise exception 'Este negócio não está aguardando confirmação';end if;
 if n.expires_on<d then
  perform public.cw_neg_close(n.id,'expired','O prazo para confirmar terminou e o atleta seguiu outro caminho.');
  raise exception 'O prazo para confirmar terminou';
 end if;
 if not coalesce(p_accept,false) then
  perform public.cw_neg_close(n.id,'cancelled','Você desistiu do negócio na confirmação final.');
  return public.econ_request_save(car.id,p_request,'transfer_confirm',jsonb_build_object('ok',true,'status','cancelled'));
 end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
  perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
  return public.econ_request_save(car.id,p_request,'transfer_confirm',jsonb_build_object('ok',false,'status','rejected'));
 end if;
 begin
  perform public.cw_reserve_offer(n.id);
  update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',
   register_on=coalesce(n.register_on,case when n.seller_club is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d)
    then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end) where id=n.id;
  perform public.cw_neg_history(n.id,'user','Negócio confirmado pelo treinador.');
  perform public.cw_register_transfer(n.id);
 exception when raise_exception then
  perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);
  return public.econ_request_save(car.id,p_request,'transfer_confirm',jsonb_build_object('ok',false,'status','failed_funds','reason',sqlerrm));
 end;
 select * into n from public.cw_negotiations where id=p_id;
 return public.econ_request_save(car.id,p_request,'transfer_confirm',jsonb_build_object('ok',true,'status',n.status,'register_on',n.register_on));
end $$;

-- E-mails das negociações no formato do CM17 (aceite para confirmar; pedidos em salário semanal)
do $$ declare src text;begin
 select pg_get_functiondef('public.cw_neg_inbox_trg()'::regprocedure) into src;
 if src like '%player_accepted%' then return;end if;
 if position(E' elsif new.status in(''agreed'',''precontract'') and mine_buy then' in src)=0
  or position('Agora apresente salário, duração (até 5 anos) e papel ao atleta.' in src)=0
  or position('||'' por mês.''' in src)=0 then raise exception 'cw_neg_inbox_trg diferente do esperado';end if;
 src:=replace(src,E' elsif new.status in(''agreed'',''precontract'') and mine_buy then',
  E' elsif new.status=''player_accepted'' and mine_buy then t:=pl||'' aceita sua oferta'';b:=coalesce(new.response,''Confirme o negócio para concluir.'');\n elsif new.status in(''agreed'',''precontract'') and mine_buy then');
 src:=replace(src,'Agora apresente salário, duração (até 5 anos) e papel ao atleta.','Agora negocie o contrato: salário por semana e duração (até 5 anos).');
 src:=replace(src,'Pedido: ''||public.cw_money_label(new.monthly_salary)||'' por mês.''','Pedido: ''||public.cw_money_label(public.cw_weekly(new.monthly_salary))||'' por semana.''');
 execute src;
end $$;

revoke all on function public.career_transfer_confirm(uuid,boolean,uuid) from public,anon;
grant execute on function public.career_transfer_confirm(uuid,boolean,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
