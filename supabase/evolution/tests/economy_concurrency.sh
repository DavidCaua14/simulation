#!/bin/bash
# Teste de CONCORRÊNCIA da loja e da roleta (duas conexões ao mesmo tempo). Banco de DESENVOLVIMENTO.
#   PSQL="psql -h /tmp -U pg -d evo_t" bash supabase/evolution/tests/economy_concurrency.sh
# Cria um usuário de teste, dispara compras simultâneas e apaga tudo no final.
set -e
PSQL=${PSQL:-psql}
U=c0c0c0c0-0000-0000-0000-000000000001
CAR=c0c0c0c0-0000-0000-0000-0000000000c1
REQ=$(cat /proc/sys/kernel/random/uuid)
$PSQL -qAt -v ON_ERROR_STOP=1 <<SQL
delete from public.careers where user_id = '$U';
insert into auth.users (id) values ('$U') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, coins) values ('$CAR', '$U', 'teste_conc', 'p1', 'BR', 30, 'sport', 50000);
SQL
CARD=$($PSQL -qAt -c "set role authenticated; set request.jwt.claim.sub = '$U'; select public.shop_catalog() -> 'sections' -> 0 -> 'items' -> 0 -> 'card' ->> 'id'" | tail -1)
buy() {  # $1 = request id; segura a transação 1 s depois de comprar (a outra conexão chega enquanto isso)
  $PSQL -qAt -c "begin; set local role authenticated; set local request.jwt.claim.sub = '$U';
                 select (public.shop_buy_card('$CARD', 'coins', '$1')) ->> 'replayed'; select pg_sleep(1); commit;" 2>&1 | grep -v '^$' | head -1
}
echo "1) mesmo pedido em duas conexões ao mesmo tempo:"
buy $REQ > /tmp/conc_a.txt & sleep 0.2; buy $REQ > /tmp/conc_b.txt; wait
echo "   conexão A: replayed=$(cat /tmp/conc_a.txt) | conexão B: replayed=$(cat /tmp/conc_b.txt)"
echo "2) dois pedidos DIFERENTES para a última cópia ao mesmo tempo:"
$PSQL -qAt -c "delete from public.shop_purchases where career_id = '$CAR'; delete from public.user_cards where career_id = '$CAR'"
buy $(cat /proc/sys/kernel/random/uuid) > /tmp/conc_a.txt & sleep 0.2; buy $(cat /proc/sys/kernel/random/uuid) > /tmp/conc_b.txt; wait
echo "   conexão A: $(cat /tmp/conc_a.txt) | conexão B: $(cat /tmp/conc_b.txt)"
R=$($PSQL -qAt -c "select (select count(*) from public.shop_purchases where career_id = '$CAR') || '|' ||
                         (select coalesce(sum(qty),0) from public.user_cards where career_id = '$CAR') || '|' ||
                         (select coins from public.careers where id = '$CAR') || '|' ||
                         (select -sum(delta) from public.wallet_ledger where career_id = '$CAR' and reason = 'shop_card') || '|' ||
                         (select count(*) from public.econ_requests where career_id = '$CAR')")
echo "3) roleta: o mesmo giro em duas conexões ao mesmo tempo:"
$PSQL -qAt -c "update public.careers set diamonds = 15 where id = '$CAR'"
WREQ=$(cat /proc/sys/kernel/random/uuid)
spin() { $PSQL -qAt -c "begin; set local role authenticated; set local request.jwt.claim.sub = '$U';
                 select (public.wheel_spin('$WREQ')) ->> 'replayed'; select pg_sleep(1); commit;" 2>&1 | grep -v '^$' | head -1; }
spin > /tmp/conc_a.txt & sleep 0.2; spin > /tmp/conc_b.txt; wait
W=$($PSQL -qAt -c "select (select count(*) from public.wheel_spins where career_id = '$CAR') || '|' || (select diamonds from public.careers where id = '$CAR')")
echo "   conexão A: replayed=$(cat /tmp/conc_a.txt) | conexão B: replayed=$(cat /tmp/conc_b.txt) | giros: ${W%%|*} | diamantes: ${W##*|}"
[ "$W" = "1|5" ] || { echo " FALHOU (roleta)"; exit 1; }
$PSQL -qAt -c "delete from public.careers where user_id = '$U'; delete from auth.users where id = '$U'"
IFS='|' read -r NP NQ COINS SPENT NREQ <<< "$R"
echo "   compras gravadas na rodada 2: $NP | cartas: $NQ | moedas: $COINS | gasto total no livro (2 rodadas): $SPENT | pedidos: $NREQ"
[ "$NP" = "1" ] && [ "$NQ" = "1" ] && [ "$COINS" = "$((50000 - SPENT))" ] && [ "$NREQ" = "2" ] \
  && echo " TESTE DE CONCORRÊNCIA PASSOU" || { echo " FALHOU"; exit 1; }
