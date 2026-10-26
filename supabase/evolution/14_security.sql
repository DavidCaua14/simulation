-- =====================================================================
-- EVOLUÇÃO 14 — SEGURANÇA E INTEGRIDADE (Etapa 13)
--
-- A) Origem de TODA movimentação de carteira: funções antigas (abrir caixa, descartar, prêmios de partida/competição,
--    luvas de contrato, energia da partida, palpites) passam a aparecer no extrato com motivo próprio em vez de "other",
--    sem reescrever essas funções: o gatilho do livro identifica a função que fez a alteração (pilha de chamadas).
-- B) Funções internas deixam de ser chamáveis pela API (antes: anon/authenticated podiam executar, p.ex.,
--    sim_create_season(p_career) com o id de QUALQUER carreira). Nada do app chamava essas funções.
-- C) Escrita direta em tabelas pela API: só o que o app usa (criar carreira, colunas do formulário). TRUNCATE fora.
--    Funções novas nascem sem permissão para anon/PUBLIC (cada migração concede explicitamente).
-- D) Limites de requisição por usuário (compras/giros/mercado, foto de perfil, anúncios, palpites, administração).
-- Rode depois de evolution/13. Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) MOTIVO DAS MOVIMENTAÇÕES ANTIGAS
-- ---------------------------------------------------------------------
create table if not exists public.econ_reason_map (
  fn     text primary key,      -- nome da função que altera a carteira sem informar motivo
  reason text not null,
  label  text not null
);
insert into public.econ_reason_map (fn, reason, label) values
  ('box_open',               'box_open',            'Caixa aberta'),
  ('card_discard',           'card_discard',        'Carta descartada'),
  ('choose_initial_club',    'signing_bonus',       'Luvas de contrato'),
  ('mgr_offer_respond',      'signing_bonus',       'Luvas de contrato'),
  ('season_offer_respond',   'signing_bonus',       'Luvas de contrato'),
  ('mgr_after_user_match',   'match_reward',        'Prêmio de partida'),
  ('season_play',            'match_reward',        'Prêmio de partida'),
  ('mgr_match_start',        'match_energy',        'Energia da partida'),
  ('sim_finish_competition', 'competition_prize',   'Premiação de competição'),
  ('place_ticket',           'prediction_stake',    'Palpite feito'),
  ('settle_tickets',         'prediction_payout',   'Palpite premiado')
on conflict (fn) do update set reason = excluded.reason, label = excluded.label;
alter table public.econ_reason_map enable row level security;
revoke all on public.econ_reason_map from anon, authenticated;

create or replace function public.econ_ledger_trg()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_reason text := nullif(current_setting('econ.reason', true), '');
  v_ref    text := nullif(current_setting('econ.ref', true), '');
  v_cur    text;
  v_old    int;
  v_new    int;
  v_ctx    text;
  v_fn     text;
  v_map    text;
  v_looked boolean := false;
  v_frames int := 0;
begin
  foreach v_cur in array array['coins', 'diamonds', 'energy', 'bonus_energy'] loop
    v_new := (to_jsonb(new) ->> v_cur)::int;
    v_old := case when tg_op = 'INSERT' then 0 else (to_jsonb(old) ->> v_cur)::int end;
    if v_new is distinct from v_old and coalesce(v_new, 0) - coalesce(v_old, 0) <> 0 then
      -- sem motivo informado: procura, da chamada mais interna para fora, a primeira função conhecida
      if v_reason is null and tg_op = 'UPDATE' and not v_looked then
        v_looked := true;
        get diagnostics v_ctx = pg_context;
        for v_fn in select m[1] from regexp_matches(coalesce(v_ctx, ''), 'function (?:public\.)?([a-z_0-9]+)\(', 'g') as m loop
          continue when v_fn = 'econ_ledger_trg';
          v_frames := v_frames + 1;
          select reason into v_map from public.econ_reason_map where fn = v_fn;
          exit when v_map is not null;
        end loop;
        -- alteração feita direto no banco (painel/SQL do administrador), fora de qualquer função do jogo
        if v_map is null and v_frames = 0 then v_map := 'manual_adjustment'; end if;
      end if;
      insert into public.wallet_ledger (career_id, currency, delta, balance_after, reason, ref)
      values (new.id, v_cur, coalesce(v_new, 0) - coalesce(v_old, 0), coalesce(v_new, 0),
              coalesce(v_reason,
                       case when tg_op = 'INSERT' then 'opening_balance'
                            -- recarga automática de energia (sim_lock_career): só a energia sobe e o relógio anda
                            when v_cur = 'energy' and new.energy_reset_at is distinct from old.energy_reset_at and v_new > v_old then 'energy_regen'
                            else coalesce(v_map, 'other') end),
              v_ref);
    end if;
  end loop;
  return null;
