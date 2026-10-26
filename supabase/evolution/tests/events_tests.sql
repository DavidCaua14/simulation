-- =====================================================================
-- TESTES da Etapa 12 — eventos recorrentes, sequência diária e administração (DESENVOLVIMENTO, depois de evolution/13)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/events_tests.sql
-- Usuários: A (admin, Ana_T12) e B (Bia_T12). Tudo termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;
insert into auth.users (id) values ('e12e0000-0000-0000-0000-00000000000a'), ('e12e0000-0000-0000-0000-00000000000b') on conflict do nothing;
insert into public.careers (user_id, nickname, photo_id, country, age, club_id) values
  ('e12e0000-0000-0000-0000-00000000000a', 'Ana_T12', 'p1', 'BR', 30, 'nautico'),
  ('e12e0000-0000-0000-0000-00000000000b', 'Bia_T12', 'p1', 'BR', 30, 'londrina');
insert into public.admins (user_id) values ('e12e0000-0000-0000-0000-00000000000a');
-- temporada de treinador de A com 6 partidas a jogar (2 contra "gigantes" de força 88)
insert into public.career_seasons (id, career_id, season_no, year, mode, region, club_id)
select 'e12e5000-0000-0000-0000-00000000000a', id, 1, 2026, 'coach', 'BRA', 'nautico' from public.careers where nickname = 'Ana_T12';
insert into public.season_fixtures (id, season_id, competition_id, stage, round_no, home_club, away_club, player_match, coach_club) overriding system value values
  (9120001, 'e12e5000-0000-0000-0000-00000000000a', 'serie_b', 'league', 1, 'nautico', 'londrina', true, 'nautico'),
  (9120002, 'e12e5000-0000-0000-0000-00000000000a', 'serie_b', 'league', 2, 'ponte-preta', 'nautico', true, 'nautico'),
  (9120003, 'e12e5000-0000-0000-0000-00000000000a', 'copa_brasil', 'r1', 3, 'nautico', 'bayern', true, 'nautico'),
  (9120004, 'e12e5000-0000-0000-0000-00000000000a', 'copa_brasil', 'r1', 4, 'arsenal', 'nautico', true, 'nautico'),
  (9120005, 'e12e5000-0000-0000-0000-00000000000a', 'serie_b', 'league', 5, 'nautico', 'ponte-preta', false, null);
-- tira os eventos semeados da frente: os testes criam os seus
update public.events set status = 'draft';

create or replace function pg_temp.play(p_id bigint, h int, a int) returns void language sql security definer as $$
  update public.season_fixtures set home_goals = h, away_goals = a, status = 'played', played_at = now() where id = p_id $$;

set local role authenticated;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, true) $$;
create or replace function pg_temp.ev(p_slug text) returns jsonb language sql as $$
  select e from jsonb_array_elements(public.events_overview() -> 'active') e where e ->> 'slug' = p_slug
  union all select e from jsonb_array_elements(public.events_overview() -> 'upcoming') e where e ->> 'slug' = p_slug limit 1 $$;

