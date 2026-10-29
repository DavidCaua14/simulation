"""Durable full-season test with one PostgreSQL transaction per real RPC call.
Only accepts disposable simulation_validation_* databases in the local test container.
Pass --resume after fixing a failing phase to verify real persisted resumption.
"""
from pathlib import Path
import json, os, subprocess, sys, time, uuid
container, database = sys.argv[1:3]
if not database.startswith('simulation_validation_'): raise SystemExit('Disposable test database required')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
cmd=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-At','-v','ON_ERROR_STOP=1']
def sql(source):
 r=subprocess.run(cmd,input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if r.returncode: raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().splitlines()
cid='41414141-0000-0000-0000-000000000011';uid='41414141-0000-0000-0000-000000000001'
header=f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
if '--resume' not in sys.argv:
 sql(f"insert into auth.users(id) values('{uid}');insert into public.careers(id,user_id,nickname,club_id,country,age,bonus_energy) values('{cid}','{uid}','Full cycle test','palmeiras','BR',30,100);")
 sql(header+f"select public.mgr_hub() is not null;select public.mgr_end_spell('{cid}','left');commit;")
started=time.monotonic()
for batch in range(1,2001):
 request=str(uuid.uuid4())
 query=header+f"select public.career_world_advance(14,'{request}');commit;"
 result=next(json.loads(s) for s in sql(query) if s.startswith('{'))
 if batch%10==0 or result['today']>='2027-01-02': print('CYCLE',batch,result['today'],'matches',result['matches'],'elapsed',round(time.monotonic()-started),flush=True)
 # A retry uses the same id and must not advance or simulate anything twice.
 if batch%25==0:
  repeat=next(json.loads(s) for s in sql(query) if s.startswith('{'))
  assert repeat['today']==result['today'] and repeat['matches']==result['matches'] and repeat.get('replayed'),(repeat,result)
 if result.get('next_season_ready'):
  sql(header+"select public.mgr_season_next();commit;")
 if result['today']>='2027-01-02':break
else: raise AssertionError('Calendar failed to reach next season')
verify=Path(__file__).resolve().parents[1]/'supabase/evolution/tests/career_world_cycle_verify.sql'
sql(verify.read_text())
print('PASS durable complete season: two regions, full-time games, champion MVP, next-season qualification, AI international transfers and idempotent retries',flush=True)
