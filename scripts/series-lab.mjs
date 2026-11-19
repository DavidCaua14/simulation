// LABORATÓRIO DAS SÉRIES (fase 35) — cria a estrutura A/B/C/D, joga temporadas inteiras pelo relógio (on_tick) e confere
// as regras. Nada em produção: PGlite com o catálogo fictício dos testes.
//
// Uso: PGLITE_DIR=<pasta com @electric-sql/pglite> node scripts/series-lab.mjs [--seasons 1] [--out r.json]
//
// Fase 39: os técnicos (clubes de usuário) trocam de estilo de jogo a cada turno (sorteado), definem ordem de pênaltis,
// batedores de falta e de escanteio de cada lado e, às vezes, uma marcação individual. Cada partida encerrada é guardada
// (estilos, aderência, força, placar, gols de bola parada) e conferida: suspenso ou lesionado não joga, cobrador de pênalti
// segue a ordem, gol de escanteio tem o batedor do lado como assistente, função passa para quem entra na substituição.
//
// Antes da estrutura nova, roda a suíte antiga (online_tests.sql), que deixa uma temporada de liga única com técnicos,
// títulos e elencos: é o mesmo caminho da migração em produção (on_series_bootstrap fecha a temporada e leva os técnicos
// para a Série D com elenco e caixa).
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = new URL('..', import.meta.url).pathname
const ONLINE = join(ROOT, 'supabase', 'online')
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d }
const SEASONS = +arg('seasons', 1), OUT = arg('out', null)

const entry = createRequire(join(process.env.PGLITE_DIR || '/tmp/pglite', 'package.json')).resolve('@electric-sql/pglite')
const { PGlite } = await import(pathToFileURL(entry).href)
const db = new PGlite()
const files = [join(ONLINE, 'tests', 'support', 'stub.sql'), ...readdirSync(ONLINE).filter((f) => /^\d+_.*\.sql$/.test(f)).sort().map((f) => join(ONLINE, f)),
  join(ONLINE, 'tests', 'online_tests.sql')]
for (const f of files) { try { await db.exec(readFileSync(f, 'utf8')) } catch (e) { console.error(f, e.message); process.exit(3) } }
const q = async (sql, p) => { try { return (await db.query(sql, p)).rows } catch (e) { console.error('SQL:', e.message, '\n', sql.slice(0, 160)); process.exit(3) } }
const one = async (sql, p) => (await q(sql, p))[0]
const fail = []
const check = (ok, msg) => { if (!ok) fail.push(msg); console.log(`${ok ? 'ok  ' : 'FALHA'} ${msg}`) }

// títulos antes da migração (precisam continuar lá)
const honorsBefore = (await one('select count(*)::int n from public.on_honors')).n
const historyBefore = (await one('select count(*)::int n from public.on_history')).n
const usersBefore = await q('select k.user_id,k.cash::bigint cash,(select count(*)::int from public.on_players p where p.club_id=k.id) roster from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status=\'live\' where k.user_id is not null order by k.user_id')

