"""Two concurrent compensation requests, only against a disposable local DB."""
import json,os,subprocess,sys,uuid
from concurrent.futures import ThreadPoolExecutor
container,database=sys.argv[1:]
assert database.startswith('simulation_validation_')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
command=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-At','-v','ON_ERROR_STOP=1','-c']
career='31313131-0000-0000-0000-000000000011';source='concurrency-'+uuid.uuid4().hex
def sql(query):return subprocess.check_output(command+[query],env=env,text=True).strip()
def wallet():return json.loads(sql("select json_build_array(coins,bonus_energy) from public.careers where id='"+career+"'"))
before=wallet()
query="begin; select public.base_compensate('"+career+"','box','"+source+"','basica',1); select pg_sleep(0.2); commit;"
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(sql,[query,query]))
answers=[next(line for line in r.splitlines() if line in ['t','f']) for r in results]
assert sorted(answers)==['f','t'],answers
after=wallet();assert after==[before[0]+55,before[1]+1],(before,after)
assert sql("select count(*) from public.base_card_compensations where career_id='"+career+"' and source_id='"+source+"'")=='1'
print('PASS two concurrent compensation requests: one credit and one audit entry')
