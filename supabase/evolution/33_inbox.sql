-- EVOLUÇÃO 33: caixa de mensagens organizada por assunto.
-- Satisfação e pedidos de saída, contratos, propostas recebidas e cada resposta das negociações do SEU clube
-- passam a chegar como mensagens (além das notícias do Mundo), com categoria e atalho para a tela certa.
-- Aditiva: colunas novas com padrão em mgr_messages, gatilhos novos e um embrulho do mgr_hub. Mensagens antigas ficam como estão.
begin;

alter table public.mgr_messages add column if not exists category text not null default 'club';
alter table public.mgr_messages add column if not exists player_id text;
alter table public.mgr_messages add column if not exists negotiation_id uuid;
alter table public.mgr_messages add column if not exists action text;
alter table public.mgr_messages add column if not exists event_key text;
do $$ begin
 alter table public.mgr_messages drop constraint if exists mgr_messages_kind_check;
 alter table public.mgr_messages add constraint mgr_messages_kind_check check (kind in ('board','fans','medical','offer','result','system','press','title','squad','transfer','contract','finance'));
 if not exists(select 1 from pg_constraint where conname='mgr_messages_category_check') then
  alter table public.mgr_messages add constraint mgr_messages_category_check check (category in ('squad','market','club','career'));
 end if;
end $$;
create unique index if not exists mgr_messages_event_uq on public.mgr_messages(career_id,event_key) where event_key is not null;
-- Mensagens antigas: propostas de emprego vão para Carreira; o resto continua em Clube.
update public.mgr_messages set category='career' where kind='offer' and category='club';

create or replace function public.cw_inbox_add(p_career uuid,p_key text,p_kind text,p_category text,p_title text,p_body text,
  p_club text default null,p_player text default null,p_negotiation uuid default null,p_action text default null)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;
begin
 select cs.* into s from public.career_seasons cs join public.cw_world w on w.primary_season=cs.id where w.career_id=p_career;
 insert into public.mgr_messages(career_id,season_id,day_no,kind,category,title,body,club_id,player_id,negotiation_id,action,event_key)
 values(p_career,s.id,s.day_no,p_kind,p_category,left(p_title,140),p_body,p_club,p_player,p_negotiation,p_action,p_key)
 on conflict (career_id,event_key) where event_key is not null do nothing;
end $$;

-- Notícias do Mundo que dizem respeito ao seu clube também viram mensagem (sem repetir as de negociação).
create or replace function public.cw_news_inbox_trg()
returns trigger language plpgsql security definer set search_path=public as $$
declare own text;cat text;act text;k text;
begin
 select club_id into own from public.mgr_coach where career_id=new.career_id and status='employed';
 if own is null or new.club_id is distinct from own then return null;end if;
 if new.event_key like 'incoming:%' or new.event_key like 'transfer:%' or new.event_key like 'precontract:%' or new.event_key like 'release:%' then return null;end if;
 if new.kind='squad' then cat:='squad';k:='squad';act:='open_player';
 elsif new.kind='contract' then cat:='squad';k:='contract';act:='open_player';
 elsif new.kind in('board','finance') then cat:='club';k:=case when new.kind='board' then 'board' else 'finance' end;act:='open_finance';
 else return null;end if;
 perform public.cw_inbox_add(new.career_id,'news:'||new.id,k,cat,new.title,new.body,own,new.player_id,null,act);
 return null;
end $$;
drop trigger if exists cw_news_inbox on public.cw_news;
create trigger cw_news_inbox after insert on public.cw_news for each row execute function public.cw_news_inbox_trg();

