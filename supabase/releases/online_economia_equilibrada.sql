-- Online: aportes externos limitados a 20% do caixa inicial.
-- Executar atomicamente; não altera saldos pessoais existentes, salvo estorno.
lock table public.on_config, public.on_clubs, public.on_lots, public.careers, public.on_ledger in share row exclusive mode;

-- Estorna somente aportes legados ainda integralmente disponíveis e auditáveis.
do $$
declare r record; k uuid;
begin
 for r in
  select c.id,c.user_id,c.coins_conv,sum(l.amount)::bigint amount
  from public.on_clubs c join public.on_seasons s on s.id=c.season_id and s.status='live'
  join public.on_ledger l on l.club_id=c.id and l.kind='coins'
  where c.coins_conv>0
    and not exists(select 1 from public.on_ledger e where e.club_id=c.id and e.kind='economy_refund')
  group by c.id,c.user_id,c.coins_conv
 loop
  if r.amount<>r.coins_conv::bigint*1000
     or exists(select 1 from public.on_ledger where club_id=r.id and kind='coins' and note!~'^[0-9]+ moedas$')
     or not exists(select 1 from public.on_clubs where id=r.id and debt=0 and cash-reserved>=r.amount)
  then raise exception 'Aporte legado exige revisão antes do estorno'; end if;
  select id into k from public.careers where user_id=r.user_id order by (status='active') desc,created_at desc limit 1 for update;
  if k is null then raise exception 'Carteira do estorno não encontrada';end if;
  perform set_config('econ.reason','online_economy_refund',true);
  update public.careers set coins=coins+r.coins_conv where id=k;
  perform public.on_money(r.id,-r.amount,'economy_refund',format('Estorno de aporte legado; %s moedas devolvidas',r.coins_conv));
  update public.on_clubs set coins_conv=0 where id=r.id;
  insert into public.on_news(club_id,kind,text) values(r.id,'finance','Economia equilibrada: aporte antigo estornado e moedas devolvidas. Novo câmbio 1:1, limite compartilhado de $ 30.000 por temporada.');
 end loop;
end $$;

alter table public.on_config alter column coin_rate set default 1;
alter table public.on_config alter column coin_bid_rate set default 1;
alter table public.on_config alter column coin_cap set default 30000;
update public.on_config set coin_rate=1,coin_bid_rate=1,coin_cap=30000;
alter table public.on_config add constraint on_economy_limits check(coin_rate=1 and coin_bid_rate=1 and coin_cap between 0 and 30000);

create or replace function public.online_coins_convert(p_coins int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;k public.careers;
begin
 select * into strict cfg from public.on_config;
 if p_coins is null or p_coins<1 then raise exception 'Quantidade inválida';end if;
 if p_coins>greatest(0,cfg.coin_cap-c.coins_conv) then
  raise exception 'Limite compartilhado da temporada: restam % moedas para aportes e lances',greatest(0,cfg.coin_cap-c.coins_conv);
 end if;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
 if k.id is null or k.coins<p_coins then raise exception 'Moedas insuficientes';end if;
 perform set_config('econ.reason','online_investment',true);
 update public.careers set coins=coins-p_coins where id=k.id;
 perform public.on_money(c.id,p_coins::bigint*cfg.coin_rate,'coins',format('%s moedas',p_coins));
 update public.on_clubs set coins_conv=coins_conv+p_coins where id=c.id;
 return public.on_club();
end $$;

create or replace function public.on_bid(p_lot bigint,p_amount bigint,p_coins boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();l public.on_lots;cfg public.on_config;k public.careers;v_need bigint;v_coins int;
begin
 if p_amount is null or p_amount<=0 then raise exception 'Lance inválido';end if;
 select * into l from public.on_lots where id=p_lot and season_id=c.season_id for update;
 if l.id is null then raise exception 'Leilão não encontrado';end if;
 if coalesce(p_coins,false) then
  select * into strict cfg from public.on_config;
  select x.* into c from public.on_clubs x where x.id=c.id for update;
  v_need:=p_amount-case when l.best_club=c.id then l.best_bid else 0 end-(c.cash-c.reserved);
  if v_need>0 and c.debt=0 and l.status='open' and now()<l.ends_at and p_amount>=public.on_min_bid(l) then
   if ceil(v_need::numeric/cfg.coin_bid_rate)>greatest(0,cfg.coin_cap-c.coins_conv) then
    raise exception 'Limite compartilhado da temporada: restam % moedas para aportes e lances',greatest(0,cfg.coin_cap-c.coins_conv);
   end if;
   v_coins:=ceil(v_need::numeric/cfg.coin_bid_rate)::int;
   select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
   if k.id is null or k.coins<v_coins then raise exception 'Moedas insuficientes: esse lance pede % moedas',v_coins;end if;
   perform set_config('econ.reason','online_bid_investment',true);
   update public.careers set coins=coins-v_coins where id=k.id;
   perform public.on_money(c.id,v_coins::bigint*cfg.coin_bid_rate,'coins',format('%s moedas em lance',v_coins));
   update public.on_clubs set coins_conv=coins_conv+v_coins where id=c.id;
  end if;
 end if;
 perform public.on_bid_as(c.id,p_lot,p_amount);
 return public.on_market();
end $$;
revoke all on function public.online_coins_convert(int),public.on_bid(bigint,bigint,boolean) from public,anon;
grant execute on function public.online_coins_convert(int),public.on_bid(bigint,bigint,boolean) to authenticated;

