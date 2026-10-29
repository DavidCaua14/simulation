"""Two real PostgreSQL connections; fake careers only, no DATABASE_URL accepted."""
from concurrent.futures import ThreadPoolExecutor
import json, os, subprocess, sys
container, database = sys.argv[1:3]
if not database.startswith('simulation_validation_'): raise SystemExit('Disposable test database required')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-At','-v','ON_ERROR_STOP=1']
def sql(source):
 r=subprocess.run(cmd,input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if r.returncode: raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().splitlines()
cid='51515151-0000-0000-0000-000000000011';uid='51515151-0000-0000-0000-000000000001'
header=f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
try:
 sql(f"insert into auth.users(id) values('{uid}');insert into public.careers(id,user_id,nickname,club_id,country,age,coins) values('{cid}','{uid}','Concurrency coach','flamengo','BR',30,1000);")
 sql(header+"select public.mgr_hub() is not null;"+f"update public.cw_world set today='2026-01-10',needs_sync=false where career_id='{cid}';commit;")
 call=header+"select public.career_club_invest(50,'51515151-0000-0000-0000-000000000099');commit;"
 with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(sql,[call,call]))
 balances=sql(f"select coins from public.careers where id='{cid}';select count(*) from public.cw_finance where career_id='{cid}' and kind='coach_investment';")
 assert balances==['950','1'], balances
 call=header+"select public.career_world_advance(0,'51515151-0000-0000-0000-000000000098');commit;"
 with ThreadPoolExecutor(max_workers=2) as pool: results=list(pool.map(sql,[call,call]))
 parsed=[next(json.loads(line) for line in r if line.startswith('{')) for r in results]
 assert parsed[0]['matches']==parsed[1]['matches']
 count=sql(f"select count(*) from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id='{cid}' and f.status='played';")
 assert int(count[0])==parsed[0]['matches'],(count,parsed)
 print('PASS two concurrent connections: one club investment and one world simulation batch, both resumable without duplicate writes')
finally:
 # No broad deletes: test database owner drops the disposable database afterwards.
 pass
