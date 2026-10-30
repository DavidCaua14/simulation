-- Gerado por scripts/build-editor-release.mjs a partir de 39_squad_cash_window_storage.sql: elenco, caixa, janela de transferências e banco menor.
-- Requer a evolução 38 (supabase/releases/banco_enxuto.sql). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Feito para o jogo NO AR: não compara impressões digitais (os jogadores continuam jogando durante a instalação).
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('39_squad_cash_window_storage.sql'));
 if to_regprocedure('public.cw_compact_month(uuid,date)') is null then raise exception 'Requer a evolução 38 (supabase/releases/banco_enxuto.sql); nada foi alterado';end if;
 

-- ===================== 39_squad_cash_window_storage.sql =====================
-- ---------- elenco ----------
update public.cw_rules set rules=rules||'{"squad_limit":40}' where coalesce((rules->>'squad_limit')::int,30)<40;
create or replace function public.cw_squad_count(p_career uuid,p_club text)
returns int language sql stable security definer set search_path=public as $$
 select count(*)::int from public.mgr_players mp
 join public.sim_players p on p.id=mp.player_id join public.sim_positions sp on sp.code=p.position join public.sim_player_attrs a on a.player_id=p.id
 join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
 join public.cw_world w on w.career_id=mp.career_id
 where mp.career_id=p_career and mp.club_id=p_club
  and cp.age_at_start+floor((w.today-w.started_on)/365.25)::int>=coalesce((select (rules->>'squad_limit_age')::int from public.cw_rules),21)
$$;

-- ---------- caixa: sem recolhimento no seu clube ----------
create or replace function public.cw_settle_month_before_v38(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue+apps*(300+club.prestige::int*12);
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Receitas comerciais, torcida e bilheteria');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id;
 end loop;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  -- Seu clube pode juntar até 10× o orçamento inicial para contratar; os da IA seguem com 3×.
  -- O caixa do seu clube é seu: nunca vira "patrimônio". Só os clubes da IA guardam o excedente acima de 3× o orçamento.
  surplus:=case when club.club_id=(select mc.club_id from public.mgr_coach mc where mc.career_id=p_career and mc.status='employed') then 0
   else greatest(0,club.cash-3*club.initial_budget) end;
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $function$;

-- ---------- janela de transferências ----------
update public.cw_windows set start_month=1,start_day=3,end_month=4,end_day=7 where region='BRA' and start_month=1;
update public.cw_windows set start_month=7,start_day=10,end_month=8,end_day=2 where region='BRA' and start_month=7;
update public.cw_windows set start_month=6,start_day=14,end_month=9,end_day=1 where region='ENG' and start_month=6;
update public.cw_windows set start_month=1,start_day=1,end_month=2,end_day=2 where region='ENG' and start_month=1;

-- Início da janela em que um registro feito em p_date cai (a aberta agora ou a próxima).
create or replace function public.cw_window_start(p_region text,p_date date)
returns date language sql stable security definer set search_path=public as $$
 select case when public.cw_window_open(p_region,p_date) then
  (select max(make_date(extract(year from p_date)::int+y.n,w.start_month,w.start_day)) from public.cw_windows w cross join generate_series(-1,0) y(n)
    where w.region=p_region and make_date(extract(year from p_date)::int+y.n,w.start_month,w.start_day)<=p_date)
  else public.cw_next_window(p_region,p_date) end
$$;

do $$ begin
 if to_regprocedure('public.cw_register_transfer_before_v39(uuid)') is null then
  alter function public.cw_register_transfer(uuid) rename to cw_register_transfer_before_v39;
 end if;
 if to_regprocedure('public.career_transfer_bid_before_v39(text,bigint,integer,bigint,boolean,uuid)') is null then
  alter function public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid) rename to career_transfer_bid_before_v39;
 end if;
end $$;

