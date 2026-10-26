#!/bin/bash
# Teste de CONCORRÊNCIA do mercado (conexões simultâneas). Banco de DESENVOLVIMENTO.
#   PSQL="psql -h /tmp -U pg -d evo_t" bash supabase/evolution/tests/market_concurrency.sh
# 1) dois compradores no MESMO anúncio ao mesmo tempo → um compra, o outro é recusado, nada em dobro
# 2) dois jogadores comprando UM DO OUTRO ao mesmo tempo → as duas compras terminam (sem deadlock)
set -e
PSQL=${PSQL:-psql}
A=d0d00000-0000-0000-0000-00000000000a; B=d0d00000-0000-0000-0000-00000000000b; C=d0d00000-0000-0000-0000-00000000000c
cleanup() { $PSQL -qAt -c "delete from public.careers where user_id in ('$A','$B','$C'); delete from auth.users where id in ('$A','$B','$C')" >/dev/null; }
cleanup
L1=$($PSQL -qAt -c "select id from public.cards where tier = 'lenda' and active order by id limit 1")
L2=$($PSQL -qAt -c "select id from public.cards where tier = 'lenda' and active order by id offset 1 limit 1")
$PSQL -qAt -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (id) values ('$A'), ('$B'), ('$C') on conflict do nothing;
insert into public.careers (user_id, nickname, photo_id, country, age, club_id, coins) values
  ('$A', 'conc_a', 'p1', 'BR', 30, 'sport', 50000), ('$B', 'conc_b', 'p1', 'BR', 30, 'goias', 50000), ('$C', 'conc_c', 'p1', 'BR', 30, 'avai', 50000);
insert into public.user_cards (career_id, card_id, qty) select id, '$L1', 1 from public.careers where user_id = '$A';
insert into public.user_cards (career_id, card_id, qty) select id, '$L2', 1 from public.careers where user_id = '$B';
SQL
as() { echo "set local role authenticated; set local request.jwt.claim.sub = '$1';"; }
LA=$($PSQL -qAt -c "begin; $(as $A) select public.market_list_card('$L1', 5000, gen_random_uuid()) ->> 'listing_id'; commit;" | grep -E '^[0-9a-f-]{36}$')
LB=$($PSQL -qAt -c "begin; $(as $B) select public.market_list_card('$L2', 3000, gen_random_uuid()) ->> 'listing_id'; commit;" | grep -E '^[0-9a-f-]{36}$')
buy() { $PSQL -qAt -c "begin; $(as $1) select public.market_buy('$2', gen_random_uuid()) ->> 'ok'; select pg_sleep(1); commit;" 2>&1 | grep -v '^$' | head -1; }

echo "1) B e C compram o anúncio de A ao mesmo tempo:"
buy $B $LA > /tmp/mc1.txt & sleep 0.2; buy $C $LA > /tmp/mc2.txt; wait
echo "   B: $(cat /tmp/mc1.txt) | C: $(cat /tmp/mc2.txt)"
R1=$($PSQL -qAt -c "select (select count(*) from public.market_listings where id = '$LA' and status = 'sold') || '|' ||
  (select coalesce(sum(qty),0) from public.user_cards uc join public.careers c on c.id = uc.career_id where c.user_id in ('$B','$C') and uc.card_id = '$L1') || '|' ||
  (select coins from public.careers where user_id = '$A') || '|' ||
  (select sum(coins) from public.careers where user_id in ('$B','$C'))")
echo "   vendido: ${R1%%|*} | cópias com B+C | moedas A | moedas B+C = $R1"

echo "2) A compra o anúncio de B enquanto B compra um anúncio de A (cruzado):"
# A anuncia um Destaque; ao mesmo tempo A compra o anúncio de B e B compra o de A
L3=$($PSQL -qAt -c "select id from public.cards where tier = 'destaque' and active order by id limit 1")
$PSQL -qAt -c "insert into public.user_cards (career_id, card_id, qty) select id, '$L3', 1 from public.careers where user_id = '$A' on conflict (career_id, card_id) do update set qty = 1" >/dev/null
LA3=$($PSQL -qAt -c "begin; $(as $A) select public.market_list_card('$L3', 900, gen_random_uuid()) ->> 'listing_id'; commit;" | grep -E '^[0-9a-f-]{36}$')
buy $A $LB > /tmp/mc3.txt & sleep 0.1; buy $B $LA3 > /tmp/mc4.txt; wait
echo "   A comprou de B: $(cat /tmp/mc3.txt) | B comprou de A: $(cat /tmp/mc4.txt)"
R2=$($PSQL -qAt -c "select count(*) from public.market_listings where id in ('$LB','$LA3') and status = 'sold'")
# o dinheiro fecha: soma de todas as moedas = inicial − taxas
TOT=$($PSQL -qAt -c "select sum(coins) from public.careers where user_id in ('$A','$B','$C')")
FEES=$($PSQL -qAt -c "select coalesce(sum(fee),0) from public.market_listings l join public.careers c on c.id = l.seller_career where c.user_id in ('$A','$B','$C') and l.status = 'sold'")
echo "   vendidos no cruzamento: $R2 | moedas totais: $TOT = 150000 − taxas ($FEES)"
cleanup
if [ "${R1%%|*}" = "1" ] && [ "$(echo $R1 | cut -d'|' -f2)" = "1" ] && grep -q "já foi vendido" /tmp/mc1.txt /tmp/mc2.txt \
   && [ "$R2" = "2" ] && [ "$TOT" = "$((150000 - FEES))" ]; then echo " TESTE DE CONCORRÊNCIA DO MERCADO PASSOU"; else echo " FALHOU"; exit 1; fi
