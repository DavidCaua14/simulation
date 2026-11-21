-- MODO ONLINE — Fase 47: o caixa do Online transferido no reinício (fase 44) entrava calado no clube do modo
-- Temporadas (só uma linha no extrato) e ficava no clube em que o técnico estava naquele momento. Agora:
--  1. on_restart_club avisa o técnico: notícia no clube do modo Temporadas e aviso no jogo (player_notices).
--  2. Correção dos reinícios de 20/11/2026: quem trocou de clube depois recebe o valor no clube atual (sai do clube
--     antigo) e todos recebem o aviso com o valor. Idempotente (referências fixas no extrato e no aviso).

create or replace function public.on_cash_notice(p_car uuid,p_club text,p_units bigint,p_ref text) returns void
language plpgsql security definer set search_path=public as $$
declare v_label text;v_name text;
begin
 if p_car is null or p_units<=0 then return;end if;
 v_label:=public.cw_money_label(p_units);
 select coalesce(c.name,p_club) into v_name from public.sim_clubs c where c.id=p_club;
 v_name:=coalesce(v_name,p_club);
 perform public.cw_news_add(p_car,'online-cash:'||p_ref,'finance','Caixa do Online chegou ao clube',
  'O Online recomeçou e o caixa do seu antigo clube Online ('||v_label||') entrou no caixa do '||v_name||'.',70,p_club);
 if not exists(select 1 from public.player_notices n where n.career_id=p_car and n.kind='info' and n.title='Seu caixa do Online foi transferido') then
  insert into public.player_notices(career_id,kind,title,body) values(p_car,'info','Seu caixa do Online foi transferido',
   'Com o recomeço do Online, '||v_label||' do caixa do seu clube Online foram para o '||v_name||' no modo Temporadas. Confira em Finanças do clube.');
 end if;
end $$;
revoke all on function public.on_cash_notice(uuid,text,bigint,text) from public, anon, authenticated;

do $$ begin
 -- só existe onde há o modo Temporadas (produção); no banco de testes do Online a função fica como está
 if to_regprocedure('public.cw_news_add(uuid,text,text,text,text,integer,text,text,uuid,jsonb)') is not null then
  perform public.on_patch('public.on_restart_club(integer,text)',
   '    using v_car,v_cw,v_sent,''online-restart:''||k.id||'':''||k.season_id,jsonb_build_object(''online_club'',k.id,''online_cash'',v_amount);',
   '    using v_car,v_cw,v_sent,''online-restart:''||k.id||'':''||k.season_id,jsonb_build_object(''online_club'',k.id,''online_cash'',v_amount);
   perform public.on_cash_notice(v_car,v_cw,v_sent,k.id||'':''||k.season_id);');
 end if;
end $$;

-- correção dos reinícios já feitos
do $$
declare r record;v_now text;
begin
 if to_regclass('public.cw_finance') is null then return;end if;
 for r in select f.id,f.career_id car,f.club_id old_club,f.amount from public.cw_finance f where f.kind='online_transfer' and f.reference like 'online-restart:%' loop
  select m.club_id into v_now from public.mgr_coach m where m.career_id=r.car and m.status='employed' limit 1;
  if v_now is not null and v_now<>r.old_club and exists(select 1 from public.cw_clubs w where w.career_id=r.car and w.club_id=v_now) then
   perform public.cw_cash(r.car,r.old_club,-r.amount,'online_transfer_move','move:'||r.id,'Caixa do Online levado para o clube atual do técnico',true,'{}');
   perform public.cw_cash(r.car,v_now,r.amount,'online_transfer','move:'||r.id,'Caixa do clube Online transferido pelo técnico',false,jsonb_build_object('from_club',r.old_club));
  end if;
  perform public.on_cash_notice(r.car,coalesce(v_now,r.old_club),r.amount,'fix:'||r.id);
 end loop;
end $$;
