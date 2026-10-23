-- =====================================================================
-- MODO TEMPORADAS — 4/4: NOVIDADES (rode DEPOIS do 03_engine.sql)
--   1) Cadastro: 2 propostas iniciais aleatórias, entre os clubes mais fracos da Série A
--   2) Calendário único: campeonatos em que seu clube NÃO joga avançam no botão "Próximo" (sem energia)
--   3) Propostas com PRAZO, "esfriamento" do clube que ficou para trás e retorno mais fácil se você trocar de time
-- Pode rodar de novo sem medo.
-- =====================================================================

-- Assinaturas antigas que mudaram (evita funções duplicadas/ambíguas)
drop function if exists public.season_play(text);
drop function if exists public.choose_initial_club(text);
drop function if exists public.sim_make_offer(uuid, uuid, text, int);

alter table public.season_offers add column if not exists expires_at timestamptz;   -- null = sem prazo (propostas iniciais)

-- ---------------------------------------------------------------------
-- A) CARREIRA: recarga de energia (igual) + propostas vencidas saem sozinhas
-- ---------------------------------------------------------------------
create or replace function public.sim_lock_career()
returns public.careers language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_k int;
begin
  select * into v_c from public.careers where user_id = auth.uid() and status = 'active' for update;
  if not found then raise exception 'Carreira ativa não encontrada'; end if;

  if now() >= v_c.energy_reset_at + interval '5 hours' then
    v_k := floor(extract(epoch from (now() - v_c.energy_reset_at)) / 18000)::int;
    update public.careers
       set energy = greatest(energy, 10),
           energy_reset_at = energy_reset_at + (v_k * interval '5 hours')
     where id = v_c.id
    returning * into v_c;
  end if;

  -- proposta que passou do prazo some (e o clube "esfria": ver sim_club_weight)
  update public.season_offers set status = 'expired', responded_at = now()
   where career_id = v_c.id and status = 'pending' and expires_at is not null and expires_at <= now();

  return v_c;
end;
$$;

-- ---------------------------------------------------------------------
-- B) CALENDÁRIO: qual é o próximo "dia" da temporada?
-- Escolhe o campeonato mais atrasado (menos rodadas concluídas / rodadas esperadas).
-- Empate: Libertadores, Copa do Brasil, Brasileirão.
--   kind = 'mine' -> seu clube joga nessa rodada (você simula a SUA partida, gasta 1 energia)
--   kind = 'free' -> seu clube não joga (outro campeonato): o botão "Próximo" simula a rodada, sem energia
-- ---------------------------------------------------------------------
create or replace function public.sim_next_event(p_season uuid, p_club text)
returns table (o_comp text, o_kind text, o_stage text, o_round int)
language sql stable set search_path = public as $$
  with x_rounds as (
    select f.competition_id as x_comp, f.stage as x_stage, f.round_no as x_round,
           bool_and(f.status = 'played') as x_done,
           coalesce(bool_or(f.status = 'pending' and (f.home_club = p_club or f.away_club = p_club)), false) as x_mine
      from public.season_fixtures f
     where f.season_id = p_season
     group by f.competition_id, f.stage, f.round_no
  ),
  x_pick as (
    select r.x_comp,
           (count(*) filter (where r.x_done))::numeric
             / (case r.x_comp when 'brasileirao' then 38 when 'copa_brasil' then 7 else 13 end) as x_ratio,
           (case r.x_comp when 'libertadores' then 1 when 'copa_brasil' then 2 else 3 end) as x_prio
      from x_rounds r
     group by r.x_comp
    having bool_or(not r.x_done)
     order by 2, 3
     limit 1
  )
  select p.x_comp, (case when n.x_mine then 'mine' else 'free' end), n.x_stage, n.x_round
    from x_pick p
    join lateral (
      select * from x_rounds rr
       where rr.x_comp = p.x_comp and not rr.x_done
       order by case rr.x_stage when 'league' then 0 when 'group' then 1 when 'r16' then 2 when 'qf' then 3 when 'sf' then 4 else 5 end,
                rr.x_round
       limit 1
    ) n on true;
$$;

