-- Moral e relação com o elenco (2026-11-09).
-- 1. Time do treinador: a moral começa a pesar abaixo de 80 (o atleta quer mais espaço) e pesa mais quanto mais baixa.
--    O clima do elenco inteiro (índice "Elenco", 0–100) também muda o rendimento do time: elenco feliz rende mais.
--    Clubes da IA continuam com a regra antiga (só pesa abaixo de 45).
-- 2. Moral semanal do time do treinador: quem joga sobe, quem fica sem minutos cai (resultado não compensa quem não joga).
-- 3. Diretoria acompanha o elenco: avisa que está preocupada, depois que pensa em trocar o treinador.
--    Eliminação com o elenco insatisfeito (depois do aviso) = demissão, perda de ranking e de reputação,
--    e o clube não volta a fazer proposta (salvo se ele for rebaixado).
-- Nada do progresso é apagado: só regras, colunas novas com padrão e funções.

alter table public.mgr_failure_rules
  add column if not exists squad_warn1 numeric not null default 55,            -- diretoria preocupada
  add column if not exists squad_warn2 numeric not null default 40,            -- diretoria pensa em trocar
  add column if not exists squad_fire numeric not null default 45,             -- eliminação abaixo disso (já avisado) demite
  add column if not exists squad_fire_rank_points int not null default 120,
  add column if not exists squad_fire_reputation numeric not null default 3,
  add column if not exists squad_board_drag numeric not null default 15;       -- abaixo de warn1: diretoria perde (warn1-elenco)/drag por jogo

alter table public.mgr_coach add column if not exists squad_warned smallint not null default 0;
alter table public.mgr_club_bans add column if not exists division int;

-- Moral do atleta x rendimento no time do treinador: 80+ dá até +4%; abaixo de 80 perde cada vez mais (até −22% com moral 0).
create or replace function public.cw_coach_morale_factor(p_morale numeric)
returns numeric language sql immutable set search_path=public,pg_temp as $$
 select case when p_morale is null then 1
             when p_morale>=80 then 1+least(20,p_morale-80)/20*.04
             else 1-power((80-greatest(0,p_morale))/80,1.15)*.22 end
$$;

create or replace function public.cw_morale_perf_trg()
 returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare car uuid;us char;f numeric;m numeric;
begin
 select career_id,user_side into car,us from public.mgr_matches where fixture_id=new.fixture_id;
 if car is null then return new;end if;
 select morale into m from public.cw_players where career_id=car and player_id=new.player_id;
 if m is null then return new;end if;
 f:=case when new.side=us then public.cw_coach_morale_factor(m) else public.cw_morale_factor(m) end;
 if f is null or f=1 then return new;end if;
 new.c_att:=round(new.c_att*f,2);new.c_cre:=round(new.c_cre*f,2);new.c_def:=round(new.c_def*f,2);new.c_ctl:=round(new.c_ctl*f,2);
 new.c_gk:=round(new.c_gk*f,2);new.c_fin:=round(new.c_fin*f,2);new.c_head:=round(new.c_head*f,2);new.c_pace:=round(new.c_pace*f,2);
 new.c_tack:=round(new.c_tack*f,2);new.c_str:=round(new.c_str*f,2);
 return new;
end $function$;

-- Clima do elenco. Faixas de satisfação: satisfeito 80+, neutro 60–79, insatisfeito 35–59, revoltado abaixo de 35.
-- Atletas na lista de transferências ficam de fora (já estão sendo negociados).
-- harmony = média da moral − 1,5 por insatisfeito − 3 por revoltado − 2 por quem pede para sair.
-- factor: 80+ até +3%; abaixo de 80 até −10%. Chaves antigas (unhappy, angry, rebels, penalty, factor) continuam.
create or replace function public.cw_squad_unrest(p_career uuid, p_club text)
 returns jsonb language sql stable security definer set search_path to 'public' as $function$
 with x as (
  select count(*) total,
         coalesce(avg(cp.morale),65) avg_m,
         count(*) filter(where cp.morale>=80) satisfied,
         count(*) filter(where cp.morale>=60 and cp.morale<80) neutral,
         count(*) filter(where cp.morale>=35 and cp.morale<60) unhappy,
         count(*) filter(where cp.morale<35) angry,
         count(u.player_id) rebels
    from public.mgr_players mp join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
    left join public.cw_player_unrest u on u.career_id=mp.career_id and u.player_id=mp.player_id and u.msgs>0
   where mp.career_id=p_career and mp.club_id=p_club and not coalesce(cp.transfer_listed,false)),
 h as (select *,round(greatest(0,least(100,avg_m-1.5*unhappy-3*angry-2*rebels)),1) harmony from x),
 f as (select *,case when harmony>=80 then 1+(harmony-80)/20*.03 else 1-(80-harmony)/80*.10 end factor from h)
 select jsonb_build_object('harmony',harmony,'avg',round(avg_m,1),'total',total,
  'satisfied',satisfied,'neutral',neutral,'unhappy',unhappy,'angry',angry,'rebels',rebels,
  'penalty',round(greatest(0,1-factor),4),'bonus',round(greatest(0,factor-1),4),'factor',round(factor,4)) from f
