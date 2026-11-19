// LABORATÓRIO DO MODO ONLINE — simula temporadas inteiras com o motor real das partidas (PGlite, nada em produção).
//
// Uso:
//   PGLITE_DIR=<pasta com @electric-sql/pglite> node scripts/online-lab.mjs [opções]
//     --seasons N      temporadas de liga (12 clubes, 22 rodadas). Padrão 10.
//     --duels N        jogos por confronto na matriz de táticas (0 desliga). Padrão 0.
//     --extra a.sql    SQL aplicado depois das fases (para testar uma mudança de motor antes de virar fase).
//     --out r.json     grava o resultado bruto.
//     --label texto    nome da rodada no relatório.
//     --upto NN        só aplica as fases até o arquivo NN (ex.: 32 = motor antes dos planos de jogo).
//     --arrows N       condição: N jogos por seta (1 a 5) do time A contra o mesmo elenco com seta amarela.
//     --styles N       estilos: N jogos por plano com estilos que combinam com o plano contra o mesmo elenco sem estilo.
//     --marks N        marcação individual: N jogos com o melhor defensor marcando o melhor atacante rival, e N sem marcação.
//
// Cada temporada: elencos gerados como no online (19 genéricos + 3 craques), força espalhada de -5 a +5 por clube,
// e um "técnico" por clube:
//   bot      — o clube é bot (escalação e tática automáticas, ajustes da IA durante o jogo);
//   ativo    — usuário que escala o melhor time disponível e escolhe a tática pela diferença de força;
//   passivo  — usuário que escalou uma vez no começo e nunca mais mexeu (tática padrão);
//   aleatorio— usuário que escala bem mas escolhe a tática ao acaso.
// Entre as rodadas a condição recupera +55 (departamento médico nível 1 a 2 em 7 horas), lesionado fica 2 rodadas fora.
import { readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const ROOT = new URL('..', import.meta.url).pathname
const ONLINE = join(ROOT, 'supabase', 'online')
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d }
const SEASONS = +arg('seasons', 10), DUELS = +arg('duels', 0), ARROWS = +arg('arrows', 0), STYLES = +arg('styles', 0), MARKS = +arg('marks', 0), EXTRA = arg('extra', null), OUT = arg('out', null)
const LABEL = arg('label', EXTRA ? EXTRA.split('/').pop() : 'motor atual')
const PROFILES = ['bot', 'ativo', 'passivo', 'aleatorio']

const entry = createRequire(join(process.env.PGLITE_DIR || '/tmp/pglite', 'package.json')).resolve('@electric-sql/pglite')
const { PGlite } = await import(pathToFileURL(entry).href)
const db = new PGlite()
const UPTO = +arg('upto', 999) // --upto 32: motor como estava até a fase do arquivo 32 (para comparar antes e depois)
const files = [join(ONLINE, 'tests', 'support', 'stub.sql'), ...readdirSync(ONLINE).filter((f) => /^\d+_.*\.sql$/.test(f) && +f.split('_')[0] <= UPTO).sort().map((f) => join(ONLINE, f))]
for (const f of files) await db.exec(readFileSync(f, 'utf8'))
if (EXTRA) await db.exec(readFileSync(EXTRA, 'utf8'))

await db.exec(`
alter table public.on_players add column if not exists lab_back smallint;
update public.on_config set join_instant=false,finish_hooks='{}',tick_hooks='{}';
-- joga uma partida inteira sem ninguém assistindo; devolve placar, táticas e números do jogo
create or replace function public.lab_play(p_fx bigint) returns jsonb language plpgsql as $$
declare f public.on_fixtures;m public.on_matches;x jsonb;
begin
 select * into f from public.on_fixtures where id=p_fx;
 perform public.on_match_open(f);
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 perform public.on_advance(f.id,f.kickoff+interval '1 day',null);
 select * into m from public.on_matches where fixture_id=p_fx;
 select jsonb_build_object('shots',jsonb_build_array(sum(shots) filter(where side='h'),sum(shots) filter(where side='a')),
  'sot',jsonb_build_array(sum(sot) filter(where side='h'),sum(sot) filter(where side='a')),
  'reds',sum(red),'inj',count(*) filter(where injured)) into x
 from public.on_match_players where fixture_id=p_fx;
 return jsonb_build_object('hg',(m.state->'score'->>0)::int,'ag',(m.state->'score'->>1)::int,'tac',m.state->'tactics',
  'poss',m.state->'poss','str',m.state->'strength')||x;
end $$;
-- força do clube: média da nota dos 11 da escalação automática (com todos descansados)
create or replace function public.lab_strength(p_club int) returns numeric language sql as $$
 select round(avg(p.ovr),2) from public.on_lineups l,jsonb_each_text(l.slots) s join public.on_players p on p.id=s.value where l.club_id=p_club $$;
`)

