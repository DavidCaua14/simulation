-- =====================================================================
-- CORREÇÃO DO MÓDULO DE PALPITES — rode inteiro no Supabase -> SQL Editor
-- 1) tabela sync_state (controle de frequência + diagnóstico da sincronização)
-- 2) place_ticket com ODDS FIXAS (casa 1.5 | empate 2.0 | fora 1.5)
-- 3) settle_tickets (mesma regra, mas sem erro de arredondamento e sem pagar 2x)
-- 4) start_due_matches (o BANCO marca "live" no horário do apito)
-- Não apaga dados. Bilhetes antigos mantêm a odd que já tinham.
-- =====================================================================

-- 1) controle/diagnóstico ----------------------------------------------
create table if not exists public.sync_state (
  key         text primary key,
  last_run_at timestamptz not null default now(),
  last_status text,
  detail      jsonb
);
alter table public.sync_state enable row level security;   -- sem policy: só service role

-- 2) place_ticket: ODDS FIXAS ------------------------------------------
-- Para mudar as odds, altere SÓ as constantes abaixo (e FIXED_ODDS em
-- src/features/predictions/data/predictionRules.js, que é apenas o que aparece na tela).
create or replace function public.place_ticket(p_stake int, p_picks jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  c_odd_home     constant numeric := 1.5;
  c_odd_away     constant numeric := 1.5;
  c_odd_draw     constant numeric := 2.0;
  c_odd_btts_yes constant numeric := 1.85;
  c_odd_btts_no  constant numeric := 1.95;
  c_max_mult     constant numeric := 100;

  v_career public.careers%rowtype;
  v_ticket_id uuid;
  v_match public.matches%rowtype;
  v_pick jsonb;
  v_result text;
  v_btts boolean;
  v_pm numeric;
  v_total numeric := 1;
  v_n int;
begin
  select * into v_career from public.careers
   where user_id = auth.uid() and status = 'active' for update;
  if not found then raise exception 'Carreira ativa não encontrada'; end if;

  v_n := coalesce(jsonb_array_length(p_picks), 0);
  if v_n < 1 or v_n > 10 then raise exception 'Escolha de 1 a 10 jogos no bilhete'; end if;
  if p_stake < 10 or p_stake > 1000 then raise exception 'Valor deve ficar entre 10 e 1000 moedas'; end if;
  if v_career.coins < p_stake then raise exception 'Moedas insuficientes'; end if;

  insert into public.tickets (career_id, stake) values (v_career.id, p_stake)
  returning id into v_ticket_id;

  for v_pick in select * from jsonb_array_elements(p_picks) loop
    select * into v_match from public.matches where id = (v_pick->>'match_id')::bigint;
    if not found or v_match.status <> 'scheduled' or v_match.kickoff_at <= now() then
      raise exception 'Um dos jogos não aceita mais palpites';
    end if;

    v_result := nullif(v_pick->>'result', '');
    v_btts := case when v_pick ? 'btts' and jsonb_typeof(v_pick->'btts') = 'boolean'
                   then (v_pick->>'btts')::boolean else null end;
    if v_result is not null and v_result not in ('home', 'draw', 'away') then
      raise exception 'Palpite de resultado inválido';
    end if;

    v_pm := 1;
    if v_result = 'home' then v_pm := v_pm * c_odd_home; end if;
    if v_result = 'away' then v_pm := v_pm * c_odd_away; end if;
    if v_result = 'draw' then v_pm := v_pm * c_odd_draw; end if;
    if v_btts is true  then v_pm := v_pm * c_odd_btts_yes; end if;
    if v_btts is false then v_pm := v_pm * c_odd_btts_no;  end if;
    if v_pm = 1 then raise exception 'Palpite vazio'; end if;
    v_pm := round(v_pm, 2);

    insert into public.ticket_picks (ticket_id, match_id, pick_result, pick_btts, multiplier)
    values (v_ticket_id, v_match.id, v_result, v_btts, v_pm);   -- unique impede jogo repetido

    v_total := v_total * v_pm;
  end loop;

  v_total := least(round(v_total, 2), c_max_mult);
  update public.tickets
     set multiplier = v_total, potential_coins = floor(p_stake * v_total)
   where id = v_ticket_id;

  update public.careers set coins = coins - p_stake where id = v_career.id;
  return v_ticket_id;
end;
$$;
revoke all on function public.place_ticket(int, jsonb) from public, anon;
grant execute on function public.place_ticket(int, jsonb) to authenticated;

-- 3) settle_tickets -----------------------------------------------------
create or replace function public.settle_tickets()
returns int
language plpgsql security definer set search_path = public as $$
declare
  t record;
  v_count int := 0;
  v_coins int; v_xp int; v_energy int; v_points int;
