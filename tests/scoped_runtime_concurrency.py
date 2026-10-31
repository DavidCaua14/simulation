"""Only a disposable local PostgreSQL database; no production URL accepted."""
from concurrent.futures import ThreadPoolExecutor
import json, os, subprocess, sys, uuid
container,database=sys.argv[1:3]
if not database.startswith('simulation_validation_'):raise SystemExit('Disposable database required')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
command=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-XAt','-v','ON_ERROR_STOP=1']
def sql(source):
 r=subprocess.run(command,input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().splitlines()
uid=str(uuid.uuid4());cid=str(uuid.uuid4())
sql(f"insert into auth.users(id) values('{uid}');insert into public.careers(id,user_id,nickname,club_id,coins,photo_id,age) values('{cid}','{uid}','Scoped-{cid[:8]}','flamengo',1000,'1',30)")
header=f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
sql(header+'select public.career_runtime_initialize() is not null;commit;')
version=sql(f"select version from public.cw_runtime where career_id='{cid}'")[0]
requests=[str(uuid.uuid4()) for _ in range(2)]
def prepare(request):
 lines=sql(header+f"select public.career_world_prepare(1,'{request}',{version});commit;")
 return next(json.loads(s) for s in lines if s.startswith('{'))
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(prepare,requests))
assert sum(bool(r.get('requires_refresh')) for r in results)==1,results
winner=next(i for i,r in enumerate(results) if not r.get('requires_refresh'))
assert prepare(requests[winner])==results[winner],'Lost-response retry did not return durable receipt'
assert sql(f"select count(*) from public.cw_operations where career_id='{cid}'")==['1'],'Duplicate operation'
assert sql(f"select calls from public.cw_runtime_metrics where career_id='{cid}'")==['1'],'Advanced twice'
print('PASS two tabs with different UUIDs and same version: one advance, one refresh; lost response replayed once')