$function$;

-- Moral semanal. Time do treinador: regra nova. Demais clubes: regra antiga (cw_cm_morale_next_ai).
create or replace function public.cw_cm_morale_next_ai(p_career uuid,p_club text,p_player text,p_morale numeric,p_games int,p_apps int,p_arrears numeric,p_day date)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare rk int;expected numeric;share numeric;delta numeric:=0;w int;l int;
begin
 rk:=coalesce(public.cw_squad_rank(p_career,p_club,p_player),30);
 expected:=case when rk<=11 then .60 when rk<=16 then .30 else .10 end;
 if p_games>=3 then
  share:=p_apps::numeric/p_games;
  delta:=greatest(-6,least(6,round(10*(share-expected))));
  if share>=expected and delta<1 then delta:=1;end if;
 else
  delta:=case when p_morale<60 then 1 when p_morale>70 then -1 else 0 end;
 end if;
 select count(*) filter(where (f.home_club=p_club and f.home_goals>f.away_goals) or (f.away_club=p_club and f.away_goals>f.home_goals)),
        count(*) filter(where (f.home_club=p_club and f.home_goals<f.away_goals) or (f.away_club=p_club and f.away_goals<f.home_goals))
   into w,l
   from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id
  where fd.career_id=p_career and fd.club_id=p_club and f.status='played' and fd.due_on between p_day-7 and p_day;
 delta:=delta+greatest(-4,least(4,2*coalesce(w,0)-2*coalesce(l,0)));
 if coalesce(p_arrears,0)>0 then delta:=delta-8;end if;
 return greatest(0,least(100,p_morale+delta));
end $$;

create or replace function public.cw_cm_morale_next(p_career uuid,p_club text,p_player text,p_morale numeric,p_games int,p_apps int,p_arrears numeric,p_day date)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare rk int;expected numeric;share numeric;delta numeric:=0;w int;l int;
begin
 if not exists(select 1 from public.mgr_coach where career_id=p_career and club_id=p_club and status='employed') then
  return public.cw_cm_morale_next_ai(p_career,p_club,p_player,p_morale,p_games,p_apps,p_arrears,p_day);
 end if;
 -- quanto o atleta espera jogar (jogos com 30+ minutos nos últimos 28 dias), pelo lugar no elenco
 rk:=coalesce(public.cw_squad_rank(p_career,p_club,p_player),30);
 expected:=case when rk<=11 then .55 when rk<=16 then .30 else .15 end;
 select count(*) filter(where (f.home_club=p_club and f.home_goals>f.away_goals) or (f.away_club=p_club and f.away_goals>f.home_goals)),
        count(*) filter(where (f.home_club=p_club and f.home_goals<f.away_goals) or (f.away_club=p_club and f.away_goals<f.home_goals))
   into w,l
   from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id
  where fd.career_id=p_career and fd.club_id=p_club and f.status='played' and fd.due_on between p_day-7 and p_day;
 if p_games>=3 then
  share:=p_apps::numeric/p_games;
  delta:=greatest(-8,least(7,round(16*(share-expected))));
  if share>=expected and delta<2 then delta:=2;end if;
  -- vitória só anima quem está jogando; derrota pesa em todos
  if share>=expected*.5 then delta:=delta+greatest(-3,least(3,2*coalesce(w,0)-2*coalesce(l,0)));
  else delta:=delta-least(3,coalesce(l,0)); end if;
 else
  delta:=case when p_morale<70 then 1 when p_morale>85 then -1 else 0 end;
 end if;
 if coalesce(p_arrears,0)>0 then delta:=delta-8;end if;
 return greatest(0,least(100,p_morale+delta));
end $$;