await q(`update public.on_config set tick_hooks='{}',join_instant=true`)
// os lances da partida são apagados na virada; guarda os da disputa de pênaltis para medir
await db.exec(`create table public.lab_games(fixture_id bigint,season_id smallint,comp text,div text,stage text,plan_h text,plan_a text,edge_h numeric,edge_a numeric,
  str_h numeric,str_a numeric,user_h boolean,user_a boolean,hg int,ag int,sp_goals int,fk_goals int,pen_goals int,pen_miss int,reds int,yellows int,marks int,
  bad_pen int,bad_ck int,bad_inherit int,subs int,bad_so int);
create table public.lab_viol(kind text,fixture_id bigint,player_id text,info text);
create function public.lab_game_keep() returns trigger language plpgsql as $f$
declare f public.on_fixtures;pm jsonb;pa jsonb;st jsonb:=new.state;
begin
 if new.status<>'finished' or old.status='finished' then return new;end if;
 select * into f from public.on_fixtures where id=new.fixture_id;
 pm:=public.on_side_profile(f.id,'h');pa:=public.on_side_profile(f.id,'a');
 insert into public.lab_games select f.id,f.season_id,f.comp,f.div,f.stage,st->'tactics'->'h'->>'plan',st->'tactics'->'a'->>'plan',
  public.on_plan_edge(st->'tactics'->'h'->>'plan',pm,pa),public.on_plan_edge(st->'tactics'->'a'->>'plan',pa,pm),
  (st->'strength'->>0)::numeric,(st->'strength'->>1)::numeric,
  (select user_id is not null from public.on_clubs where id=f.home),(select user_id is not null from public.on_clubs where id=f.away),
  (st->'score'->>0)::int,(st->'score'->>1)::int,
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='goal' and e.detail like 'escanteio%'),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='goal' and e.detail like '%falta%'),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='pen_goal'),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='pen_miss'),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind in('red','second_yellow')),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='yellow'),
  coalesce(jsonb_array_length(st->'tactics'->'h'->'marks'),0)+coalesce(jsonb_array_length(st->'tactics'->'a'->'marks'),0),
  -- pênalti no jogo: cobra o primeiro da ordem que estava em campo naquele minuto (se a ordem tem alguém em campo)
  (select count(*) from public.on_match_events e cross join lateral(
    select o.id from jsonb_array_elements_text(coalesce(st->'pen_order'->e.side::text,'[]')) with ordinality o(id,i)
    join public.on_match_players mp on mp.fixture_id=f.id and mp.player_id=o.id
    where coalesce(mp.entered_min,0)<=e.minute and coalesce(mp.left_min,999)>e.minute and mp.status<>'bench' order by o.i limit 1) x
   where e.fixture_id=f.id and e.kind in('pen_goal','pen_miss') and x.id<>e.player_id
    and not exists(select 1 from public.on_match_players q where q.fixture_id=f.id and coalesce(q.entered_min,0)>0
     and st->'pen_order'->e.side::text ? q.player_id)),
  -- gol de escanteio: assistência é do batedor daquele lado quando os dois batedores definidos estavam em campo
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='goal' and e.detail like 'escanteio%'
    and st->'ck_r'->>e.side::text is not null and st->'ck_l'->>e.side::text is not null
    and exists(select 1 from public.on_match_players mp where mp.fixture_id=f.id and mp.player_id=st->'ck_r'->>e.side::text and mp.status='on' and coalesce(mp.entered_min,0)<=e.minute)
    and exists(select 1 from public.on_match_players mp where mp.fixture_id=f.id and mp.player_id=st->'ck_l'->>e.side::text and mp.status='on' and coalesce(mp.entered_min,0)<=e.minute)
    and e.player2_id is distinct from st->'ck_r'->>e.side::text and e.player2_id is distinct from st->'ck_l'->>e.side::text),
  -- herança: ninguém que saiu substituído continua com função ou marcação
  (select count(*) from public.on_match_players mp where mp.fixture_id=f.id and mp.status='off' and (
    st->'pen_order'->mp.side::text ? mp.player_id or st->'ck_r'->>mp.side::text=mp.player_id or st->'ck_l'->>mp.side::text=mp.player_id
    or st->'fk_taker'->>mp.side::text=mp.player_id or st->'captain'->>mp.side::text=mp.player_id
    or exists(select 1 from jsonb_array_elements(coalesce(st->'tactics'->mp.side::text->'marks','[]')) m where m->>'by'=mp.player_id))),
  (select count(*) from public.on_match_events e where e.fixture_id=f.id and e.kind='sub'),
  -- disputa de pênaltis: o primeiro a bater de cada lado é o primeiro da ordem que terminou em campo
  (select count(*) from(values('h'),('a')) v(sd) cross join lateral(
    select (select e.player_id from public.on_match_events e where e.fixture_id=f.id and e.side=v.sd and e.kind in('so_goal','so_save','so_miss') order by e.seq limit 1) took,
     (select o.id from jsonb_array_elements_text(coalesce(st->'pen_order'->v.sd,'[]')) with ordinality o(id,i)
      join public.on_match_players mp on mp.fixture_id=f.id and mp.player_id=o.id and mp.status='on' order by o.i limit 1) want) x
   where x.took is not null and x.want is not null and x.took<>x.want);
 return new;
end $f$;
create trigger lab_game after update on public.on_matches for each row execute function public.lab_game_keep();
-- suspenso ou lesionado não pode entrar na partida
create function public.lab_play_keep() returns trigger language plpgsql as $f$
declare f public.on_fixtures;p public.on_players;
begin
 select * into f from public.on_fixtures where id=new.fixture_id;select * into p from public.on_players where id=new.player_id;
 if coalesce((p.susp->>f.comp)::int,0)>0 then insert into public.lab_viol values('suspenso jogou',f.id,p.id,p.susp::text);end if;
 if p.inj_until is not null and p.inj_until>(f.kickoff at time zone 'America/Sao_Paulo')::date and new.status in('on','bench') then
  insert into public.lab_viol values('lesionado relacionado',f.id,p.id,p.inj_until::text);end if;
 return new;
end $f$;
create trigger lab_play after insert on public.on_match_players for each row execute function public.lab_play_keep();
create table public.lab_so as select e.*,0::smallint season_id from public.on_match_events e where false;
create function public.lab_so_keep() returns trigger language plpgsql as $f$ begin
 if new.kind in('so_goal','so_save','so_miss') then insert into public.lab_so select new.*,(select season_id from public.on_fixtures where id=new.fixture_id);end if;return new;end $f$;
create trigger lab_so after insert on public.on_match_events for each row execute function public.lab_so_keep();`)
const START = '2026-12-01'
let t0 = Date.now()
const sid = (await one(`select public.on_series_bootstrap(date '${START}')::int s`)).s
console.log(`\nestrutura criada em ${Date.now() - t0} ms (temporada ${sid})`)