create or replace function public.cw_register_transfer(p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare n public.cw_negotiations;own text;d date;region text;
begin
 select * into n from public.cw_negotiations where id=p_id;
 if n.status='agreed' and n.initiator<>'renewal' then
  select today into d from public.cw_world where career_id=n.career_id;
  region:=public.cw_region(n.buyer_club);
  if not public.cw_window_open(region,d) then
   select club_id into own from public.mgr_coach where career_id=n.career_id and status='employed';
   -- Livres também esperam a janela; só clubes da IA com elenco curto registram fora dela.
   if n.buyer_club is not distinct from own or (select count(*) from public.mgr_players where career_id=n.career_id and club_id=n.buyer_club)>=18 then
    update public.cw_negotiations set register_on=greatest(coalesce(register_on,d),public.cw_next_window(region,d)),
     response='Acordo fechado. O registro acontece na abertura da janela de transferências.' where id=n.id and coalesce(register_on,d)<public.cw_next_window(region,d);
    return false;
   end if;
  end if;
 end if;
 return public.cw_register_transfer_before_v39(p_id);
end $$;

create or replace function public.career_transfer_bid(p_player text,p_fee bigint,p_installments int,p_bonus bigint,p_precontract boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();own text;d date;ws date;n int;
begin
 select club_id into own from public.mgr_coach where career_id=car and status='employed';
 if own is not null and public.econ_request_get(car,p_request,'transfer_bid') is null and not coalesce(p_precontract,false) then
  select today into d from public.cw_world where career_id=car;
  ws:=public.cw_window_start(public.cw_region(own),d);
  select count(*) into n from public.cw_negotiations x where x.career_id=car and x.buyer_club=own and x.initiator='user'
   and (x.status='agreed' or (x.status='completed' and x.register_on>=ws));
  if n>=6 then raise exception 'Limite de 6 contratações por janela atingido. Aguarde a próxima janela (a partir de %).',to_char(public.cw_next_window(public.cw_region(own),greatest(d,ws)+1),'DD/MM/YYYY');end if;
 end if;
 return public.career_transfer_bid_before_v39(p_player,p_fee,p_installments,p_bonus,p_precontract,p_request);
end $$;

-- ---------- banco menor ----------
do $$ begin
 if to_regprocedure('public.cw_compact_month_before_v39(uuid,date)') is null then
  alter function public.cw_compact_month(uuid,date) rename to cw_compact_month_before_v39;
 end if;
end $$;

create or replace function public.cw_prune_career(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare today date;own text;
begin
 select w.today into today from public.cw_world w where w.career_id=p_career;
 if today is null then return;end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 create temp table if not exists _cw_mine(club_id text primary key) on commit drop;
 truncate _cw_mine;
 insert into _cw_mine select own where own is not null on conflict do nothing;
 insert into _cw_mine select distinct cc.club_id from public.cw_coach_contracts cc where cc.career_id=p_career on conflict do nothing;
 -- Finanças antigas dos clubes da IA (o extrato que você vê é só do seu clube).
 delete from public.cw_finance f where f.career_id=p_career and f.on_date<today-60 and not exists(select 1 from _cw_mine m where m.club_id=f.club_id);
 -- Partidas da IA com mais de 30 dias: o relatório usa placar, estatísticas e lances guardados no jogo.
 delete from public.mgr_matches m using public.cw_fixture_dates fd
  where m.career_id=p_career and m.status='finished' and m.user_side is null and fd.fixture_id=m.fixture_id and fd.due_on<today-30;
 delete from public.mgr_match_events e using public.season_fixtures f,public.career_seasons cs,public.cw_fixture_dates fd
  where cs.career_id=p_career and f.season_id=cs.id and e.fixture_id=f.id and fd.fixture_id=f.id and fd.due_on<today-30
   and not coalesce(f.player_match,false) and e.kind not in('goal','pen_goal','own_goal','so_goal','so_miss','red','second_yellow','kickoff','ft');
 -- Negociações encerradas entre clubes da IA e contratos encerrados de atletas fora dos seus clubes.
 delete from public.cw_offer_history h using public.cw_negotiations n
  where h.negotiation_id=n.id and n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds') and n.created_on<today-60
   and not exists(select 1 from _cw_mine m where m.club_id in(n.buyer_club,n.seller_club));
 delete from public.cw_negotiations n where n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds') and n.created_on<today-60
  and not exists(select 1 from _cw_mine m where m.club_id in(n.buyer_club,n.seller_club))
  and not exists(select 1 from public.cw_commitments c where c.negotiation_id=n.id)
  and not exists(select 1 from public.cw_offer_history h where h.negotiation_id=n.id);
 delete from public.cw_contracts c where c.career_id=p_career and c.status<>'active' and coalesce(c.ended_on,c.expires_on)<today-60
  and not exists(select 1 from _cw_mine m where m.club_id=c.club_id)
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.agreed_owner_contract=c.id);
 -- Vagas de jogos de temporadas já encerradas (só servem para montar calendários novos).
 delete from public.season_fixture_slots s using public.career_seasons cs where cs.career_id=p_career and s.season_id=cs.id and cs.status<>'active';
 delete from public.econ_requests r where r.career_id=p_career and r.created_at<now()-interval '3 days';
end $$;

create or replace function public.cw_compact_month(p_career uuid,p_month date)
returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.cw_compact_month_before_v39(p_career,p_month);
 perform public.cw_prune_career(p_career);
end $$;

revoke all on function public.cw_squad_count(uuid,text),public.cw_window_start(text,date),public.cw_register_transfer(uuid),public.cw_register_transfer_before_v39(uuid),
 public.career_transfer_bid_before_v39(text,bigint,integer,bigint,boolean,uuid),public.cw_prune_career(uuid),public.cw_compact_month(uuid,date),
 public.cw_compact_month_before_v39(uuid,date),public.cw_settle_month_before_v38(uuid,date) from public,anon,authenticated;
revoke all on function public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid) from public,anon;
grant execute on function public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid) to authenticated;

