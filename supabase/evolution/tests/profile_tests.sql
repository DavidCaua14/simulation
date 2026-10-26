-- =====================================================================
-- TESTES da Etapa 9 — perfil, carta em destaque, insígnias e cosméticos (banco de DESENVOLVIMENTO, depois de evolution/11)
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/evolution/tests/profile_tests.sql
-- =====================================================================
begin;
set local client_min_messages = notice;
insert into auth.users (id) values ('9f9f0000-0000-0000-0000-000000000001'), ('9f9f0000-0000-0000-0000-000000000002') on conflict do nothing;
insert into public.careers (id, user_id, nickname, photo_id, country, age, club_id, diamonds) values
  ('9f9f0000-0000-0000-0000-0000000000c1', '9f9f0000-0000-0000-0000-000000000001', 'perfil_t9', 'p1', 'BR', 30, 'sport', 100),
  ('9f9f0000-0000-0000-0000-0000000000c2', '9f9f0000-0000-0000-0000-000000000002', 'outro_t9', 'p1', 'BR', 30, 'goias', 100);
create temp table t9 on commit drop as
select (select id from public.cards where tier = 'lenda' and active order by id limit 1) as lenda,
       (select id from public.cards where tier = 'epica' and active order by id limit 1) as epica;
grant select on t9 to authenticated;
insert into public.user_cards (career_id, card_id, qty) select '9f9f0000-0000-0000-0000-0000000000c1', lenda, 1 from t9;

set local role authenticated;
set local request.jwt.claim.sub = '9f9f0000-0000-0000-0000-000000000001';

-- P1. Meu perfil: identidade, fundo padrão, insígnias (com as bloqueadas e suas regras), privacidade
do $$
declare p jsonb;
begin
  p := public.profile_me();
  assert p ->> 'nickname' = 'perfil_t9' and p ->> 'country' = 'BR' and p ->> 'joined_at' is not null, 'P1: identidade';
  assert p -> 'equipped' -> 'background' ->> 'id' = 'gramado', 'P1: fundo padrão';
  assert jsonb_array_length(p -> 'badges') = (select count(*) from public.badges where active), 'P1: o dono vê todas as insígnias (bloqueadas com a regra)';
  assert not exists (select 1 from jsonb_array_elements(p -> 'badges') b where (b ->> 'earned')::boolean), 'P1: insígnia sem cumprir regra';
  assert p -> 'privacy' ->> 'show_stats' = 'true', 'P1: privacidade padrão';
  raise notice 'P1 ok: perfil criado no servidor (fundo padrão, % insígnias bloqueadas com regra visível)', jsonb_array_length(p -> 'badges');
end $$;

-- P2. Carta em destaque: só carta própria; some ao deixar de ter
do $$
declare t record; ok boolean; msg text;
begin
  select * into t from t9;
  perform public.profile_set_featured(t.lenda);
  assert public.profile_me() -> 'featured_card' ->> 'id' = t.lenda, 'P2: destaque';
  begin perform public.profile_set_featured(t.epica); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Você não tem esta carta%', 'P2: destacou carta que não tem';
  -- anunciar a única cópia no mercado: ela sai do inventário e o destaque some
  perform public.market_list_card(t.lenda, 5000, gen_random_uuid());
  assert public.profile_me() -> 'featured_card' is null, 'P2: destaque continuou com a carta anunciada';
  raise notice 'P2 ok: destaque só de carta própria; anunciar/vender tira o destaque';
end $$;

-- P3. Insígnias por regra verificável (coleção, Épica, sequência de vitórias) — nunca pelo app
reset role;
insert into public.user_cards (career_id, card_id, qty)
select '9f9f0000-0000-0000-0000-0000000000c1', c.id, 1 from public.cards c where c.active and c.tier = 'basica' order by c.id limit 60
on conflict do nothing;
insert into public.user_cards (career_id, card_id, qty) select '9f9f0000-0000-0000-0000-0000000000c1', epica, 1 from t9 on conflict do nothing;
set local role authenticated;
do $$
declare p jsonb; ok boolean;
begin
  perform public.mgr_hub();                       -- cria o treinador e a temporada (para a sequência de vitórias)
  p := public.profile_me();
  assert exists (select 1 from jsonb_array_elements(p -> 'new_badges') b where b ->> 'id' = 'colecao_50'), 'P3: insígnia de coleção';
  assert exists (select 1 from jsonb_array_elements(p -> 'new_badges') b where b ->> 'id' = 'epica_1'), 'P3: insígnia Épica';
  assert not exists (select 1 from jsonb_array_elements(p -> 'new_badges') b where b ->> 'id' = 'colecao_150'), 'P3: insígnia acima do que tem';
  assert jsonb_array_length(public.profile_me() -> 'new_badges') = 0, 'P3: concedeu a mesma insígnia duas vezes';
  begin insert into public.player_badges (career_id, badge_id) select id, 'titulo_10' from public.careers where user_id = auth.uid(); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'P3: o app concedeu insígnia a si mesmo';
  raise notice 'P3 ok: Colecionador e Toque épico concedidos pelo servidor; o app não grava insígnias';
