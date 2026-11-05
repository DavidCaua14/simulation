// "Diretor" da transmissão 2.5D. Só APRESENTAÇÃO: placar, lances e cartões vêm do motor no servidor.
// O jogo corrido é contínuo (posse, passes, pressão, bloco que sobe e desce) e cada evento real vira uma jogada
// construída A PARTIR DE ONDE A BOLA ESTÁ: recuperação, troca de passes até a área e a finalização com o resultado
// do evento. Nada é teletransportado. O relógio da partida espera a jogada (holdMinute) para o lance não ser cortado.

export const L = 105
export const W = 68
const GOAL_HALF = 3.66
const SPRINT = 7.6 // m/s
const JOG = 4.6
const ACCEL = 10 // m/s²
const PASS_SPEED = 17
export const DIRS = ['S', 'SE', 'E', 'NE', 'N', 'NW', 'W', 'SW']
// octante na TELA (0 = leste, sentido horário porque o y da tela cresce para baixo) → índice em DIRS
const OCT_TO_DIR = [2, 1, 0, 7, 6, 5, 4, 3]

const rnd = (() => {
  let s = 1234567
  return () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    return s / 0x7fffffff
  }
})()
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)
const lerp = (a, b, k) => a + (b - a) * k

// Direção de sprite a partir de um vetor no CAMPO, usando a mesma inclinação da câmera (projeção do kit).
export function faceIndex(vx, vy) {
  const sx = 10.095 * vx + 0.882 * vy
  const sy = 5.588 * vy
  const oct = ((Math.round(Math.atan2(sy, sx) / (Math.PI / 4)) % 8) + 8) % 8
  return OCT_TO_DIR[oct]
}

const SHOT_KINDS = new Set(['goal', 'pen_goal', 'save', 'shot_off', 'pen_miss'])
const CARD_KINDS = new Set(['yellow', 'red', 'second_yellow'])
// Lances que a transmissão mostra antes de o relógio seguir
export const HOLD_KINDS = new Set([...SHOT_KINDS, ...CARD_KINDS, 'offside'])
export const BANNER_KINDS = {
  goal: { img: 'goal', ms: 2400 },
  pen_goal: { img: 'goal', ms: 2400 },
  yellow: { img: 'yellow', ms: 1500 },
  red: { img: 'red', ms: 1700 },
  second_yellow: { img: 'second_yellow', ms: 1700 },
  offside: { img: 'offside', ms: 1300 },
  injury: { img: 'injury', ms: 1500 },
  sub: { img: 'sub', ms: 1500 },
  foul: { img: 'referee', ms: 1200 },
}