const rnd = (a) => a[Math.floor(Math.random() * a.length)]
const HAS_PLANS = (await db.query(`select to_regprocedure('public.on_ai_plan(int,int,numeric,boolean)') is not null ok`)).rows[0].ok
// estilos de jogo do banco (fase 39: posse, contra, contra_longo, pontas, direto, sobrecarga)
const PLAN_IDS = HAS_PLANS ? (await db.query('select public.on_plans() p')).rows[0].p : []
const NEUTRAL = PLAN_IDS.includes('equilibrado') ? 'equilibrado' : PLAN_IDS[0]
// tática "de quem sabe": a mesma regra da IA (pela diferença de força e, com planos, pela aderência do elenco)
const smartTactics = async (c, o, diff, home) => HAS_PLANS
  ? (await db.query('select public.on_ai_plan($1,$2,$3,$4) t', [c, o, diff, home])).rows[0].t
  : (await db.query('select public.mgr_ai_tactics($1,$2) t', [diff, home])).rows[0].t
// combinação qualquer das opções da tela
const randomTactics = () => HAS_PLANS ? ({
  plan: rnd(PLAN_IDS),
  tackling: rnd(['light', 'balanced', 'heavy']),
  manage: rnd(['normal', 'keep', 'chase']),
}) : ({
  style: rnd(['defensive', 'neutral', 'attacking', 'counter']),
  ...rnd([{ passing: 'short', tempo: 'slow' }, { passing: 'mixed', tempo: 'normal' }, { passing: 'long', tempo: 'fast' }]),
  marking: rnd(['low', 'medium', 'high']),
  tackling: rnd(['light', 'balanced', 'heavy']),
  ...rnd([{ attack: 'central', crossing: 'rarely' }, { attack: 'mixed', crossing: 'mixed' }, { attack: 'both', crossing: 'byline' }]),
  manage: rnd(['normal', 'chase']),
})