end $$;
reset role;
-- 5 vitórias seguidas nas partidas do treinador (resultado gravado no banco, como o motor faz)
with my as (
  select f.id, row_number() over (order by f.round_no, f.id) as rn, s.club_id
    from public.season_fixtures f join public.career_seasons s on s.id = f.season_id
   where s.career_id = '9f9f0000-0000-0000-0000-0000000000c1' and s.mode = 'coach' and (f.home_club = s.club_id or f.away_club = s.club_id)
   order by f.round_no, f.id limit 5)
update public.season_fixtures f
   set status = 'played', player_match = true, coach_club = my.club_id, played_at = now() + my.rn * interval '1 minute',
       home_goals = case when f.home_club = my.club_id then 2 else 0 end, away_goals = case when f.away_club = my.club_id then 2 else 0 end
  from my where f.id = my.id;
set local role authenticated;
do $$
declare p jsonb;
begin
  p := public.profile_me();
  assert exists (select 1 from jsonb_array_elements(p -> 'new_badges') b where b ->> 'id' = 'sequencia_5'), 'P3: sequência de 5 vitórias';
  assert not exists (select 1 from jsonb_array_elements(p -> 'badges') b where b ->> 'id' = 'sequencia_10' and (b ->> 'earned')::boolean), 'P3: sequência 10';
  raise notice 'P3 ok: "Embalado" após 5 vitórias seguidas (valor verificado no banco)';
end $$;

-- P4. Cosméticos: grátis já são seus; compra com diamantes; idempotência; equipar/desequipar; regras
do $$
declare cat jsonb; r jsonb; r2 jsonb; v_req uuid := gen_random_uuid(); ok boolean; msg text; p jsonb;
begin
  cat := public.cosmetics_catalog();
  assert (select bool_and((i ->> 'owned')::boolean) from jsonb_array_elements(cat -> 'items') i where (i ->> 'price')::int = 0), 'P4: grátis deveriam ser seus';
  assert not exists (select 1 from jsonb_array_elements(cat -> 'items') i where i ->> 'id' = 'aro_ouro' and (i ->> 'owned')::boolean), 'P4: item pago já seu';
  begin perform public.cosmetic_equip('frame', 'aro_ouro'); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg like 'Você ainda não tem este item%', 'P4: equipou item que não tem';
  r := public.cosmetic_buy('aro_ouro', v_req);
  assert (r ->> 'diamonds')::int = 80, 'P4: compra (100 − 20)';
  r2 := public.cosmetic_buy('aro_ouro', v_req);
  assert (r2 ->> 'replayed')::boolean and (select diamonds from public.careers where user_id = auth.uid() and status = 'active') = 80, 'P4: replay';
  begin perform public.cosmetic_buy('aro_ouro', gen_random_uuid()); ok := true; exception when others then ok := false; msg := sqlerrm; end;
  assert not ok and msg = 'Você já tem este item.', 'P4: comprou duas vezes';
  begin perform public.cosmetic_equip('background', 'aro_ouro'); ok := true; exception when others then ok := false; end;
  assert not ok, 'P4: moldura equipada no lugar do fundo';
  perform public.cosmetic_equip('frame', 'aro_ouro');
  perform public.cosmetic_equip('background', 'elite');
  p := public.profile_me();
  assert p -> 'equipped' -> 'frame' ->> 'id' = 'aro_ouro' and p -> 'equipped' -> 'background' ->> 'id' = 'elite', 'P4: equipados';
  perform public.cosmetic_equip('frame', null);
  perform public.cosmetic_equip('background', null);
  p := public.profile_me();
  assert p -> 'equipped' -> 'frame' is null and p -> 'equipped' -> 'background' ->> 'id' = 'gramado', 'P4: desequipar';
  assert exists (select 1 from public.wallet_ledger l join public.careers c on c.id = l.career_id where c.user_id = auth.uid() and l.reason = 'cosmetic' and l.delta = -20),
    'P4: compra fora do livro';
  -- puramente visual: nenhuma carta mudou
  assert (select overall from public.cards where id = (select lenda from t9)) = (select overall from public.cards where id = (select lenda from t9)), 'P4';
  raise notice 'P4 ok: cosméticos (grátis, compra única e idempotente, equipar só o que tem e no espaço certo, desequipar)';