-- "Próximo": simula as rodadas dos campeonatos paralelos (sem energia) até chegar a uma
-- partida do SEU clube (ou ao fim da temporada). Devolve um resumo do que aconteceu.
create or replace function public.season_advance()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_s     public.career_seasons;
  v_ev    record;
  v_i     int;
  v_lvl0  int;
  v_rows  jsonb;
  v_sc    public.season_competitions;
  v_out   jsonb := '[]'::jsonb;
  v_done  boolean := false;
begin
  v_c := public.sim_lock_career();
  v_lvl0 := v_c.level;

  select * into v_s from public.career_seasons where career_id = v_c.id and status = 'active';
  if not found then raise exception 'Não há temporada em andamento.'; end if;

  select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
  if not found then raise exception 'Não há partidas pendentes nesta temporada.'; end if;
  if v_ev.o_kind <> 'free' then
    raise exception 'Agora é dia de jogo do seu clube: toque em "Jogar partida".';
  end if;

  for v_i in 1 .. 15 loop                                   -- trava de segurança
    select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
    exit when not found;
    exit when v_ev.o_kind <> 'free';

    perform public.sim_play_round(v_s.id, v_ev.o_comp, v_ev.o_stage, v_ev.o_round);

    select jsonb_agg(jsonb_build_object('home', f.home_club, 'away', f.away_club, 'hg', f.home_goals, 'ag', f.away_goals,
                                        'group', f.group_label) order by f.id)
      into v_rows
      from public.season_fixtures f
     where f.season_id = v_s.id and f.competition_id = v_ev.o_comp and f.stage = v_ev.o_stage and f.round_no = v_ev.o_round;

    perform public.sim_advance(v_s.id, v_ev.o_comp);
    select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_ev.o_comp;

    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round, 'results', coalesce(v_rows, '[]'::jsonb),
      'finished', (v_sc.status = 'finished'),
      'champion', case when v_sc.status = 'finished' then v_sc.champion_club end,
      'player_result', case when v_sc.status = 'finished' then v_sc.player_result end,
      'bonus_xp', case when v_sc.status = 'finished' then v_sc.player_bonus_xp end,
      'bonus_coins', case when v_sc.status = 'finished' then v_sc.player_bonus_coins end));
  end loop;

  if not exists (select 1 from public.season_fixtures where season_id = v_s.id and status = 'pending') then
    perform public.sim_finalize_season(v_s.id);
    v_done := true;
  end if;

  select * into v_c from public.careers where id = v_c.id;
  return jsonb_build_object('rounds', v_out, 'season_finished', v_done,
                            'level_up', v_c.level > v_lvl0, 'new_level', v_c.level);
end;
$$;

-- ---------------------------------------------------------------------
-- C) PROPOSTAS: prazo, "esfriamento" e retorno mais fácil depois de trocar de time
-- ---------------------------------------------------------------------
-- Peso de um clube na hora de sortear quem faz proposta (1 = normal)
--   proposta recusada/vencida e você continua no mesmo time -> 0,25 (bem mais difícil)
--   você trocou de time depois disso                         -> 0,60 (volta a ser possível, mas abaixo do normal)
create or replace function public.sim_club_weight(p_career uuid, p_club text)
returns double precision language plpgsql stable security definer set search_path = public as $$
declare
  v_last  timestamptz;
  v_moved boolean;
begin
  select max(coalesce(o.responded_at, o.created_at)) into v_last
    from public.season_offers o
   where o.career_id = p_career and o.from_club = p_club and o.status in ('expired', 'declined');
  if v_last is null then return 1; end if;

  select exists (select 1 from public.season_offers o
                  where o.career_id = p_career and o.status = 'accepted' and o.responded_at > v_last) into v_moved;
  return case when v_moved then 0.6 else 0.25 end;
end;
$$;

create or replace function public.sim_make_offer(p_career uuid, p_season uuid, p_cur text, p_pop int, p_hours int default 48)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_cur   int;
  v_cand  text;
  v_str   int;
  v_w     double precision;
  v_bonus int;
  v_pitch text;
  v_id    uuid;
  v_exp   timestamptz := now() + make_interval(hours => p_hours);