const games = [] // {season, round, h, a, ph, pa, sh, sa, hg, ag, ...}
const seasons = []
const t0 = Date.now()
for (let s = 0; s < SEASONS; s++) {
  await db.exec(`update public.on_seasons set status='closed' where status='live';`)
  const sid = (await db.query(`select public.on_season_bootstrap('{}'::uuid[],date '2020-01-06') s`)).rows[0].s
  const clubs = (await db.query('select id from public.on_clubs where season_id=$1 order by id', [sid])).rows.map((r) => r.id)
  // perfis: 3 de cada, em assentos sorteados; força espalhada
  const prof = {}
  const deck = PROFILES.flatMap((p) => [p, p, p]).sort(() => Math.random() - 0.5)
  for (const [i, c] of clubs.entries()) {
    prof[c] = deck[i]
    const delta = Math.round((Math.random() * 10 - 5) * 10) / 10
    await db.query(`update public.on_players set level=least(95,level+round($2::numeric)),ovr=least(95,ovr+$2::numeric) where club_id=$1`, [c, delta])
    if (deck[i] !== 'bot') await db.query(`update public.on_clubs set user_id=gen_random_uuid(),draft_step=3 where id=$1`, [c])
    await db.query('select public.on_auto_lineup($1)', [c])
  }
  const str = {}
  for (const c of clubs) str[c] = +(await db.query('select public.lab_strength($1) s', [c])).rows[0].s
  const fx = (await db.query(`select id,round,home,away from public.on_fixtures where season_id=$1 and comp='L' order by round,id`, [sid])).rows
  const rounds = [...new Set(fx.map((f) => f.round))]
  for (const r of rounds) {
    if (r > rounds[0]) {
      await db.query(`update public.on_players p set cond=least(100,cond+55) from public.on_clubs k where k.id=p.club_id and k.season_id=$1`, [sid])
      await db.query(`update public.on_players p set inj_until=null,lab_back=null from public.on_clubs k where k.id=p.club_id and k.season_id=$1 and lab_back<=$2`, [sid, r])
    }
    for (const f of fx.filter((x) => x.round === r)) {
      for (const [c, o, home] of [[f.home, f.away, true], [f.away, f.home, false]]) {
        const p = prof[c]
        if (p === 'ativo') {
          await db.query('select public.on_auto_lineup($1)', [c])
          // com planos: escolhe pelo elenco e pela força (o plano do adversário não é conhecido)
          const t = await smartTactics(c, o, str[c] - str[o], home)
          await db.query('update public.on_lineups set tactics=$2 where club_id=$1', [c, JSON.stringify(t)])
        } else if (p === 'aleatorio') {
          await db.query('select public.on_auto_lineup($1)', [c])
          await db.query('update public.on_lineups set tactics=$2 where club_id=$1', [c, JSON.stringify(randomTactics())])
        } else if (p === 'passivo' && r === rounds[0]) {
          await db.query(`update public.on_lineups set tactics='{}' where club_id=$1`, [c])
        }
      }
      const g = (await db.query('select public.lab_play($1) g', [f.id])).rows[0].g
      games.push({ season: s, round: r, h: f.home, a: f.away, ph: prof[f.home], pa: prof[f.away], sh: str[f.home], sa: str[f.away], ...g })
    }
    await db.query(`update public.on_players p set lab_back=$2+2,inj_until=date '2999-01-01' from public.on_clubs k
      where k.id=p.club_id and k.season_id=$1 and p.inj_until is not null and p.lab_back is null`, [sid, r])
  }
  const table = (await db.query(`select club_id,pts,gf-ga gd,gf from public.on_table where season_id=$1 order by pts desc,gf-ga desc,gf desc`, [sid])).rows
  const byStr = [...clubs].sort((x, y) => str[y] - str[x])
  seasons.push({ table: table.map((t) => ({ club: t.club_id, pts: t.pts, prof: prof[t.club_id], str: str[t.club_id], strRank: byStr.indexOf(t.club_id) + 1 })) })
  process.stderr.write(`temporada ${s + 1}/${SEASONS} (${((Date.now() - t0) / 1000).toFixed(0)} s)\n`)
}