begin
  -- impede duas liquidações simultâneas (evita pagar o mesmo bilhete 2x)
  perform pg_advisory_xact_lock(hashtext('settle_tickets'));

  -- a) resolve cada palpite cujo jogo terminou (ou foi anulado)
  update ticket_picks p set status = case
    when m.status = 'void' then 'void'
    when (p.pick_result is null or p.pick_result =
            case when m.home_score > m.away_score then 'home'
                 when m.home_score < m.away_score then 'away' else 'draw' end)
     and (p.pick_btts is null or p.pick_btts = (m.home_score > 0 and m.away_score > 0))
    then 'won' else 'lost' end
  from matches m
  where m.id = p.match_id and p.status = 'pending'
    and ((m.status = 'finished' and m.home_score is not null and m.away_score is not null)
         or m.status = 'void');

  -- b) bilhetes decididos: algum palpite perdido (perde na hora) ou todos resolvidos
  for t in
    select tk.id, tk.career_id, tk.stake,
           bool_or(p.status = 'lost') as any_lost,
           count(*) filter (where p.status = 'won') as n_won,
           coalesce(round(exp(sum(ln(p.multiplier)) filter (where p.status = 'won'))::numeric, 2), 1) as mult
    from tickets tk join ticket_picks p on p.ticket_id = tk.id
    where tk.status = 'pending'
    group by tk.id
    having bool_or(p.status = 'lost') or bool_and(p.status <> 'pending')
  loop
    if t.any_lost then
      update tickets set status = 'lost', settled_at = now() where id = t.id;
      insert into prediction_stats (career_id, tickets_lost) values (t.career_id, 1)
        on conflict (career_id) do update
        set tickets_lost = prediction_stats.tickets_lost + 1, updated_at = now();

    elsif t.n_won = 0 then   -- todos anulados: devolve as moedas
      update tickets set status = 'void', settled_at = now() where id = t.id;
      update careers set coins = coins + t.stake where id = t.career_id;

    else
      v_coins := floor(t.stake * least(t.mult, 100));
      v_xp := greatest(5, floor(t.stake * 0.2 * t.mult));
      v_energy := 1 + case when t.n_won >= 3 then 1 else 0 end;
      v_points := round(10 * t.mult);

      update tickets set status = 'won', settled_at = now(), reward_coins = v_coins,
             reward_xp = v_xp, reward_energy = v_energy where id = t.id;
      update careers set coins = coins + v_coins, xp = xp + v_xp, energy = energy + v_energy
       where id = t.career_id;
      insert into prediction_stats (career_id, points, tickets_won, best_multiplier)
        values (t.career_id, v_points, 1, t.mult)
        on conflict (career_id) do update
        set points = prediction_stats.points + v_points,
            tickets_won = prediction_stats.tickets_won + 1,
            best_multiplier = greatest(prediction_stats.best_multiplier, t.mult),
            updated_at = now();
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.settle_tickets() from public, anon, authenticated;
grant execute on function public.settle_tickets() to service_role;

-- 4) o banco marca "live" no horário do apito (sem API) ----------------
create or replace function public.start_due_matches()
returns int
language sql security definer set search_path = public as $$
  with u as (
    update matches set status = 'live', updated_at = now()
    where status = 'scheduled' and kickoff_at <= now()
      and kickoff_at >= now() - interval '7 days'
    returning 1
  )
  select count(*)::int from u;
$$;
revoke all on function public.start_due_matches() from public, anon, authenticated;