begin
  select strength into v_cur from public.sim_clubs where id = p_cur;

  -- sorteio PONDERADO: clubes que você recusou/deixou vencer pesam menos
  select s.id, s.strength, s.w into v_cand, v_str, v_w
    from (
      select c.id, c.strength, public.sim_club_weight(p_career, c.id) as w
        from public.sim_clubs c
       where c.tier = 'serie_a' and c.id <> p_cur
         and c.id not in (select o.from_club from public.season_offers o where o.career_id = p_career and o.status = 'pending')
         and c.strength <= v_cur + 4 + p_pop / 40
         and c.strength >= v_cur - 6
    ) s
   order by power(random()::double precision, (1.0 / s.w)::double precision) desc
   limit 1;
  if v_cand is null then return null; end if;
  if random() > v_w then return null; end if;                 -- clube "esfriado": às vezes nem tenta

  v_bonus := (round((300 + p_pop * 4 + v_str * 8) / 50.0) * 50)::int;
  v_pitch := case
    when v_str > v_cur + 3 then 'Projeto ambicioso: querem você como peça-chave para brigar por títulos.'
    when v_str < v_cur - 2 then 'Prometem a camisa de titular absoluto e o clube inteiro jogando em torno de você.'
    else 'Mesmo patamar, mais protagonismo: você seria uma das estrelas do elenco.'
  end;

  insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch, expires_at)
  values (p_career, p_season, v_cand, v_bonus, v_pitch, v_exp) returning id into v_id;

  return jsonb_build_object('id', v_id, 'club_id', v_cand, 'bonus_coins', v_bonus, 'pitch', v_pitch, 'expires_at', v_exp);
end;
$$;