-- E1. Administração: só admin; validação de tipos, parâmetros e recompensas; criar e publicar
do $$
declare r jsonb; ok boolean; msg text; v_base jsonb;
begin
  v_base := jsonb_build_object('slug', 't12-diario', 'name', 'Diário T12', 'description', 'teste', 'category', 'daily',
    'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days', 'recurrence', 'daily', 'claim_grace_hours', 24,
    'objectives', jsonb_build_array(jsonb_build_object('kind', 'match_won', 'target', 2), jsonb_build_object('kind', 'goals_scored', 'target', 3)),
    'rewards', jsonb_build_array(jsonb_build_object('kind', 'coins', 'amount', 70), jsonb_build_object('kind', 'box', 'amount', 1, 'ref', 'basica')));
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000b');
  begin perform public.admin_event_save(v_base); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E1: não-admin criou evento';
  begin perform public.admin_events_list(); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E1: não-admin listou eventos de administração';
  assert not (public.events_overview() ->> 'is_admin')::boolean, 'E1: B aparece como admin';

  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  assert (public.events_overview() ->> 'is_admin')::boolean, 'E1: A deveria ser admin';
  begin perform public.admin_event_save(jsonb_set(v_base, '{objectives,0,kind}', '"rodar_sql"')); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Tipo de objetivo inválido%', 'E1: tipo livre aceito';
  begin perform public.admin_event_save(jsonb_set(v_base, '{objectives,0,params}', '{"tier":"lenda"}')); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Parâmetro "tier" não é permitido%', 'E1: parâmetro fora do tipo aceito: ' || coalesce(msg, '');
  begin perform public.admin_event_save(jsonb_set(v_base, '{rewards,1,ref}', '"inexistente"')); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Caixa de raridade inexistente.', 'E1: caixa inexistente aceita';
  begin perform public.admin_event_save(jsonb_set(v_base, '{ends_at}', to_jsonb(now() - interval '2 hours'))); ok := true; exception when others then ok := false; end;
  assert not ok, 'E1: fim antes do início aceito';
  begin perform public.admin_event_save(jsonb_set(v_base, '{timezone}', '"Lua/Base"')); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Fuso horário inválido.', 'E1: fuso inválido aceito';

  r := public.admin_event_save(v_base);
  assert r ->> 'status' = 'draft', 'E1: salvar cria rascunho';
  assert pg_temp.ev('t12-diario') is null, 'E1: rascunho visível para jogadores';
  perform public.admin_event_set_status((r ->> 'id')::uuid, 'published');
  assert pg_temp.ev('t12-diario') ->> 'state' = 'active', 'E1: publicado não está ativo';
  begin perform public.admin_event_save(v_base || jsonb_build_object('id', r ->> 'id')); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Evento já começou%', 'E1: editou objetivos de evento em andamento';

  -- temático agendado (começa amanhã) com filtro de força do adversário e limite de 1 conclusão
  r := public.admin_event_save(jsonb_build_object('slug', 't12-gigantes', 'name', 'Gigantes T12', 'description', 'teste', 'category', 'themed',
    'starts_at', now() + interval '1 day', 'ends_at', now() + interval '8 days', 'max_completions', 1,
    'objectives', jsonb_build_array(jsonb_build_object('kind', 'match_won', 'target', 1, 'params', '{"min_opponent_strength": 80}'::jsonb)),
    'rewards', jsonb_build_array(jsonb_build_object('kind', 'cosmetic', 'ref', 'emb_chama'), jsonb_build_object('kind', 'badge', 'ref', 'evento_gigantes_2026'))));
  perform public.admin_event_set_status((r ->> 'id')::uuid, 'published');
  assert pg_temp.ev('t12-gigantes') ->> 'state' = 'scheduled', 'E1: agendado deveria aparecer em "em breve"';
  raise notice 'E1 ok: só admin administra; tipos/parâmetros/recompensas/datas/fuso validados; rascunho oculto; evento em andamento travado';
end $$;

