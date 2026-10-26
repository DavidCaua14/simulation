-- =====================================================================
-- TESTES da Etapa 10 — amigos e convites (banco de DESENVOLVIMENTO, depois de evolution/12)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/friends_tests.sql
-- Usuários: A (Ana_T10), B (Bia_T10), C (Caio_T10), D (Dudu_T10). Tudo termina em ROLLBACK.
-- =====================================================================
begin;
set local client_min_messages = notice;
insert into auth.users (id) values ('f10f0000-0000-0000-0000-00000000000a'), ('f10f0000-0000-0000-0000-00000000000b'),
  ('f10f0000-0000-0000-0000-00000000000c'), ('f10f0000-0000-0000-0000-00000000000d') on conflict do nothing;
insert into public.careers (user_id, nickname, photo_id, country, age, club_id) values
  ('f10f0000-0000-0000-0000-00000000000a', 'Ana_T10', 'p1', 'BR', 30, 'sport'),
  ('f10f0000-0000-0000-0000-00000000000b', 'Bia_T10', 'p1', 'EN', 30, 'bolton'),
  ('f10f0000-0000-0000-0000-00000000000c', 'Caio_T10', 'p1', 'BR', 30, 'goias'),
  ('f10f0000-0000-0000-0000-00000000000d', 'Dudu_T10', 'p1', 'BR', 30, 'avai');
set local role authenticated;
create or replace function pg_temp.as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, true) $$;