// ── Matriz de táticas: dois clubes de força igual, a mesma partida repetida com o mando alternado ──
const PLANS = HAS_PLANS ? Object.fromEntries(PLAN_IDS.map((p) => [p, { plan: p }])) : {
  equilibrado: { style: 'neutral' },
  defensivo: { style: 'defensive', marking: 'low' },
  ofensivo: { style: 'attacking' },
  contra: { style: 'counter' },
  toque: { style: 'neutral', passing: 'short', tempo: 'slow' },
  direto: { style: 'neutral', passing: 'long', tempo: 'fast' },
  pressao: { style: 'neutral', marking: 'high' },
  pontas: { style: 'neutral', attack: 'both', crossing: 'byline' },
}
const duels = {}, arrowsTest = {}, stylesTest = {}, marksTest = {}
const HAS_STYLES = (await db.query(`select to_regprocedure('public.on_arrow_next(char,int,numeric,boolean,float8)') is not null ok`)).rows[0].ok
if (DUELS > 0 || ARROWS > 0 || STYLES > 0 || MARKS > 0) {
  await db.exec(`update public.on_seasons set status='closed' where status='live';`)
  const sid = (await db.query(`select public.on_season_bootstrap('{}'::uuid[],date '2020-01-06') s`)).rows[0].s
  const [A, B] = (await db.query('select id from public.on_clubs where season_id=$1 order by id limit 2', [sid])).rows.map((r) => r.id)
  // B recebe uma cópia exata do elenco de A: só a tática muda
  await db.query('delete from public.on_players where club_id=$1', [B])
  await db.query(`insert into public.on_players(id,club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,agg,disc,star,sec,g)
    select id||'b',$2,name,pos,age,level,pot,ovr,number,wage,contract_end,agg,disc,star,sec,g from public.on_players where club_id=$1`, [A, B])
  if (HAS_STYLES) await db.query(`update public.on_players b set style_off=a.style_off,style_def=a.style_def,ai_styles=a.ai_styles,form=a.form
    from public.on_players a where a.club_id=$1 and b.club_id=$2 and b.id=a.id||'b'`, [A, B])
  await db.query(`update public.on_clubs set user_id=gen_random_uuid(),draft_step=3 where id in($1,$2)`, [A, B])
  await db.exec(`create or replace function public.lab_duel(a int,b int,ta jsonb,tb jsonb,k int,arr int default 3) returns int[] language plpgsql as $$
   declare f public.on_fixtures;h int;w int;g jsonb;
   begin
    h:=case when k%2=0 then a else b end;w:=case when k%2=0 then b else a end;
    select * into f from public.on_fixtures where comp='L' and home=h and away=w order by id limit 1;
    delete from public.on_matches where fixture_id=f.id;
    update public.on_fixtures set status='sched',hg=null,ag=null,pens=null where id=f.id;
    update public.on_players set cond=100,rhythm=80,inj_until=null,susp_round=null,yellows=0 where club_id in(a,b);
    ${HAS_STYLES ? "update public.on_players set arrow=case when club_id=a then arr else 3 end where club_id in(a,b);" : ''}
    perform public.on_auto_lineup(a,'4-3-3');perform public.on_auto_lineup(b,'4-3-3');
    update public.on_lineups set tactics=ta where club_id=a;update public.on_lineups set tactics=tb where club_id=b;
    g:=public.lab_play(f.id);
    return case when h=a then array[(g->>'hg')::int,(g->>'ag')::int] else array[(g->>'ag')::int,(g->>'hg')::int] end;
   end $$;`)
  const names = DUELS > 0 ? Object.keys(PLANS) : []
  for (const x of names) for (const y of names) {
    if (x >= y && x !== y) continue
    let w = 0, d = 0, l = 0, gf = 0, ga = 0
    for (let k = 0; k < DUELS; k++) {
      const r = (await db.query('select public.lab_duel($1,$2,$3,$4,$5) r', [A, B, JSON.stringify(PLANS[x]), JSON.stringify(PLANS[y]), k])).rows[0].r
      gf += r[0]; ga += r[1]; if (r[0] > r[1]) w++; else if (r[0] === r[1]) d++; else l++
    }
    duels[`${x}|${y}`] = { w, d, l, gf, ga, n: DUELS }
    process.stderr.write(`duelo ${x} x ${y}: ${w}-${d}-${l}\n`)
  }
  const play = async (n, ta, tb, arr = 3) => {
    let w = 0, d = 0, l = 0, gf = 0, ga = 0
    for (let k = 0; k < n; k++) {
      const r = (await db.query('select public.lab_duel($1,$2,$3,$4,$5,$6) r', [A, B, JSON.stringify(ta), JSON.stringify(tb), k, arr])).rows[0].r
      gf += r[0]; ga += r[1]; if (r[0] > r[1]) w++; else if (r[0] === r[1]) d++; else l++
    }
    return { w, d, l, gf, ga, n }
  }
  // condição: o time A com cada seta contra o mesmo elenco com seta amarela
  if (ARROWS > 0 && HAS_STYLES) for (const a of [1, 2, 3, 4, 5]) {
    arrowsTest[a] = await play(ARROWS, { plan: NEUTRAL }, { plan: NEUTRAL }, a)
    process.stderr.write(`seta ${a}: ${arrowsTest[a].w}-${arrowsTest[a].d}-${arrowsTest[a].l}\n`)
  }
  // estilos: o time A joga o plano com estilos que combinam (melhor estilo da posição para o plano) contra o mesmo
  // plano sem estilo nenhum; o adversário é o mesmo elenco, equilibrado e sem estilo
  if (STYLES > 0 && HAS_STYLES) {
    const save = (await db.query('select id,style_off,style_def,ai_styles from public.on_players where club_id in($1,$2)', [A, B])).rows
    await db.query(`update public.on_players set style_off=null,style_def=null,ai_styles='{}' where club_id=$1`, [B])
    for (const plan of PLAN_IDS.filter((p) => p !== 'equilibrado')) {
      await db.query(`update public.on_players p set
        style_off=(select s.code from public.on_styles s where s.kind='off' and p.pos=any(s.pos) and $2=any(s.plans) order by s.code limit 1),
        style_def=(select s.code from public.on_styles s where s.kind='def' and p.pos=any(s.pos) and $2=any(s.plans) order by s.code limit 1),
        ai_styles='{}' where club_id=$1`, [A, plan])
      const withS = await play(STYLES, { plan }, { plan })
      await db.query(`update public.on_players set style_off=null,style_def=null,ai_styles='{}' where club_id=$1`, [A])
      const noS = await play(STYLES, { plan }, { plan })
      stylesTest[plan] = { with: withS, without: noS }
      process.stderr.write(`estilos ${plan}: com ${withS.w}-${withS.d}-${withS.l} sem ${noS.w}-${noS.d}-${noS.l}\n`)
    }
    for (const r of save) await db.query('update public.on_players set style_off=$2,style_def=$3,ai_styles=$4 where id=$1', [r.id, r.style_off, r.style_def, r.ai_styles])
  }
  // marcação individual: o melhor defensor de A (zagueiro ou volante) marca o atacante de B que mais finaliza; gols do alvo
  if (MARKS > 0) {
    const by = (await db.query(`select id from public.on_players where club_id=$1 and pos in('ZAG','VOL') order by ovr desc limit 1`, [A])).rows[0].id
    const on = (await db.query(`select id from public.on_players where club_id=$1 and pos='ATA' order by ovr desc limit 1`, [B])).rows[0].id
    const goalsOf = async () => (await db.query(`select coalesce(sum(goals),0)::int g,coalesce(sum(shots),0)::int s from public.lab_marks`)).rows[0]
    await db.exec(`create table if not exists public.lab_marks(goals int,shots int);
     create or replace function public.lab_marks_keep() returns trigger language plpgsql as $f$ begin
      if new.status='finished' and old.status<>'finished' then
       insert into public.lab_marks select goals,shots from public.on_match_players where fixture_id=new.fixture_id and player_id='${on}';
      end if;return new;end $f$;
     drop trigger if exists lab_marks on public.on_matches;
     create trigger lab_marks after update on public.on_matches for each row execute function public.lab_marks_keep();`)
    for (const [k, ta] of [['sem', { plan: 'posse' }], ['com', { plan: 'posse', marks: [{ by, on }] }]]) {
      await db.exec('delete from public.lab_marks')
      const r = await play(MARKS, ta, { plan: 'posse' })
      marksTest[k] = { ...r, target: await goalsOf() }
      process.stderr.write(`marcação ${k}: ${r.w}-${r.d}-${r.l}, alvo ${JSON.stringify(marksTest[k].target)}\n`)
    }
  }
}

