-- =====================================================================
-- EVENTOS TURBINADOS (2026-11-09)
--
-- 1) Sequência diária: moedas em escada (1k → 7k) e diamantes de verdade no Dia 5 (120) e no Dia 7 (410).
--    O painel mostrava as moedas do dia ao lado do ícone de diamante; a correção visual está no StreakPanel.
-- 2) Eventos diários com recompensas na casa dos milhares e dois diários novos (Muralha, Rotina de campeão,
--    Palpite do dia).
-- 3) Eventos semanais que duram a semana toda (segunda a domingo, horário de Brasília), em degraus para quem
--    joga pouco (Bronze) e para quem joga muito (Prata, Ouro), mais desafios de gols, defesa, gigantes e palpites.
-- 4) Evento especial "Maratona de Novembro" (09/11 a 16/11).
-- 5) Tela de novidades dos eventos: aparece uma vez por carreira (release_news).
--
-- Não toca em progresso de jogadores: event_progress, event_completions, player_streaks e saldos ficam como estão.
-- Recompensas ainda não resgatadas passam a pagar os valores novos (event_claim lê event_rewards na hora).
-- Idempotente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) SEQUÊNCIA DIÁRIA
-- ---------------------------------------------------------------------
insert into public.streak_rewards (day, coins, diamonds, energy) values
  (1, 1000,   0, 0),
  (2, 2000,   0, 0),
  (3, 3000,   0, 1),
  (4, 4000,   0, 0),
  (5, 5000, 120, 0),
  (6, 6000,   0, 1),
  (7, 7000, 410, 2)
on conflict (day) do update set coins = excluded.coins, diamonds = excluded.diamonds, energy = excluded.energy, box_tier = null;

-- ---------------------------------------------------------------------
-- 2-4) EVENTOS (upsert por slug; objetivos/recompensas regravados só onde mudam)
-- ---------------------------------------------------------------------
create or replace function pg_temp.ev_upsert(p_slug text, p_name text, p_desc text, p_cat text, p_icon text, p_css text,
                                             p_start timestamptz, p_end timestamptz, p_rec text, p_order int, p_grace int,
                                             p_maxc int, p_objs jsonb, p_rewards jsonb, p_replace_objs boolean)
returns void language plpgsql as $$
declare v_id uuid; o jsonb; w jsonb; i int;
begin
  insert into public.events (slug, name, description, category, banner, starts_at, ends_at, timezone, recurrence,
                             min_level, max_completions, claim_grace_hours, status, sort_order)
  values (p_slug, p_name, p_desc, p_cat, jsonb_build_object('css', p_css, 'icon', p_icon), p_start, p_end,
          'America/Sao_Paulo', p_rec, 1, p_maxc, p_grace, 'published', p_order)
  on conflict (slug) do update set name = excluded.name, description = excluded.description, banner = excluded.banner,
    sort_order = excluded.sort_order, claim_grace_hours = excluded.claim_grace_hours, status = 'published', updated_at = now()
  returning id into v_id;

  -- objetivos: só são criados quando o evento não tem nenhum (eventos que já rodam mantêm ids e progresso)
  if p_replace_objs or not exists (select 1 from public.event_objectives where event_id = v_id) then
    if exists (select 1 from public.event_progress where event_id = v_id) then
      raise exception 'Evento % já tem progresso: objetivos não podem ser trocados.', p_slug;
    end if;
    delete from public.event_objectives where event_id = v_id;
    i := 0;
    for o in select * from jsonb_array_elements(p_objs) loop
      i := i + 1;
      insert into public.event_objectives (event_id, kind, target, params, label, sort_order)
      values (v_id, o ->> 'kind', (o ->> 'target')::int, coalesce(o -> 'params', '{}'::jsonb), o ->> 'label', i);
    end loop;
  end if;

  delete from public.event_rewards where event_id = v_id;
  i := 0;
  for w in select * from jsonb_array_elements(p_rewards) loop
    i := i + 1;
    insert into public.event_rewards (event_id, kind, amount, ref, sort_order)
    values (v_id, w ->> 'kind', (w ->> 'amount')::int, w ->> 'ref', i);
  end loop;
end;
$$;

do $$
declare
  t0 timestamptz := '2026-11-09 03:00:00+00';   -- 09/11/2026 00:00 em Brasília
  t1 timestamptz := '2027-12-31 03:00:00+00';
