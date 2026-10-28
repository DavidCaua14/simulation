-- Reparação de dados DEPOIS das migrações 15..19 e do backup.
-- A migração não reinicia nem apaga temporadas. Se houver inconsistência,
-- toda a transação falha; não tenta adivinhar resultados.
begin;
set local lock_timeout='5s';
set local statement_timeout='10min';
do $$
declare r record;v jsonb;before_hash text;after_hash text;
begin
 select md5(coalesce(string_agg(md5(to_jsonb(f)::text),'' order by f.id),'')) into before_hash from public.season_fixtures f where status='played';
 for r in select id from public.career_seasons where status in('finished','archived')
  and not exists(select 1 from public.season_fixtures f where f.season_id=career_seasons.id and f.status<>'played') loop
  perform public.sim_record_final_tables(r.id);
 end loop;
 for r in select distinct f.season_id,f.competition_id,f.stage from public.season_fixtures f
  join public.career_seasons s on s.id=f.season_id join public.sim_competitions c on c.id=f.competition_id
  where s.status='active' and s.mode='coach' and c.kind='league' and f.status='pending'
    and public.sim_phase(f.competition_id,f.stage)->>'type'='league'
  order by f.season_id,f.competition_id,f.stage loop
  v:=public.sim_rebalance_pending(r.season_id,r.competition_id,r.stage);
  raise notice 'Calendário % / %: %',r.season_id,r.competition_id,v;
 end loop;
 select md5(coalesce(string_agg(md5(to_jsonb(f)::text),'' order by f.id),'')) into after_hash from public.season_fixtures f where status='played';
 if before_hash<>after_hash then raise exception 'Partidas disputadas foram alteradas; abortando reparação';end if;
end $$;
set constraints all immediate;
commit;
