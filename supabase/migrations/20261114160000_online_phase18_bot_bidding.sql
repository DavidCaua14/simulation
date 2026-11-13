-- MODO ONLINE — Fase 18: bots dão lance como um técnico daria.
-- Antes, qualquer leilão com lance de um técnico recebia lance de algum bot até 70%–90% do valor. Dava para "queimar"
-- um jogador do mercado com um lance mínimo: o bot cobria e levava. Agora cada bot decide por conta própria:
--  • só se interessa se o jogador melhora o elenco dele (nota perto ou acima da força do clube, ou posição carente);
--  • mesmo assim, só parte dos bots entra em cada leilão (perfil fixo por leilão e clube, não muda a cada minuto);
--  • cada bot interessado tem o próprio teto, entre 50% e 90% do valor, e para quando o preço passa dele.
-- Jogador fraco não recebe lance de bot: quem der lance nele fica com ele.

-- Teto do bot p_club no leilão p_lot (0 = sem interesse).
create or replace function public.on_bot_limit(p_club int,p_lot bigint,p_player text) returns bigint
language sql stable security definer set search_path=public as $$
 select case
  when not(p.ovr>=st.s-2 or (pos.n<2 and p.ovr>=st.s-6)) then 0   -- não melhora o elenco
  when public.sim_hash01('botwant:'||p_lot||':'||p_club)>=.45 then 0 -- este clube não entrou nessa disputa
  else round(public.on_value(p.ovr,p.age,p.pot)*(.50+.40*public.sim_hash01('botcap:'||p_lot||':'||p_club)))::bigint end
 from public.on_players p
 cross join lateral(select coalesce(avg(x.ovr),60) s from(select q.ovr from public.on_players q where q.club_id=p_club order by q.ovr desc limit 11) x) st
 cross join lateral(select count(*) n from public.on_players q where q.club_id=p_club and q.pos=p.pos) pos
 where p.id=p_player
$$;
revoke all on function public.on_bot_limit(int,bigint,text) from public,anon,authenticated;

do $$ begin
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  '  continue when v_bid>r.v*(.7+.2*public.sim_hash01(''botcap:''||r.id));',
  '  -- cada bot tem interesse e teto próprios (on_bot_limit)');
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  '   and c.id is distinct from r.seller and c.debt=0 and c.cash-c.reserved>=v_bid and (select count(*) from public.on_players x where x.club_id=c.id)<26',
  '   and c.id is distinct from r.seller and c.debt=0 and c.cash-c.reserved>=v_bid and (select count(*) from public.on_players x where x.club_id=c.id)<26
   and public.on_bot_limit(c.id,r.id,r.player_id)>=v_bid');
 -- jogador anunciado por técnico e sem lances: só um bot interessado compra
 perform public.on_patch('public.on_lot_settle(bigint,timestamp with time zone)',
  'and k.cash-k.reserved>=v_price and v_price<=v_value*.8',
  'and k.cash-k.reserved>=v_price and v_price<=v_value*.8 and public.on_bot_limit(k.id,l.id,l.player_id)>=v_price');
end $$;
