// Teste sem navegador do diretor da transmissão (o mesmo do campo 2D e do 3D).
// Joga partidas completas com o relógio igual ao da tela (MatchLive): 1x, 2x e 4x, esperando os lances (holdMinute).
// Mede: gol só anunciado depois da bola cruzar a linha, goleiro caído, reinício após o gol, pressão no portador,
// jogadores parados, lances que travam o relógio e valores inválidos.
// Uso: node scripts/test-match-director.mjs
import { HOLD_KINDS, L, W, createDirector } from '../src/features/match2d/director.js'

const F433 = {
  id: '4-3-3',
  slots: [
    { slot: 'GOL', pos: 'GOL', x: 50, y: 94 },
    { slot: 'LD', pos: 'LD', x: 88, y: 72 },
    { slot: 'ZAG1', pos: 'ZAG', x: 63, y: 80 },
    { slot: 'ZAG2', pos: 'ZAG', x: 37, y: 80 },
    { slot: 'LE', pos: 'LE', x: 12, y: 72 },
    { slot: 'VOL', pos: 'VOL', x: 50, y: 62 },
    { slot: 'MC1', pos: 'MC', x: 70, y: 48 },
    { slot: 'MC2', pos: 'MC', x: 30, y: 48 },
    { slot: 'PD', pos: 'PD', x: 84, y: 24 },
    { slot: 'ATA', pos: 'ATA', x: 50, y: 16 },
    { slot: 'PE', pos: 'PE', x: 16, y: 24 },
  ],
}
const SPEEDS = [
  { id: 1, ms: 700 },
  { id: 2, ms: 330 },
  { id: 4, ms: 140 },
]

function rng(seed) {
  let s = seed >>> 0
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    return s / 4294967296
  }
}

function players() {
  const out = []
  for (const side of ['h', 'a']) F433.slots.forEach((s, i) => out.push({ id: `${side}${i + 1}`, side, name: `${side}${i + 1}`, number: i + 1, pos: s.pos, slot: s.slot, status: 'on' }))
  return out
}

function events(seed) {
  const r = rng(seed)
  const out = []
  let seq = 1
  for (let m = 1; m <= 90; m += 1) {
    const side = r() < 0.5 ? 'h' : 'a'
    const p = `${side}${2 + Math.floor(r() * 10)}`
    const x = r()
    const ev = (kind, extra = {}) => out.push({ seq: ++seq, minute: m, kind, side, player: p, player_name: p, ...extra })
    const opp = side === 'h' ? 'a' : 'h'
    // assistente: outro jogador de linha do mesmo time (como no motor: player2 = id do assistente)
    const mate = `${side}${2 + ((Number(p.slice(1)) - 2 + 1 + Math.floor(r() * 8)) % 10)}`
    if (x < 0.04) ev('goal', r() < 0.7 ? { player2: mate, player2_name: mate } : {})
    else if (x < 0.09) ev('save', { detail: r() < 0.3 ? 'grande chance' : null, player2: `${opp}1`, player2_name: `${opp}1` })
    else if (x < 0.14) ev('shot_off', { detail: r() < 0.25 ? 'bloqueado' : null })
    else if (x < 0.17) ev('yellow')
    else if (x < 0.19) ev('offside')
    else if (x < 0.195) ev('pen_goal')
  }
  return out
}

