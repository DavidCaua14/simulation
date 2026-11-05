"""Two simultaneous registrations (CM17, evolução 69: sem limite por janela) register once each. Local disposable PostgreSQL only."""
from concurrent.futures import ThreadPoolExecutor
import json, os, subprocess, sys, uuid
container, database = sys.argv[1:3]
if not database.startswith('simulation_validation_'):
    raise SystemExit('Disposable database required')
env = {k: v for k, v in os.environ.items() if k not in ['DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH']}
command = ['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', container, 'psql', '-U', 'postgres', '-d', database, '-XAt', '-v', 'ON_ERROR_STOP=1']
def sql(source):
    result = subprocess.run(command, input=source.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if result.returncode:
        raise RuntimeError(result.stderr.decode())
    return result.stdout.decode().splitlines()
uid, cid = str(uuid.uuid4()), str(uuid.uuid4())
header = f"begin;select set_config('request.jwt.claim.sub','{uid}',true);"
setup = f"""
insert into auth.users(id) values('{uid}');
insert into public.careers(id,user_id,nickname,club_id,photo_id,age,coins)
 values('{cid}','{uid}','Market-{cid[:8]}','sport','1',30,1000);
"""
sql('begin;' + setup + f"select set_config('request.jwt.claim.sub','{uid}',true);select public.career_runtime_initialize() is not null;" + f"""
update public.cw_world set today='2026-01-05',needs_sync=false where career_id='{cid}';
update public.cw_clubs set cash=20000000,debt=0,financial_risk=0,monthly_revenue=1000000 where career_id='{cid}';
create temp table targets as select mp.player_id from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
 join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
 where mp.career_id='{cid}' and mp.club_id<>'sport' and r.rating between 60 and 70 order by mp.player_id limit 2;
update public.cw_contracts set status='expired',starts_on='2025-01-01',expires_on='2026-01-04',ended_on='2026-01-04'
 where career_id='{cid}' and player_id in(select player_id from targets) and status='active';
update public.mgr_players set club_id=null where career_id='{cid}' and player_id in(select player_id from targets);
insert into public.cw_transfer_registrations select '{cid}',gen_random_uuid(),'quota-fixture','sport','2026-01-05' from generate_series(1,5);
insert into public.cw_negotiations(career_id,player_id,buyer_club,initiator,status,fee,valuation,monthly_salary,signing_bonus,contract_years,created_on,reply_on,expires_on,register_on)
 select '{cid}',player_id,'sport','user','agreed',0,1000,public.cw_salary_demand('{cid}',player_id,'sport'),2*public.cw_salary_demand('{cid}',player_id,'sport'),3,'2026-01-05','2026-01-05','2026-01-12','2026-01-05' from targets;
commit;
""")
ids = sql(f"select id from public.cw_negotiations where career_id='{cid}' order by id")
assert len(ids) == 2
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda oid: sql(header + f"select public.cw_register_transfer('{oid}');commit;"), ids))
assert sorted(lines[-2 if lines[-1] == 'COMMIT' else -1] for lines in results) == ['t', 't'], results
state = json.loads(sql(f"""select jsonb_build_object(
 'registered',public.cw_registered_in_window('{cid}','sport','2026-01-05'),
 'completed',(select count(*) from public.cw_negotiations where career_id='{cid}' and status='completed'),
 'queued',(select count(*) from public.cw_negotiations where career_id='{cid}' and status='agreed' and register_on='2026-07-10'),
 'coins',(select coins from public.careers where id='{cid}'),
 'today',(select today from public.cw_world where career_id='{cid}'))""")[0])
assert state == {'registered': 7, 'completed': 2, 'queued': 0, 'coins': 1000, 'today': '2026-01-05'}, state
winner = sql(f"select id from public.cw_negotiations where career_id='{cid}' and status='completed' order by id")[0]
assert 't' in sql(header + f"select public.cw_register_transfer('{winner}');commit;")
assert sql(f"select count(*) from public.cw_transfer_registrations where career_id='{cid}'") == ['7']
assert sql(f"select count(*) from public.cw_finance where career_id='{cid}' and kind='player_signing'") == ['2']
print('PASS simultaneous registrations: both signings registered once, one bonus payment each, stable date and personal wallet')