-- F1. Convite por username (maiúsculas/minúsculas), duplicado, a si mesmo, inexistente, convite mútuo = aceitar
do $$
declare r jsonb; ok boolean; msg text;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  r := public.friend_request('  bia_t10 ');
  assert r ->> 'status' = 'sent' and r ->> 'nickname' = 'Bia_T10', 'F1: convite';
  begin perform public.friend_request('BIA_T10'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você já enviou um convite para este jogador.', 'F1: duplicado: ' || coalesce(msg, '');
  begin perform public.friend_request('Ana_T10'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você não pode convidar a si mesmo.', 'F1: a si mesmo';
  begin perform public.friend_request('ninguem_assim'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Usuário não encontrado.', 'F1: inexistente';
  begin perform public.friend_request('B'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Usuário não encontrado.', 'F1: busca parcial deveria falhar (não lista nomes)';

  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000b');
  assert jsonb_array_length(public.friends_overview() -> 'incoming') = 1, 'F1: B não viu o convite recebido';
  r := public.friend_request('ana_t10');        -- B convida A, que já tinha convidado B → vira amizade
  assert r ->> 'status' = 'accepted', 'F1: convite mútuo deveria aceitar';
  assert jsonb_array_length(public.friends_overview() -> 'friends') = 1 and jsonb_array_length(public.friends_overview() -> 'incoming') = 0, 'F1: lista de B';
  begin perform public.friend_request('Ana_T10'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Vocês já são amigos.', 'F1: amizade duplicada';
  raise notice 'F1 ok: convite por username, duplicado/si mesmo/inexistente/busca parcial recusados, convite mútuo vira amizade';
end $$;

-- F2. Recusar, aparecer como recusado para quem convidou, reenviar e aceitar
do $$
declare r jsonb; ov jsonb; v_id uuid;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  r := public.friend_request('Caio_T10');
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000c');
  v_id := (public.friends_overview() -> 'incoming' -> 0 ->> 'id')::uuid;
  assert (public.friend_respond(v_id, false)) ->> 'status' = 'declined', 'F2: recusar';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  ov := public.friends_overview();
  assert exists (select 1 from jsonb_array_elements(ov -> 'declined') d where d ->> 'nickname' = 'Caio_T10'), 'F2: A não vê a recusa';
  assert jsonb_array_length(ov -> 'outgoing') = 0, 'F2: convite recusado ainda pendente';
  r := public.friend_request('Caio_T10');
  assert r ->> 'status' = 'sent', 'F2: reenviar depois de recusado';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000c');
  assert (public.friend_respond((public.friends_overview() -> 'incoming' -> 0 ->> 'id')::uuid, true)) ->> 'status' = 'accepted', 'F2: aceitar';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  assert jsonb_array_length(public.friends_overview() -> 'friends') = 2, 'F2: A deveria ter 2 amigos';
  raise notice 'F2 ok: recusa visível para quem convidou; reenviar; aceitar; lista atualizada';
end $$;

-- F3. Proteções do convite: responder duas vezes, responder convite alheio, cancelar
do $$
declare v_id uuid; ok boolean; msg text;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  v_id := ((public.friend_request('Dudu_T10')) ->> 'id')::uuid;
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000b');
  begin perform public.friend_respond(v_id, true); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Convite não encontrado.', 'F3: B aceitou convite que era para D';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  begin perform public.friend_respond(v_id, true); ok := true; exception when others then ok := false; end;
  assert not ok, 'F3: quem enviou aceitou o próprio convite';
  assert (public.friend_cancel(v_id)) ->> 'status' = 'cancelled', 'F3: cancelar';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000d');
  assert jsonb_array_length(public.friends_overview() -> 'incoming') = 0, 'F3: D ainda vê convite cancelado';
  begin perform public.friend_respond(v_id, true); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok, 'F3: aceitou convite cancelado';
  raise notice 'F3 ok: só o destinatário responde; cancelar some para o destinatário';
end $$;

-- F4. Perfil do amigo: só amigos, somente leitura e respeitando a privacidade dele
do $$
declare p jsonb; ok boolean; msg text;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000b');
  perform public.profile_set_privacy('{"show_stats": false, "show_career": false}');
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  p := public.friend_profile('BIA_T10');
  assert p ->> 'nickname' = 'Bia_T10' and p ->> 'country' = 'EN' and p ->> 'friend_since' is not null, 'F4: perfil do amigo';
  assert p -> 'stats' is null and p -> 'club_id' is null and p -> 'privacy' is null and p -> 'career_id' is null, 'F4: privacidade de B ignorada';
  begin perform public.friend_profile('Dudu_T10'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Só amigos podem ver este perfil.', 'F4: viu perfil de quem não é amigo';
  -- somente leitura: as funções de alteração sempre agem sobre a PRÓPRIA carreira
  perform public.profile_set_featured(null);
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000b');
  assert (public.profile_me() -> 'privacy' ->> 'show_stats') = 'false', 'F4: A alterou algo de B';
  raise notice 'F4 ok: perfil público só para amigos, com a privacidade do dono';
end $$;

-- F5. Desfazer amizade
do $$
declare v_id uuid; ok boolean;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');
  select (f ->> 'id')::uuid into v_id from jsonb_array_elements(public.friends_overview() -> 'friends') f where f ->> 'nickname' = 'Bia_T10';
  assert (public.friend_remove(v_id)) ->> 'status' = 'removed', 'F5: desfazer';
  begin perform public.friend_profile('Bia_T10'); ok := true; exception when others then ok := false; end;
  assert not ok, 'F5: ainda vê o perfil depois de desfazer';
  assert (public.friend_request('Bia_T10')) ->> 'status' = 'sent', 'F5: novo convite depois de desfazer';
  raise notice 'F5 ok: desfazer amizade e convidar de novo';
end $$;

-- F6. Anti-spam e permissões
reset role;
update public.friends_config set max_requests_hour = 3;
set local role authenticated;
do $$
declare ok boolean; msg text;
begin
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000a');   -- A já enviou 5 convites nesta hora
  begin perform public.friend_request('Dudu_T10'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Muitos convites%', 'F6: limite por hora: ' || coalesce(msg, '');
  begin insert into public.friendships (requester, addressee) select a.id, b.id from public.careers a, public.careers b
        where a.nickname = 'Ana_T10' and b.nickname = 'Dudu_T10'; ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'F6: app criou amizade direto';
  begin update public.friendships set status = 'accepted'; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'F6: app aceitou convite direto';
  perform pg_temp.as_user('f10f0000-0000-0000-0000-00000000000d');
  assert (select count(*) from public.friendships) > 0, 'F6: D deveria ver as próprias linhas';
  assert not exists (select 1 from public.friendships f
                      where (select id from public.careers where nickname = 'Dudu_T10') not in (f.requester, f.addressee)), 'F6: D vê amizades alheias';
  raise notice 'F6 ok: limite de convites por hora; o app não grava amizades; cada um só vê as próprias';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 10 PASSARAM'; end $$;
rollback;