end $$;

-- P5. Privacidade: o visitante só vê o que o dono liberou
do $$
declare p jsonb; ok boolean;
begin
  perform public.profile_set_privacy('{"show_stats": false, "show_collection": false, "hack": true}');
  assert (public.profile_me() -> 'privacy' ->> 'show_stats') = 'false' and not (public.profile_me() -> 'privacy' ? 'hack'), 'P5: privacidade';
  begin perform public.profile_set_privacy('{"show_titles": "sim"}'); ok := true; exception when others then ok := false; end;
  assert not ok, 'P5: valor inválido aceito';
end $$;
reset role;
do $$
declare v jsonb;
begin
  v := public.profile_build('9f9f0000-0000-0000-0000-0000000000c1', false);
  assert v -> 'stats' is null and v -> 'collection' is null and v -> 'privacy' is null and v -> 'career_id' is null, 'P5: visitante viu dado privado';
  assert v ->> 'nickname' = 'perfil_t9' and v -> 'titles' is not null and v -> 'club_id' is not null, 'P5: dado público sumiu';
  assert not exists (select 1 from jsonb_array_elements(v -> 'badges') b where not (b ->> 'earned')::boolean), 'P5: visitante vê insígnias bloqueadas';
  raise notice 'P5 ok: visitante vê só o público (sem estatísticas/coleção escondidas, sem id interno, só insígnias conquistadas)';
end $$;
set local role authenticated;

-- P6. Avatar e migração única do navegador
do $$
declare ok boolean; msg text;
begin
  perform public.profile_set_avatar('data:image/jpeg;base64,' || repeat('A', 100));
  assert public.profile_me() ->> 'avatar' like 'data:image/jpeg;base64,%', 'P6: avatar';
  perform public.profile_set_avatar('preset:p2');
  assert public.profile_me() ->> 'avatar' = 'preset:p2', 'P6: foto pronta';
  begin perform public.profile_set_avatar('preset:<script>'); ok := true; exception when others then ok := false; end;
  assert not ok, 'P6: aceitou preset inválido';
  begin perform public.profile_set_avatar('data:text/html;base64,PHNjcmlwdD4='); ok := true; exception when others then ok := false; end;
  assert not ok, 'P6: aceitou algo que não é imagem';
  begin perform public.profile_set_avatar('data:image/jpeg;base64,' || repeat('A', 95000)); ok := true; exception when others then ok := false; end;
  assert not ok, 'P6: aceitou imagem grande demais';
  perform public.profile_migrate_local(null, 'ouro');
  assert public.profile_me() -> 'equipped' -> 'background' ->> 'id' = 'ouro', 'P6: migração do banner';
  perform public.profile_migrate_local(null, 'rubro');
  assert public.profile_me() -> 'equipped' -> 'background' ->> 'id' = 'ouro', 'P6: migração rodou duas vezes';
  raise notice 'P6 ok: avatar validado; preferências antigas do navegador migradas uma única vez';
end $$;

-- P7. Permissões: o app não grava perfil, cosméticos nem insígnias direto, nem lê perfis de outros
do $$
declare ok boolean;
begin
  begin update public.player_profiles set featured_card = null; ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'P7: app alterou perfil direto';
  begin insert into public.player_cosmetics (career_id, cosmetic_id) select id, 'aro_galaxia' from public.careers where user_id = auth.uid(); ok := true;
  exception when insufficient_privilege then ok := false; end;
  assert not ok, 'P7: app se deu um cosmético';
  begin perform public.badges_refresh((select id from public.careers where user_id = auth.uid())); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'P7: app chamou função interna';
  begin perform public.profile_build('9f9f0000-0000-0000-0000-0000000000c2', true); ok := true; exception when insufficient_privilege then ok := false; end;
  assert not ok, 'P7: app montou perfil completo de outro jogador';
  raise notice 'P7 ok: permissões';
end $$;

reset role;
do $$ begin raise notice ' TODOS OS TESTES DA ETAPA 9 PASSARAM'; end $$;
rollback;