// ── estrutura ──
const divs = await q(`select div,count(*)::int n,count(user_id)::int users,count(*) filter(where sq='star')::int star,count(*) filter(where sq='base')::int base,count(*) filter(where sq='gen')::int gen
 from public.on_clubs where season_id=$1 group by div order by div`, [sid])
console.table(divs)
const size = Object.fromEntries(divs.map((d) => [d.div, d.n]))
check(size.A === 20 && size.B === 20 && size.C === 24 && size.D === 30, `tamanhos A20 B20 C24 D30: ${JSON.stringify(size)}`)
check(divs.find((d) => d.div === 'D').users === usersBefore.length, `técnicos na Série D: ${usersBefore.length}`)
const usersAfter = await q('select k.user_id,k.cash::bigint cash,(select count(*)::int from public.on_players p where p.club_id=k.id) roster from public.on_clubs k where k.season_id=$1 and k.user_id is not null order by k.user_id', [sid])
check(JSON.stringify(usersAfter) === JSON.stringify(usersBefore), 'técnicos mantêm elenco e caixa')
check((await one('select count(*)::int n from public.on_honors')).n === honorsBefore && (await one('select count(*)::int n from public.on_history')).n === historyBefore, 'títulos e histórico preservados')
const sq = await q(`select k.div,round(avg(p.ovr),1)::float ovr,count(*) filter(where p.tier='destaque')::int destaque,round(avg(p.pot-p.ovr),1)::float grow,count(*)::int players
 from public.on_clubs k join public.on_players p on p.club_id=k.id where k.season_id=$1 and k.user_id is null group by 1 order by 1`, [sid])
console.table(sq)
check(sq.every((r) => r.players >= 18 * size[r.div]), 'elencos de bot com 18+ jogadores')
check(sq.find((r) => r.div === 'A').destaque > 0 && sq.filter((r) => r.div !== 'A').every((r) => r.destaque === 0), 'cartas de destaque só na A')

// ── calendário ──
const fx = await q(`select comp,div,count(*)::int n from public.on_fixtures where season_id=$1 group by 1,2 order by 1,2`, [sid])
console.table(fx)
const nfx = (c, d) => fx.find((x) => x.comp === c && (x.div || null) === d)?.n
check(nfx('L', 'A') === 380 && nfx('L', 'B') === 380 && nfx('L', 'C') === 276 && nfx('L', 'D') === 420 && nfx('C', null) === 30,
  'jogos da 1ª fase: A 380, B 380, C 276, D 420, copa 30')
const hours = await one(`select min((kickoff at time zone 'America/Sao_Paulo')::time)::text lo,max((kickoff at time zone 'America/Sao_Paulo')::time)::text hi
 from public.on_fixtures where season_id=$1`, [sid])
check(hours.lo >= '08:00:00' && hours.hi <= '21:30:00', `pontapés entre 08:00 e 21:30 (${hours.lo} a ${hours.hi})`)
const gapHours = await one(`select count(*)::int n from public.on_fixtures where season_id=$1 and (kickoff at time zone 'America/Sao_Paulo')::time>='17:00' and (kickoff at time zone 'America/Sao_Paulo')::time<'18:40'`, [sid])
check(gapHours.n === 0, 'nenhum jogo entre 17:00 e 18:40')
const dupK = await one(`select count(*)::int n from(select kickoff from public.on_fixtures where season_id=$1 group by 1 having count(*)>1) x`, [sid])
check(dupK.n === 0, 'cada jogo num horário diferente')
const rest = await one(`select min(b.kickoff-a.kickoff)::text mn,avg(b.kickoff-a.kickoff)::text av from public.on_fixtures a join public.on_fixtures b on b.season_id=a.season_id and b.slot=a.slot+1 and a.slot%2=0
 and (b.home in(a.home,a.away) or b.away in(a.home,a.away)) where a.season_id=$1`, [sid])
