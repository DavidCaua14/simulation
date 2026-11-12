-- Aportes sem teto de temporada; câmbio preservado em 1:1.
alter table public.on_config drop constraint on_economy_limits;
alter table public.on_config alter column coin_cap set default 2147483647;
update public.on_config set coin_cap=2147483647;
alter table public.on_config add constraint on_economy_exchange_rates check(coin_rate=1 and coin_bid_rate=1);
alter table public.on_clubs alter column coins_conv type bigint;
create or replace function public.online_coins_convert(p_coins int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;k public.careers;
begin
 select * into strict cfg from public.on_config;
 if p_coins is null or p_coins<1 then raise exception 'Quantidade inválida';end if;
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
   if ceil(v_need::numeric/cfg.coin_bid_rate)>2147483647 then raise exception 'Moedas insuficientes';end if;
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

-- Compatibilidade com clientes antigos: o espaço exibido sempre equivale à carteira.
do $$
declare fn regprocedure;src text;
begin
 foreach fn in array array['public.on_club()'::regprocedure,'public.on_market()'::regprocedure] loop
  src:=pg_get_functiondef(fn);
  if position('''cap'',cfg.coin_cap' in src)=0 then raise exception 'Payload de moedas não reconhecido: %',fn;end if;
  src:=replace(src,'''cap'',cfg.coin_cap','''cap'',c.coins_conv+coalesce(public.on_wallet(),0),''unlimited'',true');
  execute src;
 end loop;
end $$;
