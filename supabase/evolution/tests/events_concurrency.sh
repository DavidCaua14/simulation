#!/bin/bash
# Teste de CONCORRÊNCIA dos resgates de evento e da sequência diária (duas conexões ao mesmo tempo). DESENVOLVIMENTO.
#   PSQL="psql -h /tmp -U pg -d evo_t" bash supabase/evolution/tests/events_concurrency.sh
# Cria um usuário e um evento de teste, dispara resgates simultâneos e apaga tudo no final.
set -e
PSQL=${PSQL:-psql}
U=c0c0c0c0-0000-0000-0000-000000000012
CAR=c0c0c0c0-0000-0000-0000-0000000000d2
$PSQL -qAt -v ON_ERROR_STOP=1 <<SQL
delete from public.events where slug = 'conc-t12';
delete from public.careers where user_id = '$U';
insert into auth.users (id) values ('$U') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, coins) values ('$CAR', '$U', 'teste_conc12', 'p1', 'BR', 30, 'sport', 0);
insert into public.events (slug, name, description, category, starts_at, ends_at, status)
values ('conc-t12', 'Conc', 'teste', 'themed', now() - interval '1 hour', now() + interval '1 day', 'published');
insert into public.event_objectives (event_id, kind, target, label) select id, 'prediction_placed', 1, 'x' from public.events where slug = 'conc-t12';
insert into public.event_rewards (event_id, kind, amount) select id, 'coins', 300 from public.events where slug = 'conc-t12';
insert into public.tickets (career_id) values ('$CAR');      -- conclui o evento e libera a sequência do dia
SQL
COMP=$($PSQL -qAt -c "select c.id from public.event_completions c join public.events e on e.id = c.event_id where e.slug = 'conc-t12' and c.career_id = '$CAR'")
call() { $PSQL -qAt -c "begin; set local role authenticated; set local request.jwt.claim.sub = '$U';
                 select ($1) ->> 'replayed'; select pg_sleep(1); commit;" 2>&1 | grep -v '^$' | head -1; }
echo "1) o mesmo resgate de evento em duas conexões:"
call "public.event_claim('$COMP')" > /tmp/conc_a.txt & sleep 0.2; call "public.event_claim('$COMP')" > /tmp/conc_b.txt; wait
echo "   A: replayed=$(cat /tmp/conc_a.txt) | B: replayed=$(cat /tmp/conc_b.txt)"
echo "2) a recompensa diária da sequência em duas conexões:"
call "public.streak_claim()" > /tmp/conc_c.txt & sleep 0.2; call "public.streak_claim()" > /tmp/conc_d.txt; wait
echo "   A: replayed=$(cat /tmp/conc_c.txt) | B: replayed=$(cat /tmp/conc_d.txt)"
R=$($PSQL -qAt -c "select (select coins from public.careers where id = '$CAR') || '|' ||
                         (select count(*) from public.wallet_ledger where career_id = '$CAR' and reason = 'event_reward') || '|' ||
                         (select count(*) from public.wallet_ledger where career_id = '$CAR' and reason = 'daily_streak') || '|' ||
                         (select current from public.player_streaks where career_id = '$CAR')")
$PSQL -qAt -c "delete from public.events where slug = 'conc-t12'; delete from public.tickets where career_id = '$CAR';
               delete from public.careers where user_id = '$U'; delete from auth.users where id = '$U'"
echo "   moedas | lançamentos de evento | lançamentos de sequência | sequência = $R"
[ "$R" = "340|1|1|1" ] && echo " TESTE DE CONCORRÊNCIA DE EVENTOS PASSOU" || { echo " FALHOU"; exit 1; }
