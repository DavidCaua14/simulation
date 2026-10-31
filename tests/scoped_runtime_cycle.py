"""Full new-runtime season using a synthetic unemployed coach in a disposable DB."""
from pathlib import Path
import json,os,subprocess,sys,time,uuid
container,database=sys.argv[1:3]
if not database.startswith('simulation_validation_'):raise SystemExit('Disposable database required')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
command=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-XAt','-v','ON_ERROR_STOP=1']
def sql(source):
 r=subprocess.run(command,input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
 if r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().splitlines()
uid=str(uuid.uuid4());cid=str(uuid.uuid4());header=f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
sql(f"insert into auth.users(id) values('{uid}');insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins) values('{cid}','{uid}','Cycle-{cid[:8]}','flamengo','1',30,1000)")
sql(header+f"select public.career_runtime_initialize() is not null;select public.mgr_end_spell('{cid}','left');commit;")
started=time.monotonic();max_ms=0
for batch in range(400):
 request=str(uuid.uuid4())
 # Explicitly defer each proposal in this test; real users decide in the interface.
 sql(header+f"do $$ declare a jsonb;begin for i in 1..100 loop a:=public.cw_attention('{cid}');exit when a is null;perform public.career_attention_ack(a->>'key');end loop;end $$;commit;")
 lines=sql(header+f"select public.career_world_advance(14,'{request}');commit;")
 result=next(json.loads(s) for s in lines if s.startswith('{'))
 if batch%20==0:print('Cycle batch',batch,'date',result['today'],flush=True)
 if result.get('next_season_ready'):
  old=sql(f"select primary_season from public.cw_world where career_id='{cid}'")[0]
  sql(header+'select public.mgr_season_next();commit;')
  checks=sql(f"select (primary_season<>'{old}')::int from public.cw_world where career_id='{cid}';select count(*) from public.cw_seasons where career_id='{cid}' and region<>'BRA';select count(*) from public.season_competitions where season_id='{old}' and status<>'finished';")
  assert checks==['1','0','0'],checks
  print('PASS full domestic and continental season, unemployed decisions, season rollover and no foreign league; seconds',round(time.monotonic()-started,2),flush=True)
  break
else:raise AssertionError('Failed to reach season boundary')
