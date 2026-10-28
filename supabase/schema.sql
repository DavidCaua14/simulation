-- =====================================================================
-- MÓDULO DE PALPITES ESPORTIVOS (simulação, sem dinheiro real)
-- Rode inteiro em: Supabase → SQL Editor → New query.
-- Todos os valores de balanceamento (multiplicadores, XP, energia) estão
-- nas funções place_ticket e settle_tickets — ajuste lá.
-- =====================================================================

-- 1) Moedas e energia na carreira ------------------------------------
alter table public.careers add column if not exists coins int not null default 1000 check (coins >= 0);
alter table public.careers add column if not exists energy int not null default 10 check (energy >= 0);

-- 2) Competições -----------------------------------------------------
create table if not exists public.competitions (
  id smallint primary key,
  name text not null,
  tier text not null,
  api_league_id int not null unique   -- IDs da API-Football: confira no painel/doc
);
insert into public.competitions (id, name, tier, api_league_id) values
  (1, 'Brasileirão Série A', 'A', 71),
  (2, 'Brasileirão Série B', 'B', 72),
  (3, 'Brasileirão Série C', 'C', 75)
on conflict (id) do nothing;

-- 3) Jogos (alimentados APENAS pela Edge Function, via service role) --
create table if not exists public.matches (
  id bigint generated always as identity primary key,
  api_fixture_id bigint not null unique,
  competition_id smallint not null references public.competitions(id),
  season int not null,
  round text,
  home_team text not null,
  away_team text not null,
  home_logo text,
  away_logo text,
  kickoff_at timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'live', 'finished', 'void')),  -- void = adiado/cancelado/WO
  minute int,
  home_score int,
  away_score int,
  updated_at timestamptz not null default now()
);
create index if not exists matches_kickoff_idx on public.matches (kickoff_at);
create index if not exists matches_status_idx on public.matches (status);

alter table public.competitions enable row level security;
alter table public.matches enable row level security;
create policy "read_competitions" on public.competitions for select to authenticated using (true);
create policy "read_matches" on public.matches for select to authenticated using (true);

-- Placar ao vivo no app via Supabase Realtime
alter publication supabase_realtime add table public.matches;

-- 4) Bilhetes e palpites ---------------------------------------------
create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  career_id uuid not null references public.careers(id) on delete cascade,
  stake int not null check (stake between 10 and 1000),
  multiplier numeric(8,2) not null default 1,
  potential_coins int not null default 0,
  status text not null default 'pending' check (status in ('pending', 'won', 'lost', 'void')),
  reward_coins int not null default 0,
  reward_xp int not null default 0,
  reward_energy int not null default 0,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);
create index if not exists tickets_career_idx on public.tickets (career_id, created_at desc);
create index if not exists tickets_pending_idx on public.tickets (status) where status = 'pending';

create table if not exists public.ticket_picks (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.tickets(id) on delete cascade,
  match_id bigint not null references public.matches(id),
  pick_result text check (pick_result in ('home', 'draw', 'away')),
  pick_btts boolean,                       -- true = ambas marcam, false = não
  multiplier numeric(6,2) not null,
  status text not null default 'pending' check (status in ('pending', 'won', 'lost', 'void')),
  unique (ticket_id, match_id),
  check (pick_result is not null or pick_btts is not null)
);
create index if not exists ticket_picks_match_idx on public.ticket_picks (match_id);

alter table public.tickets enable row level security;
alter table public.ticket_picks enable row level security;

-- Usuário só LÊ os próprios bilhetes. Ninguém insere/edita direto: só via RPC.
create policy "select_own_tickets" on public.tickets for select to authenticated
  using (exists (select 1 from public.careers c where c.id = tickets.career_id and c.user_id = auth.uid()));
create policy "select_own_picks" on public.ticket_picks for select to authenticated
  using (exists (
    select 1 from public.tickets t join public.careers c on c.id = t.career_id
    where t.id = ticket_picks.ticket_id and c.user_id = auth.uid()));