create or replace function public.sim_maybe_offer(p_career uuid, p_season uuid, p_cur text, p_pop int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  select count(*) into v_n from public.season_offers where career_id = p_career and status = 'pending';
  if v_n >= 3 then return null; end if;
  if random() > 0.01 + p_pop * 0.0004 then return null; end if;
  return public.sim_make_offer(p_career, p_season, p_cur, p_pop, 48);   -- prazo de 48h
end;
$$;

-- Aceitar / recusar. Proposta vencida não pode mais ser aceita.
create or replace function public.season_offer_respond(p_offer uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_o public.season_offers;
begin
  v_c := public.sim_lock_career();            -- já marca como vencidas as propostas fora do prazo
  select * into v_o from public.season_offers where id = p_offer and career_id = v_c.id for update;
  if not found then raise exception 'Proposta não encontrada'; end if;
  if v_o.status = 'expired' then raise exception 'Esta proposta expirou.'; end if;
  if v_o.status <> 'pending' then raise exception 'Esta proposta não está mais disponível'; end if;

  if p_accept then
    update public.career_seasons set club_id = v_o.from_club where career_id = v_c.id and status = 'active';
    update public.careers set club_id = v_o.from_club, coins = coins + v_o.bonus_coins where id = v_c.id;
    update public.season_offers set status = 'accepted', responded_at = now() where id = v_o.id;
    update public.season_offers set status = 'expired', responded_at = now()
     where career_id = v_c.id and status = 'pending' and id <> v_o.id;
  else
    update public.season_offers set status = 'declined', responded_at = now() where id = v_o.id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept, 'club_id', v_o.from_club);
end;
$$;

-- Começar a próxima temporada: as propostas pendentes continuam valendo até o prazo
create or replace function public.season_start_next()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c public.careers;
begin
  v_c := public.sim_lock_career();
  if exists (select 1 from public.career_seasons where career_id = v_c.id and status = 'active') then
    raise exception 'Você ainda tem uma temporada em andamento.';
  end if;
  perform public.sim_create_season(v_c.id);
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------
-- D) CADASTRO: 2 propostas iniciais aleatórias, entre os clubes mais fracos da Série A
-- Ficam GRAVADAS no banco: recarregar a página não sorteia de novo.
-- ---------------------------------------------------------------------
create or replace function public.get_initial_offers()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_n constant int := 2;               -- quantas propostas iniciais
  v_pool constant int := 6;            -- sorteia entre os N clubes mais fracos da Série A
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is not null then return '[]'::jsonb; end if;

  if not exists (select 1 from public.season_offers where career_id = v_c.id and season_id is null and status = 'pending') then
    insert into public.season_offers (career_id, season_id, from_club, bonus_coins, pitch)
    select v_c.id, null, p.id,
           (((200 + floor(random() * 300))::int / 50) * 50),
           (array[
             'Querem apostar em você desde o primeiro dia: vaga de titular pedida pelo treinador.',
             'Clube em reconstrução e uma torcida apaixonada. Você pode virar ídolo aqui.',
             'Projeto de longo prazo com espaço para jovens talentos brilharem.',
             'Elenco humilde e muita vontade. É a chance de mostrar serviço no Brasileirão.'
           ])[1 + floor(random() * 4)::int]
      from (
        select w.id from (
          select id, strength from public.sim_clubs where tier = 'serie_a' order by strength asc, random() limit v_pool
        ) w order by random() limit v_n
      ) p;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch)
                     order by o.created_at, o.id)
      from public.season_offers o
     where o.career_id = v_c.id and o.season_id is null and o.status = 'pending'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.choose_initial_club(p_offer uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_c public.careers;
  v_o public.season_offers;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is not null then raise exception 'Você já tem clube.'; end if;

  select * into v_o from public.season_offers
   where id = p_offer and career_id = v_c.id and season_id is null and status = 'pending' for update;
  if not found then raise exception 'Proposta inválida.'; end if;

  update public.careers set club_id = v_o.from_club, coins = coins + v_o.bonus_coins where id = v_c.id;
  update public.season_offers set status = 'accepted', responded_at = now() where id = v_o.id;
  update public.season_offers set status = 'declined', responded_at = now()
   where career_id = v_c.id and season_id is null and status = 'pending' and id <> v_o.id;
end;
$$;

-- ---------------------------------------------------------------------
-- E) Funções reescritas (season_play sem argumento, hub com "próximo evento", fim de temporada)
-- ---------------------------------------------------------------------
create or replace function public.season_play()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_s     public.career_seasons;
  v_cid   text;
  v_ev    record;
  v_comp  public.sim_competitions;
  v_sc    public.season_competitions;
  v_f     public.season_fixtures;
  v_f2    public.season_fixtures;
  v_lvl0  int;
  v_home  boolean;
  v_sh    int;
  v_sa    int;
  v_q     double precision;
  v_gs    double precision;
  v_as    double precision;
  v_fac   double precision;
  v_sco   int[];
  v_hg    int;
  v_ag    int;
  v_my    int;
  v_opp   int;
  v_pg    int := 0;
  v_pa    int := 0;
  v_i     int;
  v_res   text;
  v_rat   numeric;
  v_mult  numeric;
  v_xp    int;
  v_coins int;
  v_pop   int;     -- popularidade TOTAL (para a chance de proposta)
  v_dpop  int;     -- variação de popularidade desta partida
  v_pending int;
  v_cst   text;
  v_offer jsonb;
  v_round jsonb;
  v_comp_done boolean := false;
  v_season_done boolean := false;