check(rest.mn >= '03:00:00', `descanso entre os jogos do dia: mínimo ${rest.mn}, média ${rest.av}`)
const botMax = await one(`select count(*)::int n from public.on_players p join public.on_clubs k on k.id=p.club_id where k.season_id=$1 and k.user_id is null and p.ovr<greatest(p.pot,p.level)`, [sid])
check(botMax.n === 0, 'jogadores dos bots no nível máximo')
const twice = await one(`select count(*)::int n from(select club,slot from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(club) where season_id=$1 group by 1,2 having count(*)>1) x`, [sid])
check(twice.n === 0, 'nenhum clube joga duas vezes no mesmo turno')
const perDay = await one(`select max(n)::int mx from(select club,(kickoff at time zone 'America/Sao_Paulo')::date d,count(*) n from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(club) where season_id=$1 group by 1,2) x`, [sid])
check(perDay.mx <= 2, `no máximo 2 jogos por clube por dia (${perDay.mx})`)
const ampm = await one(`select bool_and((slot%2=0)=((kickoff at time zone 'America/Sao_Paulo')::time<'14:00')) ok from public.on_fixtures where season_id=$1`, [sid])
check(ampm.ok, 'turnos pares de manhã, ímpares à tarde')

// ── temporada pelo relógio ──
const report = { seasons: [] }
for (let season = 0; season < SEASONS; season++) {
  const cur = (await one(`select id::int from public.on_seasons where status='live'`)).id
  const startT = Date.now()
  let ticks = 0, worst = 0
  // anda de turno em turno: no último pontapé do turno, 101 e 202 minutos depois (todos os jogos sem ninguém assistindo)
  const plans = (await one('select public.on_plans() p')).p
  for (let guard = 0; guard < 400; guard++) {
    const nx = await one(`select slot,max(kickoff) k from public.on_fixtures where season_id=$1 and status<>'done'
      and slot=(select min(slot) from public.on_fixtures where season_id=$1 and status<>'done') group by slot`, [cur])
    if (!nx) break
    // técnicos: estilo sorteado, funções e às vezes uma marcação individual no melhor atacante do adversário
    const mine = await q(`select f.id,k.id club,case when f.home=k.id then f.away else f.home end opp from public.on_fixtures f join public.on_clubs k on k.id in(f.home,f.away)
      where f.season_id=$1 and f.slot=$2 and k.user_id is not null and f.status<>'done'`, [cur, nx.slot])
    for (const m of mine) {
      const xi = await q(`select p.id,p.pos,p.fin,p.ovr from public.on_lineups l,jsonb_each_text(l.slots) e join lateral(select x.id,x.pos,x.ovr,(public.on_comp(x.id,x.pos,x.level,x.g))[6] fin from public.on_players x where x.id=e.value) p on true where l.club_id=$1`, [m.club])
      const field = xi.filter((p) => p.pos !== 'GOL')
      const pen = [...field].sort((a, b) => b.fin - a.fin).slice(0, 5).map((p) => p.id)
      const pick = () => field[Math.floor(Math.random() * field.length)]?.id
      const roles = { captain: pick(), pen, fk: pen[0], ck_r: pick(), ck_l: pick() }
      const target = (await one(`select p.id from public.on_lineups l,jsonb_each_text(l.slots) e join public.on_players p on p.id=e.value where l.club_id=$1 and p.pos<>'GOL' order by p.ovr desc limit 1`, [m.opp]))?.id
      const marks = target && Math.random() < 0.5 ? [{ by: pick(), on: target }] : []
      const t = { plan: plans[Math.floor(Math.random() * plans.length)], marks, manage: ['normal', 'keep', 'chase'][Math.floor(Math.random() * 3)] }
      await q(`update public.on_lineups set tactics=public.on_tactics_clean($2::jsonb),roles=$3::jsonb where club_id=$1`, [m.club, JSON.stringify(t), JSON.stringify(roles)])
    }
    for (const off of [0, 101, 202]) {
      const t = Date.now()
      await q(`select public.on_tick($1::timestamptz+make_interval(mins=>$2))`, [nx.k, off])
      worst = Math.max(worst, Date.now() - t)
      ticks++
    }
    // recuperação da condição entre turnos (o tick horário depende do relógio do servidor)
    await q(`update public.on_players p set cond=least(100,p.cond+20) from public.on_clubs k where k.id=p.club_id and k.season_id=$1`, [cur])
    if ((await one(`select status from public.on_seasons where id=$1`, [cur])).status !== 'live') break
    if (guard % 10 === 9) console.log(`  turno ${guard + 1}: ${(await one(`select count(*) filter(where status='done')::int d,count(*)::int n from public.on_fixtures where season_id=$1`, [cur])).d} jogos encerrados, ${Math.round((Date.now() - startT) / 1000)} s`)
  }
  const s = await one(`select status from public.on_seasons where id=$1`, [cur])
  console.log(`\ntemporada ${cur}: ${ticks} ticks em ${Math.round((Date.now() - startT) / 1000)} s (pior tick ${worst} ms), status ${s.status}`)
  check(s.status === 'closed', `temporada ${cur} terminou`)
  const fx2 = await q(`select comp,div,stage,count(*)::int n from public.on_fixtures where season_id=$1 and (stage is not null or tphase=2) group by 1,2,3 order by 1,2,3`, [cur])
  console.table(fx2)
  const res = await q(`select div,result,count(*)::int n from public.on_history where season_id=$1 group by 1,2 order by 1,2`, [cur])
  console.table(res)
  const cnt = (d, r) => res.find((x) => x.div === d && x.result === r)?.n || 0
  check(cnt('A', 'relegated') === 4 && cnt('B', 'relegated') === 4 && cnt('C', 'relegated') === 4, 'caem 4 da A, da B e da C')
  check(cnt('B', 'champion') + cnt('B', 'promoted') === 4 && cnt('C', 'champion') + cnt('C', 'promoted') === 4 && cnt('D', 'champion') + cnt('D', 'promoted') === 4,
    'sobem 4 da B, da C e da D')
  check((await one(`select count(*)::int n from public.on_history where season_id=$1 and cup='champion'`, [cur])).n === 1, 'copa tem um campeão')
  const so = await one(`select count(distinct fixture_id)::int games,count(*) filter(where kind='so_goal')::int goals,count(*) filter(where kind='so_save')::int saves,count(*) filter(where kind='so_miss')::int misses
   from public.lab_so e where e.season_id=$1`, [cur])
  console.log('pênaltis:', so, 'conversão', (so.goals / Math.max(1, so.goals + so.saves + so.misses)).toFixed(3))
  check(so.games === (await one(`select count(*)::int n from public.on_fixtures where season_id=$1 and pens is not null`, [cur])).n, 'toda disputa de pênaltis tem os lances registrados')
  const goals = await one(`select round(avg(hg+ag),2)::float g,round(avg((hg>ag)::int),3)::float home from public.on_fixtures where season_id=$1`, [cur])
  const cards = await one(`select count(*) filter(where (susp->>'L')::int>0 or (susp->>'C')::int>0)::int susp from public.on_players`)
  const champs = await q(`select h.div,h.name,h.pts from public.on_history h where h.season_id=$1 and h.result='champion' order by h.div`, [cur])
  console.table(champs)
  const nxt = await one(`select id::int,starts_on::text from public.on_seasons where status='live'`)
  const divs2 = await q(`select div,count(*)::int n from public.on_clubs where season_id=$1 group by 1 order by 1`, [nxt.id])
  check(JSON.stringify(divs2.map((d) => d.n)) === '[20,20,24,30]', `nova temporada ${nxt.id} (${nxt.starts_on}) com 20/20/24/30`)
  const moved = await one(`select count(*)::int n from public.on_clubs k join public.on_history h on h.club_id=k.id and h.season_id=$1 where k.season_id=$2 and k.div<>h.div`, [cur, nxt.id])
  check(moved.n === 24, `24 clubes mudaram de série (${moved.n})`)
  const wrongSq = await one(`select count(*)::int n from public.on_clubs where season_id=$1 and user_id is null and real_key is not null
    and sq<>case when div='A' and real_key in(select key from public.on_real_clubs where sim_club is not null) then 'star' when div='B' and real_key in(select key from public.on_real_clubs where sim_club is not null) then 'base' when real_key in(select club_key from public.on_lower_players) then 'real' else 'gen' end`, [nxt.id])
  check(wrongSq.n === 0, 'bots trocaram o tipo de elenco ao mudar de série')
  check((await one(`select count(*)::int n from public.on_fixtures where season_id=$1 and comp='C'`, [nxt.id])).n === 30, 'copa da nova temporada sorteada')
  const g = await one(`select count(*)::int n,sum(bad_so)::int bad_so,count(*) filter(where stage is not null or comp='C')::int ko,sum(bad_pen)::int bad_pen,sum(bad_ck)::int bad_ck,sum(bad_inherit)::int bad_inherit,sum(subs)::int subs,
    round(avg(hg+ag),2)::float goals,round(avg(sp_goals+fk_goals),2)::float setpiece,round(avg(pen_goals+pen_miss),3)::float pens,round(avg(reds),3)::float reds,round(avg(yellows),2)::float yellows
    from public.lab_games where season_id=$1`, [cur])
  console.log('partidas conferidas:', g)
  check(g.bad_pen === 0, 'pênalti no jogo cobrado pelo primeiro da ordem em campo')
  check(g.bad_so === 0, 'disputa de pênaltis começa pelo primeiro da ordem em campo')
  check(g.bad_ck === 0, 'gol de escanteio com assistência do batedor do lado')
  check(g.bad_inherit === 0, 'quem sai substituído passa função e marcação para quem entra')
  const viol = await q(`select kind,count(*)::int n from public.lab_viol v join public.on_fixtures f on f.id=v.fixture_id where f.season_id=$1 group by 1`, [cur])
  check(viol.length === 0, `suspenso/lesionado fora de campo ${JSON.stringify(viol)}`)
  report.seasons.push({ season: cur, ticks, worstTick: worst, goals, cards, fixtures: fx2, results: res, champs, checks: g })
  console.log('gols por jogo', goals, 'jogadores ainda suspensos', cards.susp)
}