-- Negociações do seu clube: proposta recebida e cada resposta de clube ou atleta.
create or replace function public.cw_neg_inbox_trg()
returns trigger language plpgsql security definer set search_path=public as $$
declare own text;who text;pl text;buyer text;seller text;t text;b text;fee text;mine_buy boolean;
begin
 select club_id into own from public.mgr_coach where career_id=new.career_id and status='employed';
 if own is null or own not in(coalesce(new.buyer_club,''),coalesce(new.seller_club,'')) then return null;end if;
 if tg_op='UPDATE' and new.status is not distinct from old.status then return null;end if;
 pl:=public.mgr_player_name(new.player_id);buyer:=public.mgr_club_name(new.buyer_club);seller:=coalesce(public.mgr_club_name(new.seller_club),'o clube');
 fee:=to_char(new.fee,'FM999G999G999')||' moedas';mine_buy:=new.buyer_club=own;
 if tg_op='INSERT' then
  if new.initiator='ai' and new.seller_club=own and new.status='seller_review' then
   t:=buyer||' faz proposta por '||pl;b:='Oferta de '||fee||'. Aceite, recuse ou faça uma contraproposta até '||to_char(new.expires_on,'DD/MM')||'.';
  elsif new.initiator='ai' and new.seller_club=own and new.status='precontract' then
   t:=pl||' assina pré-contrato com '||buyer;b:='Sem renovação, o atleta deixa o clube de graça em '||to_char(new.register_on,'DD/MM/YYYY')||'.';
  else return null;end if;
 elsif new.status='club_counter' and mine_buy then t:=seller||' faz contraproposta por '||pl;b:='O clube pede '||fee||'. Responda até '||to_char(new.expires_on,'DD/MM')||'.';
 elsif new.status='player_counter' and mine_buy and old.status='club_pending' then t:=seller||' aceita negociar '||pl;b:='Clubes de acordo. Agora apresente salário, duração (até 5 anos) e papel ao atleta.';
 elsif new.status='player_counter' and mine_buy and old.status='player_pending' then t:=pl||' pede melhores condições';b:=coalesce(new.response,'O atleta quer um contrato melhor.')||' Pedido: '||to_char(new.monthly_salary,'FM999G999G999')||' por mês.';
 elsif new.status in('agreed','precontract') and mine_buy then
  t:=case when new.initiator='renewal' then pl||' aceita renovar' else 'Acordo fechado com '||pl end;
  b:=case when new.register_on>(select today from public.cw_world where career_id=new.career_id) then 'Registro em '||to_char(new.register_on,'DD/MM/YYYY')||'.' else 'Contrato registrado.' end;
 elsif new.status='completed' and new.initiator<>'renewal' then
  t:=case when mine_buy then pl||' é reforço do '||buyer else pl||' é vendido ao '||buyer end;
  b:=case when new.fee>0 then 'Valor: '||fee||'. ' else 'Transferência sem custo. ' end||'Contrato de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='completed' and new.initiator='renewal' then t:=pl||' renova contrato';b:='Novo vínculo de '||coalesce(new.contract_years,0)||' anos.';
 elsif new.status='rejected' then
  who:=case when old.status='player_pending' then pl when mine_buy then seller else buyer end;
  t:=case when not mine_buy and old.status='player_pending' then pl||' recusa ir para o '||buyer when new.initiator='renewal' then pl||' recusa a renovação' else who||' recusa a proposta por '||pl end;
  b:=coalesce(new.response,'Negociação encerrada.');
 elsif new.status='expired' then t:='Proposta por '||pl||' expirou';b:='O prazo terminou sem acordo.';
 elsif new.status='failed_funds' then t:='Negócio por '||pl||' cancelado';b:=coalesce(new.response,'Orçamento insuficiente para concluir.');
 elsif new.status='cancelled' and old.status in('agreed','precontract','club_pending','player_pending') then t:='Negociação por '||pl||' cancelada';b:=coalesce(new.response,'');
 else return null;end if;
 perform public.cw_inbox_add(new.career_id,'neg:'||new.id||':'||new.status||':'||coalesce(new.round_no,0),'transfer','market',t,b,
  case when new.buyer_club=own then coalesce(new.seller_club,own) else new.buyer_club end,new.player_id,new.id,'open_negotiations');
 return null;
end $$;
drop trigger if exists cw_neg_inbox on public.cw_negotiations;
create trigger cw_neg_inbox after insert or update of status on public.cw_negotiations for each row execute function public.cw_neg_inbox_trg();

-- Hub: mensagens com categoria, atleta, negociação e atalho; contagem de não lidas por categoria.
do $$ begin
 if to_regprocedure('public.mgr_hub_before_v33()') is null then alter function public.mgr_hub() rename to mgr_hub_before_v33;end if;
end $$;
create or replace function public.mgr_hub()
returns jsonb language plpgsql security definer set search_path=public as $$
declare h jsonb:=public.mgr_hub_before_v33();car uuid:=(h#>>'{career,id}')::uuid;
begin
 return h||jsonb_build_object(
  'messages',(select coalesce(jsonb_agg(m.j order by m.id desc),'[]') from(
    select mm.id,jsonb_build_object('id',mm.id,'kind',mm.kind,'category',mm.category,'title',mm.title,'body',mm.body,'club_id',mm.club_id,
     'player_id',mm.player_id,'negotiation_id',mm.negotiation_id,'action',mm.action,'day_no',mm.day_no,'read',mm.read,'created_at',mm.created_at) j
    from public.mgr_messages mm where mm.career_id=car order by mm.id desc limit 80) m),
  'unread_by_category',(select coalesce(jsonb_object_agg(category,n),'{}') from(select category,count(*) n from public.mgr_messages where career_id=car and not read group by category) x));
end $$;

revoke all on function public.cw_inbox_add(uuid,text,text,text,text,text,text,text,uuid,text),public.cw_news_inbox_trg(),public.cw_neg_inbox_trg(),public.mgr_hub_before_v33() from public,anon,authenticated;
revoke all on function public.mgr_hub() from public,anon;
grant execute on function public.mgr_hub() to authenticated;
notify pgrst,'reload schema';
commit;