-- E2. Progresso vem das partidas reais; filtros; conclusão única por período; evento agendado não conta
do $$
declare e jsonb;
begin
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  perform pg_temp.play(9120001, 2, 0);       -- vitória, 2 gols
  e := pg_temp.ev('t12-diario');
  assert (e -> 'objectives' -> 0 ->> 'progress')::int = 1 and (e -> 'objectives' -> 1 ->> 'progress')::int = 2, 'E2: progresso após 1ª partida: ' || e::text;
  assert e -> 'completion' = 'null'::jsonb or e -> 'completion' is null, 'E2: concluiu cedo demais';
  perform pg_temp.play(9120002, 3, 1);       -- derrota fora (nautico visitante), 1 gol
  e := pg_temp.ev('t12-diario');
  assert (e -> 'objectives' -> 0 ->> 'progress')::int = 1 and (e -> 'objectives' -> 1 ->> 'progress')::int = 3, 'E2: derrota contou como vitória? ' || e::text;
  perform pg_temp.play(9120005, 4, 0);       -- partida que não é do treinador: não conta
  perform pg_temp.play(9120003, 1, 0);       -- vitória contra o Bayern (88)
  e := pg_temp.ev('t12-diario');
  assert (e -> 'objectives' -> 0 ->> 'progress')::int = 2 and (e -> 'completion' ->> 'claimable')::boolean, 'E2: deveria ter concluído: ' || e::text;
  assert (e -> 'objectives' -> 1 ->> 'progress')::int = 3, 'E2: progresso passa da meta';
  assert (pg_temp.ev('t12-gigantes') -> 'objectives' -> 0 ->> 'progress')::int = 0, 'E2: evento agendado recebeu progresso';
  assert (public.events_overview() ->> 'claimable')::int = 1, 'E2: contador de resgates';
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000b');
  assert (pg_temp.ev('t12-diario') -> 'objectives' -> 0 ->> 'progress')::int = 0, 'E2: progresso vazou para outro jogador';
  raise notice 'E2 ok: vitórias/gols das partidas reais; derrota e partida de outro não contam; agendado ignora; por jogador';
end $$;

-- E3. Resgate: entrega uma vez, idempotente, histórico, ninguém resgata o de outro
do $$
declare v_comp uuid; r jsonb; c0 int; c1 int; b0 int; ok boolean;
begin
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  v_comp := (pg_temp.ev('t12-diario') -> 'completion' ->> 'id')::uuid;
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000b');
  begin perform public.event_claim(v_comp); ok := true; exception when others then ok := false; end;
  assert not ok, 'E3: B resgatou recompensa de A';
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  select coins into c0 from public.careers where nickname = 'Ana_T12';
  select count(*) into b0 from public.reward_boxes rb join public.careers c on c.id = rb.career_id where c.nickname = 'Ana_T12' and rb.source = 'event';
  r := public.event_claim(v_comp);
  assert not (r ->> 'replayed')::boolean and jsonb_array_length(r -> 'rewards') = 2, 'E3: resgate';
  select coins into c1 from public.careers where nickname = 'Ana_T12';
  assert c1 = c0 + 70, 'E3: moedas ' || c0 || ' → ' || c1;
  assert (select count(*) from public.reward_boxes rb join public.careers c on c.id = rb.career_id where c.nickname = 'Ana_T12' and rb.source = 'event') = b0 + 1, 'E3: caixa';
  assert exists (select 1 from public.wallet_ledger l join public.careers c on c.id = l.career_id where c.nickname = 'Ana_T12' and l.reason = 'event_reward' and l.delta = 70), 'E3: razão no extrato';
  r := public.event_claim(v_comp);
  assert (r ->> 'replayed')::boolean, 'E3: segundo resgate deveria só repetir a resposta';
  assert (select coins from public.careers where nickname = 'Ana_T12') = c1, 'E3: pagou duas vezes';
  assert jsonb_array_length(public.events_overview() -> 'history') = 1, 'E3: histórico';
  -- concluído no período: novas vitórias hoje não reabrem
  perform pg_temp.play(9120004, 0, 3);       -- vitória fora contra o Arsenal (88)
  assert (pg_temp.ev('t12-diario') ->> 'completions_total')::int = 1, 'E3: concluiu de novo no mesmo dia';
  raise notice 'E3 ok: recompensa entregue uma vez (moedas no extrato como event_reward + caixa), clique duplo seguro, histórico';
end $$;