function runMatch(speed, seed) {
  const d = createDirector({ formations: { '4-3-3': F433 }, homeId: 'h', awayId: 'a' })
  d.sync(players(), ['4-3-3', '4-3-3'])
  d.kickoff('h')
  const st = d.state
  const evs = events(seed)
  const byseq = new Map(evs.map((e) => [e.seq, e]))
  const fed = new Set()
  const FPS = 60
  const dt = 1 / FPS
  let clock = 0
  let wall = 0
  const res = { speed: speed.id, goals: 0, goalEarly: 0, gkDownMax: 0, restartMax: 0, pressSum: 0, pressN: 0, idleSum: 0, idleN: 0, stallMax: 0, nan: 0, fx: {}, turnovers: 0, wall: 0, holdStuck: 0 }
  const gkDown = new Map()
  let goalAt = null
  let goalScript = null
  let recv = { id: null }
  let lastHoldChange = 0
  let lastHold = null
  let lastOwnerSide = null
  let half = 1
  const revealedAll = new Set()
  Object.assign(res, { footGapMax: 0, behind: 0, carryN: 0, kicks: 0, kickFar: 0, saves: 0, saveMiss: 0, goalThroughGk: 0, gkOut: 0, shooterWrong: 0, assistWrong: 0, assists: 0, cardWrong: 0, passes: 0, passCtrl: 0 })
  let ownerSince = { id: null, t: 0 }
  let prevFlight = null
  let prevDelay = 0
  let lastPassTo = new Map() // receptor → quem passou (para conferir a assistência)
  const gks = () => st.players.filter((p) => p.gk)
  // conferências a cada passo do campo (inclusive dentro do 4x)
  const probe = () => {
    const b = st.ball
    const f = b.flight
    // contato: quando a bola sai, ela está no pé de quem chutou
    if (f && f === prevFlight && prevDelay > 0 && f.delay <= 0 && f.kicker) {
      const k = st.players.find((p) => p.id === f.kicker)
      res.kicks += 1
      if (k && Math.hypot(k.x - b.x, k.y - b.y) > 0.9) res.kickFar += 1
      if (f.receiver) {
        res.passes += 1
        lastPassTo.set(f.receiver, f.kicker)
      }
    }
    // passe dominado pelo receptor (sem ele ter de voltar atrás de bola parada)
    if (prevFlight && prevFlight.receiver && !f && b.owner === prevFlight.receiver) res.passCtrl += 1
    prevFlight = f
    prevDelay = f ? f.delay : 0
    // condução: bola no pé e à frente do corpo
    const o = b.owner ? st.players.find((p) => p.id === b.owner) : null
    if (o?.id !== ownerSince.id) ownerSince = { id: o?.id ?? null, t: st.t }
    if (o && !f && !b.held && st.t - ownerSince.t > 0.4) {
      const gap = Math.hypot(o.x - b.x, o.y - b.y)
      res.footGapMax = Math.max(res.footGapMax, gap)
      const sp = Math.hypot(o.vx, o.vy)
      if (sp > 2) {
        res.carryN += 1
        if (((b.x - o.x) * o.vx + (b.y - o.y) * o.vy) / sp < -0.15) res.behind += 1
      }
    }
    // goleiro: dentro do campo e sem atravessar o próprio gol
    for (const g of gks()) if (g.x < -0.35 || g.x > L + 0.35) res.gkOut += 1
  }
  while (clock < 90 && wall < 3600) {
    // relógio da tela (MatchLive): anda msPerMin por minuto, mas não passa do lance em andamento
    // nem de um lance (finalização/cartão/impedimento) que o campo ainda não mostrou
    const fieldHold = d.holdMinute()
    let pending = null
    for (const e of evs) if (HOLD_KINDS.has(e.kind) && !revealedAll.has(e.seq)) pending = pending == null ? e.minute : Math.min(pending, e.minute)
    const hold = [fieldHold, pending].filter((v) => v != null).reduce((a, c) => Math.min(a, c), Infinity)
    const cap = Number.isFinite(hold) ? Math.max(clock, hold - 0.01) : Infinity
    clock = Math.min(90, cap, clock + (dt * 1000) / speed.ms)
    if (hold !== lastHold) {
      lastHold = hold
      lastHoldChange = wall
    }
    if (hold != null) res.holdStuck = Math.max(res.holdStuck, wall - lastHoldChange)
    // a transmissão recebe os lances 1 minuto antes
    for (const e of evs) if (e.minute <= Math.floor(clock) + 1 && !fed.has(e.seq)) fed.add(e.seq), d.enqueue(e)
    const h = clock < 45 ? 1 : 2
    if (h !== half) {
      half = h
      d.setHalf(h)
    }
    // o campo anda na velocidade escolhida, em passos curtos
    let rest = dt * speed.id
    while (rest > 1e-4) {
      const s = Math.min(rest, 1 / 60)
      d.update(s)
      rest -= s
      probe()
      // revelação no passo exato em que acontece (é quando placar, relato e som mudam)
      for (const seq of d.takeRevealed() || []) {
        revealedAll.add(seq)
        const e = byseq.get(seq)
        if (!e) continue
        const b = st.ball
        const sc = st.script
        if (e.kind === 'goal' || e.kind === 'pen_goal') {
          res.goals += 1
          const onLine = b.x < -0.1 || b.x > L + 0.1
          if (!onLine) res.goalEarly += 1
          goalAt = wall
          goalScript = st.script
          // o finalizador mostrado é o do relato; o gol não passa "por dentro" do goleiro
          if (sc?.shooter && sc.shooter.id !== e.player) res.shooterWrong += 1
          if (e.kind === 'goal' && e.player2) {
            res.assists += 1
            if (lastPassTo.get(e.player) !== e.player2) res.assistWrong += 1
          }
          const g = gks().sort((a, c) => Math.hypot(a.x - b.x, a.y - b.y) - Math.hypot(c.x - b.x, c.y - b.y))[0]
          if (g && Math.hypot(g.x - b.x, g.y - b.y) < 0.45 && b.z < 1.6) res.goalThroughGk += 1
        }
        if (e.kind === 'save') {
          res.saves += 1
          // a bola está nas mãos do goleiro no momento da defesa
          const g = gks().sort((a, c) => Math.hypot(a.x - b.x, a.y - b.y) - Math.hypot(c.x - b.x, c.y - b.y))[0]
          if (!g || Math.hypot(g.x - b.x, g.y - b.y) > 1.5) res.saveMiss += 1
          if (sc?.shooter && sc.shooter.id !== e.player) res.shooterWrong += 1
        }
        if (e.kind === 'yellow' && sc?.culprit && sc.culprit.id !== e.player) res.cardWrong += 1
      }
    }
    wall += dt
    for (const f of d.takeFx() || []) res.fx[f.type] = (res.fx[f.type] || 0) + 1
    // reinício: do gol até o fim do roteiro do gol (a próxima jogada já é outra)
    if (goalAt != null && st.script !== goalScript) {
      res.restartMax = Math.max(res.restartMax, wall - goalAt)
      goalAt = null
    }
    // goleiro no chão (mergulho + levantar)
    for (const p of st.players) {
      if (!p.gk) continue
      const down = p.anim && (p.anim.name.startsWith('dive') || p.anim.name === 'getup')
      const t0 = gkDown.get(p.id)
      if (down && t0 == null) gkDown.set(p.id, wall)
      if (!down && t0 != null) {
        res.gkDownMax = Math.max(res.gkDownMax, (wall - t0) * speed.id)
        gkDown.delete(p.id)
      }
    }
    for (const p of st.players) if (!Number.isFinite(p.x + p.y + p.vx + p.vy)) res.nan += 1
    if (!Number.isFinite(st.ball.x + st.ball.y + st.ball.z)) res.nan += 1
    // jogo corrido: pressão no portador e jogadores parados
    const owner = st.ball.owner ? st.players.find((p) => p.id === st.ball.owner) : null
    // tudo o que a tela mostra com bola rolando (jogo corrido e jogadas dos lances), fora bolas paradas
    const RESTART = /setup|runup|celebrate|reset|c_out|c_place|whistle|card|freekick|free|goalkick|keeper/
    if (owner && !owner.gk && !(st.script && RESTART.test(st.script.phase))) {
      const opp = st.players.filter((p) => p.side !== owner.side && !p.gk)
      const near = Math.min(...opp.map((p) => Math.hypot(p.x - owner.x, p.y - owner.y)))
      // recepção livre (> 6 m): em 1,5 s de campo a defesa precisa encurtar pelo menos 35% da distância
      if (owner.id !== recv.id) recv = { id: owner.id, t: st.t, near, done: near <= 6 }
      else if (!recv.done && st.t - recv.t >= 1.5) {
        recv.done = true
        res.recvN = (res.recvN || 0) + 1
        if (near <= recv.near * 0.65 || near < 4) res.closedN = (res.closedN || 0) + 1
      }
      res.pressSum += near
      res.pressN += 1
      if (near < 5) res.closeN = (res.closeN || 0) + 1
      const out = st.players.filter((p) => !p.gk)
      res.idleSum += out.filter((p) => Math.hypot(p.vx, p.vy) < 0.3).length / out.length
      res.idleN += 1
    }
    if (owner && lastOwnerSide && owner.side !== lastOwnerSide) res.turnovers += 1
    if (owner) lastOwnerSide = owner.side
  }
  res.wall = Math.round(wall)
  res.finished = clock >= 90
  res.press = +(res.pressSum / Math.max(1, res.pressN)).toFixed(2)
  res.pressedPct = +(((res.closeN || 0) / Math.max(1, res.pressN)) * 100).toFixed(1)
  delete res.closeN
  res.closedPct = +(((res.closedN || 0) / Math.max(1, res.recvN || 0)) * 100).toFixed(1)
  delete res.closedN
  res.idle = +((res.idleSum / Math.max(1, res.idleN)) * 100).toFixed(1)
  res.expectedGoals = evs.filter((e) => e.kind === 'goal' || e.kind === 'pen_goal').length
  delete res.pressSum
  delete res.pressN
  delete res.idleSum
  delete res.idleN
  return res
}