// ── estilos nas temporadas: pontos de cada estilo (contra qualquer um), confronto e aderência ──
const styleRows = await q(`with r as(
  select plan_h plan,plan_a opp,edge_h edge,str_h-str_a gap,case when hg>ag then 3 when hg=ag then 1 else 0 end pts,hg gf,ag ga from public.lab_games
  union all select plan_a,plan_h,edge_a,str_a-str_h,case when ag>hg then 3 when hg=ag then 1 else 0 end,ag,hg from public.lab_games)
 select plan,count(*)::int n,round(avg(pts),3)::float ppg,round(avg(gf),2)::float gf,round(avg(ga),2)::float ga,round(avg(gap),2)::float gap from r group by plan order by plan`)
console.table(styleRows)
const vsRows = await q(`with r as(
  select plan_h plan,plan_a opp,str_h-str_a gap,case when hg>ag then 3 when hg=ag then 1 else 0 end pts from public.lab_games
  union all select plan_a,plan_h,str_a-str_h,case when ag>hg then 3 when hg=ag then 1 else 0 end from public.lab_games)
 select public.on_plan_vs(plan,opp) vs,count(*)::int n,round(avg(pts),3)::float ppg,round(avg(gap),2)::float gap from r group by 1 order by 1`)
console.log('pontos por jogo conforme o confronto de estilos (−1 desvantagem, +1 vantagem):'); console.table(vsRows)
const edgeRows = await q(`with r as(
  select edge_h edge,str_h-str_a gap,case when hg>ag then 3 when hg=ag then 1 else 0 end pts from public.lab_games
  union all select edge_a,str_a-str_h,case when ag>hg then 3 when hg=ag then 1 else 0 end from public.lab_games)
 select case when edge<-0.4 then 'baixo' when edge<0.4 then 'médio' else 'alto' end enc,count(*)::int n,round(avg(pts),3)::float ppg,round(avg(gap),2)::float gap from r group by 1 order by 1`)
console.log('pontos por jogo conforme a aderência do elenco ao estilo:'); console.table(edgeRows)
report.styles = { byPlan: styleRows, byVs: vsRows, byEdge: edgeRows }

// suspensão: amostra de quem levou cartão
const sus = await one(`select count(*)::int n from public.on_players where ylw<>'{}' or susp<>'{}'`)
console.log('jogadores com cartões ou suspensão registrados:', sus.n)

if (OUT) writeFileSync(OUT, JSON.stringify(report, null, 1))
console.log(fail.length ? `\n${fail.length} FALHA(S)` : '\nTudo certo.')
process.exit(fail.length ? 1 : 0)
