-- Gerado por scripts/build-editor-release.mjs a partir de 36_first_access_speed.sql: primeiro acesso ao modo Temporadas mais rápido.
-- Requer o modo Temporadas com mundo paralelo (evolução 26 ou supabase/releases/carreira_completa.sql). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Ao final compara as impressões digitais de carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações, mensagens
-- e satisfação; se alguma mudar, o comando é desfeito por inteiro.
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('36_first_access_speed.sql'));
 if to_regprocedure('public.cw_initialize_finances(uuid)') is null then raise exception 'Requer o modo Temporadas com mundo paralelo (evolução 26 ou supabase/releases/carreira_completa.sql); nada foi alterado';end if;
 select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players)) into antes;

-- ===================== 36_first_access_speed.sql =====================
create index if not exists season_fixture_slots_fixture_idx on public.season_fixture_slots(fixture_id);

create or replace function public.sim_fixture_slots_sync()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='UPDATE' then delete from public.season_fixture_slots where fixture_id=new.id;end if;
 insert into public.season_fixture_slots values
 (new.season_id,new.competition_id,new.stage,new.round_no,new.home_club,new.id),
 (new.season_id,new.competition_id,new.stage,new.round_no,new.away_club,new.id);
 return null;
end $$;

create or replace function public.cw_initialize_finances(p_career uuid)
returns void
language plpgsql
security definer
set search_path=public
as $function$
#variable_conflict use_column
declare w public.cw_world;r record;fresh boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 if not w.stats_initialized then
  insert into public.cw_stats_opening(career_id,season_id,player_id,competition_id,club_id,apps,minutes,goals,assists,rating_sum)
   select p_career,st.season_id,st.player_id,st.competition_id,st.club_id,st.apps,st.minutes,st.goals,st.assists,st.rating_sum
   from public.mgr_player_stats st join public.career_seasons cs on cs.id=st.season_id where cs.career_id=p_career on conflict do nothing;
  update public.cw_world set stats_initialized=true where career_id=p_career;
 end if;
 insert into public.cw_clubs(career_id,club_id,cash,initial_budget,monthly_revenue,prestige,strategy,fanbase)
 select p_career,c.id,round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((5000+power(greatest(5,c.strength-40),3)*3)*case when public.cw_region(c.id)='ENG' then 1.8 else 1 end),
 round((2000+power(greatest(5,c.strength-40),2)*25)*case when public.cw_region(c.id)='ENG' then 1.5 else 1 end),
 c.strength,case abs(hashtext(c.id)::bigint)%4 when 0 then 'youth' when 1 then 'balanced' when 2 then 'ambitious' else 'sustainable' end,
 greatest(1000,(c.strength-30)*(c.strength-30)*150)
 from public.sim_clubs c on conflict do nothing;
 insert into public.cw_players(career_id,player_id,age_at_start,age_estimated,potential)
 select p_career,p.id,coalesce(p.age,case when p.is_youth then 19 else 26 end),p.age is null,
 least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career on conflict do nothing;
 update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and market_value=0;
 fresh:=not exists(select 1 from public.cw_contracts where career_id=p_career);
 insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
 select p_career,mp.player_id,mp.club_id,w.today,(w.today+make_interval(years=>1+(abs(hashtext(mp.player_id)::bigint)%4)::int))::date,
 greatest(40,round(public.cw_player_value(p_career,mp.player_id)*.0065)),case when p.is_youth then 'prospect' when r.rating>=82 then 'key' when r.rating>=74 then 'starter' else 'rotation' end
 from public.mgr_players mp join public.sim_players p on p.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 where mp.career_id=p_career and mp.club_id is not null and (fresh or not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id));
 -- Papel prometido = papel do contrato ativo. Atualiza atleta a atleta pela chave primária: numa carreira
 -- recém-criada as estatísticas das tabelas não existem e um join cruzava todos os atletas com todos os contratos.
 for r in select ct.player_id,ct.role from public.cw_contracts ct where ct.career_id=p_career and ct.status='active' loop
  update public.cw_players set promised_role=r.role where career_id=p_career and player_id=r.player_id and promised_role is distinct from r.role;
 end loop;
 insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description)
 select p_career,c.club_id,w.today,'opening',c.cash,c.cash,'opening','Orçamento inicial estimado do clube' from public.cw_clubs c where c.career_id=p_career on conflict do nothing;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
 select p_career,c.spell_id,c.club_id,w.today,(w.today+interval '2years')::date,p.monthly_salary from public.mgr_coach c join public.cw_coach p on p.career_id=c.career_id
 where c.career_id=p_career and c.status='employed' and c.spell_id is not null on conflict do nothing;
end $function$;

revoke all on function public.cw_initialize_finances(uuid) from public,anon,authenticated;

analyze public.season_fixture_slots;
perform pg_notify('pgrst','reload schema');

 select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players)) into depois;
 select string_agg(k,', ') into mudou from jsonb_object_keys(antes) k where antes->k is distinct from depois->k;
 if mudou is not null then raise exception 'Abortado: dados de usuários mudariam (%); nada foi alterado',mudou;end if;
 if to_regprocedure('public.cw_initialize_finances(uuid)') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: primeiro acesso ao modo Temporadas mais rápido; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.cw_initialize_finances(uuid)') is not null then 'Instalação concluída: primeiro acesso ao modo Temporadas mais rápido; dados dos usuários preservados.' else 'Não instalado' end as resultado;
