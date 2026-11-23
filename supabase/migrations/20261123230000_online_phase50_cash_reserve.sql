-- MODO ONLINE — Fase 50: reserva do clube (o caixa do reinício volta para o Online, 10% por dia).
--
-- No reinício de 20/11/2026 (fase 44) o caixa do Online de cada técnico foi para o clube dele no modo Temporadas.
-- Agora esse valor volta para o Online, numa reserva separada do caixa:
--  • on_reserves: total, quanto já foi liberado e a parte de cada dia (10% do total).
--  • on_reserve_tick (cron): libera a parte do dia às 00:00 (horário da temporada), com extrato e notícia no Online.
--    A primeira parte sai já na criação da reserva. Em 10 dias tudo está no caixa.
--  • O mesmo valor sai do clube do técnico no modo Temporadas (sem deixar o caixa negativo), com notícia e aviso.
--  • on_finance devolve a reserva para a tela de Finanças.

create table if not exists public.on_reserves(
 club_id int primary key references public.on_clubs(id) on delete cascade,
 total bigint not null check (total>0),
 released bigint not null default 0,
 per_day bigint not null,
 started date not null,
 ref text not null unique,
 created_at timestamptz not null default now()
);
alter table public.on_reserves enable row level security;

-- Valor do Online por extenso: $ 7.567.087
create or replace function public.on_money_text(p bigint) returns text language sql immutable as $$
 select '$ '||replace(to_char(p,'FM999,999,999,999'),',','.')
$$;

-- Libera o que já venceu: até (dias desde o início + 1) × parte do dia, sem passar do total.
create or replace function public.on_reserve_release(p_club int,p_today date) returns bigint
language plpgsql security definer set search_path=public as $$
declare r public.on_reserves;v_due bigint;v bigint;
begin
 select * into r from public.on_reserves where club_id=p_club for update;
 if r.club_id is null then return 0;end if;
 v_due:=least(r.total,r.per_day*greatest(0,(p_today-r.started)+1));
 v:=v_due-r.released;
 if v<=0 then return 0;end if;
 update public.on_reserves set released=v_due where club_id=p_club;
 perform public.on_money(p_club,v,'reserve','Reserva do clube: parte do dia ('||
  case when v_due>=r.total then 'última' else ((v_due*10/r.total))||' de 10' end||')',true);
 insert into public.on_news(club_id,kind,text) values(p_club,'finance',
  'Reserva do clube: '||public.on_money_text(v)||' entraram no caixa'||
  case when v_due>=r.total then '. A reserva terminou.' else '. Faltam '||public.on_money_text(r.total-v_due)||'.' end);
 return v;
end $$;

create or replace function public.on_reserve_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare r record;v_today date;
begin
 v_today:=(p_now at time zone coalesce((select tz from public.on_seasons where status='live' limit 1),'America/Sao_Paulo'))::date;
 for r in select club_id from public.on_reserves where released<total
   and least(total,per_day*greatest(0,(v_today-started)+1))>released loop
  perform public.on_reserve_release(r.club_id,v_today);
 end loop;
end $$;

-- Finanças: a reserva aparece junto do caixa.
create or replace function public.on_finance() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 return jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,
  'wages',(select coalesce(sum(wage),0) from public.on_players where club_id=c.id),
  'reserve',(select jsonb_build_object('total',r.total,'released',r.released,'per_day',r.per_day,'left',r.total-r.released,
     'days_left',ceil((r.total-r.released)::numeric/r.per_day)::int) from public.on_reserves r where r.club_id=c.id and r.released<r.total),
  'ledger',coalesce((select jsonb_agg(jsonb_build_object('kind',x.kind,'amount',x.amount,'note',x.note,'at',x.at) order by x.id desc)
   from(select * from public.on_ledger where club_id=c.id order by id desc limit 30) x),'[]'::jsonb),
  'news',coalesce((select jsonb_agg(jsonb_build_object('kind',x.kind,'text',x.text,'at',x.at) order by x.id desc)
   from(select * from public.on_news where club_id=c.id order by id desc limit 20) x),'[]'::jsonb));
end $$;

update public.on_config set tick_hooks=array_append(tick_hooks,'on_reserve_tick') where not ('on_reserve_tick'=any(tick_hooks));

-- Devolução do reinício de 20/11/2026: cada transferência vira reserva no clube Online do técnico, e o mesmo valor
-- sai do clube em que o dinheiro está hoje no modo Temporadas. Idempotente (ref única).
do $$
declare r record;v_club int;v_today date:=(now() at time zone 'America/Sao_Paulo')::date;v_take bigint;v_label text;
begin
 if to_regclass('public.cw_finance') is null then return;end if;
 for r in select f.id,f.career_id car,(f.metadata->>'online_cash')::bigint oc,f.amount units,ca.user_id,
   coalesce((select m.club_id from public.mgr_coach m where m.career_id=f.career_id and m.status='employed' limit 1),f.club_id) cw_club
  from public.cw_finance f join public.careers ca on ca.id=f.career_id
  where f.kind='online_transfer' and f.reference like 'online-restart:%' and f.amount>0 loop
  select k.id into v_club from public.on_clubs k where k.user_id=r.user_id;
  if v_club is null or exists(select 1 from public.on_reserves where ref='restart-back:'||r.id) then continue;end if;
  insert into public.on_reserves(club_id,total,per_day,started,ref)
   values(v_club,r.oc,ceil(r.oc/10.0)::bigint,v_today,'restart-back:'||r.id);
  -- sai do modo Temporadas (o que houver no caixa, até o valor transferido)
  select least(r.units,greatest(0,w.cash)) into v_take from public.cw_clubs w where w.career_id=r.car and w.club_id=r.cw_club;
  if coalesce(v_take,0)>0 then
   perform public.cw_cash(r.car,r.cw_club,-v_take,'online_transfer_back','restart-back:'||r.id,
    'Caixa do Online devolvido ao clube Online (reserva)',false,jsonb_build_object('online_club',v_club,'online_cash',r.oc));
  end if;
  v_label:=public.cw_money_label(r.units);
  perform public.cw_news_add(r.car,'online-cash-back:'||r.id,'finance','Caixa do Online voltou para o Online',
   'O caixa do seu clube Online ('||v_label||') que tinha vindo para cá no recomeço voltou para o Online. Lá ele entra no caixa aos poucos: 10% por dia, em 10 dias.',
   70,r.cw_club,null,null,'{}'::jsonb);
  insert into public.player_notices(career_id,kind,title,body) values(r.car,'info','Seu caixa do Online voltou para o Online',
   'Os '||v_label||' do recomeço saíram do seu clube no modo Temporadas e viraram a Reserva do clube no Online: 10% entram no caixa por dia, em 10 dias. A primeira parte já está lá.');
  insert into public.on_news(club_id,kind,text) values(v_club,'finance',
   'Reserva do clube: o caixa do recomeço ('||public.on_money_text(r.oc)||') voltou. 10% entram no caixa por dia, em 10 dias.');
  perform public.on_reserve_release(v_club,v_today);
 end loop;
end $$;

revoke all on function public.on_money_text(bigint),public.on_reserve_release(int,date),public.on_reserve_tick(timestamptz,boolean) from public,anon,authenticated;