begin
  v_c := public.sim_lock_career();
  v_lvl0 := v_c.level;
  if v_c.energy + v_c.bonus_energy < 1 then
    raise exception 'Sem energia. Espere a recarga para simular a próxima partida.';
  end if;

  select * into v_s from public.career_seasons where career_id = v_c.id and status = 'active';
  if not found then raise exception 'Não há temporada em andamento. Inicie a próxima temporada.'; end if;

  -- O calendário decide qual campeonato é o próximo. Só dá para jogar se for dia de jogo do SEU clube.
  select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
  if not found then raise exception 'Não há partidas pendentes nesta temporada.'; end if;
  if v_ev.o_kind <> 'mine' then
    raise exception 'Hoje não é dia de jogo do seu clube. Toque em "Próximo" para avançar os outros campeonatos.';
  end if;
  v_cid := v_ev.o_comp;

  select * into v_comp from public.sim_competitions where id = v_cid;
  if not found then raise exception 'Campeonato inválido'; end if;
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_cid;

  select * into v_f from public.season_fixtures
   where season_id = v_s.id and competition_id = v_cid and status = 'pending'
     and (home_club = v_s.club_id or away_club = v_s.club_id)
   order by round_no, id limit 1;
  if not found then raise exception 'Seu clube não tem partidas pendentes neste campeonato.'; end if;

  -- gasta a energia livre primeiro; a bônus (comprada) só quando a livre acabar
  if v_c.energy >= 1 then
    update public.careers set energy = energy - 1 where id = v_c.id;
  else
    update public.careers set bonus_energy = bonus_energy - 1 where id = v_c.id;
  end if;

  -- ---- a partida ----------------------------------------------------
  v_home := (v_f.home_club = v_s.club_id);
  select strength into v_sh from public.sim_clubs where id = v_f.home_club;
  select strength into v_sa from public.sim_clubs where id = v_f.away_club;

  -- qualidade do jogador: sobe com o nível (nível 1 = 0.28 ... nível 24+ = 0.95)
  v_q := least(0.95, 0.25 + 0.03 * v_c.level);

  v_sco := public.sim_score(v_sh, v_sa, v_f.stage = 'final',
             case when v_home then 1 + 0.18 * v_q else 1 - 0.06 * v_q end,
             case when v_home then 1 - 0.06 * v_q else 1 + 0.18 * v_q end);
  v_hg := v_sco[1];  v_ag := v_sco[2];
  v_my  := case when v_home then v_hg else v_ag end;
  v_opp := case when v_home then v_ag else v_hg end;
  v_res := case when v_my > v_opp then 'win' when v_my = v_opp then 'draw' else 'loss' end;

  -- chance de o gol / a assistência do SEU time ter sido seu: depende da POSIÇÃO e do NÍVEL
  v_gs := case v_c.position when 'ATA' then 0.36 when 'PE' then 0.26 when 'PD' then 0.26 when 'MEI' then 0.24
            when 'MC' then 0.12 when 'VOL' then 0.05 when 'LD' then 0.05 when 'LE' then 0.05
            when 'ZAG' then 0.06 when 'GOL' then 0.002 else 0.12 end;
  v_as := case v_c.position when 'ATA' then 0.15 when 'PE' then 0.25 when 'PD' then 0.25 when 'MEI' then 0.32
            when 'MC' then 0.28 when 'VOL' then 0.12 when 'LD' then 0.22 when 'LE' then 0.22
            when 'ZAG' then 0.04 when 'GOL' then 0.02 else 0.12 end;
  v_fac := 0.35 + 0.65 * v_q;
  for v_i in 1 .. v_my loop
    if random() < v_gs * v_fac then v_pg := v_pg + 1;
    elsif random() < v_as * v_fac then v_pa := v_pa + 1;
    end if;
  end loop;

  -- nota da partida (3.0 a 10.0)
  v_rat := 5.8 + 1.0 * (v_q - 0.5)
         + case v_res when 'win' then 0.6 when 'draw' then 0.1 else -0.4 end
         + v_pg * 1.1 + v_pa * 0.6
         + case when v_opp = 0 and v_c.position in ('GOL', 'ZAG', 'LD', 'LE', 'VOL') then 0.7 else 0 end
         + (random() - 0.5) * 1.2;
  v_rat := round(greatest(3.0, least(10.0, v_rat))::numeric, 1);

  update public.season_fixtures
     set home_goals = v_hg, away_goals = v_ag, status = 'played', player_match = true,
         player_goals = v_pg, player_assists = v_pa, player_rating = v_rat, played_at = now()
   where id = v_f.id;
  update public.season_competitions set status = 'active'
   where season_id = v_s.id and competition_id = v_cid and status = 'pending';

  -- ---- prêmios, estatísticas e popularidade -------------------------
  v_mult := v_comp.xp_mult * (case v_f.stage when 'final' then 1.5 when 'r16' then 1.2 when 'qf' then 1.2 when 'sf' then 1.2 else 1 end);
  v_xp    := round((case v_res when 'win' then 30 when 'draw' then 15 else 8 end  + v_pg * 10 + v_pa * 6)  * v_mult)::int;
  v_coins := round((case v_res when 'win' then 60 when 'draw' then 25 else 10 end + v_pg * 30 + v_pa * 15) * v_mult)::int;
  v_dpop  := (case v_res when 'win' then 8 when 'draw' then 3 else -2 end) + v_pg * 6 + v_pa * 4
           + (case when v_rat >= 8 then 5 when v_rat < 5 then -3 else 0 end)
           + (case when v_f.stage in ('r16', 'qf', 'sf', 'final') then 2 else 0 end);

  update public.careers set xp = xp + v_xp, coins = coins + v_coins where id = v_c.id;   -- o gatilho sobe o nível a cada 1000 XP

  update public.career_stats
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         popularity = greatest(0, least(1000, popularity + v_dpop)),
         updated_at = now()
   where career_id = v_c.id;

  update public.career_seasons
     set matches = matches + 1,
         wins   = wins   + (v_res = 'win')::int,
         draws  = draws  + (v_res = 'draw')::int,
         losses = losses + (v_res = 'loss')::int,
         goals = goals + v_pg, assists = assists + v_pa,
         xp_earned = xp_earned + v_xp, coins_earned = coins_earned + v_coins
   where id = v_s.id;

  -- ---- o resto da rodada, o próximo mata-mata e o fim do campeonato --
  perform public.sim_play_round(v_s.id, v_cid, v_f.stage, v_f.round_no);
  perform public.sim_advance(v_s.id, v_cid);

  -- (se o seu clube caiu, o campeonato continua no calendário: os próximos dias viram "Próximo")
  select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = v_cid;
  v_comp_done := (v_sc.status = 'finished');

  -- ---- proposta de outro clube? -------------------------------------
  select popularity into v_pop from public.career_stats where career_id = v_c.id;
  v_offer := public.sim_maybe_offer(v_c.id, v_s.id, v_s.club_id, v_pop);

  -- ---- acabou a temporada? ------------------------------------------
  if not exists (select 1 from public.season_fixtures where season_id = v_s.id and status = 'pending') then
    perform public.sim_finalize_season(v_s.id);
    v_season_done := true;
  end if;

  -- ---- resposta para a tela -----------------------------------------
  select * into v_c  from public.careers where id = v_c.id;
  select * into v_f2 from public.season_fixtures where id = v_f.id;
  select jsonb_agg(jsonb_build_object('home', o.home_club, 'away', o.away_club, 'hg', o.home_goals, 'ag', o.away_goals, 'group', o.group_label) order by o.id)
    into v_round
    from public.season_fixtures o
   where o.season_id = v_s.id and o.competition_id = v_cid and o.stage = v_f.stage
     and o.round_no = v_f.round_no and o.id <> v_f.id;

  return jsonb_build_object(
    'competition', v_cid,
    'stage', v_f.stage, 'round', v_f.round_no, 'leg', v_f.leg, 'group', v_f.group_label,
    'venue', case when v_home then 'home' else 'away' end,
    'home', v_f2.home_club, 'away', v_f2.away_club,
    'home_goals', v_f2.home_goals, 'away_goals', v_f2.away_goals,
    'home_pens', v_f2.home_pens, 'away_pens', v_f2.away_pens, 'tie_winner', v_f2.tie_winner,
    'my_club', v_s.club_id, 'result', v_res,
    'player', jsonb_build_object('goals', v_pg, 'assists', v_pa, 'rating', v_rat),
    'rewards', jsonb_build_object('xp', v_xp, 'coins', v_coins, 'popularity', v_dpop),
    'level_up', v_c.level > v_lvl0, 'new_level', v_c.level,
    'round_results', coalesce(v_round, '[]'::jsonb),
    'competition_finished', v_comp_done,
    'competition_result', case when v_comp_done then v_sc.player_result end,
    'competition_bonus', case when v_comp_done and coalesce(v_sc.player_bonus_xp, 0) + coalesce(v_sc.player_bonus_coins, 0) > 0
                              then jsonb_build_object('xp', v_sc.player_bonus_xp, 'coins', v_sc.player_bonus_coins) end,
    'champion', case when v_comp_done then v_sc.champion_club end,
    'offer', v_offer,
    'season_finished', v_season_done,
    'energy', v_c.energy + v_c.bonus_energy);