end;
$$;
revoke all on function public.econ_ledger_trg() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- B) FUNÇÕES INTERNAS FORA DA API
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  -- nenhuma função SECURITY DEFINER do schema public é para visitantes sem login
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prosecdef
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
  -- funções de motor que recebem id de carreira/temporada: só outras funções do servidor podem chamar
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('sim_create_season', 'sim_participants_build', 'sim_phase_create', 'sim_phase_pairs',
                                'sim_season_transition', 'sim_swiss_create', 'mgr_make_offer', 'mgr_offer_region_ok',
                                'mgr_region_league_clubs') loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;
-- o app chama estas sem login? Não: a criação de personagem acontece depois de entrar.
do $$ begin
  if to_regprocedure('public.is_nickname_taken(text)') is not null then
    execute 'grant execute on function public.is_nickname_taken(text) to authenticated';
  end if;
end $$;

-- funções criadas daqui para frente não ficam abertas por padrão (cada migração concede o que o app usa)
alter default privileges in schema public revoke execute on functions from public, anon;

-- ---------------------------------------------------------------------
-- C) ESCRITA DIRETA NAS TABELAS
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
              and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') loop
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated', r.relname);
  end loop;
end $$;
-- única escrita direta do app: criar a própria carreira (RLS exige user_id = auth.uid(); só as colunas do formulário)
grant insert (user_id, nickname, photo_id, country, age) on public.careers to authenticated;
alter default privileges in schema public revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;

-- ---------------------------------------------------------------------
-- D) LIMITES DE REQUISIÇÃO
-- ---------------------------------------------------------------------
create table if not exists public.rate_limit_rules (
  action         text primary key,
  max_hits       int not null check (max_hits > 0),
  window_seconds int not null check (window_seconds between 1 and 86400),
  label          text not null
);
insert into public.rate_limit_rules (action, max_hits, window_seconds, label) values
  ('economy',      120,  60,   'compras, giros e negociações'),
  ('avatar',        20,  3600, 'trocas de foto'),
  ('market_list',   30,  3600, 'anúncios no mercado'),
  ('prediction',    60,  3600, 'palpites'),
  ('admin_events', 120,  3600, 'alterações de eventos')
on conflict (action) do nothing;

create table if not exists public.rate_limit_hits (
  user_id      uuid not null,
  action       text not null references public.rate_limit_rules (action) on delete cascade,
  window_start timestamptz not null,
  hits         int not null default 0,
  primary key (user_id, action, window_start)
);
alter table public.rate_limit_rules enable row level security;
alter table public.rate_limit_hits enable row level security;
revoke all on public.rate_limit_rules, public.rate_limit_hits from anon, authenticated;