-- Divisão atual do clube (liga nacional na temporada principal da carreira).
create or replace function public.mgr_club_division(p_career uuid, p_club text)
returns int language sql stable security definer set search_path=public as $$
 select min(sc.division) from public.cw_world w join public.season_participants sp on sp.season_id=w.primary_season
   join public.sim_competitions sc on sc.id=sp.competition_id and sc.kind='league'
  where w.career_id=p_career and sp.club_id=p_club
$$;

-- Veto em vigor: o veto por "elenco" cai quando o clube está numa divisão abaixo da que tinha ao demitir.
create or replace function public.mgr_ban_min_rep(p_career uuid, p_club text)
returns numeric language sql stable security definer set search_path=public as $$
 select b.min_reputation from public.mgr_club_bans b
  where b.career_id=p_career and b.club_id=p_club
    and not (b.reason='elenco' and b.division is not null and coalesce(public.mgr_club_division(p_career,p_club),b.division)>b.division)
$$;

create or replace function public.mgr_club_banned(p_career uuid, p_club text)
 returns boolean language sql stable security definer set search_path to 'public' as $function$
 select coalesce((select coalesce(c.reputation,0) < public.mgr_ban_min_rep(p_career,p_club) from public.mgr_coach c where c.career_id=p_career),false)
$function$;

create or replace function public.cw_required_reputation(p_career uuid, p_club text)
 returns numeric language sql stable security definer set search_path to 'public' as $function$
 select greatest(coalesce(public.mgr_ban_min_rep(p_career,p_club),0),round((coalesce(c.prestige,s.strength)-55-(coalesce(k.credibility,(select credibility from public.cw_coach where career_id=p_career),65)-65)*.18)/.32,1))
 from public.sim_clubs s left join public.cw_clubs c on c.career_id=p_career and c.club_id=s.id left join public.cw_coach k on k.career_id=c.career_id
 where s.id=p_club
$function$;