end;
$$;

create or replace function public.season_hub()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_c     public.careers;
  v_st    public.career_stats;
  v_s     public.career_seasons;
  v_sc    public.season_competitions;
  v_nf    public.season_fixtures;
  r       record;
  v_total int;
  v_played int;
  v_pending int;
  v_status text;
  v_grp   text;
  v_pos   int;
  v_pts   int;
  v_pl    int;
  v_item  jsonb;
  v_comps jsonb := '[]'::jsonb;
  v_offers jsonb;
  v_hist  jsonb;
  v_ev    record;
  v_next  jsonb := null;
begin
  v_c := public.sim_lock_career();
  if v_c.club_id is null then raise exception 'Escolha um clube antes de jogar temporadas.'; end if;

  insert into public.career_stats (career_id) values (v_c.id) on conflict do nothing;
  select * into v_st from public.career_stats where career_id = v_c.id;

  select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  if v_s.id is null then
    perform public.sim_create_season(v_c.id);
    select * into v_s from public.career_seasons where career_id = v_c.id order by season_no desc limit 1;
  end if;

  for r in select id, name, short_name from public.sim_competitions order by sort_order loop
    select * into v_sc from public.season_competitions where season_id = v_s.id and competition_id = r.id;

    select count(*), count(*) filter (where status = 'played'), count(*) filter (where status = 'pending')
      into v_total, v_played, v_pending
      from public.season_fixtures
     where season_id = v_s.id and competition_id = r.id and (home_club = v_s.club_id or away_club = v_s.club_id);

    v_status := case when v_sc.status = 'finished' then 'finished'
                     when v_total = 0 then 'not_in'
                     when v_pending = 0 then 'out'
                     else 'active' end;

    v_item := jsonb_build_object(
      'id', r.id, 'name', r.name, 'short_name', r.short_name, 'status', v_status, 'stage', v_sc.stage,
      'played', v_played, 'total', v_total,
      'champion', v_sc.champion_club, 'runner_up', v_sc.runner_up_club,
      'player_result', v_sc.player_result, 'bonus_xp', v_sc.player_bonus_xp, 'bonus_coins', v_sc.player_bonus_coins);

    if v_status = 'active' then
      select * into v_nf from public.season_fixtures
       where season_id = v_s.id and competition_id = r.id and status = 'pending'
         and (home_club = v_s.club_id or away_club = v_s.club_id)
       order by round_no, id limit 1;
      v_item := v_item || jsonb_build_object('next', jsonb_build_object(
        'home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
        'leg', v_nf.leg, 'group', v_nf.group_label,
        'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end,
        'neutral', (v_nf.stage = 'final')));
    end if;

    -- posição na tabela (Brasileirão e fase de grupos da Libertadores)
    if v_total > 0 and r.id <> 'copa_brasil' then
      v_grp := null;
      if r.id = 'libertadores' then
        select group_label into v_grp from public.season_fixtures
         where season_id = v_s.id and competition_id = r.id and stage = 'group'
           and (home_club = v_s.club_id or away_club = v_s.club_id) limit 1;
      end if;
      select t.pos, t.points, t.played into v_pos, v_pts, v_pl
        from public.sim_standings(v_s.id, r.id, v_grp) t where t.club_id = v_s.club_id;
      v_item := v_item || jsonb_build_object('table', jsonb_build_object('group', v_grp, 'pos', v_pos, 'points', v_pts, 'played', v_pl));
    end if;

    v_comps := v_comps || jsonb_build_array(v_item);
  end loop;

  -- o que vem agora no calendário: uma partida do seu clube ("mine") ou rodadas de outros campeonatos ("free")
  if v_s.status = 'active' then
    select * into v_ev from public.sim_next_event(v_s.id, v_s.club_id);
    if found then
      if v_ev.o_kind = 'mine' then
        select * into v_nf from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and status = 'pending'
           and (home_club = v_s.club_id or away_club = v_s.club_id)
         order by round_no, id limit 1;
        v_next := jsonb_build_object('kind', 'mine', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round,
          'match', jsonb_build_object('home', v_nf.home_club, 'away', v_nf.away_club, 'round', v_nf.round_no, 'stage', v_nf.stage,
            'leg', v_nf.leg, 'group', v_nf.group_label,
            'venue', case when v_nf.home_club = v_s.club_id then 'home' else 'away' end, 'neutral', (v_nf.stage = 'final')));
      else
        select count(*) into v_total from public.season_fixtures
         where season_id = v_s.id and competition_id = v_ev.o_comp and stage = v_ev.o_stage and round_no = v_ev.o_round;
        v_next := jsonb_build_object('kind', 'free', 'competition', v_ev.o_comp, 'stage', v_ev.o_stage, 'round', v_ev.o_round, 'matches', v_total);
      end if;
    end if;
  end if;

  select coalesce(jsonb_agg(x.j order by x.ts desc), '[]'::jsonb) into v_hist from (
    select jsonb_build_object('id', h.id, 'club_id', h.from_club, 'status', h.status, 'bonus_coins', h.bonus_coins) as j,
           coalesce(h.responded_at, h.created_at) as ts
      from public.season_offers h
     where h.career_id = v_c.id and h.status <> 'pending' and h.season_id is not null
     order by 2 desc limit 8) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id, 'club_id', o.from_club, 'bonus_coins', o.bonus_coins, 'pitch', o.pitch, 'created_at', o.created_at, 'expires_at', o.expires_at)
         order by o.created_at desc), '[]'::jsonb)
    into v_offers from public.season_offers o where o.career_id = v_c.id and o.status = 'pending';

  return jsonb_build_object(
    'career', jsonb_build_object(
      'id', v_c.id, 'nickname', v_c.nickname, 'position', v_c.position, 'level', v_c.level, 'xp', v_c.xp,
      'coins', v_c.coins, 'energy', v_c.energy, 'bonus_energy', v_c.bonus_energy,
      'next_reset_at', v_c.energy_reset_at + interval '5 hours', 'club_id', v_c.club_id),
    'stats', to_jsonb(v_st) - 'career_id',
    'season', to_jsonb(v_s) - 'career_id',
    'competitions', v_comps,
    'next_event', v_next,
    'offers', v_offers,
    'offer_history', v_hist);