-- E4. Períodos no fuso do evento; prazo de resgate; cancelamento; limite de conclusões
do $$
declare v_ev public.events; p record; v_comp uuid; ok boolean; msg text;
begin
  reset role;
  select * into v_ev from public.events where slug = 't12-diario';
  select * into p from public.event_period(v_ev, '2026-10-26 02:30+00');        -- 23:30 em Brasília do dia 25
  assert p.period_key = '2026-10-25', 'E4: dia no fuso: ' || p.period_key;
  select * into p from public.event_period(v_ev, '2026-10-26 03:00+00');        -- 00:00 em Brasília do dia 26
  assert p.period_key = '2026-10-26' and p.period_end = '2026-10-27 03:00+00', 'E4: virada do dia';
  v_ev.recurrence := 'weekly';
  select * into p from public.event_period(v_ev, '2026-11-01 23:00-03');        -- domingo
  assert p.period_key = 'semana-2026-10-26', 'E4: semana começa na segunda: ' || p.period_key;

  -- prazo vencido / evento cancelado
  update public.event_completions set claim_until = now() - interval '1 minute', claimed_at = null
   where event_id = (select id from public.events where slug = 't12-diario');
  set local role authenticated;
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  v_comp := (pg_temp.ev('t12-diario') -> 'completion' ->> 'id')::uuid;
  assert not (pg_temp.ev('t12-diario') -> 'completion' ->> 'claimable')::boolean, 'E4: vencido aparece como resgatável';
  begin perform public.event_claim(v_comp); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'O prazo para resgatar%', 'E4: resgatou fora do prazo';
  perform public.admin_event_set_status((pg_temp.ev('t12-diario') ->> 'id')::uuid, 'cancelled');
  assert pg_temp.ev('t12-diario') is null, 'E4: cancelado continua listado como ativo';
  raise notice 'E4 ok: dia/semana no fuso de Brasília; prazo de resgate; cancelamento tira o evento do ar';
end $$;

-- E5. Caixas, cartas novas, venda no mercado e palpites também alimentam eventos
do $$
declare r jsonb; e jsonb; v_box uuid; v_car uuid;
begin
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  r := public.admin_event_save(jsonb_build_object('slug', 't12-colecao', 'name', 'Coleção T12', 'description', 'teste', 'category', 'collection',
    'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '3 days', 'max_completions', 1,
    'objectives', jsonb_build_array(jsonb_build_object('kind', 'box_opened', 'target', 1), jsonb_build_object('kind', 'card_collected', 'target', 1),
                                    jsonb_build_object('kind', 'prediction_placed', 'target', 2)),
    'rewards', jsonb_build_array(jsonb_build_object('kind', 'diamonds', 'amount', 1))));
  perform public.admin_event_set_status((r ->> 'id')::uuid, 'published');
  select id into v_car from public.careers where nickname = 'Ana_T12';
  reset role;
  insert into public.tickets (career_id) values (v_car), (v_car), (v_car);
  v_box := public.card_grant_box(v_car, 'basica', 'test', 't12');
  set local role authenticated;
  perform public.box_open(v_box);
  e := pg_temp.ev('t12-colecao');
  assert (e -> 'objectives' -> 0 ->> 'progress')::int = 1, 'E5: caixa aberta: ' || e::text;
  assert (e -> 'objectives' -> 1 ->> 'progress')::int = 1, 'E5: carta nova';
  assert (e -> 'objectives' -> 2 ->> 'progress')::int = 2, 'E5: palpites';
  assert (e -> 'completion' ->> 'claimable')::boolean, 'E5: deveria ter concluído';
  assert (e ->> 'completions_total')::int = 1, 'E5: total';
  assert not ((public.event_claim((e -> 'completion' ->> 'id')::uuid)) ->> 'replayed')::boolean, 'E5: resgate';
  raise notice 'E5 ok: abrir caixa, carta nova e palpite geram progresso; evento de conclusão única';
end $$;

