-- MODO ONLINE — Fase 19: lance superado devolve as moedas usadas.
-- O dinheiro do clube nunca saiu num lance: ele fica reservado e é liberado na hora em que outro clube cobre. Mas as
-- moedas usadas para completar um lance viravam caixa do clube e ali ficavam, mesmo perdendo o leilão. Agora, ao ser
-- superado, o técnico recebe de volta as moedas daquele lance (o valor correspondente sai do caixa do clube).
alter table public.on_bids add column if not exists coins int not null default 0;
alter table public.on_bids add column if not exists coins_back boolean not null default false;

-- Devolve as moedas dos lances do clube p_club no leilão p_lot (chamada quando ele é superado).
create or replace function public.on_bid_refund(p_lot bigint,p_club int) returns int
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;v_rate int;v_sum int;v_back int;v_name text;
begin
 select * into k from public.on_clubs where id=p_club;
 if k.user_id is null then return 0;end if;
 select coalesce(sum(b.coins),0) into v_sum from public.on_bids b where b.lot_id=p_lot and b.club_id=p_club and not b.coins_back;
 if v_sum<=0 then return 0;end if;
 select coin_bid_rate into v_rate from public.on_config;
 -- só o que ainda está livre no caixa volta (o técnico pode ter gasto parte em outra coisa)
 v_back:=least(v_sum,floor(greatest(0,k.cash-k.reserved)::numeric/v_rate)::int);
 update public.on_bids set coins_back=true where lot_id=p_lot and club_id=p_club and not coins_back;
 if v_back<=0 then return 0;end if;
 perform public.on_money(p_club,-(v_back::bigint*v_rate),'coins_back',format('%s moedas devolvidas (lance superado)',v_back));
 perform set_config('econ.reason','online_bid_refund',true);
 update public.careers set coins=coins+v_back where id=public.on_career_of(k.user_id);
 perform set_config('econ.reason','',true);
 update public.on_clubs set coins_conv=greatest(0,coins_conv-v_back) where id=p_club;
 select p.name into v_name from public.on_lots l join public.on_players p on p.id=l.player_id where l.id=p_lot;
 insert into public.on_news(club_id,kind,text) values(p_club,'market',format('Seu lance em %s foi superado: %s moedas voltaram para a sua conta.',coalesce(v_name,'um jogador'),v_back));
 return v_back;
end $$;
revoke all on function public.on_bid_refund(bigint,int) from public,anon,authenticated;

do $$ begin
 -- registra as moedas usadas no lance
 perform public.on_patch('public.on_bid(bigint,bigint,boolean)',
  ' perform public.on_bid_as(c.id,p_lot,p_amount);',
  ' perform public.on_bid_as(c.id,p_lot,p_amount);'||chr(10)||
  ' if coalesce(v_coins,0)>0 then update public.on_bids set coins=v_coins where id=(select max(b.id) from public.on_bids b where b.lot_id=p_lot and b.club_id=c.id);end if;');
 -- ao cobrir o lance de outro clube: a reserva dele é liberada (já era) e as moedas voltam
 perform public.on_patch('public.on_bid_as(integer,bigint,bigint,timestamp with time zone)',
  '  update public.on_clubs set reserved=reserved-l.best_bid where id=v_prev;',
  '  update public.on_clubs set reserved=reserved-l.best_bid where id=v_prev;'||chr(10)||'  perform public.on_bid_refund(l.id,v_prev);');
end $$;
