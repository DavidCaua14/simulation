-- Insatisfação no elenco, modo "Buscar o resultado" e títulos para comemorar.
--  * Moral baixa vira insatisfação: abaixo de 35% o atleta fica insatisfeito, abaixo de 20% fica revoltado.
--    Muitos insatisfeitos no elenco (titulares, banco ou fora da lista) derrubam o rendimento do time inteiro
--    (cw_squad_unrest, aplicado no começo de cada partida do treinador).
--  * Revoltado manda mensagem pedindo para ser negociado (ou liberado, se for reserva distante do time).
--    Sem solução, a moral cai mais a cada semana e as reclamações ficam mais frequentes. Colocar na lista de
--    transferências acalma (para de reclamar); moral de volta a 35% encerra o caso.
--  * Tática "Buscar o resultado" (manage = 'chase'): sem estar vencendo, o time joga um degrau mais ofensivo o jogo
--    todo; perdendo depois dos 70', dois degraus. A IA continua com o 'push' de antes.
--  * career_hub_read devolve 'titles': títulos do seu clube na temporada atual (campeão ou campeão matematicamente
--    nos pontos corridos) para o app mostrar a comemoração.
-- Nada do progresso é alterado: só colunas novas com padrão e funções.

-- Uma linha só para quem está reclamando (cw_players é view; o caso de insatisfação fica à parte).
create table if not exists public.cw_player_unrest(
 career_id uuid not null references public.careers(id) on delete cascade,
 player_id text not null,
 msgs smallint not null default 0,
 last_on date,
 primary key(career_id,player_id));
alter table public.cw_player_unrest enable row level security;
revoke all on public.cw_player_unrest from public,anon,authenticated;

-- ---------------------------------------------------------------- clima do elenco
create or replace function public.cw_squad_unrest(p_career uuid,p_club text)
returns jsonb language sql stable security definer set search_path=public as $$
 with x as (
  select count(*) filter(where cp.morale<35 and cp.morale>=20) unhappy,
         count(*) filter(where cp.morale<20) angry,
         count(u.player_id) filter(where not coalesce(cp.transfer_listed,false)) rebels
    from public.mgr_players mp join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
    left join public.cw_player_unrest u on u.career_id=mp.career_id and u.player_id=mp.player_id and u.msgs>0
   where mp.career_id=p_career and mp.club_id=p_club),
 w as (select *,unhappy+2*angry+rebels weight from x)
 select jsonb_build_object('unhappy',unhappy,'angry',angry,'rebels',rebels,
  'penalty',least(0.08,greatest(0,weight-3)*0.0075),
  'factor',1-least(0.08,greatest(0,weight-3)*0.0075)) from w
$$;

