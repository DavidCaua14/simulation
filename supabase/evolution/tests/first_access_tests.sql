-- ATENÇÃO: teste do banco LOCAL descartável (scripts/test-seasons-db.py). Não rode no Supabase de produção.
do $guard$ begin
 if not exists(select 1 from public.careers where id='31313131-0000-0000-0000-000000000011') then
  raise exception 'Este arquivo é só para o banco de teste local (carreiras fictícias). Nada foi alterado.';
 end if;
end $guard$;
-- Testes da evolução 36 (primeiro acesso ao modo Temporadas). Transação com ROLLBACK.
begin;
do $test$
declare uid uuid:=gen_random_uuid();car uuid:=gen_random_uuid();t timestamptz;ms int;bad int;
begin
 insert into auth.users(id) values(uid);
 insert into public.careers(id,user_id,nickname,club_id,country,age) values(car,uid,'Primeiro'||left(md5(random()::text),6),'gremio','BR',30);
 perform set_config('request.jwt.claim.sub',uid::text,true);
 t:=clock_timestamp();
 perform public.mgr_hub();
 ms:=round(extract(epoch from clock_timestamp()-t)*1000);
 if ms>7000 then raise exception 'Primeiro acesso levou % ms (limite da API: 8000)',ms;end if;
 raise notice 'PASS primeiro acesso monta o mundo em % ms',ms;
 select count(*) into bad from public.cw_contracts ct join public.cw_players cp using(career_id,player_id)
  where ct.career_id=car and ct.status='active' and cp.promised_role is distinct from ct.role;
 if bad>0 or not exists(select 1 from public.cw_contracts where career_id=car) then raise exception 'Papel prometido diferente do contrato em % atletas',bad;end if;
 select count(*) into bad from public.mgr_players mp where mp.career_id=car and mp.club_id is not null
  and (select count(*) from public.cw_contracts ct where ct.career_id=car and ct.player_id=mp.player_id and ct.status='active')<>1;
 if bad>0 then raise exception 'Atletas sem exatamente um contrato ativo: %',bad;end if;
 raise notice 'PASS contratos e papéis prometidos criados uma vez por atleta';
 select count(*) into bad from (select f.season_id,f.competition_id,f.stage,f.round_no,c.club from public.season_fixtures f join public.career_seasons cs on cs.id=f.season_id
   cross join lateral (values(f.home_club),(f.away_club)) c(club) where cs.career_id=car group by 1,2,3,4,5 having count(*)>1) x;
 if bad>0 then raise exception 'Clube em dois jogos da mesma rodada: %',bad;end if;
 raise notice 'PASS nenhum clube joga duas vezes na mesma rodada';
end $test$;
rollback;