-- E6. Sequência diária: exige atividade real, paga uma vez por dia, continua/zera
do $$
declare s jsonb; r jsonb; ok boolean; msg text; c0 int;
begin
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000b');           -- B não jogou hoje
  s := public.events_overview() -> 'streak';
  assert not (s ->> 'eligible_today')::boolean and (s ->> 'today_day')::int = 1, 'E6: B elegível sem jogar';
  begin perform public.streak_claim(); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Jogue uma partida%', 'E6: B recebeu sem atividade';

  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');           -- A jogou hoje
  assert (public.events_overview() -> 'streak' ->> 'eligible_today')::boolean, 'E6: A deveria estar elegível';
  -- A vinha de 6 dias seguidos até ontem: hoje é o 7º (recompensa maior)
  reset role;
  insert into public.player_streaks (career_id, current, best, last_day)
  select id, 6, 6, (now() at time zone 'America/Sao_Paulo')::date - 1 from public.careers where nickname = 'Ana_T12';
  set local role authenticated;
  select coins into c0 from public.careers where nickname = 'Ana_T12';
  r := public.streak_claim();
  assert (r ->> 'current')::int = 7 and (r ->> 'day')::int = 7 and r ->> 'box_tier' = 'destaque', 'E6: dia 7: ' || r::text;
  assert (select coins from public.careers where nickname = 'Ana_T12') = c0 + 200, 'E6: moedas do dia 7';
  assert (public.streak_claim() ->> 'replayed')::boolean, 'E6: pagou duas vezes no mesmo dia';
  assert (select coins from public.careers where nickname = 'Ana_T12') = c0 + 200, 'E6: moedas duplicadas';
  s := public.events_overview() -> 'streak';
  assert (s ->> 'claimed_today')::boolean and (s ->> 'current')::int = 7 and (s ->> 'best')::int = 7, 'E6: estado: ' || s::text;
  -- pulou um dia: recomeça do 1
  reset role;
  update public.player_streaks set last_day = last_day - 3 where career_id = (select id from public.careers where nickname = 'Ana_T12');
  set local role authenticated;
  r := public.streak_claim();
  assert (r ->> 'current')::int = 1 and (r ->> 'day')::int = 1, 'E6: sequência quebrada deveria recomeçar: ' || r::text;
  raise notice 'E6 ok: exige partida/palpite no dia; dia 7 com caixa destaque; uma vez por dia; quebra recomeça';
end $$;

-- E7. O app não escreve nem lê as tabelas diretamente; insígnia de eventos
do $$
declare ok boolean;
begin
  perform pg_temp.as_user('e12e0000-0000-0000-0000-00000000000a');
  begin insert into public.event_progress select event_id, career_id, period_key, objective_id, 999 from public.event_progress limit 1; ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E7: app gravou progresso';
  begin update public.event_completions set claimed_at = null; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E7: app alterou conclusão';
  begin perform 1 from public.events; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E7: app leu a tabela de eventos direto';
  begin perform public.event_track((select id from public.careers where nickname = 'Ana_T12'), 'match_won', 50, '{}'); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E7: app chamou o motor de progresso';
  begin insert into public.admins values ('e12e0000-0000-0000-0000-00000000000b'); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'E7: app se promoveu a admin';
  raise notice 'E7 ok: progresso, conclusões, eventos e admins fora do alcance do app';
end $$;

reset role;
-- E8. Insígnias: eventos resgatados e melhor sequência
do $$
declare v uuid := (select id from public.careers where nickname = 'Ana_T12');
begin
  assert public.badge_metric(v, 'events_completed', 1) = 1, 'E8: métrica de eventos';
  assert public.badge_metric(v, 'daily_streak', 7) = 7, 'E8: métrica de sequência (melhor marca)';
  perform public.badges_refresh(v);
  assert exists (select 1 from public.player_badges where career_id = v and badge_id = 'evento_1'), 'E8: insígnia Participante';
  assert exists (select 1 from public.player_badges where career_id = v and badge_id = 'sequencia_diaria_7'), 'E8: insígnia Semana completa';
  raise notice 'E8 ok: insígnias de eventos e de sequência concedidas pela regra do perfil';
end $$;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 12 PASSARAM'; end $$;
rollback;