-- Penalidade entra no 'form' do lado do treinador, uma vez, junto com capitão e exercícios.
do $$ declare src text;begin
 select pg_get_functiondef('public.cw_cm_match_prepare(bigint,uuid,character)'::regprocedure) into src;
 if src like '%cw_squad_unrest%' then return;end if;
 if position(' -- exercícios pré-jogo só valem para o time do treinador e gastam um jogo cada' in src)=0 then
  raise exception 'cw_cm_match_prepare diferente do esperado';
 end if;
 execute replace(src,' -- exercícios pré-jogo só valem para o time do treinador e gastam um jogo cada',
 ' -- insatisfação no elenco do treinador derruba o rendimento do time
 if p_user_side in(''h'',''a'') then
  form[case when p_user_side=''h'' then 1 else 2 end]:=form[case when p_user_side=''h'' then 1 else 2 end]
   *coalesce((public.cw_squad_unrest(p_career,case when p_user_side=''h'' then f.home_club else f.away_club end)->>''factor'')::numeric,1);
 end if;
 -- exercícios pré-jogo só valem para o time do treinador e gastam um jogo cada');
end $$;

-- ---------------------------------------------------------------- reclamações na caixa de entrada
create or replace function public.cw_unrest_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
declare d date;own text;p record;gap int;title text;body text;wants text;n int;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is null or d is null then return;end if;
 -- só no dia em que a moral semanal do atleta acabou de ser recalculada
 for p in select cp.player_id,cp.morale,coalesce(u.msgs,0) unrest_msgs,u.last_on unrest_last_on,coalesce(cp.transfer_listed,false) listed,
                 sp.short_name pname,public.cw_squad_rank(p_career,own,cp.player_id) rk
            from public.cw_players cp join public.mgr_players mp on mp.career_id=cp.career_id and mp.player_id=cp.player_id
            join public.sim_players sp on sp.id=cp.player_id
            left join public.cw_player_unrest u on u.career_id=cp.career_id and u.player_id=cp.player_id
           where cp.career_id=p_career and mp.club_id=own and cp.last_morale_on=d
             and (cp.morale<20 or coalesce(u.msgs,0)>0) loop
  if p.morale>=35 then
   delete from public.cw_player_unrest where career_id=p_career and player_id=p.player_id;
   perform public.cw_inbox_add(p_career,'unrest_ok:'||p.player_id||':'||d,'squad','squad',
    p.pname||' está mais tranquilo',
    p.pname||' voltou a ter espaço e deixou de lado o pedido para sair. O clima no vestiário melhorou.',
    own,p.player_id,null,'open_player');
   continue;
  end if;
  if p.listed then continue;end if; -- já está sendo oferecido: espera propostas sem reclamar
  wants:=case when coalesce(p.rk,99)<=18 then 'trade' else 'release' end;
  if p.unrest_msgs=0 then
   n:=1;
  else
   -- sem solução: mais irritado a cada semana e reclamando com mais frequência (14 dias, depois 7)
   update public.cw_players set morale=greatest(0,morale-3),morale_trend=-1 where career_id=p_career and player_id=p.player_id;
   gap:=case when p.unrest_msgs>=2 then 7 else 14 end;
   if p.unrest_last_on is not null and d-p.unrest_last_on<gap then continue;end if;
   n:=p.unrest_msgs+1;
  end if;
  title:=case when n=1 then case wants when 'trade' then p.pname||' pede para ser negociado' else p.pname||' pede para ser liberado' end
              when n=2 then p.pname||' volta a cobrar uma saída'
              else p.pname||' perdeu a paciência' end;
  body:=case when n=1 then
          case wants when 'trade' then p.pname||' está muito insatisfeito com a falta de oportunidades e pediu para ser negociado. Dê minutos a ele ou coloque-o na lista de transferências.'
                     else p.pname||' não vê espaço no elenco e pediu para ser liberado. Dê uma chance a ele, coloque-o na lista de transferências ou rescinda o contrato.' end
             when n=2 then p.pname||' segue sem resposta e voltou a reclamar. A insatisfação dele já pesa no vestiário e no rendimento do time.'
             else p.pname||' reclamou publicamente e está cada vez mais irritado. Enquanto nada mudar, ele vai continuar cobrando — e o time sente.' end;
  perform public.cw_inbox_add(p_career,'unrest:'||p.player_id||':'||d,'squad','squad',title,body,own,p.player_id,null,'open_player');
  insert into public.cw_player_unrest(career_id,player_id,msgs,last_on) values(p_career,p.player_id,least(n,99),d)
  on conflict(career_id,player_id) do update set msgs=excluded.msgs,last_on=excluded.last_on;
 end loop;
end $$;

create or replace function public.cw_market_tick(p_career uuid)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare d date;own text;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is not null and current_setting('cw.release_user_bids',true) is distinct from 'on'
    and exists(select 1 from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
               where s.career_id=p_career and s.status='active' and f.status='pending' and own in(f.home_club,f.away_club)) then
  -- Em espera até o fim da próxima partida; o prazo acompanha para a proposta não expirar enquanto espera.
  update public.cw_negotiations set reply_on=greatest(reply_on,d+1),expires_on=greatest(expires_on,d+1)
   where career_id=p_career and initiator='user' and buyer_club=own and status in('club_pending','player_pending') and reply_on<=d;
 end if;
 perform public.cw_market_tick_before_v70(p_career);
 perform public.cw_unrest_tick(p_career);
end $function$;

-- Elenco: clima do vestiário e o status de cada insatisfeito
do $$ begin
 if not exists(select 1 from pg_proc where proname='mgr_squad_before_v90' and pronamespace='public'::regnamespace) then
  alter function public.mgr_squad(text) rename to mgr_squad_before_v90;
 end if;
end $$;
create or replace function public.mgr_squad(p_club text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;car uuid;club text;
begin
 r:=public.mgr_squad_before_v90(p_club);
 car:=(public.cw_read_career()).id;
 club:=coalesce(r->>'club_id',p_club,(select club_id from public.mgr_coach where career_id=car));
 if club is distinct from (select club_id from public.mgr_coach where career_id=car) then return r;end if;
 return r||jsonb_build_object('unrest',public.cw_squad_unrest(car,club),
  'players',coalesce((select jsonb_agg(e.v||jsonb_build_object('unrest',u.player_id is not null and not coalesce(cp.transfer_listed,false)) order by e.i)
    from jsonb_array_elements(r->'players') with ordinality e(v,i)
    left join public.cw_players cp on cp.career_id=car and cp.player_id=e.v->>'id'
    left join public.cw_player_unrest u on u.career_id=car and u.player_id=e.v->>'id' and u.msgs>0),'[]'::jsonb));
end $$;
revoke all on function public.mgr_squad_before_v90(text) from public,anon,authenticated;
grant execute on function public.mgr_squad(text) to authenticated;

-- ---------------------------------------------------------------- tática "Buscar o resultado"
do $$ declare src text;begin
 select pg_get_functiondef('public.mgr_tactics_clean(jsonb)'::regprocedure) into src;
 if src like '%''chase''%' then return;end if;
 if position('''manage'',case when not cm and t->>''manage'' in(''keep'',''normal'',''push'') then t->>''manage'' else ''normal'' end' in src)=0 then
  raise exception 'mgr_tactics_clean diferente do esperado';
 end if;
 execute replace(src,'''manage'',case when not cm and t->>''manage'' in(''keep'',''normal'',''push'') then t->>''manage'' else ''normal'' end',
  '''manage'',case when t->>''manage''=''chase'' then ''chase'' when not cm and t->>''manage'' in(''keep'',''normal'',''push'') then t->>''manage'' else ''normal'' end');
end $$;

do $$ declare fn text;src text;old text:='if v_tmanage[s] = ''push'' and v_lead <= 0 and v_min >= 60 then v_ment[s] := least(2, v_ment[s] + 1); end if;';begin
 foreach fn in array array['public.mgr_engine_run_v1(bigint,integer,character)','public.mgr_engine_run_v2(bigint,integer,character)'] loop
  select pg_get_functiondef(fn::regprocedure) into src;
  continue when src like '%''chase''%';
  if position(old in src)=0 then raise exception '% diferente do esperado',fn;end if;
  execute replace(src,old,old||' if v_tmanage[s] = ''chase'' and v_lead <= 0 then v_ment[s] := least(2, v_ment[s] + case when v_lead < 0 and v_min >= 70 then 2 else 1 end); end if;');
 end loop;
end $$;

-- ---------------------------------------------------------------- títulos da temporada atual
create or replace function public.cw_title_watch(p_career uuid,p_season uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare own text;res jsonb:='[]';c record;mine record;best numeric;
begin
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is null or p_season is null then return res;end if;
 for c in select sc.competition_id,sc.champion_club,co.rules->>'format' format,coalesce((co.rules->'points'->>'win')::int,3) pw,coalesce((co.rules->'points'->>'draw')::int,1) pd
            from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
           where sc.season_id=p_season loop
  if c.champion_club=own then
   res:=res||jsonb_build_array(jsonb_build_object('competition',c.competition_id,'kind','champion'));
   continue;
  end if;
  continue when c.champion_club is not null or c.format is distinct from 'league';
  -- pontos corridos: ninguém mais alcança o seu clube, nem vencendo todos os jogos que faltam
  with fx as (select home_club,away_club,home_goals,away_goals,status from public.season_fixtures
               where season_id=p_season and competition_id=c.competition_id and stage='league'),
   cl as (select home_club k from fx union select away_club from fx),
   t as (select cl.k,
     coalesce(sum(case when f.status='played' then case when (f.home_club=cl.k and f.home_goals>f.away_goals) or (f.away_club=cl.k and f.away_goals>f.home_goals) then c.pw
       when f.home_goals=f.away_goals then c.pd else 0 end end),0) pts,
     count(*) filter(where f.status<>'played') rem
     from cl join fx f on cl.k in(f.home_club,f.away_club) group by cl.k)
  select (select pts from t where k=own) mp,(select max(pts+c.pw*rem) from t where k<>own) other into mine;
  if mine.mp is not null and mine.other is not null and mine.mp>mine.other then
   res:=res||jsonb_build_array(jsonb_build_object('competition',c.competition_id,'kind','clinched'));
  end if;
 end loop;
 return res;
end $$;

do $$ declare src text;begin
 select pg_get_functiondef('public.career_hub_read()'::regprocedure) into src;
 if src like '%cw_title_watch%' then return;end if;
 if position(' ''league_status'',public.cw_league_status(c.id),' in src)=0 then raise exception 'career_hub_read diferente do esperado';end if;
 execute replace(src,' ''league_status'',public.cw_league_status(c.id),',
  ' ''league_status'',public.cw_league_status(c.id),
 ''titles'',public.cw_title_watch(c.id,(h#>>''{season,id}'')::uuid),');
end $$;

revoke all on function public.cw_squad_unrest(uuid,text),public.cw_unrest_tick(uuid),public.cw_title_watch(uuid,uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
