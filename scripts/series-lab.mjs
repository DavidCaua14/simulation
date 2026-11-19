// LABORATÓRIO DAS SÉRIES (fase 35) — cria a estrutura A/B/C/D, joga temporadas inteiras pelo relógio (on_tick) e confere
// as regras. Nada em produção: PGlite com o catálogo fictício dos testes.
//
// Uso: PGLITE_DIR=<pasta com @electric-sql/pglite> node scripts/series-lab.mjs [--seasons 1] [--out r.json]
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
await db.exec(`create table public.lab_so as select e.*,0::smallint season_id from public.on_match_events e where false;
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
check(hours.lo >= '08:00:00' && hours.hi <= '16:00:00', `pontapés entre 08:00 e 16:00 (${hours.lo} a ${hours.hi})`)
const twice = await one(`select count(*)::int n from(select club,slot from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(club) where season_id=$1 group by 1,2 having count(*)>1) x`, [sid])
check(twice.n === 0, 'nenhum clube joga duas vezes no mesmo turno')
const perDay = await one(`select max(n)::int mx from(select club,(kickoff at time zone 'America/Sao_Paulo')::date d,count(*) n from public.on_fixtures f cross join lateral(values(f.home),(f.away)) v(club) where season_id=$1 group by 1,2) x`, [sid])
check(perDay.mx <= 2, `no máximo 2 jogos por clube por dia (${perDay.mx})`)
const ampm = await one(`select bool_and(slot%2=0)=bool_and((kickoff at time zone 'America/Sao_Paulo')::time<'12:00') ok from public.on_fixtures where season_id=$1`, [sid])
check(ampm.ok, 'turnos pares de manhã, ímpares à tarde')

// ── temporada pelo relógio ──
const report = { seasons: [] }
for (let season = 0; season < SEASONS; season++) {
  const cur = (await one(`select id::int from public.on_seasons where status='live'`)).id
  const startT = Date.now()
  let ticks = 0, worst = 0
  // anda de turno em turno: pontapé, e 100 minutos depois (fim de todos os jogos sem ninguém assistindo)
  for (let guard = 0; guard < 400; guard++) {
    const nx = await one(`select min(kickoff) k from public.on_fixtures where season_id=$1 and status<>'done'`, [cur])
    if (!nx.k) break
    for (const off of [0, 101]) {
      const t = Date.now()
      await q(`select public.on_tick($1::timestamptz+make_interval(mins=>$2))`, [nx.k, off])
      worst = Math.max(worst, Date.now() - t)
      ticks++
    }
    // recuperação da condição entre turnos (o tick horário depende do relógio do servidor)
    await q(`update public.on_players p set cond=least(100,p.cond+20) from public.on_clubs k where k.id=p.club_id and k.season_id=$1`, [cur])
    if ((await one(`select status from public.on_seasons where id=$1`, [cur])).status !== 'live') break
    if (guard % 5 === 4) console.log(`  turno ${guard + 1}: ${(await one(`select count(*) filter(where status='done')::int d,count(*)::int n from public.on_fixtures where season_id=$1`, [cur])).d} jogos encerrados, ${Math.round((Date.now() - startT) / 1000)} s`)
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
    and sq<>case when div='A' and real_key in(select key from public.on_real_clubs where sim_club is not null) then 'star' when div='B' and real_key in(select key from public.on_real_clubs where sim_club is not null) then 'base' else 'gen' end`, [nxt.id])
  check(wrongSq.n === 0, 'bots trocaram o tipo de elenco ao mudar de série')
  check((await one(`select count(*)::int n from public.on_fixtures where season_id=$1 and comp='C'`, [nxt.id])).n === 30, 'copa da nova temporada sorteada')
  report.seasons.push({ season: cur, ticks, worstTick: worst, goals, cards, fixtures: fx2, results: res, champs })
  console.log('gols por jogo', goals, 'jogadores ainda suspensos', cards.susp)
}

// suspensão: amostra de quem levou cartão
const sus = await one(`select count(*)::int n from public.on_players where ylw<>'{}' or susp<>'{}'`)
console.log('jogadores com cartões ou suspensão registrados:', sus.n)

if (OUT) writeFileSync(OUT, JSON.stringify(report, null, 1))
console.log(fail.length ? `\n${fail.length} FALHA(S)` : '\nTudo certo.')
process.exit(fail.length ? 1 : 0)
