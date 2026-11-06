-- Proteção do ranking geral (2026-11-06)
-- 1. Palpites: as odds são fixas (1,5 / 2,0 / 1,85 / 1,95), então apostas cobertas no mesmo jogo ou no favorito
--    rendiam XP sem limite, e XP vira nível e pontos no ranking. Agora o XP dos palpites tem teto diário por carreira.
-- 2. Pedir demissão quando a diretoria ou a torcida já deram o ultimato conta como demissão no ranking
--    (antes, sair um jogo antes de ser demitido evitava os −150 pontos).

create table if not exists public.prediction_xp_days(
 career_id uuid not null references public.careers(id) on delete cascade,
 day date not null,
 xp int not null default 0,
 primary key(career_id, day));
alter table public.prediction_xp_days enable row level security;

create or replace function public.prediction_xp_grant(p_career uuid, p_xp int)
 returns int language plpgsql security definer set search_path to 'public'
as $function$
declare cap constant int := 150; used int; give int;
begin
 insert into public.prediction_xp_days(career_id,day,xp) values(p_career,current_date,0) on conflict do nothing;
 select xp into used from public.prediction_xp_days where career_id=p_career and day=current_date for update;
 give:=greatest(0,least(p_xp,cap-used));
 if give>0 then update public.prediction_xp_days set xp=xp+give where career_id=p_career and day=current_date;end if;
 return give;
end $function$;
revoke all on function public.prediction_xp_grant(uuid,int) from public, anon, authenticated;

-- settle_tickets: igual ao anterior, mas o XP passa pelo teto diário
create or replace function public.settle_tickets()
 returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  t record;
  v_count int := 0;
  v_coins int; v_xp int; v_energy int; v_points int;
begin
  perform pg_advisory_xact_lock(hashtext('settle_tickets'));
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
    elsif t.n_won = 0 then
      update tickets set status = 'void', settled_at = now() where id = t.id;
      update careers set coins = coins + t.stake where id = t.career_id;
    else
      v_coins := floor(t.stake * least(t.mult, 100));
      v_xp := public.prediction_xp_grant(t.career_id, greatest(5, floor(t.stake * 0.2 * t.mult))::int);
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
$function$;

-- Demissão sob ultimato conta como demissão (fired_count) para o ranking
create or replace function public.mgr_resign()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
v_car public.careers;
v_c   public.mgr_coach;
v_s   public.career_seasons;
begin
v_car := public.mgr_lock();
select * into v_c from public.mgr_coach where career_id = v_car.id;
if v_c.status <> 'employed' then raise exception 'Você já está sem clube.'; end if;
if exists (select 1 from public.mgr_matches where career_id = v_car.id and status = 'live' and user_side is not null) then
raise exception 'Termine a partida em andamento primeiro.';
end if;
select * into v_s from public.career_seasons where career_id = v_car.id and mode = 'coach' order by season_no desc limit 1;
perform public.mgr_end_spell(v_car.id, 'resigned');
-- sob ultimato (diretoria no último aviso ou torcida em protesto), sair conta como demissão no ranking
update public.mgr_coach set reputation = greatest(0, reputation - 2), board_confidence = 50, fan_mood = 50,
  fired_count = fired_count + case when v_c.warned >= 2 or v_c.fan_warned >= 1 then 1 else 0 end
 where career_id = v_car.id;
perform public.mgr_msg(v_car.id, v_s.id, v_s.day_no, 'board', 'Você pediu demissão',
format('Você deixou %s. Avance os dias para receber propostas.', public.mgr_club_o(v_c.club_id)), v_c.club_id);
return jsonb_build_object('ok', true);
end;
$function$;
