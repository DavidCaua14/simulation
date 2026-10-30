-- Gerado por scripts/build-editor-release.mjs a partir de 41_match_history_diet.sql: histórico de partidas enxuto e desempate por fair play corrigido.
-- Requer a evolução 39 (supabase/releases/elenco_caixa_janela.sql). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Feito para o jogo NO AR: não compara impressões digitais (os jogadores continuam jogando durante a instalação).
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('41_match_history_diet.sql'));
 if to_regprocedure('public.cw_prune_career(uuid)') is null then raise exception 'Requer a evolução 39 (supabase/releases/elenco_caixa_janela.sql); nada foi alterado';end if;
 

-- ===================== 41_match_history_diet.sql =====================
create or replace function public.cw_competition_news()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare s public.career_seasons;co public.sim_competitions;mvp record;runner text;scorer record;
begin
 if new.status<>'finished' or (tg_op='UPDATE' and old.status='finished') then return new;end if;
 select * into s from public.career_seasons where id=new.season_id;
 if not exists(select 1 from public.cw_world where career_id=s.career_id) then return new;end if;
 select * into co from public.sim_competitions where id=new.competition_id;
 runner:=new.runner_up_club;
 if co.kind='league' then select club_id into runner from public.sim_standings(s.id,co.id,null) where pos=2;end if;
 with contributions as (
  -- Totais da temporada já consolidados (iguais à soma jogo a jogo + estatísticas de abertura).
  select st.player_id,st.club_id,st.apps,st.goals,st.assists,st.rating_sum from public.mgr_player_stats st where st.season_id=s.id and st.competition_id=co.id and st.apps>0
 ), scores as (
  select player_id,club_id,sum(apps)::int as apps,sum(goals)::int as goals,sum(assists)::int as assists,round(sum(rating_sum)/greatest(sum(apps),1),2) as rating from contributions
  where club_id=new.champion_club group by player_id,club_id
 ) select * into mvp from scores where apps>=greatest(1,(select max(apps)/3 from scores)) order by rating desc,goals desc,assists desc,player_id limit 1;
 select st.player_id,sum(st.goals)::int as goals into scorer from public.mgr_player_stats st where st.season_id=s.id and st.competition_id=co.id group by st.player_id order by sum(st.goals) desc,sum(st.assists) desc,st.player_id limit 1;
 perform public.cw_news_add(s.career_id,'champion:'||s.id||':'||co.id,'title',public.mgr_club_name(new.champion_club)||' conquista '||co.name,
 'Campeão: '||public.mgr_club_name(new.champion_club)||coalesce('. Vice: '||public.mgr_club_name(runner),'')||coalesce('. Melhor atleta da equipe campeã: '||public.mgr_player_name(mvp.player_id)||' (nota '||mvp.rating||')','')||case when scorer.goals>0 then '. Artilheiro: '||public.mgr_player_name(scorer.player_id)||' ('||scorer.goals||' gols)' else '' end||'.',85,new.champion_club,mvp.player_id,s.id,
 jsonb_build_object('competition',co.id,'champion',new.champion_club,'runner_up',runner,'mvp',to_jsonb(mvp),'top_scorer',to_jsonb(scorer)));
 perform public.cw_cash(s.career_id,new.champion_club,case when co.kind='continental' then 30000 when co.kind='league' then 20000 else 10000 end,'competition_prize',s.id||':'||co.id,'Premiação por título: '||co.name);
 if runner is not null then perform public.cw_cash(s.career_id,runner,case when co.kind='continental' then 15000 when co.kind='league' then 10000 else 5000 end,'competition_runner',s.id||':'||co.id,'Premiação por vice: '||co.name);end if;
 if new.champion_club=(select club_id from public.mgr_coach where career_id=s.career_id) and s.id=(select primary_season from public.cw_world where career_id=s.career_id) then update public.cw_coach set credibility=least(100,credibility+4) where career_id=s.career_id;end if;
 return new;
end $function$;