end;
$$;

create or replace function public.sim_finalize_season(p_season uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_s   public.career_seasons;
  r     record;
  v_sum jsonb;
  v_pop int;
  v_n   int;
  v_i   int;
begin
  select * into v_s from public.career_seasons where id = p_season;

  -- campeonatos que o jogador não disputou (ou dos quais saiu) terminam "sozinhos"
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;

  select jsonb_agg(jsonb_build_object(
           'competition', sc.competition_id, 'champion', sc.champion_club, 'runner_up', sc.runner_up_club,
           'player_result', sc.player_result, 'bonus_xp', sc.player_bonus_xp, 'bonus_coins', sc.player_bonus_coins)
         order by sc.competition_id)
    into v_sum from public.season_competitions sc where sc.season_id = p_season;

  update public.career_seasons set status = 'finished', finished_at = now(), summary = v_sum where id = p_season;
  update public.career_stats set seasons_played = seasons_played + 1, updated_at = now() where career_id = v_s.career_id;

  -- janela de transferências: 0 a 3 propostas, conforme a popularidade
  select popularity into v_pop from public.career_stats where career_id = v_s.career_id;
  v_n := least(3, v_pop / 200 + (case when random() < 0.5 then 1 else 0 end));
  for v_i in 1 .. v_n loop
    perform public.sim_make_offer(v_s.career_id, p_season, v_s.club_id, v_pop, 72);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- F) PERMISSÕES (o app só chama as funções "públicas")
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'sim\_%' or p.proname like 'season\_%'
                 or p.proname in ('refresh_wallet', 'choose_initial_club', 'get_initial_offers', 'careers_level_up'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('season_hub', 'season_play', 'season_advance', 'season_start_next', 'season_offer_respond',
                     'season_standings', 'refresh_wallet', 'choose_initial_club', 'get_initial_offers') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