export function createDirector({ formations, homeId, awayId }) {
  const st = {
    t: 0,
    half: 1,
    pendingHalf: null,
    players: [],
    ball: { x: L / 2, y: W / 2, z: 0, owner: null, flight: null, hidden: false, spin: 0 },
    poss: 'h',
    hold: 1,
    script: null,
    queue: [],
    banners: [],
    possShare: 0.5,
    netShake: null,
    released: new Set(), // eventos já mostrados (o relógio pode seguir)
    homeId,
    awayId,
  }

  const dirOf = (side) => ((side === 'h') === (st.half === 1) ? 1 : -1)
  const goalX = (side) => (dirOf(side) === 1 ? L : 0) // gol que o time ATACA
  const other = (side) => (side === 'h' ? 'a' : 'h')

  function slotBase(form, slot, side) {
    const s = formations?.[form]?.slots?.find((x) => x.slot === slot)
    const depth = s ? (100 - s.y) / 100 : 0.5
    const width = s ? s.x / 100 : 0.5
    const d = dirOf(side)
    const x = d === 1 ? 3 + depth * 46 : L - 3 - depth * 46
    const y = d === 1 ? 4 + width * (W - 8) : W - 4 - width * (W - 8)
    return { x, y, depth }
  }

  function sync(list, formationPair) {
    const on = list.filter((p) => p.status === 'on' && p.slot)
    const keep = new Map(st.players.map((p) => [p.id, p]))
    st.players = on.map((p) => {
      const form = p.side === 'h' ? formationPair?.[0] : formationPair?.[1]
      const old = keep.get(p.id)
      const base = slotBase(form, p.slot, p.side)
      const gk = p.pos === 'GOL' || p.slot === 'GOL'
      if (old) return Object.assign(old, { form, slot: p.slot, depth: base.depth, gk, name: p.name, number: p.number })
      // quem entra (substituição) chega pela lateral, perto do meio-campo
      const fresh = st.players.length > 0
      return {
        id: p.id,
        side: p.side,
        name: p.name,
        number: p.number,
        gk,
        slot: p.slot,
        form,
        depth: base.depth,
        x: fresh ? L / 2 + (p.side === 'h' ? -3 : 3) : base.x,
        y: fresh ? W + 1 : base.y,
        vx: 0,
        vy: 0,
        face: p.side === 'h' ? 2 : 6,
        faceHold: 0,
        stride: rnd() * 8,
        anim: null,
        tx: base.x,
        ty: base.y,
        speed: JOG,
      }
    })
    if (st.ball.owner && !st.players.some((p) => p.id === st.ball.owner)) st.ball.owner = null
  }

  const team = (side) => st.players.filter((p) => p.side === side)
  const outfield = (side) => team(side).filter((p) => !p.gk)
  const byId = (id) => st.players.find((p) => p.id === id)
  const keeper = (side) => team(side).find((p) => p.gk) || team(side)[0]
  const nearest = (list, pt, except = null) => list.filter((p) => p !== except).sort((a, b) => dist(a, pt) - dist(b, pt))[0] || null
  const play = (p, name, dur, opts = {}) => p && (p.anim = { name, t: 0, dur, hold: Boolean(opts.hold) })

  function kickoffPositions(side) {
    for (const p of st.players) {
      const b = slotBase(p.form, p.slot, p.side)
      const d = dirOf(p.side)
      let x = clamp(b.x - d * 6, 1, L - 1)
      if (p.side !== side) x = d === 1 ? Math.min(x, L / 2 - 9.5) : Math.max(x, L / 2 + 9.5)
      else x = d === 1 ? Math.min(x, L / 2 - 1) : Math.max(x, L / 2 + 1)
      p.tx = x
      p.ty = b.y
    }
    const taker = outfield(side).sort((a, b) => b.depth - a.depth)[0]
    if (taker) {
      taker.tx = L / 2 - dirOf(side) * 0.6
      taker.ty = W / 2
    }
    return taker
  }
  function kickoff(side, { snap = true } = {}) {
    const taker = kickoffPositions(side)
    if (snap) for (const p of st.players) Object.assign(p, { x: p.tx, y: p.ty, vx: 0, vy: 0, anim: null })
    Object.assign(st.ball, { x: L / 2, y: W / 2, z: 0, flight: null, owner: taker?.id || null, hidden: false })
    st.poss = side
    st.hold = 0.8
  }

  // ---------- bola ----------
  function kick(from, to, opts = {}) {
    const b = st.ball
    const d = Math.max(1, dist(from, to))
    const speed = opts.speed ?? PASS_SPEED
    const dur = opts.dur ?? d / speed
    const peak = opts.peak ?? (d > 28 ? Math.min(7, d / 8) : 0.2)
    b.flight = { from: { x: from.x, y: from.y }, to: { x: to.x, y: to.y }, t: 0, dur, peak, z0: b.z, z1: opts.z1 ?? 0, onEnd: opts.onEnd || null, receiver: opts.receiver ?? null, ground: peak < 0.5 }
    b.owner = null
    if (opts.kicker) {
      play(opts.kicker, 'kick', 0.32)
      opts.kicker.face = faceIndex(to.x - from.x, to.y - from.y)
    }
  }
  // passe para um colega: mira na frente dele (ele corre para o ponto de encontro)
  function pass(owner, target, opts = {}) {
    const lead = opts.lead ?? 0.5
    const to = { x: clamp(target.x + target.vx * lead, 1, L - 1), y: clamp(target.y + target.vy * lead, 1, W - 1) }
    target.tx = to.x
    target.ty = to.y
    kick(owner, to, { ...opts, kicker: owner, receiver: target.id })
  }

  function chooseReceiver(owner) {
    const d = dirOf(owner.side)
    const opp = outfield(other(owner.side))
    let best = null
    let bestScore = -Infinity
    for (const m of outfield(owner.side)) {
      if (m === owner) continue
      const dd = dist(owner, m)
      if (dd < 6 || dd > 34) continue
      const forward = (m.x - owner.x) * d
      // linha de passe livre: distância do adversário mais próximo ao segmento
      let lane = 99
      for (const o of opp) {
        const t = clamp(((o.x - owner.x) * (m.x - owner.x) + (o.y - owner.y) * (m.y - owner.y)) / (dd * dd), 0, 1)
        lane = Math.min(lane, Math.hypot(owner.x + (m.x - owner.x) * t - o.x, owner.y + (m.y - owner.y) * t - o.y))
      }
      const free = Math.min(dist(m, nearest(opp, m) || { x: 999, y: 999 }), 12)
      const score = clamp(forward / 18, -0.5, 1.2) + Math.min(lane, 6) / 6 + free / 12 - dd / 60 + rnd() * 0.5
      if (score > bestScore) {
        bestScore = score
        best = m
      }
    }
    return best
  }

  // ---------- eventos → jogadas ----------
  function enqueue(ev) {
    st.queue.push(ev)
    if (!HOLD_KINDS.has(ev.kind)) st.released.add(ev.seq)
  }
  const release = (ev) => ev && st.released.add(ev.seq)
  function banner(kind, ev, extra = {}) {
    const meta = BANNER_KINDS[kind]
    if (!meta && kind !== 'text') return
    st.banners.push({ id: `${ev?.seq ?? st.t}-${kind}`, kind, img: meta?.img, ms: meta?.ms ?? extra.ms ?? 1600, ev, ...extra })
  }

  function startScript(ev) {
    const side = ev.side || st.poss
    if (SHOT_KINDS.has(ev.kind)) {
      const pen = ev.kind === 'pen_goal' || ev.kind === 'pen_miss'
      const d = dirOf(side)
      const gx = goalX(side)
      const cand = byId(ev.player)
      const shooter = cand && !cand.gk && cand.side === side ? cand : outfield(side).sort((a, b) => b.depth - a.depth)[Math.floor(rnd() * 3)] || outfield(side)[0]
      const laneY = clamp(shooter ? shooter.y : W / 2, W / 2 - 16, W / 2 + 16)
      const spot = pen ? { x: gx - d * 11, y: W / 2 } : { x: gx - d * (12 + rnd() * 9), y: clamp(laneY + (rnd() - 0.5) * 10, W / 2 - 15, W / 2 + 15) }
      st.script = { ev, kind: pen ? 'penalty' : 'attack', phase: 'win', t: 0, side, opp: other(side), shooter, spot, steps: null }
      if (pen) {
        st.script.phase = 'setup'
        st.ball.owner = null
        st.ball.flight = null
        banner('foul', ev, { text: 'Pênalti!' })
      }
      return
    }
    if (CARD_KINDS.has(ev.kind)) {
      const culprit = byId(ev.player) || nearest(outfield(side), st.ball)
      st.script = { ev, kind: 'foul', phase: 'approach', t: 0, side, opp: other(side), culprit }
      return
    }
    if (ev.kind === 'offside') {
      st.script = { ev, kind: 'offside', phase: 'flag', t: 0, side, opp: other(side) }
      return
    }
    if (ev.kind === 'injury') banner('injury', ev)
    else if (ev.kind === 'sub') banner('sub', ev)
    else if (ev.kind === 'ht' || ev.kind === 'et_ht') banner('text', ev, { text: 'Intervalo', ms: 1600 })
    else if (ev.kind === 'ft') banner('text', ev, { text: 'Fim de jogo', ms: 2200 })
    release(ev)
  }

  // Recupera a posse para o time do lance (desarme do jogador mais próximo da bola), sem teletransporte.
  function winBall(s) {
    const b = st.ball
    if (b.flight) return false
    const owner = b.owner ? byId(b.owner) : null
    if (owner && owner.side === s.side) return true
    const hunter = nearest(outfield(s.side), b)
    if (!hunter) return true
    hunter.tx = b.x
    hunter.ty = b.y
    hunter.speed = SPRINT
    if (owner) {
      owner.speed = 3
    }
    if (dist(hunter, b) < 1.3 || s.t > 2.6) {
      b.owner = hunter.id
      st.poss = s.side
      if (owner) play(owner, 'stumble', 0.4)
      return true
    }
    return false
  }

  // Divide o caminho da bola até o ponto de finalização em passes de até ~24 m, com colegas que correm para cada ponto.
  function planSteps(s) {
    const b = st.ball
    const d = dirOf(s.side)
    const total = Math.abs(s.spot.x - b.x)
    const n = clamp(Math.ceil(total / 22), 1, 4)
    const used = new Set([s.shooter?.id])
    const steps = []
    for (let i = 1; i < n; i += 1) {
      const k = i / n
      const wp = {
        x: clamp(lerp(b.x, s.spot.x, k) + d * 2, 4, L - 4),
        y: clamp(lerp(b.y, s.spot.y, k) + (rnd() - 0.5) * 24, 6, W - 6),
      }
      const mate = outfield(s.side).filter((p) => !used.has(p.id) && p.id !== b.owner).sort((a, c) => dist(a, wp) - dist(c, wp))[0]
      if (!mate) continue
      used.add(mate.id)
      steps.push({ who: mate, at: wp })
    }
    steps.push({ who: s.shooter, at: s.spot, final: true })
    return steps
  }

  function stepAttack(s, dt) {
    const b = st.ball
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    if (!s.shooter) {
      release(s.ev)
      st.script = null
      return
    }
    if (s.phase === 'win') {
      if (winBall(s) && !b.flight) {
        s.steps = planSteps(s)
        s.phase = 'build'
        s.t = 0
      }
      return
    }
    if (s.phase === 'build') {
      const step = s.steps[0]
      const owner = b.owner ? byId(b.owner) : null
      // quem vai receber corre para o ponto combinado; o finalizador já se aproxima da área
      for (const st2 of s.steps) {
        if (!st2.who || st2.who === owner) continue
        st2.who.tx = st2.at.x
        st2.who.ty = st2.at.y
        st2.who.speed = st2 === step ? SPRINT : JOG + 1
      }
      if (b.flight) return
      if (!owner || owner.side !== s.side) {
        // a bola sobrou: o mais próximo do time do lance domina
        const n2 = nearest(outfield(s.side), b)
        if (n2) {
          n2.tx = b.x
          n2.ty = b.y
          n2.speed = SPRINT
          if (dist(n2, b) < 1.2) b.owner = n2.id
        }
        return
      }
      if (owner === step.who) {
        s.steps.shift()
        s.t = 0
        if (step.final) {
          s.phase = 'aim'
          s.t = 0
        }
        return
      }
      // conduz em direção ao alvo e passa quando o colega chega (ou o tempo aperta)
      owner.tx = owner.x + d * 4
      owner.ty = owner.y + (step.at.y - owner.y) * 0.1
      owner.speed = JOG + 1
      const near = dist(step.who, step.at) < 5
      if ((near && s.t > 0.5) || s.t > 2.4) {
        pass(owner, step.who, { lead: 0.35, speed: dist(owner, step.who) > 25 ? 22 : PASS_SPEED + 2 })
        s.t = 0
      }
      return
    }
    if (s.phase === 'aim') {
      // ajeita e finaliza
      const sh = s.shooter
      sh.tx = sh.x + d * 1.5
      sh.ty = sh.y + (W / 2 - sh.y) * 0.05
      sh.speed = JOG
      if (s.t > 0.35) shoot(s)
      return
    }
    stepFinish(s, dt, gx, d)
  }

  function shoot(s) {
    const sh = s.shooter
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    const k = s.ev.kind
    const gk = keeper(s.opp)
    const saved = k === 'save' || (k === 'pen_miss' && s.ev.detail === 'defendido')
    const sideY = rnd() < 0.5 ? -1 : 1
    let to
    let z1
    if (k === 'goal' || k === 'pen_goal') {
      to = { x: gx + d * 0.6, y: W / 2 + sideY * (1.2 + rnd() * (GOAL_HALF - 1.6)) }
      z1 = rnd() < 0.5 ? 0.25 + rnd() * 0.5 : 1.2 + rnd() * 1
    } else if (saved) {
      to = { x: gx - d * 0.9, y: W / 2 + sideY * (0.6 + rnd() * 2.4) }
      z1 = 0.3 + rnd() * 1.6
    } else {
      const wide = rnd() < 0.55
      to = wide ? { x: gx + d * 2, y: W / 2 + sideY * (GOAL_HALF + 0.8 + rnd() * 3) } : { x: gx + d * 2, y: W / 2 + sideY * rnd() * GOAL_HALF }
      z1 = wide ? 0.3 + rnd() : 2.9 + rnd() * 1.3
    }
    const far = dist(sh, to)
    const from = { x: st.ball.x, y: st.ball.y }
    kick(from, to, { speed: s.kind === 'penalty' ? 24 : 27, peak: Math.max(z1 * 0.6, far > 20 ? 1.4 : 0.6), z1, kicker: sh })
    s.target = to
    s.saved = saved
    s.phase = 'flight'
    s.t = 0
    // goleiro reage ao chute
    if (gk) {
      const dy = (to.y - gk.y) * (dirOf(s.opp) === 1 ? 1 : -1)
      s.gkDy = to.y - gk.y
      if (saved && Math.abs(to.y - gk.y) < 1.2) play(gk, z1 > 1.3 ? 'catch_high' : 'catch_low', 0.9, { hold: true })
      else play(gk, dy > 0 ? 'dive_right' : 'dive_left', 1.15, { hold: true })
    }
  }

  function stepFinish(s, dt, gx, d) {
    const b = st.ball
    const gk = keeper(s.opp)
    const k = s.ev.kind
    if (s.phase === 'flight') {
      if (gk && gk.anim?.name?.startsWith('dive')) {
        // o mergulho leva o goleiro até a linha da bola
        const reach = s.saved ? s.target.y : s.target.y - Math.sign(s.gkDy || 1) * 1.1
        gk.y += clamp(reach - gk.y, -6 * dt, 6 * dt)
        gk.tx = gk.x
        gk.ty = gk.y
      }
      if (b.flight) return
      if (k === 'goal' || k === 'pen_goal') {
        // a bola entra e estufa a rede
        Object.assign(b, { x: gx + d * 1.3, z: Math.min(b.z, 1.6) })
        st.netShake = { side: gx === L ? 1 : 0, t: 0 }
        banner('goal', s.ev)
        release(s.ev)
        s.phase = 'celebrate'
        s.t = 0
        s.corner = { x: gx - d * 2, y: s.shooter.y < W / 2 ? 2 : W - 2 }
        return
      }
      if (s.saved && gk) {
        b.owner = gk.id
        b.hidden = true
        release(s.ev)
        s.phase = 'keeper'
        s.t = 0
        return
      }
      release(s.ev)
      s.phase = 'goalkick'
      s.t = 0
      return
    }
    if (s.phase === 'celebrate') {
      const sh = s.shooter
      sh.tx = s.corner.x
      sh.ty = s.corner.y
      sh.speed = SPRINT
      for (const m of outfield(s.side)) {
        if (m === sh) continue
        if (dist(m, sh) < 30) {
          m.tx = sh.x - d * 2 + (rnd() - 0.5) * 3
          m.ty = sh.y + (rnd() - 0.5) * 3
          m.speed = JOG
        }
      }
      if (dist(sh, s.corner) < 2 && !sh.anim) play(sh, 'celebrate', 1.4)
      if (s.t > 3.6) {
        s.phase = 'reset'
        s.t = 0
        kickoffPositions(s.opp)
        for (const p of st.players) p.speed = JOG + 1
        // a bola volta ao centro com o árbitro (fora de cena) até a nova saída
        Object.assign(b, { x: L / 2, y: W / 2, z: 0, owner: null, flight: null, hidden: true })
      }
      return
    }
    if (s.phase === 'reset') {
      // os times voltam às posições de saída andando; quem demora entra no lugar no fim
      if (s.t > 3 || st.players.every((p) => dist(p, { x: p.tx, y: p.ty }) < 1.5)) {
        kickoff(s.opp)
        st.script = null
      }
      return
    }
    if (s.phase === 'keeper') {
      if (gk) {
        gk.speed = 2
        if (s.t > 1.1 && !s.thrown) {
          s.thrown = true
          b.hidden = false
          const mate = outfield(s.opp).sort((a, c) => Math.abs(a.x - gk.x) - Math.abs(c.x - gk.x))[1] || outfield(s.opp)[0]
          Object.assign(b, { x: gk.x, y: gk.y, z: 1.2 })
          play(gk, 'throw', 0.7)
          if (mate) pass(gk, mate, { lead: 0.2, speed: 16, peak: 1.2 })
          st.poss = s.opp
        }
      }
      if (s.thrown && !b.flight) {
        st.script = null
        st.hold = 0.6
      }
      return
    }
    if (s.phase === 'goalkick') {
      // tiro de meta: a bola saiu (some), reaparece na pequena área e o goleiro lança para o meio-campo
      const spot = { x: gx - d * 5.5, y: W / 2 + (s.target?.y > W / 2 ? 6 : -6) }
      if (!s.placed) b.hidden = s.t > 0.4
      if (!s.placed && s.t > 0.8) {
        s.placed = true
        Object.assign(b, { x: spot.x, y: spot.y, z: 0, flight: null, owner: null, hidden: false })
      }
      if (gk && s.placed) {
        gk.tx = spot.x + d * 1.2
        gk.ty = spot.y
        gk.speed = JOG
        if (dist(gk, { x: gk.tx, y: gk.ty }) < 0.8 && !s.kicked) {
          s.kicked = true
          play(gk, 'kick', 0.8)
          const mate = outfield(s.opp).sort((a, c) => a.depth - c.depth).slice(3).sort(() => rnd() - 0.5)[0]
          const to = mate ? { x: mate.x, y: mate.y } : { x: L / 2, y: W / 2 }
          setTimeoutFree(s, 0.25, () => kick({ x: b.x, y: b.y }, to, { speed: 24, peak: 8, receiver: mate?.id }))
        }
      }
      if (s.kicked && s.fired && !b.flight) {
        st.poss = s.opp
        st.script = null
        st.hold = 0.8
      }
      if (s.t > 7) st.script = null
    }
  }
  // atraso dentro do roteiro (sem timers do navegador: avança com o relógio da transmissão)
  function setTimeoutFree(s, delay, fn) {
    s.timers = s.timers || []
    s.timers.push({ at: s.t + delay, fn })
  }

  function stepPenalty(s, dt) {
    const b = st.ball
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    if (s.phase === 'setup') {
      // todos fora da área; batedor atrás da bola; goleiro na linha. A bola some e reaparece na marca (árbitro).
      Object.assign(b, { x: s.spot.x, y: s.spot.y, z: 0, owner: null, flight: null, hidden: s.t < 1 })
      for (const p of st.players) {
        if (p === s.shooter) {
          p.tx = s.spot.x - d * 2.2
          p.ty = s.spot.y + 0.6
        } else if (p.gk && p.side === s.opp) {
          p.tx = gx - d * 0.3
          p.ty = W / 2
        } else if (!p.gk) {
          const inBox = Math.abs(p.x - gx) < 18
          p.tx = inBox ? gx - d * (19 + rnd() * 4) : p.x
          p.ty = clamp(p.y, 12, W - 12)
        }
        p.speed = JOG
      }
      s.shooter.speed = SPRINT
      if ((s.t > 2.6 && dist(s.shooter, { x: s.shooter.tx, y: s.shooter.ty }) < 1.5) || s.t > 7) {
        s.shooter.x = s.shooter.tx
        s.shooter.y = s.shooter.ty
        s.phase = 'runup'
        s.t = 0
      }
      return
    }
    if (s.phase === 'runup') {
      s.shooter.tx = s.spot.x - d * 0.4
      s.shooter.ty = s.spot.y
      s.shooter.speed = 3.2
      if (dist(s.shooter, b) < 0.7 || s.t > 1.4) shoot(s)
      return
    }
    stepFinish(s, dt, gx, d)
  }

  function stepFoul(s) {
    const b = st.ball
    if (s.phase === 'approach') {
      const c = s.culprit
      if (c) {
        c.tx = b.x
        c.ty = b.y
        c.speed = SPRINT
      }
      if (!c || dist(c, b) < 1.6 || s.t > 1.8) {
        const victim = b.owner ? byId(b.owner) : null
        if (victim && victim.side !== s.side) play(victim, 'stumble', 0.6)
        b.flight = null
        b.owner = null
        banner('foul', s.ev, { text: 'Falta' })
        banner(s.ev.kind, s.ev)
        release(s.ev)
        s.phase = 'card'
        s.t = 0
      }
      return
    }
    if (s.phase === 'card' && s.t > 1.8) {
      const taker = nearest(outfield(s.opp), b)
      if (taker) {
        taker.tx = b.x - dirOf(s.opp) * 0.8
        taker.ty = b.y
      }
      if (s.ev.kind !== 'yellow' && s.culprit) {
        // expulso: sai pela lateral
        s.culprit.tx = s.culprit.x
        s.culprit.ty = W + 4
        s.culprit.speed = 2
      }
      if (taker && dist(taker, b) < 1.4) {
        b.owner = taker.id
        st.poss = s.opp
        st.hold = 0.5
        st.script = null
      } else if (s.t > 4) st.script = null
    }
  }

  function stepOffside(s) {
    const b = st.ball
    if (s.phase === 'flag') {
      banner('offside', s.ev)
      release(s.ev)
      b.flight = null
      b.owner = null
      s.phase = 'free'
      s.t = 0
      return
    }
    const gk = keeper(s.opp)
    const taker = nearest(outfield(s.opp), b) || gk
    if (taker) {
      taker.tx = b.x
      taker.ty = b.y
      taker.speed = JOG
      if (dist(taker, b) < 1.2 || s.t > 3) {
        b.owner = taker.id
        st.poss = s.opp
        st.hold = 0.6
        st.script = null
      }
    }
  }

  // ---------- jogo corrido ----------
  function openPlay(dt) {
    const b = st.ball
    if (b.flight) return
    let owner = b.owner ? byId(b.owner) : null
    if (!owner) {
      // bola solta: os dois mais próximos disputam
      const h = nearest(outfield('h'), b)
      const a = nearest(outfield('a'), b)
      for (const p of [h, a]) {
        if (!p) continue
        p.tx = b.x
        p.ty = b.y
        p.speed = SPRINT
      }
      const win = [h, a].filter(Boolean).sort((x, y) => dist(x, b) - dist(y, b))[0]
      if (win && dist(win, b) < 1) {
        b.owner = win.id
        st.poss = win.side
        st.hold = 0.6 + rnd() * 0.8
      }
      return
    }
    st.poss = owner.side
    st.hold -= dt
    const d = dirOf(owner.side)
    // conduz para a frente, desviando do marcador; não entra na área (finalização só vem de evento real)
    const limit = goalX(owner.side) - d * 24
    const marker = nearest(outfield(other(owner.side)), owner)
    const away = marker && dist(marker, owner) < 4 ? Math.sign(owner.y - marker.y || 1) * 3 : 0
    owner.tx = d === 1 ? Math.min(owner.x + 5, limit) : Math.max(owner.x - 5, limit)
    owner.ty = clamp(owner.y + away + (W / 2 - owner.y) * 0.04, 3, W - 3)
    owner.speed = JOG + 0.6
    const stuck = Math.abs(owner.x - limit) < 2
    if (st.hold <= 0 || stuck) {
      const r = chooseReceiver(owner)
      // desarme cosmético quando o time tem menos posse no jogo real
      const share = owner.side === 'h' ? st.possShare : 1 - st.possShare
      if (marker && dist(marker, owner) < 2 && rnd() < 0.35 * (1 - share)) {
        b.owner = marker.id
        st.poss = marker.side
        play(owner, 'stumble', 0.4)
        st.hold = 0.8 + rnd()
        return
      }
      if (r) {
        const long = dist(owner, r) > 26
        pass(owner, r, { lead: 0.5, speed: long ? 21 : PASS_SPEED, peak: long ? 3.5 : 0.2 })
        // interceptação ocasional ao fim do passe
        const opp = outfield(other(owner.side))
        if (rnd() < 0.14 + 0.16 * (1 - share) && opp.length) {
          const cutter = nearest(opp, { x: (owner.x + r.x) / 2, y: (owner.y + r.y) / 2 })
          if (cutter) st.ball.flight.interceptBy = cutter.id
        }
      }
      st.hold = 1 + rnd() * 1.6
    }
  }

  // forma dos dois blocos a partir da bola
  function shape(p) {
    const b = st.ball
    const base = slotBase(p.form, p.slot, p.side)
    const d = dirOf(p.side)
    const progress = d === 1 ? b.x / L : 1 - b.x / L
    const inPoss = st.poss === p.side
    if (p.gk) {
      const gx = d === 1 ? 0 : L
      const toBall = Math.hypot(b.x - gx, b.y - W / 2) || 1
      const off = clamp(1 + (1 - progress) * 4, 1, 6)
      return { x: gx + ((b.x - gx) / toBall) * off, y: W / 2 + ((b.y - W / 2) / toBall) * off * 0.9, speed: JOG }
    }
    let x = base.x + d * ((progress - 0.45) * 36 + (inPoss ? 8 : -2))
    // compacta o bloco na largura conforme o lado da bola
    let y = base.y + (b.y - base.y) * (inPoss ? 0.1 : 0.32)
    if (inPoss) y = W / 2 + (y - W / 2) * 1.12
    x = clamp(x, 2, L - 2)
    return { x, y: clamp(y, 2, W - 2), speed: inPoss ? JOG + 0.4 : JOG }
  }

  function steer(p, dt) {
    const dx = p.tx - p.x
    const dy = p.ty - p.y
    const dd = Math.hypot(dx, dy)
    const want = dd < 0.25 ? 0 : Math.min(p.speed, dd * 1.6) // chega desacelerando
    const vxT = dd > 0.01 ? (dx / dd) * want : 0
    const vyT = dd > 0.01 ? (dy / dd) * want : 0
    const ax = vxT - p.vx
    const ay = vyT - p.vy
    const a = Math.hypot(ax, ay)
    const maxA = ACCEL * dt
    const k = a > maxA ? maxA / a : 1
    p.vx += ax * k
    p.vy += ay * k
    // em mergulho/comemoração o corpo não desliza
    if (p.anim && ['celebrate', 'catch_high', 'catch_low', 'throw', 'kick'].includes(p.anim.name) && p.gk) {
      p.vx *= 0.5
      p.vy *= 0.5
    }
    p.x = clamp(p.x + p.vx * dt, -3, L + 3)
    p.y = clamp(p.y + p.vy * dt, -2, W + 6)
    const sp = Math.hypot(p.vx, p.vy)
    // passada proporcional à distância percorrida: 8 quadros a cada ~2,6 m
    p.stride = (p.stride + (sp * dt * 8) / 2.6) % 8
    // direção do corpo: segue o movimento; parado, olha para a bola (com pequena histerese)
    const b = st.ball
    const want8 = sp > 0.9 ? faceIndex(p.vx, p.vy) : faceIndex(b.x - p.x, b.y - p.y)
    if (want8 !== p.face) {
      p.faceHold += dt
      if (p.faceHold > (sp > 0.9 ? 0.08 : 0.35)) {
        p.face = want8
        p.faceHold = 0
      }
    } else p.faceHold = 0
    if (p.anim) {
      p.anim.t += dt
      if (p.anim.t >= p.anim.dur && !p.anim.hold) p.anim = null
    }
  }

  // ---------- ciclo ----------
  function update(dt) {
    st.t += dt
    for (const bn of st.banners) bn.age = (bn.age || 0) + dt * 1000
    if (st.banners.length && st.banners[0].age >= st.banners[0].ms) st.banners.shift()
    if (st.banners.length > 1) for (let i = 1; i < st.banners.length; i += 1) st.banners[i].age = 0
    if (st.netShake) {
      st.netShake.t += dt
      if (st.netShake.t > 1.2) st.netShake = null
    }

    if (!st.script && st.pendingHalf != null) {
      st.half = st.pendingHalf
      st.pendingHalf = null
      kickoff(st.half === 1 ? 'h' : 'a')
    }
    if (!st.script && st.queue.length) startScript(st.queue.shift())

    // velocidades padrão; roteiros e o jogo corrido ajustam depois
    for (const p of st.players) {
      const s = shape(p)
      p.tx = s.x
      p.ty = s.y
      p.speed = s.speed
    }
    // pressão: o mais próximo marca quem tem a bola, o segundo cobre
    const b = st.ball
    const ownerNow = b.owner ? byId(b.owner) : null
    if (ownerNow && !st.script?.phase?.match(/setup|runup|celebrate|reset/)) {
      const defs = outfield(other(ownerNow.side)).sort((x, y) => dist(x, ownerNow) - dist(y, ownerNow))
      const dd = dirOf(defs[0]?.side || 'h')
      if (defs[0]) {
        defs[0].tx = ownerNow.x - dd * 1.4
        defs[0].ty = ownerNow.y
        defs[0].speed = JOG + 1.6
      }
      if (defs[1]) {
        defs[1].tx = ownerNow.x - dd * 6
        defs[1].ty = (ownerNow.y + W / 2) / 2
      }
    }
    // quem vai receber o passe corre para o ponto de encontro
    if (b.flight?.receiver) {
      const r = byId(b.flight.receiver)
      if (r) {
        r.tx = b.flight.to.x
        r.ty = b.flight.to.y
        r.speed = SPRINT
      }
      if (b.flight.interceptBy) {
        const c = byId(b.flight.interceptBy)
        if (c) {
          c.tx = lerp(b.flight.from.x, b.flight.to.x, 0.8)
          c.ty = lerp(b.flight.from.y, b.flight.to.y, 0.8)
          c.speed = SPRINT
        }
      }
    }

    // roteiro do evento atual
    const s = st.script
    if (s) {
      s.t += dt
      if (s.timers) {
        for (const tm of s.timers) if (!tm.done && s.t >= tm.at) (tm.done = true), tm.fn(), (s.fired = true)
      }
      if (s.kind === 'attack') stepAttack(s, dt)
      else if (s.kind === 'penalty') stepPenalty(s, dt)
      else if (s.kind === 'foul') stepFoul(s)
      else if (s.kind === 'offside') stepOffside(s)
      // segurança: nenhum roteiro prende a transmissão
      if (st.script === s && s.t > 14 && s.phase !== 'reset') {
        release(s.ev)
        st.script = null
      }
    } else openPlay(dt)

    // bola em voo
    if (b.flight) {
      const f = b.flight
      f.t += dt
      // passe rasteiro desacelera; chute e lançamento seguem a parábola
      const lin = clamp(f.t / f.dur, 0, 1)
      const k = f.ground ? 1 - (1 - lin) * (1 - lin) * 0.35 - (1 - lin) * 0.65 : lin
      b.x = f.from.x + (f.to.x - f.from.x) * k
      b.y = f.from.y + (f.to.y - f.from.y) * k
      b.z = f.z0 + (f.z1 - f.z0) * lin + f.peak * 4 * lin * (1 - lin)
      b.spin += dt * 14
      // interceptação no caminho (só no jogo corrido)
      if (!st.script && f.interceptBy) {
        const c = byId(f.interceptBy)
        if (c && dist(c, b) < 1.1 && b.z < 1.2) {
          b.flight = null
          b.owner = c.id
          st.poss = c.side
          st.hold = 0.7 + rnd()
          b.z = 0
        }
      }
      if (b.flight && lin >= 1) {
        b.flight = null
        b.z = f.z1
        const r = f.receiver ? byId(f.receiver) : null
        if (r && dist(r, b) < 1.6) b.owner = r.id
        if (r && !st.script) st.hold = 0.8 + rnd() * 1.4
        if (f.onEnd) f.onEnd()
      }
    }

    for (const p of st.players) steer(p, dt)

    // bola nos pés de quem conduz: pequenos toques à frente do corpo
    if (b.owner && !b.flight) {
      const o = byId(b.owner)
      if (o) {
        const sp = Math.hypot(o.vx, o.vy)
        const ux = sp > 0.3 ? o.vx / sp : dirOf(o.side)
        const uy = sp > 0.3 ? o.vy / sp : 0
        const touch = 0.55 + (sp > 1 ? 0.35 * Math.abs(Math.sin(o.stride * Math.PI / 4)) : 0)
        b.x = o.x + ux * touch
        b.y = o.y + uy * touch * 0.8
        b.z = o.gk && b.hidden ? 1 : 0
        if (sp > 0.3) b.spin += dt * sp * 2
      }
    }
  }

  // Menor minuto de um lance que ainda não foi mostrado: o relógio da partida espera até ele terminar.
  function holdMinute() {
    let m = null
    const s = st.script
    if (s?.ev && !st.released.has(s.ev.seq)) m = s.ev.minute
    for (const ev of st.queue) if (HOLD_KINDS.has(ev.kind) && !st.released.has(ev.seq)) m = m == null ? ev.minute : Math.min(m, ev.minute)
    return m
  }

  return {
    state: st,
    sync,
    kickoff,
    enqueue,
    update,
    holdMinute,
    releaseAll() {
      for (const ev of st.queue) st.released.add(ev.seq)
      if (st.script?.ev) st.released.add(st.script.ev.seq)
    },
    setHalf(h) {
      if (h === st.half || st.pendingHalf === h) return
      if (st.script) st.pendingHalf = h
      else {
        st.half = h
        kickoff(h === 1 ? 'h' : 'a')
      }
    },
    setPossession(share) {
      st.possShare = Number.isFinite(share) ? share : 0.5
    },
    teamOf: team,
  }
}
