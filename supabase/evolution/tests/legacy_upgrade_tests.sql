begin;
select set_config('request.jwt.claim.sub','21212121-0000-0000-0000-000000000001',true);
do $$
declare saved public.test_upgrade_snapshot;current public.mgr_matches;result jsonb;
begin
 select * into saved from public.test_upgrade_snapshot;
 assert saved.fixture_id is not null,'Faltou preparar a partida legada';
 select * into current from public.mgr_matches where fixture_id=saved.fixture_id;
 assert to_jsonb(current)=saved.match_data,'Migração alterou estado da partida aberta';
 assert (select jsonb_agg(to_jsonb(p) order by p.player_id) from public.mgr_match_players p where p.fixture_id=current.fixture_id)=saved.players,'Migração alterou atletas da partida';
 assert (select jsonb_agg(to_jsonb(e) order by e.seq) from public.mgr_match_events e where e.fixture_id=current.fixture_id) is not distinct from saved.events,'Migração alterou lances';
 assert (select to_jsonb(c) from public.careers c where c.id=current.career_id)=saved.career,'Migração alterou saldo/progresso';
 assert (select jsonb_agg(to_jsonb(f) order by f.id) from public.season_fixtures f where f.season_id=current.season_id and f.status='played')=saved.played,'Migração alterou resultados anteriores';
 result:=public.mgr_match_payload(current.fixture_id,0);
 assert (result->>'engine_version')::int=1,'Partida antiga mudou de motor';
 result:=public.mgr_match_step(current.fixture_id,current.minute,120,null,true,0);
 assert result->>'status'='finished','Partida legada não pôde continuar';
 assert (result->>'engine_version')::int=1,'Retomar partida trocou a versão';
 raise notice 'PASS upgrade real: partida v1, lances, atletas, saldo e resultados preservados; retomada concluída';
end $$;
rollback;