create or replace function public.cw_prune_career(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare today date;own text;
begin
 select w.today into today from public.cw_world w where w.career_id=p_career;
 if today is null then return;end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 create temp table if not exists _cw_mine(club_id text primary key) on commit drop;
 truncate _cw_mine;
 insert into _cw_mine select own where own is not null on conflict do nothing;
 insert into _cw_mine select distinct cc.club_id from public.cw_coach_contracts cc where cc.career_id=p_career on conflict do nothing;
 -- Finanças antigas dos clubes da IA (o extrato que você vê é só do seu clube).
 delete from public.cw_finance f where f.career_id=p_career and f.on_date<today-60 and not exists(select 1 from _cw_mine m where m.club_id=f.club_id);
 -- Partidas da IA com mais de 30 dias: o relatório usa placar, estatísticas e lances guardados no jogo.
 delete from public.mgr_matches m using public.cw_fixture_dates fd
  where m.career_id=p_career and m.status='finished' and m.user_side is null and fd.fixture_id=m.fixture_id and fd.due_on<today-7;
 delete from public.mgr_match_events e using public.season_fixtures f,public.career_seasons cs,public.cw_fixture_dates fd
  where cs.career_id=p_career and f.season_id=cs.id and e.fixture_id=f.id and fd.fixture_id=f.id and fd.due_on<today-7
   and not coalesce(f.player_match,false) and e.kind not in('goal','pen_goal','own_goal','so_goal','so_miss','yellow','red','second_yellow');
 -- Escalações de partidas da IA já encerradas (as atuações foram arquivadas ao fim do jogo).
 delete from public.mgr_match_players mp using public.mgr_matches m
  where m.career_id=p_career and mp.fixture_id=m.fixture_id and m.status='finished' and m.user_side is null;
 -- Atuações jogo a jogo: 45 dias bastam (salário por jogo, satisfação, valor de mercado). Os totais da temporada
 -- ficam em mgr_player_stats. Quem tem cláusula de desempenho em aberto guarda as atuações desde o registro.
 delete from public.cw_appearances a where a.career_id=p_career and a.on_date<today-45
  and not exists(select 1 from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
   where cm.career_id=p_career and cm.kind='performance' and cm.status='reserved' and n.player_id=a.player_id and n.buyer_club=a.club_id);
 -- Negociações encerradas entre clubes da IA e contratos encerrados de atletas fora dos seus clubes.
 delete from public.cw_offer_history h using public.cw_negotiations n
  where h.negotiation_id=n.id and n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds') and n.created_on<today-60
   and not exists(select 1 from _cw_mine m where m.club_id in(n.buyer_club,n.seller_club));
 delete from public.cw_negotiations n where n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds') and n.created_on<today-60
  and not exists(select 1 from _cw_mine m where m.club_id in(n.buyer_club,n.seller_club))
  and not exists(select 1 from public.cw_commitments c where c.negotiation_id=n.id)
  and not exists(select 1 from public.cw_offer_history h where h.negotiation_id=n.id);
 delete from public.cw_contracts c where c.career_id=p_career and c.status<>'active' and coalesce(c.ended_on,c.expires_on)<today-60
  and not exists(select 1 from _cw_mine m where m.club_id=c.club_id)
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.agreed_owner_contract=c.id);
 -- Vagas de jogos de temporadas já encerradas (só servem para montar calendários novos).
 delete from public.season_fixture_slots s using public.career_seasons cs where cs.career_id=p_career and s.season_id=cs.id and cs.status<>'active';
 delete from public.econ_requests r where r.career_id=p_career and r.created_at<now()-interval '3 days';
end $function$;

revoke all on function public.cw_competition_news(),public.cw_prune_career(uuid) from public,anon,authenticated;

-- Cópia de estatísticas de abertura: não é mais lida (as premiações usam mgr_player_stats).
truncate public.cw_stats_opening;

-- Carreiras antigas (sem mundo): escalações de jogos encerrados da IA, partidas da IA com mais de 7 dias e lances
-- menores delas (gols, pênaltis e cartões ficam; o relatório usa placar, estatísticas e esses lances).
delete from public.mgr_match_players mp using public.mgr_matches m
 where mp.fixture_id=m.fixture_id and m.status='finished' and m.user_side is null;
delete from public.mgr_match_events e using public.season_fixtures f,public.mgr_matches m
 where e.fixture_id=f.id and m.fixture_id=f.id and m.status='finished' and m.user_side is null and not coalesce(f.player_match,false)
  and f.played_at<now()-interval '7 days' and e.kind not in('goal','pen_goal','own_goal','so_goal','so_miss','yellow','red','second_yellow')
  and not exists(select 1 from public.cw_world w where w.career_id=m.career_id);
delete from public.mgr_matches m using public.season_fixtures f
 where m.fixture_id=f.id and m.status='finished' and m.user_side is null and not coalesce(f.player_match,false)
  and f.played_at<now()-interval '7 days' and not exists(select 1 from public.cw_world w where w.career_id=m.career_id);

do $$ declare c uuid;begin
 for c in select career_id from public.cw_world loop perform public.cw_prune_career(c);end loop;
end $$;

-- Agendador: histórico de execuções cresce ~3 mil linhas por dia (tarefas a cada minuto). Limpa e agenda limpeza diária.
do $$ begin
 if to_regclass('cron.job_run_details') is not null then
  execute 'delete from cron.job_run_details where end_time<now()-interval ''1 day''';
  if not exists(select 1 from cron.job where jobname='purge-cron-history') then
   perform cron.schedule('purge-cron-history','17 4 * * *',$job$delete from cron.job_run_details where end_time<now()-interval '1 day'$job$);
  end if;
 end if;
exception when insufficient_privilege then raise notice 'Sem permissão para limpar o histórico do agendador; nada feito nele.';
end $$;

analyze public.cw_appearances;analyze public.mgr_matches;analyze public.mgr_match_players;analyze public.mgr_match_events;
perform pg_notify('pgrst','reload schema');


 if to_regprocedure('public.cw_prune_career(uuid)') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: histórico de partidas enxuto e desempate por fair play corrigido; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.cw_prune_career(uuid)') is not null then 'Instalação concluída: histórico de partidas enxuto e desempate por fair play corrigido; dados dos usuários preservados.' else 'Não instalado' end as resultado;