-- 5) Estatísticas / rank ----------------------------------------------
create table if not exists public.prediction_stats (
  career_id uuid primary key references public.careers(id) on delete cascade,
  points int not null default 0,
  tickets_won int not null default 0,
  tickets_lost int not null default 0,
  best_multiplier numeric(8,2) not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.prediction_stats enable row level security;
create policy "select_own_stats" on public.prediction_stats for select to authenticated
  using (exists (select 1 from public.careers c where c.id = prediction_stats.career_id and c.user_id = auth.uid()));

-- Ranking público (só quem tem pontos > 0), sem expor dados sensíveis
create or replace function public.get_prediction_leaderboard(p_limit int default 50)
returns table ("position" bigint, career_id uuid, nickname text, photo_id text, level int,
               points int, tickets_won int)
language sql security definer set search_path = public as $$
  select row_number() over (order by s.points desc, s.tickets_won desc, c.nickname),
         c.id, c.nickname, c.photo_id, c.level, s.points, s.tickets_won
  from prediction_stats s
  join careers c on c.id = s.career_id
  where s.points > 0
  order by 1
  limit least(greatest(p_limit, 1), 100);
$$;
grant execute on function public.get_prediction_leaderboard(int) to authenticated;

-- 6) Criar bilhete (toda validação no servidor) -----------------------
-- p_picks: [{"match_id": 123, "result": "home"|"draw"|"away"|null, "btts": true|false|null}, ...]
create or replace function public.place_ticket(p_stake int, p_picks jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
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
    if v_result in ('home', 'away') then v_pm := v_pm * 1.8; end if;
    if v_result = 'draw' then v_pm := v_pm * 2.2; end if;
    if v_btts is not null then v_pm := v_pm * 1.5; end if;
    if v_pm = 1 then raise exception 'Palpite vazio'; end if;

    insert into public.ticket_picks (ticket_id, match_id, pick_result, pick_btts, multiplier)
    values (v_ticket_id, v_match.id, v_result, v_btts, v_pm);   -- unique impede jogo repetido

    v_total := v_total * v_pm;
  end loop;

  v_total := least(round(v_total, 2), 100);   -- teto do multiplicador
  update public.tickets
     set multiplier = v_total, potential_coins = floor(p_stake * v_total)
   where id = v_ticket_id;

  update public.careers set coins = coins - p_stake where id = v_career.id;
  return v_ticket_id;
end;
$$;
revoke all on function public.place_ticket(int, jsonb) from public, anon;
grant execute on function public.place_ticket(int, jsonb) to authenticated;

-- 7) Liquidar bilhetes (chamada pela Edge Function / cron, nunca pelo app)
create or replace function public.settle_tickets()
returns int
language plpgsql security definer set search_path = public as $$
declare
  t record;
  v_count int := 0;
  v_coins int; v_xp int; v_energy int; v_points int;
begin
  -- a) resolve cada palpite cujo jogo terminou (ou foi anulado)
  update ticket_picks p set status = case
    when m.status = 'void' then 'void'
    when (p.pick_result is null or p.pick_result =
            case when m.home_score > m.away_score then 'home'
                 when m.home_score < m.away_score then 'away' else 'draw' end)
     and (p.pick_btts is null or p.pick_btts = (m.home_score > 0 and m.away_score > 0))
    then 'won' else 'lost' end
  from matches m
  where m.id = p.match_id and p.status = 'pending' and m.status in ('finished', 'void');

  -- b) bilhetes decididos: algum palpite perdido (perde na hora) ou todos resolvidos
  for t in
    select tk.id, tk.career_id, tk.stake,
           bool_or(p.status = 'lost') as any_lost,
           count(*) filter (where p.status = 'won') as n_won,
           coalesce(exp(sum(ln(p.multiplier)) filter (where p.status = 'won')), 1) as mult
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
      v_points := round(10 * t.mult);          -- pontos independem do valor apostado

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

-- 8) SEGURANÇA (ativo) -------------------------------------------------
-- As policies da tabela careers deixam o usuário gravar QUALQUER coluna da
-- própria carreira, inclusive coins, energy, xp e level, direto do navegador.
-- Aqui limitamos às colunas que o app realmente grava hoje:
--   playerService.createPlayer -> insert(user_id, nickname, photo_id, country, age)
--   clubService.chooseClub     -> update(club_id)
-- Se um dia o app precisar gravar outra coluna do client (ex.: position),
-- adicione-a nos grants abaixo.
revoke insert, update on public.careers from authenticated;
grant insert (user_id, nickname, photo_id, country, age) on public.careers to authenticated;
grant update (club_id) on public.careers to authenticated;