begin
  -- ---------------- DIÁRIOS ----------------
  perform pg_temp.ev_upsert('diario-entre-em-campo', 'Entre em campo',
    'Jogue uma partida em Temporadas hoje e garanta moedas para o seu clube.',
    'daily', 'activity', 'linear-gradient(135deg,#0b4a2a,#1f9d55)', t0, t1, 'daily', 1, 24, null,
    '[{"kind":"match_played","target":1,"label":"Jogue 1 partida"}]',
    '[{"kind":"coins","amount":1000}]', false);

  perform pg_temp.ev_upsert('diario-vitoria', 'Vitória do dia',
    'Vença uma partida hoje. A vitória paga moedas e energia bônus.',
    'daily', 'trophy', 'linear-gradient(135deg,#6b4a06,#e0a82e)', t0, t1, 'daily', 2, 24, null,
    '[{"kind":"match_won","target":1,"label":"Vença 1 partida"}]',
    '[{"kind":"coins","amount":2000},{"kind":"energy","amount":1}]', false);

  perform pg_temp.ev_upsert('diario-ataque', 'Ataque afiado',
    'Marque 3 gols hoje, somando todas as suas partidas.',
    'daily', 'flame', 'linear-gradient(135deg,#4d0a12,#d6283a)', t0, t1, 'daily', 3, 24, null,
    '[{"kind":"goals_scored","target":3,"label":"Marque 3 gols"}]',
    '[{"kind":"coins","amount":1500}]', false);

  perform pg_temp.ev_upsert('diario-muralha', 'Muralha do dia',
    'Termine uma partida sem sofrer gol hoje.',
    'daily', 'star', 'linear-gradient(135deg,#0b2b4a,#1f7fd1)', t0, t1, 'daily', 4, 24, null,
    '[{"kind":"clean_sheet","target":1,"label":"1 jogo sem sofrer gol"}]',
    '[{"kind":"coins","amount":1500}]', false);

  perform pg_temp.ev_upsert('diario-rotina-campeao', 'Rotina de campeão',
    'O desafio diário mais difícil: jogue 5 partidas e vença 3 no mesmo dia.',
    'daily', 'crown', 'linear-gradient(135deg,#3b1d00,#f59e0b)', t0, t1, 'daily', 5, 24, null,
    '[{"kind":"match_played","target":5,"label":"Jogue 5 partidas"},{"kind":"match_won","target":3,"label":"Vença 3 partidas"}]',
    '[{"kind":"coins","amount":4000},{"kind":"diamonds","amount":2},{"kind":"energy","amount":2}]', false);

  perform pg_temp.ev_upsert('diario-palpite', 'Palpite do dia',
    'Faça um palpite hoje na tela de Palpites.',
    'daily', 'sparkles', 'linear-gradient(135deg,#1e1b4b,#6366f1)', t0, t1, 'daily', 6, 24, null,
    '[{"kind":"prediction_placed","target":1,"label":"Faça 1 palpite"}]',
    '[{"kind":"coins","amount":1000}]', false);

  -- ---------------- SEMANAIS (segunda a domingo) ----------------
  perform pg_temp.ev_upsert('semanal-vencedora', 'Semana vencedora · Bronze',
    'Primeiro degrau da semana: vença 5 e jogue 10 partidas até domingo. Depois tente a Prata e o Ouro.',
    'weekly', 'star', 'linear-gradient(135deg,#3a2210,#b87333)', t0, t1, 'weekly', 10, 48, null,
    '[{"kind":"match_won","target":5,"label":"Vença 5 partidas"},{"kind":"match_played","target":10,"label":"Jogue 10 partidas"}]',
    '[{"kind":"coins","amount":5000},{"kind":"diamonds","amount":10},{"kind":"energy","amount":2}]', false);

  perform pg_temp.ev_upsert('semanal-prata', 'Semana vencedora · Prata',
    'Segundo degrau: vença 20 e jogue 30 partidas até domingo.',
    'weekly', 'trophy', 'linear-gradient(135deg,#1f2937,#94a3b8)', t0, t1, 'weekly', 11, 48, null,
    '[{"kind":"match_won","target":20,"label":"Vença 20 partidas"},{"kind":"match_played","target":30,"label":"Jogue 30 partidas"}]',
    '[{"kind":"coins","amount":15000},{"kind":"diamonds","amount":25},{"kind":"energy","amount":5}]', false);

  perform pg_temp.ev_upsert('semanal-ouro', 'Semana vencedora · Ouro',
    'O topo da semana: vença 50 partidas e marque 120 gols até domingo.',
    'weekly', 'crown', 'linear-gradient(135deg,#4a3500,#facc15)', t0, t1, 'weekly', 12, 48, null,
    '[{"kind":"match_won","target":50,"label":"Vença 50 partidas"},{"kind":"goals_scored","target":120,"label":"Marque 120 gols"}]',
    '[{"kind":"coins","amount":40000},{"kind":"diamonds","amount":60},{"kind":"energy","amount":10}]', false);

  perform pg_temp.ev_upsert('semanal-artilharia', 'Artilharia da semana',
    'Some 60 gols do seu time até domingo.',
    'weekly', 'flame', 'linear-gradient(135deg,#4d0a12,#f43f5e)', t0, t1, 'weekly', 13, 48, null,
    '[{"kind":"goals_scored","target":60,"label":"Marque 60 gols"}]',
    '[{"kind":"coins","amount":10000},{"kind":"diamonds","amount":10}]', false);

  perform pg_temp.ev_upsert('semanal-muralha', 'Defesa de aço',
    'Termine 15 partidas sem sofrer gol até domingo.',
    'weekly', 'layers', 'linear-gradient(135deg,#0b2b4a,#38bdf8)', t0, t1, 'weekly', 14, 48, null,
    '[{"kind":"clean_sheet","target":15,"label":"15 jogos sem sofrer gol"}]',
    '[{"kind":"coins","amount":10000},{"kind":"diamonds","amount":10}]', false);

  perform pg_temp.ev_upsert('semanal-caca-gigantes', 'Caça-gigantes',
    'Vença 5 partidas contra gigantes (força 80 ou mais) até domingo.',
    'weekly', 'crown', 'linear-gradient(135deg,#1b1f27,#d97706)', t0, t1, 'weekly', 15, 48, null,
    '[{"kind":"match_won","target":5,"params":{"min_opponent_strength":80},"label":"Vença 5 gigantes (força 80+)"}]',
    '[{"kind":"coins","amount":20000},{"kind":"diamonds","amount":30},{"kind":"energy","amount":3}]', false);

  perform pg_temp.ev_upsert('semanal-palpiteiro', 'Palpiteiro da semana',
    'Faça 10 palpites até domingo.',
    'weekly', 'sparkles', 'linear-gradient(135deg,#1e1b4b,#8b5cf6)', t0, t1, 'weekly', 16, 48, null,
    '[{"kind":"prediction_placed","target":10,"label":"Faça 10 palpites"}]',
    '[{"kind":"coins","amount":6000},{"kind":"diamonds","amount":5}]', false);

  -- ---------------- ESPECIAL DA SEMANA ----------------
  perform pg_temp.ev_upsert('maratona-novembro-2026', 'Maratona de Novembro',
    'Evento especial de estreia dos novos eventos. Até domingo: jogue 40 partidas, vença 25 e marque 70 gols. Prêmio único com o emblema Coroa.',
    'themed', 'calendar', 'linear-gradient(135deg,#2a0a3d,#c026d3)', t0, '2026-11-16 03:00:00+00', 'none', 20, 72, 1,
    '[{"kind":"match_played","target":40,"label":"Jogue 40 partidas"},{"kind":"match_won","target":25,"label":"Vença 25 partidas"},{"kind":"goals_scored","target":70,"label":"Marque 70 gols"}]',
    '[{"kind":"coins","amount":50000},{"kind":"diamonds","amount":100},{"kind":"energy","amount":15},{"kind":"cosmetic","amount":1,"ref":"emb_coroa"}]', false);