// ── Resumo ──
const pct = (a, b) => (b ? Math.round((1000 * a) / b) / 10 : 0)
const N = games.length
const sum = (f) => games.reduce((a, g) => a + f(g), 0)
const summary = { label: LABEL, games: N, seasons: SEASONS }
summary.home = { w: pct(sum((g) => g.hg > g.ag), N), d: pct(sum((g) => g.hg === g.ag), N), l: pct(sum((g) => g.hg < g.ag), N) }
summary.goals = Math.round((100 * sum((g) => g.hg + g.ag)) / N) / 100
summary.shots = Math.round((10 * sum((g) => (g.shots?.[0] || 0) + (g.shots?.[1] || 0))) / N) / 10
// favorito por faixa de diferença de força (do ponto de vista do mais forte, mando qualquer)
const buckets = [[0, 2], [2, 4], [4, 6], [6, 9], [9, 99]]
summary.byGap = buckets.map(([lo, hi]) => {
  const gs = games.filter((g) => Math.abs(g.sh - g.sa) >= lo && Math.abs(g.sh - g.sa) < hi)
  const fw = gs.filter((g) => (g.sh >= g.sa ? g.hg > g.ag : g.ag > g.hg)).length
  const dr = gs.filter((g) => g.hg === g.ag).length
  return { gap: `${lo}-${hi === 99 ? '+' : hi}`, n: gs.length, fav: pct(fw, gs.length), draw: pct(dr, gs.length), under: pct(gs.length - fw - dr, gs.length) }
})
// pontos esperados pela força (regressão linear de pontos sobre diferença e mando) e o que cada perfil fez acima disso
const rows = games.flatMap((g) => [
  { x: g.sh - g.sa, home: 1, pts: g.hg > g.ag ? 3 : g.hg === g.ag ? 1 : 0, prof: g.ph, opp: g.pa },
  { x: g.sa - g.sh, home: 0, pts: g.ag > g.hg ? 3 : g.hg === g.ag ? 1 : 0, prof: g.pa, opp: g.ph },
])
const fit = (rs) => { // pts = b0 + b1*x + b2*home
  const X = rs.map((r) => [1, r.x, r.home]), Y = rs.map((r) => r.pts)
  const A = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], v = [0, 0, 0]
  X.forEach((x, i) => { for (let a = 0; a < 3; a++) { v[a] += x[a] * Y[i]; for (let b = 0; b < 3; b++) A[a][b] += x[a] * x[b] } })
  // Gauss
  for (let c = 0; c < 3; c++) { for (let r = c + 1; r < 3; r++) { const m = A[r][c] / A[c][c]; for (let k = c; k < 3; k++) A[r][k] -= m * A[c][k]; v[r] -= m * v[c] } }
  const b = [0, 0, 0]; for (let r = 2; r >= 0; r--) { let s = v[r]; for (let k = r + 1; k < 3; k++) s -= A[r][k] * b[k]; b[r] = s / A[r][r] }
  return b
}
const beta = fit(rows)
summary.model = { base: +beta[0].toFixed(3), perPoint: +beta[1].toFixed(3), home: +beta[2].toFixed(3) }
summary.profiles = Object.fromEntries(PROFILES.map((p) => {
  const rs = rows.filter((r) => r.prof === p)
  const exp = rs.reduce((a, r) => a + beta[0] + beta[1] * r.x + beta[2] * r.home, 0)
  const got = rs.reduce((a, r) => a + r.pts, 0)
  return [p, { n: rs.length, ppg: +(got / rs.length).toFixed(2), aboveExp: +((got - exp) / rs.length).toFixed(2) }]
}))
// bot contra humano, direto
const vsRows = rows.filter((r) => r.prof === 'bot' && r.opp !== 'bot')
summary.botVsHuman = { n: vsRows.length, botPpg: +(vsRows.reduce((a, r) => a + r.pts, 0) / vsRows.length).toFixed(2) }
// campeão: posição dele no ranking de força
const champ = seasons.map((s) => s.table[0])
summary.champion = {
  strongest: pct(champ.filter((c) => c.strRank === 1).length, SEASONS),
  top3: pct(champ.filter((c) => c.strRank <= 3).length, SEASONS),
  strongestTop3: pct(seasons.filter((s) => s.table.findIndex((t) => t.strRank === 1) < 3).length, SEASONS),
  byProfile: Object.fromEntries(PROFILES.map((p) => [p, champ.filter((c) => c.prof === p).length])),
}
// correlação força x pontos (Spearman simples)
const rho = seasons.map((s) => { const n = s.table.length; let d2 = 0; s.table.forEach((t, i) => { d2 += (i + 1 - t.strRank) ** 2 }); return 1 - (6 * d2) / (n * (n * n - 1)) })
summary.rankCorr = +(rho.reduce((a, b) => a + b, 0) / rho.length).toFixed(2)
summary.duels = duels
summary.arrows = arrowsTest
summary.styles = stylesTest
summary.marks = marksTest
summary.secs = Math.round((Date.now() - t0) / 1000)
console.log(JSON.stringify(summary, null, 1))
if (OUT) writeFileSync(OUT, JSON.stringify({ summary, games, seasons }, null, 0))