let fail = 0
const check = (ok, msg) => {
  if (!ok) {
    fail += 1
    console.log(`  FALHA: ${msg}`)
  }
}
for (const speed of SPEEDS) {
  for (const seed of [11, 29]) {
    const r = runMatch(speed, seed)
    console.log(JSON.stringify(r))
    check(r.finished, `partida não terminou (${speed.id}x, seed ${seed})`)
    check(r.nan === 0, 'valores inválidos')
    check(r.goalEarly === 0, `gol anunciado antes de a bola cruzar a linha: ${r.goalEarly}`)
    check(r.goals === r.expectedGoals, `gols mostrados ${r.goals} ≠ gols do motor ${r.expectedGoals}`)
    check(r.gkDownMax < 2.6, `goleiro caído por ${r.gkDownMax.toFixed(2)} s`)
    // gol → comemoração (2,6 s) → volta e apito: no máximo ~8 s de campo
    check(r.restartMax * speed.id < 8, `reinício após o gol levou ${(r.restartMax * speed.id).toFixed(1)} s de campo`)
    // defesa ativa: quem recebe livre é encurtado rápido (reposições do goleiro saem para o livre de propósito)
    check(r.closedPct >= 70, `defesa passiva: só ${r.closedPct}% das recepções livres foram encurtadas em 1,5 s`)
    check(r.press < 7.5 && r.pressedPct > 55, `marcador médio a ${r.press} m, colado (< 5 m) ${r.pressedPct}% do tempo`)
    check(r.idle < 20, `jogadores parados demais: ${r.idle}%`)
    check(r.holdStuck < 40, `relógio preso num lance por ${r.holdStuck.toFixed(0)} s`)
    // bola e corpo
    check(r.kickFar === 0, `${r.kickFar} de ${r.kicks} chutes saíram longe do pé (> 0,9 m)`)
    check(r.footGapMax < 1.3, `bola longe do pé na condução: ${r.footGapMax.toFixed(2)} m`)
    check(r.behind / Math.max(1, r.carryN) < 0.01, `bola atrás do corpo em ${((r.behind / Math.max(1, r.carryN)) * 100).toFixed(1)}% da condução`)
    // goleiro
    check(r.saveMiss === 0, `${r.saveMiss} de ${r.saves} defesas sem a bola chegar às mãos`)
    check(r.goalThroughGk === 0, `${r.goalThroughGk} gols passando pelo corpo do goleiro`)
    check(r.gkOut === 0, `goleiro fora do campo/atrás do gol em ${r.gkOut} passos`)
    // relato = imagem
    check(r.shooterWrong === 0, `${r.shooterWrong} finalizações mostradas com jogador diferente do relato`)
    check(r.assistWrong === 0, `${r.assistWrong} de ${r.assists} assistências com outro jogador no último passe`)
    check(r.cardWrong === 0, `${r.cardWrong} cartões no jogador errado`)
  }
}
// ---- modo ONLINE: relógio em tempo real (7 s por minuto, como onlineUtils.matchClock), sem esperar o campo.
// O campo acelera quando fica para trás (OnlineMatchLive.fieldSpeed) e, além de FIELD_LAG_MAX minutos, o relato
// segue sem ele. Mede: lances anunciados antes da imagem (só pela regra de atraso) e o maior atraso do campo.
const FIELD_LAG_MAX = 4
function runOnline(seed) {
  const d = createDirector({ formations: { '4-3-3': F433 }, homeId: 'h', awayId: 'a' })
  d.sync(players(), ['4-3-3', '4-3-3'])
  d.kickoff('h')
  const st = d.state
  const evs = events(seed)
  const byseq = new Map(evs.map((e) => [e.seq, e]))
  const revealed = new Set()
  const fed = new Set()
  const dt = 1 / 60
  let t = 0
  let half = 1
  const res = { mode: 'online', seed, holds: 0, early: 0, goals: 0, goalEarlyLine: 0, maxBehind: 0, speedUps: 0 }
  while (t < 90 * 7 + 30) {
    const clock = Math.min(90, t / 7)
    const shown = Math.floor(clock)
    for (const e of evs) if (e.minute <= shown + 1 && !fed.has(e.seq)) fed.add(e.seq), d.enqueue(e)
    const h = clock < 45 ? 1 : 2
    if (h !== half) {
      half = h
      d.setHalf(h)
    }
    // atraso do campo e velocidade (mesma regra da tela online)
    let m = null
    for (const e of evs) if (HOLD_KINDS.has(e.kind) && !revealed.has(e.seq) && e.minute <= shown) m = m == null ? e.minute : Math.min(m, e.minute)
    const behind = m == null ? 0 : shown - m
    res.maxBehind = Math.max(res.maxBehind, behind)
    const sp = behind >= 2 ? 3 : behind >= 1 ? 2 : 1
    if (sp > 1) res.speedUps += 1
    // lance que o relato soltou pela regra de atraso, antes do campo mostrar
    for (const e of evs) if (HOLD_KINDS.has(e.kind) && !revealed.has(e.seq) && e.minute < shown - FIELD_LAG_MAX && !e._early) (e._early = true), (res.early += 1)
    let rest = dt * sp
    while (rest > 1e-4) {
      const s = Math.min(rest, 1 / 60)
      d.update(s)
      rest -= s
      for (const seq of d.takeRevealed() || []) {
        revealed.add(seq)
        const e = byseq.get(seq)
        if (e && (e.kind === 'goal' || e.kind === 'pen_goal')) {
          res.goals += 1
          if (!(st.ball.x < -0.1 || st.ball.x > L + 0.1) && !e._early) res.goalEarlyLine += 1
        }
      }
    }
    d.takeFx()
    t += dt
  }
  res.holds = evs.filter((e) => HOLD_KINDS.has(e.kind)).length
  return res
}
for (const seed of [11, 29, 47]) {
  const r = runOnline(seed)
  console.log(JSON.stringify(r))
  check(r.early === 0, `online: ${r.early} de ${r.holds} lances entraram no relato antes do campo (atraso > ${FIELD_LAG_MAX} min)`)
  check(r.goalEarlyLine === 0, `online: ${r.goalEarlyLine} gols anunciados antes de a bola cruzar a linha`)
}

console.log(fail ? `\n${fail} falha(s)` : '\nTudo certo')
process.exit(fail ? 1 : 0)