-- ---------- dados: devolve ao caixa o que foi recolhido no seu clube atual ----------
do $$
declare r record;
begin
 for r in
  select mc.career_id,mc.club_id,sum(-f.amount)::bigint total
  from public.mgr_coach mc join public.cw_finance f on f.career_id=mc.career_id and f.club_id=mc.club_id
  where mc.status='employed' and f.kind='infrastructure' and f.amount<0
   and f.on_date>=coalesce((select min(cc.starts_on) from public.cw_coach_contracts cc where cc.career_id=mc.career_id and cc.club_id=mc.club_id and cc.ended_on is null),'1900-01-01'::date)
   and not exists(select 1 from public.cw_finance x where x.career_id=mc.career_id and x.club_id=mc.club_id and x.kind='infra_refund' and x.reference='v39')
  group by mc.career_id,mc.club_id having sum(-f.amount)>0
 loop
  perform public.cw_cash(r.career_id,r.club_id,r.total,'infra_refund','v39','Devolução ao caixa: valores que tinham ido para patrimônio');
  update public.cw_clubs set infrastructure=greatest(0,infrastructure-r.total) where career_id=r.career_id and club_id=r.club_id;
  raise notice 'Caixa devolvido: carreira % clube % +%',r.career_id,r.club_id,r.total;
 end loop;
end $$;

-- ---------- vagas de jogos: trava redundante (o gerador de calendário já garante um jogo por clube por rodada) ----------
drop trigger if exists sim_fixture_slots_trg on public.season_fixtures;
drop index if exists public.season_fixture_slots_fixture_idx;
truncate public.season_fixture_slots;

-- ---------- dados: enxuga todas as carreiras agora ----------
delete from public.econ_requests where created_at<now()-interval '3 days';
do $$ declare c uuid;begin
 for c in select career_id from public.cw_world loop perform public.cw_prune_career(c);end loop;
end $$;

perform pg_notify('pgrst','reload schema');


 if to_regprocedure('public.cw_prune_career(uuid)') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: elenco, caixa, janela de transferências e banco menor; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.cw_prune_career(uuid)') is not null then 'Instalação concluída: elenco, caixa, janela de transferências e banco menor; dados dos usuários preservados.' else 'Não instalado' end as resultado;
