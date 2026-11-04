// "Diretor" da transmissão 2.5D. Só APRESENTAÇÃO: o placar, os lances e os cartões vêm do motor no servidor
// (eventos da partida). Entre os lances, o diretor movimenta os times de forma plausível (posse, passes,
// bloco que sobe e desce); cada evento real dispara uma jogada roteirizada que termina no resultado do evento.
// Nada aqui decide resultado nem altera o placar.

export const L = 105
export const W = 68
const GOAL_HALF = 3.66
const SPEED = 7.2 // m/s corrida
const BALL_SPEED = 21

const rnd = (() => {
  let s = 1234567
  return () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff
    return s / 0x7fffffff
  }
})()
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y)

const SHOT_KINDS = new Set(['goal', 'pen_goal', 'save', 'shot_off', 'pen_miss'])
export const BANNER_KINDS = {
  goal: { img: 'goal', ms: 2200 },
  pen_goal: { img: 'goal', ms: 2200 },
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
    players: [],
    ball: { x: L / 2, y: W / 2, z: 0, vx: 0, vy: 0, vz: 0, owner: null, flight: null, hidden: false },
    poss: 'h',
    hold: 1,
    seq: null,
    queue: [],
    banners: [],
    stopped: 0,
    possShare: 0.5,
    pendingGoals: new Map(), // gols reais ainda não mostrados em campo (seq → lado)
    homeId,
    awayId,
  }

  const dirOf = (side) => ((side === 'h') === (st.half === 1) ? 1 : -1)
  const goalX = (side) => (dirOf(side) === 1 ? L : 0) // gol que o time ATACA

  function slotBase(form, slot, side) {
    const s = formations?.[form]?.slots?.find((x) => x.slot === slot)
    const depth = s ? (100 - s.y) / 100 : 0.5
    const width = s ? s.x / 100 : 0.5
    const d = dirOf(side)
    const x = d === 1 ? 2 + depth * 48 : L - 2 - depth * 48
    const y = d === 1 ? width * W : W - width * W
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
      return {
        id: p.id,
        side: p.side,
        name: p.name,
        number: p.number,
        gk,
        slot: p.slot,
        form,
        depth: base.depth,
        x: old ? old.x : base.x,
        y: old ? old.y : base.y,
        vx: 0,
        vy: 0,
        face: p.side === 'h' ? 'direita' : 'esquerda',
        kickT: 0,
        pose: null,
        poseT: 0,
        runT: rnd(),
        tx: base.x,
        ty: base.y,
      }
    })
    if (st.ball.owner && !st.players.some((p) => p.id === st.ball.owner)) st.ball.owner = null
  }

  const team = (side) => st.players.filter((p) => p.side === side)
  const byId = (id) => st.players.find((p) => p.id === id)
  const keeper = (side) => team(side).find((p) => p.gk) || team(side)[0]

  function kickoff(side) {
    for (const p of st.players) {
      const b = slotBase(p.form, p.slot, p.side)
      const d = dirOf(p.side)
      p.x = clamp(b.x - d * 4, 1, L - 1)
      p.y = b.y
      if (p.side !== side) p.x = d === 1 ? Math.min(p.x, L / 2 - 9.5) : Math.max(p.x, L / 2 + 9.5)
      else p.x = d === 1 ? Math.min(p.x, L / 2 - 1) : Math.max(p.x, L / 2 + 1)
      p.vx = p.vy = 0
    }
    const att = team(side).filter((p) => !p.gk).sort((a, b) => b.depth - a.depth)
    const taker = att[0]
    if (taker) {
      taker.x = L / 2 - dirOf(side) * 0.6
      taker.y = W / 2
    }
    Object.assign(st.ball, { x: L / 2, y: W / 2, z: 0, vx: 0, vy: 0, vz: 0, flight: null, owner: taker?.id || null, hidden: false })
    st.poss = side
    st.hold = 0.9
  }

  function passTo(target, opts = {}) {
    const b = st.ball
    const from = { x: b.x, y: b.y }
    const to = { x: target.x + (opts.lead ? target.vx * 0.6 : 0), y: target.y + (opts.lead ? target.vy * 0.6 : 0) }
    const d = Math.max(1, dist(from, to))
    const dur = opts.dur ?? d / (opts.speed ?? BALL_SPEED)
    b.flight = { from, to, t: 0, dur, peak: opts.peak ?? (d > 24 ? Math.min(6, d / 9) : 0.3), z0: b.z, z1: opts.z1 ?? 0, onEnd: opts.onEnd || null, receiver: target.id }
    b.owner = null
    const kicker = opts.kicker
    if (kicker) {
      kicker.kickT = 0.28
    }
  }

  function chooseReceiver(owner) {
    const mates = team(owner.side).filter((p) => p.id !== owner.id && !p.gk)
    if (!mates.length) return null
    const d = dirOf(owner.side)
    let best = null
    let bestScore = -1
    for (const m of mates) {
      const dd = dist(owner, m)
      if (dd < 5 || dd > 38) continue
      const forward = (m.x - owner.x) * d
      const score = (1 + clamp(forward / 20, -0.6, 1.2)) * (1 - dd / 60) * (0.6 + rnd() * 0.8)
      if (score > bestScore) {
        bestScore = score
        best = m
      }
    }
    return best || mates[Math.floor(rnd() * mates.length)]
  }

  // ---------- jogadas roteirizadas a partir dos eventos ----------
  function enqueue(ev) {
    if (ev.kind === 'goal' || ev.kind === 'pen_goal') st.pendingGoals.set(ev.seq, ev.side)
    st.queue.push(ev)
  }

  function banner(kind, ev, extra = {}) {
    if (kind === 'goal' && ev) st.pendingGoals.delete(ev.seq)
    const meta = BANNER_KINDS[kind]
    if (!meta) return
    st.banners.push({ id: `${ev?.seq ?? 'x'}-${kind}`, kind, img: meta.img, ms: meta.ms, ev, ...extra })
  }

  function startSequence(ev) {
    const side = ev.side || st.poss
    const opp = side === 'h' ? 'a' : 'h'
    const shooter = byId(ev.player) || team(side).filter((p) => !p.gk).sort((a, b) => b.depth - a.depth)[Math.floor(rnd() * 3)]
    const gx = goalX(side)
    const d = dirOf(side)
    if (SHOT_KINDS.has(ev.kind)) {
      const pen = ev.kind === 'pen_goal' || ev.kind === 'pen_miss'
      const spot = pen ? { x: gx - d * 11, y: W / 2 } : { x: gx - d * (12 + rnd() * 10), y: W / 2 + (rnd() - 0.5) * 22 }
      st.seq = { ev, kind: 'shot', phase: 0, t: 0, side, opp, shooter, spot, pen }
      st.poss = side
      if (pen) {
        st.stopped = 0.6
        banner('foul', ev, { text: 'Pênalti!' })
      }
      return
    }
    if (ev.kind === 'yellow' || ev.kind === 'red' || ev.kind === 'second_yellow') {
      st.seq = { ev, kind: 'foul', t: 0, side, opp, culprit: shooter }
      st.stopped = 1.4
      banner('foul', ev, { text: 'Falta' })
      banner(ev.kind, ev)
      return
    }
    if (ev.kind === 'offside') {
      st.stopped = 1
      banner('offside', ev)
      st.seq = { ev, kind: 'restart', t: 0, side: opp }
      return
    }
    if (ev.kind === 'injury') {
      st.stopped = 1.4
      banner('injury', ev)
      return
    }
    if (ev.kind === 'sub') {
      banner('sub', ev)
      return
    }
    if (ev.kind === 'kickoff') {
      kickoff('h')
      return
    }
    if (ev.kind === 'ht' || ev.kind === 'et_ht') {
      banner('text', ev)
      st.banners.push({ id: `${ev.seq}-ht`, kind: 'text', text: 'Intervalo', ms: 1600 })
      return
    }
    if (ev.kind === 'ft') st.banners.push({ id: `${ev.seq}-ft`, kind: 'text', text: 'Fim de jogo', ms: 2000 })
  }

  function stepShot(seq, dt) {
    seq.t += dt
    const s = seq.shooter
    if (!s) {
      st.pendingGoals.delete(seq.ev.seq)
      st.seq = null
      return
    }
    const gk = keeper(seq.opp)
    const gx = goalX(seq.side)
    const d = dirOf(seq.side)
    if (seq.phase === 0) {
      // aproximação: quem finaliza corre para a posição de chute e recebe a bola
      s.tx = seq.spot.x
      s.ty = seq.spot.y
      if (seq.pen) {
        s.x = seq.spot.x - d * 1.5
        s.y = seq.spot.y
        Object.assign(st.ball, { x: seq.spot.x, y: seq.spot.y, z: 0, owner: null, flight: null })
        if (gk) {
          gk.x = gx - d * 0.4
          gk.y = W / 2
        }
        seq.phase = 1
        seq.t = 0
        return
      }
      if (!st.ball.flight && (st.ball.owner !== s.id || dist(s, seq.spot) > 3)) {
        if (dist(s, seq.spot) > 9) {
          s.x += (seq.spot.x - s.x) * Math.min(1, dt * 2.2)
          s.y += (seq.spot.y - s.y) * Math.min(1, dt * 2.2)
        }
        if (seq.t > 0.25 && !seq.passed) {
          seq.passed = true
          passTo({ x: seq.spot.x, y: seq.spot.y, vx: 0, vy: 0, id: s.id }, { speed: 26, peak: 0.6 })
        }
      }
      if ((st.ball.owner === s.id || (!st.ball.flight && seq.passed)) && seq.t > 0.5) {
        seq.phase = 1
        seq.t = 0
      }
      if (seq.t > 2.2) {
        seq.phase = 1
        seq.t = 0
      }
      return
    }
    if (seq.phase === 1 && seq.t > (seq.pen ? 0.9 : 0.25)) {
      // finalização
      Object.assign(st.ball, { x: s.x + d * 0.6, y: s.y, z: 0 })
      const k = seq.ev.kind
      const goalY = W / 2 + (rnd() - 0.5) * (GOAL_HALF * 1.6)
      let to
      let z1
      if (k === 'goal' || k === 'pen_goal') {
        to = { x: gx + d * 0.8, y: goalY }
        z1 = 0.3 + rnd() * 1.6
      } else if (k === 'save' || (k === 'pen_miss' && seq.ev.detail === 'defendido')) {
        to = { x: gx - d * 0.6, y: goalY }
        z1 = 0.4 + rnd() * 1.4
      } else {
        const wide = rnd() < 0.5
        to = wide ? { x: gx + d * 0.5, y: W / 2 + (rnd() < 0.5 ? -1 : 1) * (GOAL_HALF + 1 + rnd() * 3) } : { x: gx + d * 0.5, y: goalY }
        z1 = wide ? 0.4 + rnd() : 2.7 + rnd() * 1.2
      }
      passTo({ ...to, vx: 0, vy: 0, id: null }, { speed: 30, peak: Math.max(z1, 0.8), z1, kicker: s })
      s.kickT = 0.35
      seq.phase = 2
      seq.t = 0
      seq.target = to
      return
    }
    if (seq.phase === 2) {
      // goleiro reage
      if (gk && seq.target) {
        const dy = seq.target.y - gk.y
        const k = seq.ev.kind
        if (seq.t > 0.12 && !gk.pose) {
          if (k === 'save' || (k === 'pen_miss' && seq.ev.detail === 'defendido')) gk.pose = Math.abs(dy) < 1 ? 'defesa_alta' : dy * d > 0 ? 'mergulho_direita' : 'mergulho_esquerda'
          else if (k === 'goal' || k === 'pen_goal') gk.pose = dy * d > 0 ? 'mergulho_direita' : 'mergulho_esquerda'
          gk.poseT = 1.1
          gk.y += clamp(dy, -2.2, 2.2)
        }
      }
      if (!st.ball.flight) {
        const k = seq.ev.kind
        if (k === 'goal' || k === 'pen_goal') {
          // bola na rede
          st.ball.x = gx + d * 1.4
          st.ball.z = 0.2
          banner('goal', seq.ev)
          seq.phase = 3
          seq.t = 0
        } else if (k === 'save' || (k === 'pen_miss' && seq.ev.detail === 'defendido')) {
          if (gk) {
            gk.pose = 'segurando_bola'
            gk.poseT = 1
            st.ball.hidden = true
            st.ball.owner = gk.id
          }
          seq.phase = 4
          seq.t = 0
        } else {
          seq.phase = 5
          seq.t = 0
        }
      }
      return
    }
    if (seq.phase === 3) {
      // comemoração e saída de bola
      s.tx = gx - d * 6
      s.ty = s.y < W / 2 ? 2 : W - 2
      if (seq.t > 2.2) {
        st.seq = null
        kickoff(seq.opp)
      }
      return
    }
    if (seq.phase === 4) {
      if (seq.t > 0.9) {
        st.ball.hidden = false
        if (gk) {
          gk.pose = null
          st.ball.owner = gk.id
          st.ball.x = gk.x + d * -0.8
          st.ball.y = gk.y
        }
        st.poss = seq.opp
        st.hold = 0.6
        st.seq = null
      }
      return
    }
    if (seq.phase === 5 && seq.t > 0.7) {
      // tiro de meta
      if (gk) {
        gk.x = gx - d * 5.5
        gk.y = W / 2 + (rnd() - 0.5) * 8
        st.ball.owner = gk.id
        Object.assign(st.ball, { x: gk.x, y: gk.y, z: 0, flight: null })
      }
      st.poss = seq.opp
      st.hold = 1
      st.seq = null
    }
  }

  // ---------- ciclo ----------
  function update(dt) {
    st.t += dt
    if (st.stopped > 0) st.stopped -= dt
    for (const b of st.banners) b.age = (b.age || 0) + dt * 1000
    // fila de banners: o primeiro tem a vez; os demais esperam
    if (st.banners.length && st.banners[0].age >= st.banners[0].ms) st.banners.shift()
    if (st.banners.length > 1) for (let i = 1; i < st.banners.length; i += 1) st.banners[i].age = 0

    if (!st.seq && st.queue.length && st.stopped <= 0) startSequence(st.queue.shift())

    const b = st.ball
    // voo da bola
    if (b.flight) {
      const f = b.flight
      f.t += dt
      const k = clamp(f.t / f.dur, 0, 1)
      b.x = f.from.x + (f.to.x - f.from.x) * k
      b.y = f.from.y + (f.to.y - f.from.y) * k
      b.z = f.z0 + (f.z1 - f.z0) * k + f.peak * 4 * k * (1 - k)
      if (k >= 1) {
        b.flight = null
        b.z = f.z1
        const r = f.receiver ? byId(f.receiver) : null
        if (r && !st.seq) {
          // interceptação ocasional: a posse muda
          if (rnd() < 0.18 + (st.poss === 'h' ? 1 - st.possShare : st.possShare) * 0.12) {
            const opp = team(r.side === 'h' ? 'a' : 'h').filter((p) => !p.gk).sort((a2, b2) => dist(a2, b) - dist(b2, b))[0]
            if (opp) {
              b.owner = opp.id
              st.poss = opp.side
            }
          } else {
            b.owner = r.id
          }
          st.hold = 0.5 + rnd() * 1.3
        } else if (r) b.owner = r.id
        if (f.onEnd) f.onEnd()
      }
    }

    if (st.seq?.kind === 'shot') stepShot(st.seq, dt)
    else if (st.seq?.kind === 'foul') {
      st.seq.t += dt
      if (st.seq.t > 1.3) {
        st.poss = st.seq.opp
        const taker = team(st.seq.opp).filter((p) => !p.gk).sort((a2, b2) => dist(a2, b) - dist(b2, b))[0]
        if (taker) b.owner = taker.id
        st.hold = 0.8
        st.seq = null
      }
    } else if (st.seq?.kind === 'restart') {
      st.seq.t += dt
      if (st.seq.t > 0.9) {
        const gk = keeper(st.seq.side)
        if (gk) {
          b.owner = gk.id
          Object.assign(b, { x: gk.x, y: gk.y, z: 0, flight: null })
        }
        st.poss = st.seq.side
        st.hold = 0.8
        st.seq = null
      }
    }

    // jogo corrido (sem roteiro)
    if (!st.seq && st.stopped <= 0 && !b.flight) {
      let owner = b.owner ? byId(b.owner) : null
      if (!owner) {
        owner = team(st.poss).filter((p) => !p.gk).sort((a2, b2) => dist(a2, b) - dist(b2, b))[0]
        if (owner) b.owner = owner.id
      }
      if (owner) {
        st.poss = owner.side
        st.hold -= dt
        const d = dirOf(owner.side)
        // conduz para a frente sem invadir a área (finalizações só acontecem em eventos reais)
        const limit = goalX(owner.side) - d * 20
        owner.tx = d === 1 ? Math.min(owner.x + 4, limit) : Math.max(owner.x - 4, limit)
        owner.ty = owner.y + (W / 2 - owner.y) * 0.05
        if (st.hold <= 0) {
          const r = chooseReceiver(owner)
          if (r) passTo(r, { lead: true, kicker: owner })
          st.hold = 0.6 + rnd() * 1.2
        }
      }
    }

    // posicionamento dos dois blocos
    const bp = { x: b.x, y: b.y }
    for (const p of st.players) {
      if (st.seq?.kind === 'shot' && p === st.seq.shooter) {
        // alvo definido pelo roteiro
      } else if (b.owner === p.id && !st.seq) {
        // alvo definido pela condução
      } else {
        const base = slotBase(p.form, p.slot, p.side)
        const d = dirOf(p.side)
        const progress = d === 1 ? bp.x / L : 1 - bp.x / L // 0 = perto do próprio gol
        const inPoss = st.poss === p.side
        let x = base.x + d * ((progress - 0.45) * 34 + (inPoss ? 7 : -3))
        let y = base.y + (bp.y - base.y) * (inPoss ? 0.12 : 0.28)
        if (p.gk) {
          x = d === 1 ? clamp(2 + (progress < 0.35 ? 3 : 1), 1, 14) : clamp(L - 2 - (progress < 0.35 ? 3 : 1), L - 14, L - 1)
          y = W / 2 + (bp.y - W / 2) * 0.15
        }
        // quem está mais perto da bola sem posse pressiona
        if (!inPoss && !p.gk && !b.flight) {
          const nearest = team(p.side).filter((q) => !q.gk).sort((a2, b2) => dist(a2, bp) - dist(b2, bp))[0]
          if (nearest === p) {
            x = bp.x - d * 1.2
            y = bp.y
          }
        }
        // recebe o passe
        if (b.flight?.receiver === p.id) {
          x = b.flight.to.x
          y = b.flight.to.y
        }
        p.tx = clamp(x + Math.sin(st.t * 0.7 + p.y) * 0.8, 0.8, L - 0.8)
        p.ty = clamp(y + Math.cos(st.t * 0.6 + p.x) * 0.8, 0.8, W - 0.8)
      }
      const dx = p.tx - p.x
      const dy = p.ty - p.y
      const dd = Math.hypot(dx, dy)
      const max = (st.seq?.kind === 'shot' && p === st.seq.shooter ? SPEED * 1.25 : SPEED) * (st.stopped > 0 ? 0.25 : 1)
      const v = Math.min(max, dd * 2.2)
      p.vx = dd > 0.01 ? (dx / dd) * v : 0
      p.vy = dd > 0.01 ? (dy / dd) * v : 0
      p.x += p.vx * dt
      p.y += p.vy * dt
      if (p.kickT > 0) p.kickT -= dt
      if (p.poseT > 0) {
        p.poseT -= dt
        if (p.poseT <= 0 && p.pose !== 'segurando_bola') p.pose = null
      }
      p.runT += dt * (0.6 + Math.hypot(p.vx, p.vy) / 4)
    }
    // bola acompanha quem conduz
    if (b.owner && !b.flight) {
      const o = byId(b.owner)
      if (o) {
        const d = dirOf(o.side)
        b.x = o.x + (o.vx || d) * 0.08 + d * 0.5
        b.y = o.y + o.vy * 0.08
        b.z = 0
      }
    }
  }

  return {
    state: st,
    sync,
    kickoff,
    enqueue,
    update,
    setHalf(h) {
      if (h !== st.half) {
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
