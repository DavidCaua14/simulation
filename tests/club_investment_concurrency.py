"""Real concurrent funding requests. Only a newly created local fixture is changed."""
from concurrent.futures import ThreadPoolExecutor
import json, os, subprocess, sys, uuid
container,database=sys.argv[1:3]
if not database.startswith('simulation_validation_'):raise SystemExit('Disposable database required')
env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
command=['docker','--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-XAt','-v','ON_ERROR_STOP=1']
def execute(source):return subprocess.run(command,input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
def sql(source):
 r=execute(source)
 if r.returncode:raise RuntimeError(r.stderr.decode())
 return r.stdout.decode().splitlines()
def jsonrow(source):return next(json.loads(x) for x in sql(source) if x.startswith('{'))
uid,cid=str(uuid.uuid4()),str(uuid.uuid4())
header=f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
def confirm(q,req):
 return header+f"select public.career_club_investment_confirm({q['amount']},'{q['club_id']}',{q['personal_before']},{q['cash_before']},{q['board_bonus']},'{req}');commit;"
sql(f"begin;insert into auth.users(id) values('{uid}');insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins) values('{cid}','{uid}','Funding-{cid[:8]}','sport','1',30,5000);select set_config('request.jwt.claim.sub','{uid}',true);select public.career_runtime_initialize() is not null;update public.cw_world set today='2026-01-05',needs_sync=false where career_id='{cid}';update public.cw_clubs set cash=10000,debt=0,financial_risk=0 where career_id='{cid}' and club_id='sport';commit;")
q=jsonrow(header+'select public.career_club_investment_preview(500);rollback;');request=str(uuid.uuid4())
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(execute,[confirm(q,request)]*2))
assert all(r.returncode==0 for r in results),[r.stderr.decode() for r in results]
assert sorted(next(json.loads(x)['replayed'] for x in r.stdout.decode().splitlines() if x.startswith('{')) for r in results)==[False,True]
q=jsonrow(header+'select public.career_club_investment_preview(100);rollback;')
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(execute,[confirm(q,str(uuid.uuid4())) for _ in range(2)]))
assert sorted(r.returncode==0 for r in results)==[False,True]
loser=next(r for r in results if r.returncode)
assert 'O clube ou os valores mudaram' in loser.stderr.decode()
# The compatibility RPC also serializes campaign accounting under different request IDs.
with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(execute,[header+f"select public.career_club_invest(1000,'{uuid.uuid4()}');commit;" for _ in range(2)]))
assert all(r.returncode==0 for r in results),[r.stderr.decode() for r in results]
state=jsonrow(f"select jsonb_build_object('coins',(select coins from public.careers where id='{cid}'),'cash',(select cash from public.cw_clubs where career_id='{cid}' and club_id='sport'),'bonus',(select sum(bonus_paid) from public.cw_board_contributions where career_id='{cid}'),'receipts',(select count(*) from public.cw_finance where career_id='{cid}' and kind='coach_investment'),'today',(select today from public.cw_world where career_id='{cid}'))")
assert state=={'coins':2400,'cash':12800,'bonus':200,'receipts':4,'today':'2026-01-05'},state
print('PASS concurrent funding: one debit per receipt, stale second tab blocked, capped shared board pool, four explicit contributions, no date advance',flush=True)
# The parent test runner drops this disposable database, including the synthetic fixture.
