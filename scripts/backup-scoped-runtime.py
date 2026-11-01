#!/usr/bin/env python3
"""Back up public game saves through the Management API, or restore to local Docker only.
Credentials and snapshots must remain outside this public repository. Auth secrets are not exported.
"""
import argparse,base64,json,os,re,secrets,subprocess,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('action',choices=['export','restore-local'])
parser.add_argument('--directory',type=Path,required=True)
parser.add_argument('--project-id')
parser.add_argument('--container',default='simulation-seasons-test')
parser.add_argument('--database',default='simulation_validation_backup_restore')
args=parser.parse_args()
directory=args.directory.resolve()
if directory==ROOT or ROOT in directory.parents:raise SystemExit('Use a private directory outside this public repository')
def save(name,data):
 p=directory/name;p.write_text(json.dumps(data));p.chmod(0o600)
def api(query):
 request=urllib.request.Request('https://api.supabase.com/v1/projects/'+args.project_id+'/database/query',data=json.dumps({'query':query}).encode(),headers={'Authorization':'Bearer '+os.environ['SUPABASE_ACCESS_TOKEN'],'Content-Type':'application/json'})
 time.sleep(1.25)
 with urllib.request.urlopen(request,timeout=90) as response:return json.load(response)
if args.action=='export':
 if not args.project_id or not re.fullmatch('[a-z0-9]+',args.project_id):raise SystemExit('Valid --project-id required')
 if directory.exists() and any(directory.iterdir()):raise SystemExit('Destination must be empty; existing backups are never overwritten')
 directory.mkdir(parents=True,exist_ok=True);directory.chmod(0o700)
 key=secrets.token_hex(32);(directory/'compressed.key').write_text(key);(directory/'compressed.key').chmod(0o600)
 tables=api("select table_name,json_agg(column_name) columns from information_schema.columns c where table_schema='public' and exists(select 1 from information_schema.tables t where t.table_schema=c.table_schema and t.table_name=c.table_name and t.table_type='BASE TABLE') group by table_name")
 owned={};shared=[]
 for t in tables:
  name=t['table_name'];cols=t['columns'];predicate=None
  if name=='careers':predicate='id={car}'
  elif 'career_id' in cols:predicate='career_id={car}'
  elif 'season_id' in cols:predicate='season_id in(select id from public.career_seasons where career_id={car})'
  elif 'fixture_id' in cols:predicate='fixture_id in(select f.id from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id={car})'
  if predicate:owned[name]=predicate
  else:shared.append((name,'true'))
 # Include nullable/orphan technical records outside the owned save snapshots.
 for name,pred in owned.items():
  # One anti-join per table; correlated IN queries repeatedly scanned whole fixture lists.
  if name=='careers':continue
  if pred.startswith('career_id='):orphan='not exists(select 1 from public.careers owner where owner.id=t.career_id)'
  elif pred.startswith('season_id '):orphan='not exists(select 1 from public.career_seasons s join public.careers owner on owner.id=s.career_id where s.id=t.season_id)'
  else:orphan='not exists(select 1 from public.season_fixtures f join public.career_seasons s on s.id=f.season_id join public.careers owner on owner.id=s.career_id where f.id=t.fixture_id)'
  shared.append((name,orphan))
 def snapshot(entries):
  statements=[]
  for name,pred in entries:
   quoted='"'+name.replace('"','""')+'"'
   statements.append("select '"+name+"' name,encode(extensions.pgp_sym_encrypt(coalesce(json_agg(t)::text,'[]'),'"+key+"','compress-algo=1,compress-level=6,cipher-algo=aes256'),'base64') blob from public."+quoted+' t where '+pred)
  return api("set statement_timeout='60s';"+' union all '.join(statements))
 manifest={'careers':[],'shared':['shared.union.json'],'scope':'public game saves, per-career consistent snapshots; Auth secrets excluded'}
 for i,c in enumerate(api('select id from public.careers order by id')):
  car="'"+c['id']+"'::uuid";name=f'career-{i}.union.json'
  save(name,snapshot([(t,p.format(car=car)) for t,p in owned.items()]));manifest['careers'].append(name)
  print('Exported save',i+1,flush=True)
 save('shared.union.json',snapshot(shared))
 save('schema-before.json',api((ROOT/'supabase/evolution/support/scoped_backup_schema.sql').read_text()))
 save('functions-before.json',api("select p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f' order by p.proname,p.oid"))
 save('manifest.json',manifest);print('Backup complete. Keep compressed.key in a separate protected location.')