-- Depois de cada jogo do treinador: diretoria x elenco. Chamado em mgr_user_match_finished depois de mgr_group_exit.
create or replace function public.mgr_squad_check(p_fixture bigint, p_club text, p_car jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c public.mgr_coach; rr public.mgr_failure_rules; s public.career_seasons; f public.season_fixtures;
 h jsonb; e numeric; prev smallint; drag numeric := 0; b0 numeric; div int; out jsonb;
begin
 select * into f from public.season_fixtures where id = p_fixture;
 select * into c from public.mgr_coach where career_id = (select career_id from public.mgr_matches where fixture_id = p_fixture) for update;
 if c.career_id is null or c.status <> 'employed' or c.club_id is distinct from p_club then return p_car; end if;
 select * into rr from public.mgr_failure_rules;
 select * into s from public.career_seasons where id = f.season_id;
 h := public.cw_squad_unrest(c.career_id, p_club);
 e := (h->>'harmony')::numeric;
 prev := c.squad_warned;
 b0 := coalesce((p_car #>> '{board,before}')::numeric, c.board_confidence);

 -- diretoria perde a confiança com o vestiário em crise
 if e < rr.squad_warn1 then
  drag := round((rr.squad_warn1 - e) / rr.squad_board_drag, 2);
  update public.mgr_coach set board_confidence = round(greatest(0, board_confidence - drag), 2)
   where career_id = c.career_id returning * into c;
 end if;

 if e < rr.squad_warn2 and c.squad_warned < 2 then
  perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Diretoria pensa em trocar o treinador',
   'O relacionamento entre o treinador e os jogadores preocupa muito a diretoria. Vários atletas reclamam de falta de oportunidades e já se fala em troca no comando. Uma eliminação agora pode custar o seu cargo: dê minutos a quem não está jogando.', p_club);
  update public.mgr_coach set squad_warned = 2 where career_id = c.career_id;
 elsif e < rr.squad_warn1 and c.squad_warned < 1 then
  perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Diretoria preocupada com o elenco',
   'A diretoria está preocupada com o relacionamento entre o treinador e os jogadores. Parte do elenco se sente sem espaço. Faça rodízio e use mais atletas.', p_club);
  update public.mgr_coach set squad_warned = 1 where career_id = c.career_id;
 elsif e >= rr.squad_warn1 + 8 and c.squad_warned > 0 then
  update public.mgr_coach set squad_warned = 0 where career_id = c.career_id;
 end if;

 out := p_car || jsonb_build_object('squad', jsonb_build_object('harmony', e, 'unhappy', h->'unhappy', 'angry', h->'angry'),
   'board', jsonb_build_object('before', p_car #> '{board,before}', 'after', round(c.board_confidence),
            'delta', round(c.board_confidence - b0, 1)));

 -- eliminação + elenco insatisfeito (já avisado antes deste jogo) = demissão
 if coalesce((p_car->>'eliminated')::boolean, false) and e < rr.squad_fire and prev >= 1 and p_car->>'fire_reason' is null then
  update public.mgr_coach
     set rank_penalty = rank_penalty + rr.squad_fire_rank_points,
         reputation = round(greatest(0, reputation - rr.squad_fire_reputation), 2)
   where career_id = c.career_id;
  div := public.mgr_club_division(c.career_id, p_club);
  insert into public.mgr_club_bans(career_id, club_id, reason, season_no, min_reputation, division)
  values (c.career_id, p_club, 'elenco', s.season_no, 100, div)
  on conflict (career_id, club_id) do update set reason = 'elenco', season_no = excluded.season_no,
    min_reputation = greatest(public.mgr_club_bans.min_reputation, excluded.min_reputation), division = excluded.division, created_at = now();
  perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Demitido: elenco insatisfeito',
   format('A eliminação, somada ao elenco insatisfeito por falta de oportunidades, fez a diretoria %s trocar o treinador. Você perdeu %s pontos no ranking e o clube não pretende chamá-lo de volta.',
          public.mgr_club_do(p_club), rr.squad_fire_rank_points), p_club);
  out := out || jsonb_build_object('fire_reason', 'eliminação com o elenco insatisfeito por falta de oportunidades',
    'squad_fire', true,
    'ranking', jsonb_build_object('delta', coalesce((p_car #>> '{ranking,delta}')::int, 0) - rr.squad_fire_rank_points),
    'reputation', jsonb_build_object('before', p_car #> '{reputation,before}', 'after', round(c.reputation - rr.squad_fire_reputation, 1),
                  'delta', round(coalesce((p_car #>> '{reputation,delta}')::numeric, 0) - rr.squad_fire_reputation, 2)));
 end if;
 return out;
end $$;
revoke all on function public.mgr_squad_check(bigint, text, jsonb) from public, anon, authenticated;
revoke all on function public.cw_cm_morale_next_ai(uuid,text,text,numeric,int,int,numeric,date) from public, anon, authenticated;

-- Encaixa a checagem do elenco logo depois da queda na fase de grupos.
do $$ declare src text; a text := 'v_fired := v_car ->> ''fire_reason'';'; begin
 select pg_get_functiondef('public.mgr_user_match_finished(bigint)'::regprocedure) into src;
 if src like '%mgr_squad_check%' then return; end if;
 if position(a in src) = 0 then raise exception 'mgr_user_match_finished diferente do esperado'; end if;
 execute replace(src, a, 'v_car := public.mgr_squad_check(p_fixture, v_club, v_car);' || chr(10) || a);
end $$;

-- Hub: o treinador vê o índice "Elenco" ao lado de Diretoria e Torcida.
create or replace function public.mgr_hub()
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare h jsonb;car uuid;cl text;
begin
 car:=(public.cw_read_career()).id;
 if not exists(select 1 from public.cw_world where career_id=car) then perform public.mgr_lock();end if;
 h:=public.mgr_hub_before_v33();
 select club_id into cl from public.mgr_coach where career_id=car and status='employed';
 if cl is not null and jsonb_typeof(h->'coach')='object' then
  h:=jsonb_set(h,'{coach,squad}',public.cw_squad_unrest(car,cl));
 end if;
 return h||jsonb_build_object(
  'messages',(select coalesce(jsonb_agg(m.j order by m.id desc),'[]') from(
    select mm.id,jsonb_build_object('id',mm.id,'kind',mm.kind,'category',mm.category,'title',mm.title,'body',mm.body,'club_id',mm.club_id,
     'player_id',mm.player_id,'negotiation_id',mm.negotiation_id,'action',mm.action,'day_no',mm.day_no,'read',mm.read,'created_at',mm.created_at) j
    from public.mgr_messages mm where mm.career_id=car order by mm.id desc limit 80) m),
  'unread_by_category',(select coalesce(jsonb_object_agg(category,n),'{}') from(select category,count(*) n from public.mgr_messages where career_id=car and not read group by category) x));
end $function$;

notify pgrst, 'reload schema';