-- conta uma ação do usuário logado; acima do limite recusa com código P0429. Chamadas internas (sem usuário: tarefas
-- agendadas, service_role) não são limitadas.
create or replace function public.rl_hit(p_action text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_rule public.rate_limit_rules; v_start timestamptz; v_hits int; v_wait int;
begin
  if v_uid is null then return; end if;
  select * into v_rule from public.rate_limit_rules where action = p_action;
  if not found then return; end if;
  v_start := to_timestamp(floor(extract(epoch from now()) / v_rule.window_seconds) * v_rule.window_seconds);
  insert into public.rate_limit_hits (user_id, action, window_start, hits) values (v_uid, p_action, v_start, 1)
  on conflict (user_id, action, window_start) do update set hits = public.rate_limit_hits.hits + 1
  returning hits into v_hits;
  if v_hits = 1 then   -- janela nova: limpa as antigas deste usuário/ação
    delete from public.rate_limit_hits where user_id = v_uid and action = p_action and window_start < v_start;
  end if;
  if v_hits > v_rule.max_hits then
    v_wait := ceil(extract(epoch from (v_start + make_interval(secs => v_rule.window_seconds) - now())))::int;
    raise exception using errcode = 'P0429',
      message = format('Muitas %s em pouco tempo. Tente de novo em %s.', v_rule.label,
                       case when v_wait >= 120 then (v_wait / 60) || ' minutos' else greatest(v_wait, 1) || ' segundos' end);
  end if;
end;
$$;

create or replace function public.rl_trg()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_argv[0] = 'avatar' then   -- (if aninhado: o plpgsql não garante curto-circuito no AND)
    if new.avatar_data is not distinct from old.avatar_data then return new; end if;
  end if;
  perform public.rl_hit(tg_argv[0]);
  return new;
end;
$$;
drop trigger if exists rl_economy on public.econ_requests;
create trigger rl_economy before insert on public.econ_requests for each row execute function public.rl_trg('economy');
drop trigger if exists rl_avatar on public.player_profiles;
create trigger rl_avatar before update of avatar_data on public.player_profiles for each row execute function public.rl_trg('avatar');
drop trigger if exists rl_market_list on public.market_listings;
create trigger rl_market_list before insert on public.market_listings for each row execute function public.rl_trg('market_list');
drop trigger if exists rl_admin_events on public.events;
create trigger rl_admin_events before insert or update on public.events for each row execute function public.rl_trg('admin_events');
do $$
begin
  if to_regclass('public.tickets') is not null then
    execute 'drop trigger if exists rl_prediction on public.tickets';
    execute 'create trigger rl_prediction before insert on public.tickets for each row execute function public.rl_trg(''prediction'')';
  end if;
end $$;
revoke all on function public.rl_hit(text), public.rl_trg() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- E) EXTRATO COM ORIGEM LEGÍVEL (rótulo do motivo + contraparte do mercado)
-- ---------------------------------------------------------------------
create or replace function public.wallet_history(p_limit int default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_car uuid;
begin
  select id into v_car from public.careers where user_id = auth.uid() and status = 'active';
  if v_car is null then raise exception 'Carreira ativa não encontrada'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', l.id, 'currency', l.currency, 'delta', l.delta, 'balance', l.balance_after,
                                        'reason', l.reason, 'ref', l.ref, 'at', l.created_at,
                                        'detail', x.detail) order by l.id desc)
      from (select * from public.wallet_ledger where career_id = v_car order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) l
      left join lateral (
        select case
          -- mercado: carta e a outra parte (apelido público), nunca ids internos
          when l.reason in ('market_sale', 'market_buy') then (
            select jsonb_build_object('card', c.name,
                     'other', (select nickname from public.careers where id = case when l.reason = 'market_sale' then ml.buyer_career else ml.seller_career end))
              from public.market_listings ml join public.cards c on c.id = ml.card_id
             where ml.id::text = l.ref)
          when l.reason = 'shop_card' then (select jsonb_build_object('card', c.name) from public.shop_purchases sp join public.cards c on c.id = sp.card_id where sp.id::text = l.ref)
          when l.reason = 'event_reward' then (select jsonb_build_object('event', e.name) from public.event_completions ec join public.events e on e.id = ec.event_id where ec.id::text = l.ref)
        end as detail) x on true
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.wallet_history(int) from public, anon;
grant execute on function public.wallet_history(int) to authenticated;