end $$;

-- ---------------------------------------------------------------------
-- 5) TELA DE NOVIDADES (uma vez por carreira e por versão de novidades)
-- ---------------------------------------------------------------------
create table if not exists public.release_news (
  release_id text not null,
  career_id  uuid not null references public.careers (id) on delete cascade,
  seen_at    timestamptz not null default now(),
  primary key (release_id, career_id)
);
alter table public.release_news enable row level security;
revoke all on public.release_news from anon, authenticated;

create or replace function public.release_news_status(p_release text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from public.careers where user_id = auth.uid() and status = 'active';
  if v_id is null then return jsonb_build_object('show', false); end if;
  return jsonb_build_object('release', p_release,
    'show', not exists (select 1 from public.release_news where release_id = p_release and career_id = v_id));
end;
$$;

create or replace function public.release_news_seen(p_release text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_release is null or length(p_release) > 60 then raise exception 'Versão inválida.'; end if;
  select id into v_id from public.careers where user_id = auth.uid() and status = 'active';
  if v_id is null then return jsonb_build_object('ok', false); end if;
  insert into public.release_news (release_id, career_id) values (p_release, v_id) on conflict do nothing;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.release_news_status(text) from public, anon;
revoke all on function public.release_news_seen(text) from public, anon;
grant execute on function public.release_news_status(text) to authenticated;
grant execute on function public.release_news_seen(text) to authenticated;
