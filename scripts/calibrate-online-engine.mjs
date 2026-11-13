import { readFileSync, readdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
const ROOT='/home/user/simulation', ONLINE=join(ROOT,'supabase','online')
const entry = createRequire(join(process.env.PGLITE_DIR||'/tmp/pglite','package.json')).resolve('@electric-sql/pglite')
const { PGlite } = await import(pathToFileURL(entry).href)
const db = new PGlite()
const files=[join(ONLINE,'tests','support','stub.sql'),...readdirSync(ONLINE).filter(f=>/^\d+_.*\.sql$/.test(f)).sort().map(f=>join(ONLINE,f))]
for (const f of files) await db.exec(readFileSync(f,'utf8'))
if (process.argv[3]) await db.exec(readFileSync(process.argv[3],'utf8'))
await db.exec(`
insert into public.careers(user_id,nickname) values('00000000-0000-0000-0000-000000000001','A'),('00000000-0000-0000-0000-000000000002','B');
update public.on_config set join_instant=false,finish_hooks='{}';
select public.on_season_bootstrap(array['00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002']::uuid[],date '2026-11-16');
update public.on_clubs set draft_step=3 where user_id is not null;
-- uma partida controlada: nota e condição de cada lado, táticas, forma; devolve gols e finalizações
create or replace function public.calib(p_h numeric,p_a numeric,p_ch int,p_ca int,p_th jsonb,p_ta jsonb,p_fh numeric,p_fa numeric) returns int[]
language plpgsql as $$
declare a int;b int;f public.on_fixtures;r int[];
begin
 select id into a from public.on_clubs where user_id='00000000-0000-0000-0000-000000000001';
 select id into b from public.on_clubs where user_id='00000000-0000-0000-0000-000000000002';
 select * into f from public.on_fixtures where home=a and away=b limit 1;
 delete from public.on_matches where fixture_id=f.id;
 delete from public.on_match_players where fixture_id=f.id;delete from public.on_match_events where fixture_id=f.id;
 update public.on_fixtures set status='sched',hg=null,ag=null,pens=null where id=f.id;
 update public.on_players set ovr=p_h,level=p_h,cond=p_ch,rhythm=80,inj_until=null,susp_round=null,yellows=0 where club_id=a;
 update public.on_players set ovr=p_a,level=p_a,cond=p_ca,rhythm=80,inj_until=null,susp_round=null,yellows=0 where club_id=b;
 perform public.on_auto_lineup(a,'4-3-3');perform public.on_auto_lineup(b,'4-3-3');
 update public.on_lineups set tactics=p_th where club_id=a;update public.on_lineups set tactics=p_ta where club_id=b;
 update public.on_clubs set prep='{}' where id in(a,b);
 perform public.on_match_open(f);
 update public.on_matches set state=jsonb_set(state,'{form}',jsonb_build_array(p_fh,p_fa)) where fixture_id=f.id;
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 select array[x.hg,x.ag] into r from public.on_fixtures x where x.id=f.id;
 return r;
end $$;`)
const scen=JSON.parse(readFileSync(process.argv[2]||join(ONLINE,'tests','calibration_scenarios.json'),'utf8'))
const N=+(process.env.N||60)
for (const s of scen){
  let w=0,d=0,l=0,gf=0,ga=0,n=0
  const t0=Date.now()
  for(let i=0;i<N;i++){
    const r=(await db.query('select public.calib($1,$2,$3,$4,$5,$6,$7,$8) r',[s.h,s.a,s.ch??100,s.ca??100,JSON.stringify(s.th??{}),JSON.stringify(s.ta??{}),s.fh??1,s.fa??1])).rows[0].r
    if(!r||r[0]==null) continue
    n++;gf+=r[0];ga+=r[1]; if(r[0]>r[1])w++; else if(r[0]==r[1])d++; else l++
  }
  console.log(`${s.name.padEnd(34)} n=${n} V ${(100*w/n).toFixed(0)}% E ${(100*d/n).toFixed(0)}% D ${(100*l/n).toFixed(0)}%  gols ${(gf/n).toFixed(2)}-${(ga/n).toFixed(2)}  ${((Date.now()-t0)/n).toFixed(0)}ms/jogo`)
}