else:
 if not args.database.startswith('simulation_validation_'):raise SystemExit('Only disposable simulation_validation_* databases are accepted')
 env={k:v for k,v in os.environ.items() if k not in ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']}
 docker=['docker','--host=unix:///var/run/docker.sock','exec','-i',args.container]
 def sql(source):
  result=subprocess.run(docker+['psql','-U','postgres','-d',args.database,'-XAt','-v','ON_ERROR_STOP=1'],input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
  if result.returncode:raise RuntimeError(next((s for s in result.stderr.decode().splitlines() if s.startswith('ERROR:')),'Local restore failed'))
  return result.stdout.decode()
 subprocess.run(docker+['createdb','-U','postgres',args.database],check=True,env=env)
 sql('create schema extensions;create extension pgcrypto with schema extensions;')
 sql((ROOT/'supabase/evolution/tests/support/bootstrap.sql').read_text().split('create table public.careers')[0])
 schema=json.loads((directory/'schema-before.json').read_text())[0]['schema']
 for group in ['types','sequences']:sql('\n'.join(d+';' for d in schema.get(group) or []))
 sql('\n'.join(t['ddl']+';' for t in schema['tables']))
 key=(directory/'compressed.key').read_text().strip()
 if not re.fullmatch('[0-9a-f]{64}',key):raise SystemExit('Invalid local backup key')
 manifest=json.loads((directory/'manifest.json').read_text());merged={}
 for name in manifest['shared']+manifest['careers']:
  p=directory/name
  if p.suffix=='.pgp':
   payload=base64.b64encode(p.read_bytes()).decode()
   data=json.loads(sql("select extensions.pgp_sym_decrypt(decode('"+payload+"','base64'),'"+key+"')"))['data']
  else:
   parts=["('"+r['name'].replace("'","''")+"','"+r['blob'].replace('\n','')+"')" for r in json.loads(p.read_text())]
   data=json.loads(sql("select json_object_agg(name,extensions.pgp_sym_decrypt(decode(blob,'base64'),'"+key+"')::json) from(values"+','.join(parts)+')x(name,blob)'))
  for table,rows in data.items():merged.setdefault(table,[]).extend(rows)
 sql('insert into auth.users(id) values '+','.join("('"+c['user_id']+"')" for c in merged['careers'])+' on conflict do nothing;')
 for table,rows in merged.items():
  quoted='"'+table.replace('"','""')+'"'
  for offset in range(0,len(rows),1000):
   payload=json.dumps(rows[offset:offset+1000],ensure_ascii=False).replace("'","''")
   sql('set session_replication_role=replica;insert into public.'+quoted+" overriding system value select * from json_populate_recordset(null::public."+quoted+",'"+payload+"'::json);")
  if int(sql('select count(*) from public.'+quoted))!=len(rows):raise RuntimeError('Row count differs in '+table)
 definitions=json.loads((directory/'functions-before.json').read_text())
 sql('set check_function_bodies=off;\n'+'\n'.join(d['definition'].rstrip()+';' for d in definitions))
 for group in ['constraints_no_fk','indexes','constraints_fk','triggers','rls','policies','table_grants']:
  items=schema['constraints' if group.startswith('constraints_') else group] or []
  if group.startswith('constraints_'):items=[d for d in items if ('FOREIGN KEY' in d)==(group=='constraints_fk')]
  sql('\n'.join(d+';' for d in items))
 sql('revoke all on all functions in schema public from public,anon,authenticated,service_role;')
 sql('\n'.join(d+';' for d in schema['function_grants'] or []))
 sql("do $$ declare r record;v bigint;begin for r in select table_name,column_name from information_schema.columns where table_schema='public' and is_identity='YES' loop execute format('select greatest(coalesce(max(%I),0),1) from public.%I',r.column_name,r.table_name) into v;perform setval(pg_get_serial_sequence('public.'||quote_ident(r.table_name),r.column_name),v,true);end loop;end $$;analyze;")
 print('Restored local save snapshots, functions, constraints, indexes, RLS and grants. Production was not changed.')
