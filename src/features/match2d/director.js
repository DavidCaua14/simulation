// "Diretor" da transmissão 2.5D. Só APRESENTAÇÃO: placar, lances e cartões vêm do motor no servidor.
// O jogo corrido é contínuo (posse, passes, pressão, bloco que sobe e desce) e cada evento real vira uma jogada
// construída A PARTIR DE ONDE A BOLA ESTÁ: recuperação, troca de passes até a área e a finalização com o resultado
// do evento. Nada é teletransportado. O relógio da partida espera a jogada (holdMinute) para o lance não ser cortado.

export const L = 105
export const W = 68
const GOAL_HALF = 3.66
const SPRINT = 7.6 // m/s
const JOG = 4.6
const ACCEL = 10 // m/s² (arrancada a partir de parado; cai perto da velocidade máxima)
const DECEL = 15 // m/s² (frear é mais rápido que acelerar)
const TURN = 9 // rad/s de giro parado; em velocidade o giro fica mais lento
const PASS_SPEED = 17
const KICK_DELAY = 0.1 // s entre o início do movimento da perna e o contato com a bola
const ROLL_FRICTION = 3.2 // m/s² de desaceleração da bola rolando no gramado
// fases de bola parada / roteiro em que a marcação e os desmarques do jogo corrido não valem
const RESTART = /setup|runup|celebrate|reset|c_out|c_place|whistle|card|freekick|free|goalkick|keeper/
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
  // finalizações sem gol também têm a faixa do lance (mesmo texto do relato)
  save: { img: null, ms: 1800 },
  shot_off: { img: null, ms: 1600 },
  pen_miss: { img: null, ms: 1800 },
}

// highlights: modo "melhores momentos" da transmissão 3D — só finalizações viram jogada no campo (cartão e
// impedimento só aparecem na faixa) e cada ataque é montado na hora, com a tela coberta, a 35–45 m do gol
export function createDirector({ formations, homeId, awayId, highlights = false }) {
  const st = {
    t: 0,
    half: 1,
    pendingHalf: null,
    players: [],
    ball: { x: L / 2, y: W / 2, z: 0, vx: 0, vy: 0, owner: null, flight: null, hidden: false, held: false, spin: 0 },
    poss: 'h',
    hold: 1,
    script: null,
    queue: [],
    banners: [],
    possShare: 0.5,
    lineShift: { h: 0, a: 0 }, // postura do time (ofensivo sobe o bloco, defensivo recua)
    netShake: null,
    released: new Set(), // eventos já mostrados (o relógio pode seguir)
    revealed: [], // lances que a transmissão acabou de mostrar (gol na rede, defesa, cartão): o placar e o relato atualizam na hora
    fx: [], // sons do instante visual (chute, contato, apito, rede, reação da torcida): a tela toca e esvazia
    possSide: null, // time com a bola no quadro anterior (detecta a transição)
    turnoverAt: -99,
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
        // alvo percebido: segue o alvo real com o tempo de reação de cada um (sem giros instantâneos)
        rtx: fresh ? L / 2 : base.x,
        rty: fresh ? W + 1 : base.y,
        react: 0.16 + rnd() * 0.14,
        pace: 0.94 + rnd() * 0.12,
        run: null,
        runCd: 2 + rnd() * 6,
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
  // som/efeito no instante visual (a tela consome com takeFx)
  const fx = (type, extra = {}) => {
    if (st.fx.length < 24) st.fx.push({ type, t: st.t, x: st.ball.x, y: st.ball.y, ...extra })
  }

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
    // snap: início de tempo (todos na posição). Sem snap (reinício após gol), quem ainda está voltando segue correndo.
    if (snap) for (const p of st.players) Object.assign(p, { x: p.tx, y: p.ty, rtx: p.tx, rty: p.ty, vx: 0, vy: 0, anim: null, run: null })
    Object.assign(st.ball, { x: L / 2, y: W / 2, z: 0, vx: 0, vy: 0, flight: null, owner: taker?.id || null, hidden: false, held: false })
    if (taker) taker.dribA = dirOf(side) === 1 ? 0 : Math.PI
    st.poss = side
    st.possSide = side
    st.hold = 0.8
    if (!snap) fx('whistle')
  }

  // ---------- bola ----------
  // Chute/passe. Com batedor, a bola só sai no CONTATO: o movimento da perna começa agora e a bola parte
  // KICK_DELAY depois, do pé dele (até lá ela segue no pé). Sem batedor (rebote, desvio), sai na hora.
  function kick(from, to, opts = {}) {
    const b = st.ball
    const d = Math.max(1, dist(from, to))
    const speed = opts.speed ?? PASS_SPEED
    const dur = opts.dur ?? d / speed
    const peak = opts.peak ?? (d > 28 ? Math.min(7, d / 8) : 0.2)
    const kicker = opts.kicker || null
    b.flight = {
      from: { x: from.x, y: from.y },
      to: { x: to.x, y: to.y },
      t: 0,
      dur,
      peak,
      z0: b.z,
      z1: opts.z1 ?? 0,
      onEnd: opts.onEnd || null,
      receiver: opts.receiver ?? null,
      ground: peak < 0.5,
      side: kicker?.side ?? null,
      kicker: kicker?.id ?? null,
      delay: kicker ? KICK_DELAY : 0,
    }
    b.owner = null
    b.held = false
    b.vx = 0
    b.vy = 0
    if (kicker) {
      play(kicker, opts.anim || 'kick', opts.animDur || 0.32)
      kicker.face = faceIndex(to.x - from.x, to.y - from.y)
      kicker.dribA = Math.atan2(to.y - kicker.y, to.x - kicker.x)
    }
  }
  // bola solta (desarme, rebote, dividida): rola alguns metros sem dono, e quem chegar primeiro domina
  function loose(to, speed = 9) {
    const b = st.ball
    kick({ x: b.x, y: b.y }, { x: clamp(to.x, 0.5, L - 0.5), y: clamp(to.y, 0.5, W - 0.5) }, { speed, peak: 0.1 })
  }
  // passe para um colega: mira na frente dele e dosa a força para a bola chegar quando ELE chega
  // (nem o receptor espera parado, nem volta para buscar uma bola que ficou para trás)
  function pass(owner, target, opts = {}) {
    const lead = opts.lead ?? 0.5
    const to = { x: clamp(target.x + target.vx * lead, 1, L - 1), y: clamp(target.y + target.vy * lead, 1, W - 1) }
    target.tx = to.x
    target.ty = to.y
    const d = Math.max(1, dist(owner, to))
    const run = dist(target, to) / (SPRINT * 0.85) + (target.react || 0.2)
    const speed = opts.speed ?? PASS_SPEED
    // o tempo da bola é o da corrida dele, sem ficar lenta demais (mínimo ~8 m/s)
    const dur = clamp(Math.max(d / speed, run), d / 30, d / 8)
    kick(owner, to, { ...opts, dur, kicker: owner, receiver: target.id })
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
      // no jogo corrido ninguém recebe dentro da área adversária: lá só entra o lance do motor (finalização)
      if (Math.abs(goalX(owner.side) - m.x) < 17) continue
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
  const release = (ev) => {
    if (!ev || st.released.has(ev.seq)) return
    st.released.add(ev.seq)
    if (HOLD_KINDS.has(ev.kind)) st.revealed.push(ev.seq)
  }
  // a bola vai até quem deve ficar com ela (passe curto, rebote, entrega do árbitro): nunca salta para o pé de alguém
  function rollTo(p, opts = {}) {
    const b = st.ball
    const d = dist(p, b)
    const to = { x: lerp(b.x, p.x, opts.k ?? 0.75), y: lerp(b.y, p.y, opts.k ?? 0.75) }
    kick({ x: b.x, y: b.y }, to, { speed: clamp(d * 1.1, 7, 18), peak: d > 26 ? 2.5 : 0.15, receiver: p.id })
    p.tx = to.x
    p.ty = to.y
  }
  function banner(kind, ev, extra = {}) {
    const meta = BANNER_KINDS[kind]
    if (!meta && kind !== 'text') return
    st.banners.push({ id: `${ev?.seq ?? st.t}-${kind}`, kind, img: meta?.img, ms: meta?.ms ?? extra.ms ?? 1600, ev, ...extra })
  }

  // Monta o ataque na hora (a tela da transmissão está coberta): bola com um meio-campista do time que ataca a
  // 35–45 m do gol, todos na forma tática a partir dessa bola, parados. O lance começa direto na construção.
  function stageAttack(s) {
    const b = st.ball
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    const start = { x: clamp(gx - d * (36 + rnd() * 9), 8, L - 8), y: clamp(W / 2 + (rnd() - 0.5) * 34, 8, W - 8) }
    Object.assign(b, { x: start.x, y: start.y, z: 0, flight: null, owner: null, held: false, hidden: false, vx: 0, vy: 0 })
    st.poss = s.side
    st.possSide = s.side
    st.turnoverAt = -99
    for (const p of st.players) {
      const t = shape(p)
      p.x = t.x
      p.y = t.y
      p.tx = t.x
      p.ty = t.y
      p.rtx = t.x
      p.rty = t.y
      p.vx = 0
      p.vy = 0
      p.anim = null
      p.run = null
    }
    const carrier = outfield(s.side).filter((p) => p !== s.shooter && p !== s.assist).sort((a, c) => dist(a, start) - dist(c, start))[0] || nearest(outfield(s.side), start)
    if (carrier) {
      carrier.x = start.x - d * 0.6
      carrier.y = start.y
      b.owner = carrier.id
    }
    s.steps = planSteps(s)
    s.phase = 'build'
    s.t = 0
    s.staged = true
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
      // gol sai de perto (8 a 17 m); defesa e chute para fora também podem vir de média distância (até 26 m)
      const scored = ev.kind === 'goal'
      const range = scored ? 8 + rnd() * 9 : ev.detail === 'grande chance' ? 7 + rnd() * 7 : 11 + rnd() * 15
      const spot = pen ? { x: gx - d * 11, y: W / 2 } : { x: gx - d * range, y: clamp(laneY + (rnd() - 0.5) * 10, W / 2 - (scored ? 10 : 15), W / 2 + (scored ? 10 : 15)) }
      const a2 = scored ? byId(ev.player2) : null
      const assist = a2 && a2.side === side && !a2.gk && a2 !== shooter ? a2 : null
      // com assistente, sem tabela improvisada no fim: o último passe é dele
      st.script = { ev, kind: pen ? 'penalty' : 'attack', phase: 'win', t: 0, side, opp: other(side), shooter, spot, steps: null, assist, oneTwo: Boolean(assist) }
      if (highlights && !pen) stageAttack(st.script)
      if (pen) {
        st.script.phase = 'setup'
        st.ball.owner = null
        st.ball.flight = null
        banner('foul', ev, { text: 'Pênalti!' })
      }
      return
    }
    // melhores momentos: cartão e impedimento não viram jogada no campo, só a faixa e o relato
    if (highlights && (CARD_KINDS.has(ev.kind) || ev.kind === 'offside')) {
      banner(ev.kind, ev)
      release(ev)
      return
    }
    if (CARD_KINDS.has(ev.kind)) {
      const named = byId(ev.player)
      const culprit = named && named.side === side && !named.gk ? named : nearest(outfield(side), st.ball)
      st.script = { ev, kind: 'foul', phase: 'setup', t: 0, side, opp: other(side), culprit, named: culprit === named, win: { side: other(side), t: 0 } }
      return
    }
    if (ev.kind === 'offside') {
      st.script = { ev, kind: 'offside', phase: 'win', t: 0, side, opp: other(side) }
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
    const pt = owner ? b : ballStop()
    hunter.tx = pt.x
    hunter.ty = pt.y
    hunter.speed = SPRINT
    if (owner) {
      owner.speed = 3
    }
    if (dist(hunter, b) < 1.3) {
      b.owner = hunter.id
      st.poss = s.side
      if (owner) {
        play(owner, 'stumble', 0.4)
        fx('tackle')
      }
      return true
    }
    // demorou: desarme/rebote empurra a bola na direção de quem caça, que domina quando ela chega
    if (s.t - (s.pokedAt ?? 0) > 2.6) {
      s.pokedAt = s.t
      if (owner) play(owner, 'stumble', 0.4)
      rollTo(hunter, { k: 0.6 })
    }
    return false
  }

  // Divide o caminho da bola até o ponto de finalização em passes de até ~24 m, com colegas que correm para cada ponto.
  function planSteps(s) {
    const b = st.ball
    const d = dirOf(s.side)
    // a bola já está mais perto do gol que o ponto de finalização: o ponto vem para o lado dela (mesma
    // profundidade), e o último passe sai rolado para o lado em vez de voltar para a entrada da área
    const gxP = goalX(s.side)
    if (Math.abs(gxP - b.x) < Math.abs(gxP - s.spot.x) - 3) {
      s.spot = { x: clamp(b.x - d * 1.5, 6, L - 6), y: clamp(b.y + (b.y < W / 2 ? 9 : -9), W / 2 - 14, W / 2 + 14) }
      if (Math.abs(gxP - s.spot.x) < 7) s.spot.x = gxP - d * 7
    }
    const total = Math.abs(s.spot.x - b.x)
    const n = clamp(Math.ceil(total / 22), 1, 4)
    const used = new Set([s.shooter?.id])
    const steps = []
    // o assistente já começa com a bola: ele mesmo dá o último passe (sem rodar a bola por outros antes)
    if (s.assist && s.assist.id === b.owner) return [{ who: s.shooter, at: s.spot, final: true }]
    for (let i = 1; i < n; i += 1) {
      const k = i / n
      const wp = {
        x: clamp(lerp(b.x, s.spot.x, k) + d * 2, 4, L - 4),
        y: clamp(lerp(b.y, s.spot.y, k) + (rnd() - 0.5) * 24, 6, W - 6),
      }
      const mate = outfield(s.side).filter((p) => !used.has(p.id) && p.id !== b.owner && p !== s.assist).sort((a, c) => dist(a, wp) - dist(c, wp))[0]
      if (!mate) continue
      used.add(mate.id)
      steps.push({ who: mate, at: wp })
    }
    // gol com assistência: quem o relato cita como assistente dá o ÚLTIMO passe para o finalizador
    if (s.assist && s.assist.id !== b.owner) {
      // ao lado do ponto de finalização (quase a mesma distância do gol): o último passe sai rolado para o lado,
      // nunca um toque para trás na cara do goleiro
      const at = { x: clamp(s.spot.x - d * (1 + rnd() * 2), 4, L - 4), y: clamp(s.spot.y + (s.spot.y < W / 2 ? 1 : -1) * (8 + rnd() * 4), 4, W - 4) }
      s.assistAt = at
      steps.push({ who: s.assist, at })
    }
    steps.push({ who: s.shooter, at: s.spot, final: true })
    return steps
  }

  // A bola volta ao assistente no ponto AO LADO do finalizador (s.assistAt), não onde ele está agora (que pode
  // ser lá atrás): ela chega no tempo da corrida dele, com folga para não parar antes e virar bola solta.
  // Passe do roteiro para o ponto combinado (não para onde o colega está agora), no tempo da corrida dele.
  function passTo(owner, who, at) {
    const run = (dist(who, at) / (SPRINT * 0.85) + (who.react || 0.2)) * 1.2 + 0.15
    who.tx = at.x
    who.ty = at.y
    const dd = dist(owner, at)
    kick(owner, at, { dur: Math.max(dd / (dd > 25 ? 22 : PASS_SPEED + 2), run), kicker: owner, receiver: who.id, peak: dd > 25 ? 3 : 0.2 })
  }
  function toAssist(s, owner) {
    const a = s.assist
    let spot = s.assistAt || { x: s.spot.x - dirOf(s.side) * 2, y: clamp(s.spot.y + (s.spot.y < W / 2 ? 10 : -10), 4, W - 4) }
    // assistente longe: o passe vai para o caminho dele (no máximo ~2,2 s de corrida), não para um ponto que ele
    // levaria muitos segundos para alcançar (a bola não fica rolando esperando)
    const reach = 2.2 * SPRINT * 0.85
    const da = dist(a, spot)
    if (da > reach) spot = { x: a.x + ((spot.x - a.x) * reach) / da, y: a.y + ((spot.y - a.y) * reach) / da }
    // e nunca para trás de quem passa: no máximo 3 m mais longe do gol do que ele
    const gxA = goalX(s.side)
    const dA = dirOf(s.side)
    if (Math.abs(gxA - spot.x) > Math.abs(gxA - owner.x) + 3) spot = { x: gxA - dA * (Math.abs(gxA - owner.x) + 3), y: spot.y }
    const run = (dist(a, spot) / (SPRINT * 0.85) + (a.react || 0.2)) * 1.35 + 0.3
    a.tx = spot.x
    a.ty = spot.y
    kick(owner, spot, { dur: Math.max(dist(owner, spot) / (PASS_SPEED + 2), run), kicker: owner, receiver: a.id, peak: dist(owner, spot) > 24 ? 3 : 0.2 })
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
      // o finalizador pegou a bola antes da hora: sem assistente, vai direto para a finalização (não devolve para trás)
      if (owner === s.shooter && !s.assist) {
        s.steps = [s.steps[s.steps.length - 1]]
        s.phase = 'carry'
        s.t = 0
        return
      }
      // alguém mais à frente na fila (assistente, finalizador) pegou a bola antes da vez: as etapas anteriores caem
      // (não devolve para quem ficou para trás). O finalizador com assistente ainda recebe dele o último passe.
      const idx = s.steps.findIndex((x) => x.who === owner)
      const aIdx = s.steps.findIndex((x) => x.who === s.assist)
      const from = idx > 0 ? (owner === s.shooter && aIdx >= 0 && aIdx < idx ? aIdx : idx) : 0
      if (from > 0) {
        s.steps = s.steps.slice(from)
        return
      }
      if (owner === step.who) {
        s.steps.shift()
        s.t = 0
        if (step.final) {
          s.phase = 'carry'
          s.t = 0
        }
        return
      }
      // conduz em direção ao alvo e passa quando o colega chega (ou o tempo aperta); quem não vai finalizar
      // não entra na área: para a 20 m do gol (assim ninguém toca para trás na cara do goleiro)
      const stopX = gx - d * 20
      owner.tx = d === 1 ? Math.min(owner.x + 4, Math.max(owner.x, stopX)) : Math.max(owner.x - 4, Math.min(owner.x, stopX))
      owner.ty = owner.y + (step.at.y - owner.y) * 0.1
      owner.speed = JOG + 1
      const near = dist(step.who, step.at) < 5
      if ((near && s.t > 0.5) || s.t > 2.4) {
        // o último passe é do assistente do relato: se a bola caiu com outro colega, ela volta antes para ele
        const to = step.final && s.assist && owner !== s.assist && s.assist !== step.who ? s.assist : step.who
        if (to === s.assist) toAssist(s, owner)
        else passTo(owner, to, step.at)
        s.t = 0
      }
      return
    }
    if (s.phase === 'carry') {
      // ninguém finaliza do meio-campo: o finalizador conduz até a zona de chute; longe demais, tabela com um colega à frente
      const sh = s.shooter
      const owner = b.owner ? byId(b.owner) : null
      if (b.flight) return
      if (owner !== sh) {
        if (owner && owner.side === s.side) {
          // o colega da tabela avança (até 20 m do gol) e devolve na frente
          const stopX = gx - d * 20
          owner.tx = d === 1 ? Math.min(owner.x + 4, Math.max(owner.x, stopX)) : Math.max(owner.x - 4, Math.min(owner.x, stopX))
          owner.ty = owner.y
          owner.speed = JOG + 1.5
          sh.tx = s.spot.x
          sh.ty = s.spot.y
          sh.speed = SPRINT
          // com assistente no relato, a bola passa por ele antes do finalizador (o último passe é dele)
          const via = s.assist && owner !== s.assist && s.assist !== sh ? s.assist : null
          if (via) {
            via.tx = lerp(owner.x, s.spot.x, 0.6)
            via.ty = lerp(owner.y, s.spot.y, 0.6)
            via.speed = SPRINT
          }
          if (dist(sh, s.spot) < 6 || s.t > 2.2) {
            if (via) toAssist(s, owner)
            else pass(owner, sh, { lead: 0.3, speed: 20, peak: dist(owner, sh) > 24 ? 3 : 0.2 })
            s.t = 0
          }
        } else {
          s.phase = 'win'
          s.t = 0
        }
        return
      }
      const toGoal = Math.abs(gx - sh.x)
      if (toGoal <= Math.abs(gx - s.spot.x) + 1.5 || dist(sh, s.spot) < 2.5) {
        s.phase = 'aim'
        s.t = 0
        return
      }
      sh.tx = s.spot.x
      sh.ty = s.spot.y
      sh.speed = SPRINT - 1
      if (dist(sh, s.spot) > 30 && s.t > 0.6 && !s.oneTwo) {
        const mate = outfield(s.side).filter((m) => m !== sh && (m.x - sh.x) * d > 6 && dist(m, sh) < 30).sort((a, c) => dist(a, s.spot) - dist(c, s.spot))[0]
        if (mate) {
          s.oneTwo = true
          pass(sh, mate, { lead: 0.3 })
          s.t = 0
        }
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
    const scored = k === 'goal' || k === 'pen_goal'
    const pen = s.kind === 'penalty'
    const speed = pen ? 24 : 27
    const from = { x: st.ball.x, y: st.ball.y }
    const postLo = W / 2 - GOAL_HALF + 0.3
    const postHi = W / 2 + GOAL_HALF - 0.3
    // ---- o goleiro e o tempo que ele tem: reação depois do contato + mergulho limitado pelo corpo ----
    const gy0 = gk ? clamp(gk.y, W / 2 - GOAL_HALF - 0.5, W / 2 + GOAL_HALF + 0.5) : W / 2
    const gkX = gk ? gk.x : gx - d * 0.8
    const arrive = KICK_DELAY + Math.abs(gkX - from.x) / speed // quando a bola chega à linha do goleiro
    const react = pen ? 0.04 + rnd() * 0.05 : 0.16 + rnd() * 0.08 // no pênalti ele sai no chute (aposta num lado)
    const move = Math.max(0, arrive - KICK_DELAY - react)
    // alcance lateral das mãos: passo/impulso (~5 m/s) + braço estendido; nunca mais que ~2,7 m
    const reach = clamp(0.85 + 5 * move, 0.85, 2.7)
    const awayFromGk = Math.sign(W / 2 - gy0) || (rnd() < 0.5 ? -1 : 1)
    let to
    let z1
    let plan = null // { y: centro do corpo no fim do lance, anim, h }
    const blocker = k === 'shot_off' && s.ev.detail === 'bloqueado' ? nearest(outfield(s.opp), { x: lerp(sh.x, gx, 0.35), y: lerp(sh.y, W / 2, 0.35) }) : null
    if (blocker) {
      // o zagueiro entra na frente do chute
      to = { x: lerp(sh.x, gx, 0.3), y: lerp(sh.y, W / 2, 0.3) }
      blocker.x = lerp(blocker.x, to.x, 0.5)
      blocker.y = lerp(blocker.y, to.y, 0.5)
      blocker.tx = to.x
      blocker.ty = to.y
      z1 = 0.4
      s.blocked = blocker
    } else if (scored) {
      // gol: no canto que o goleiro NÃO alcança (ou no ângulo, acima da mão, quando o canto está ao alcance);
      // a bola termina no fundo da rede (1,6 m além da linha) e o gol é anunciado quando cruza a linha
      const side = pen && rnd() < 0.5 ? -awayFromGk : awayFromGk
      let y = clamp(gy0 + side * (reach + 0.4 + rnd() * 0.6), postLo, postHi)
      z1 = rnd() < 0.55 ? 0.2 + rnd() * 0.5 : 1.3 + rnd() * 0.6
      if (Math.abs(y - gy0) < reach + 0.3) {
        y = side > 0 ? postHi : postLo
        z1 = 2.05 + rnd() * 0.2 // no ângulo: acima da mão do mergulho
      }
      to = { x: gx + d * 1.6, y }
      // o goleiro vai na bola e fica curto (ponta dos dedos a ~0,4 m)
      const dy = y - gy0
      const bodyY = gy0 + Math.sign(dy) * Math.max(0, Math.min(reach, Math.abs(dy) - 0.4) - 0.75)
      plan = { y: bodyY, anim: Math.abs(dy) < 1 ? 'catch' : 'dive', h: Math.min(z1, 1.8), miss: true }
    } else if (saved) {
      // defesa: a bola vai exatamente onde as mãos chegam a tempo
      const off = (rnd() < 0.5 ? -1 : 1) * (0.15 + rnd() * (reach - 0.15))
      const y = clamp(gy0 + off, postLo - 0.2, postHi + 0.2)
      const lateral = Math.abs(y - gy0)
      z1 = lateral < 0.9 ? 0.4 + rnd() * 1.3 : 0.25 + rnd() * 1.4
      to = { x: gkX - d * 0.35, y } // as mãos ficam um pouco à frente do corpo
      plan = { y: lateral < 0.9 ? y : y - Math.sign(y - gy0) * 0.75, anim: lateral < 0.9 ? 'catch' : 'dive', h: z1 }
    } else {
      // para fora tem de PARECER para fora: pelo lado, a bola passa a 1,6 m ou mais da trave; por cima, cruza a
      // linha bem acima do travessão. Nos dois casos ela termina atrás do gol, nunca dentro da rede.
      const wide = rnd() < 0.55
      const sideY = rnd() < 0.5 ? -1 : 1
      // o ponto que importa é onde a bola CRUZA a linha do gol; o alvo fica atrás dele, na mesma reta do chute
      // (num chute cruzado, mirar só atrás do gol faria a bola passar entre as traves)
      const cross = wide ? { x: gx, y: W / 2 + sideY * (GOAL_HALF + 1.6 + rnd() * 3.5) } : { x: gx, y: W / 2 + sideY * rnd() * (GOAL_HALF - 0.5) }
      const ux = cross.x - from.x
      const uy = cross.y - from.y
      const ul = Math.hypot(ux, uy) || 1
      const beyond = wide ? 4 : 6
      to = { x: cross.x + (ux / ul) * beyond, y: clamp(cross.y + (uy / ul) * beyond, -3, W + 3) }
      z1 = wide ? 0.3 + rnd() : 4 + rnd() * 1.5
      // para fora: só se estica se a bola passar perto; por cima, acompanha com um pulo curto
      const dy = to.y - gy0
      if (wide && Math.abs(dy) < reach + 1.2) plan = { y: gy0 + Math.sign(dy) * Math.max(0, Math.min(reach, Math.abs(dy)) - 1.1), anim: 'dive', h: Math.min(z1, 1.2), miss: true }
      else if (!wide) plan = { y: gy0 + clamp(dy, -0.8, 0.8), anim: 'jump', h: 2.2, miss: true }
    }
    const far = dist(sh, to)
    const over = !scored && !saved && !blocker && Math.abs(to.y - W / 2) < GOAL_HALF
    kick(from, to, { speed, peak: over ? Math.max(2.5, z1 * 0.7) : Math.max(z1 * 0.6, far > 20 ? 1.4 : 0.6), z1, kicker: sh })
    s.target = to
    s.saved = saved
    s.phase = 'flight'
    s.t = 0
    s.gk = gk && plan ? { ...plan, y0: gy0, at: KICK_DELAY + react, arrive, started: false } : null
  }

  // Goleiro durante o voo da bola: espera a reação, então mergulha/encaixa/pula e chega ao ponto planejado junto com a bola.
  // Limites: não passa da trave (com folga do corpo), não entra no gol, não desliza depois de cair.
  function keeperFlight(s, gk, dt, gx, d) {
    const g = s.gk
    if (!g || !gk) return
    if (!g.started && s.t >= g.at) {
      g.started = true
      const left = Math.max(0.18, g.arrive - g.at)
      g.speedY = Math.abs(g.y - gk.y) / left
      const dyS = Math.sign(g.y - gk.y) || 1
      if (g.anim === 'dive') gk.anim = { name: dyS > 0 ? 'dive_right' : 'dive_left', t: 0, dur: left + 0.15, hold: true, dy: dyS, h: g.h }
      else if (g.anim === 'jump') gk.anim = { name: 'catch_high', t: 0, dur: left + 0.25, hold: false, h: g.h }
      else gk.anim = { name: g.h > 1.3 ? 'catch_high' : 'catch_low', t: 0, dur: left + 0.3, hold: true, h: g.h }
    }
    if (g.started) {
      const step = clamp(g.y - gk.y, -g.speedY * dt, g.speedY * dt)
      gk.y = clamp(gk.y + step, W / 2 - GOAL_HALF - 0.6, W / 2 + GOAL_HALF + 0.6)
      // nunca atrás da linha do gol
      if ((gk.x - gx) * d > -0.3) gk.x = gx - d * 0.3
    }
    gk.vx = 0
    gk.vy = 0
    gk.tx = gk.rtx = gk.x
    gk.ty = gk.rty = gk.y
  }

  function stepFinish(s, dt, gx, d) {
    const b = st.ball
    const gk = keeper(s.opp)
    const k = s.ev.kind
    if (s.phase === 'flight') {
      keeperFlight(s, gk, dt, gx, d)
      const isGoal = k === 'goal' || k === 'pen_goal'
      // GOL só quando a bola inteira passa a linha (raio ~0,11 m): placar, narração e torcida neste instante
      if (isGoal && !s.crossed && (b.x - gx) * d > 0.11) {
        s.crossed = true
        banner('goal', s.ev)
        release(s.ev)
        fx('net')
      }
      if (b.flight) return
      if (isGoal) {
        // a bola estufa a rede
        Object.assign(b, { z: Math.min(b.z, 1.6) })
        st.netShake = { side: gx === L ? 1 : 0, t: 0 }
        if (!s.crossed) {
          s.crossed = true
          banner('goal', s.ev)
          release(s.ev)
          fx('net')
        }
        s.phase = 'celebrate'
        s.t = 0
        s.corner = { x: gx - d * 2, y: s.shooter.y < W / 2 ? 2 : W - 2 }
        return
      }
      const calm = st.queue.length < 2 // com lances na fila, sem lance extra
      if (!s.saved) fx('ooh')
      if (s.saved && gk) {
        fx('save')
        banner(s.ev.kind, s.ev)
        release(s.ev)
        if (s.kind === 'attack' && calm && rnd() < (s.ev.detail === 'grande chance' ? 0.6 : 0.3)) {
          // espalma para fora: escanteio (a bola sai das mãos dele)
          startCorner(s, { x: gk.x, y: gk.y })
          return
        }
        // encaixa: a bola fica nas mãos (visível), não some
        b.owner = gk.id
        b.held = true
        b.hidden = false
        s.phase = 'keeper'
        s.t = 0
        return
      }
      banner(s.ev.kind, s.ev)
      release(s.ev)
      if (s.blocked) {
        if (calm && rnd() < 0.55) startCorner(s, { x: b.x, y: b.y })
        else {
          // a bola sobra para a defesa
          b.owner = s.blocked.id
          st.poss = s.opp
          st.hold = 0.7
          st.script = null
        }
        return
      }
      s.phase = 'goalkick'
      s.t = 0
      return
    }
    if (s.phase.startsWith('c_')) {
      stepCorner(s, gx, d)
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
      if (s.t > 2.6) {
        s.phase = 'reset'
        s.t = 0
        kickoffPositions(s.opp)
        // a bola volta ao centro com o árbitro (fora de cena) até a nova saída
        Object.assign(b, { x: L / 2, y: W / 2, z: 0, owner: null, flight: null, hidden: true })
      }
      return
    }
    if (s.phase === 'reset') {
      // os times voltam trotando/correndo às posições de saída; o apito sai quando o batedor e quase todos estão no lugar
      const taker = kickoffPositions(s.opp)
      for (const p of st.players) p.speed = dist(p, { x: p.tx, y: p.ty }) > 8 ? SPRINT : JOG + 1
      const placed = st.players.filter((p) => dist(p, { x: p.tx, y: p.ty }) < 3).length
      const takerSet = !taker || dist(taker, { x: taker.tx, y: taker.ty }) < 1.5
      if ((takerSet && placed >= st.players.length - 4 && s.t > 1.2) || s.t > 4.2) {
        // sem teletransporte: quem ainda não chegou termina a volta com o jogo rolando
        kickoff(s.opp, { snap: false })
        if (taker) Object.assign(st.ball, { x: taker.x + dirOf(s.opp) * 0.6, y: taker.y })
        st.script = null
      }
      return
    }
    if (s.phase === 'keeper') {
      if (gk) {
        gk.speed = 2
        // o goleiro levanta antes de repor (mergulho → de pé → lançamento)
        const down = gk.anim && (gk.anim.name.startsWith('dive') || (gk.anim.name === 'getup' && gk.anim.t < gk.anim.dur * 0.7))
        if (((s.t > 1.1 && !down) || s.t > 3.2) && !s.thrown) {
          s.thrown = true
          b.hidden = false
          // repõe para o colega mais livre perto dele
          const opp = outfield(s.side)
          const mate =
            outfield(s.opp)
              .filter((m) => dist(m, gk) < 40)
              .sort((a, c) => dist(c, nearest(opp, c) || c) - dist(a, nearest(opp, a) || a))[0] || outfield(s.opp)[0]
          // a bola sai da mão dele (já está com ele): lançamento com o braço, sem saltar de lugar
          if (mate) pass(gk, mate, { lead: 0.2, speed: 16, peak: 1.2, anim: 'throw', animDur: 0.7 })
          else play(gk, 'throw', 0.7)
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

  // ---------- escanteio (continuação de uma defesa espalmada ou de um chute travado) ----------
  function startCorner(s, from) {
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    const up = from.y > W / 2
    s.cornerSpot = { x: gx - d * 0.6, y: up ? W - 0.6 : 0.6 }
    Object.assign(st.ball, { owner: null, hidden: false })
    kick({ x: st.ball.x, y: st.ball.y }, { x: gx + d * 1.6, y: W / 2 + (up ? 1 : -1) * (GOAL_HALF + 3 + rnd() * 5) }, { speed: 16, peak: 1.4 })
    banner('text', s.ev, { text: 'Escanteio', ms: 1400 })
    s.phase = 'c_out'
    s.t = 0
  }
  function stepCorner(s, gx, d) {
    const b = st.ball
    const gk = keeper(s.opp)
    if (s.phase === 'c_out') {
      if (b.flight) return
      b.hidden = true
      if (s.t > 1.1) {
        Object.assign(b, { x: s.cornerSpot.x, y: s.cornerSpot.y, z: 0, owner: null, flight: null, hidden: false })
        s.taker = nearest(outfield(s.side), s.cornerSpot)
        // cinco atacantes na área, cada um com um marcador; o resto guarda o rebote
        const att = outfield(s.side).filter((p) => p !== s.taker).sort((a, c) => c.depth - a.depth).slice(0, 5)
        const free = outfield(s.opp).slice()
        s.box = att.map((p, i) => {
          const at = { x: gx - d * (5 + (i % 3) * 3.2 + rnd() * 1.5), y: W / 2 + (i - 2) * 3.6 + (rnd() - 0.5) * 2 }
          const marker = free.sort((a, c) => dist(a, at) - dist(c, at)).shift() || null
          return { p, at, marker }
        })
        s.phase = 'c_place'
        s.t = 0
      }
      return
    }
    if (s.phase === 'c_place') {
      if (s.taker) {
        s.taker.tx = s.cornerSpot.x - d * 0.4
        s.taker.ty = s.cornerSpot.y + (s.cornerSpot.y > W / 2 ? 0.7 : -0.7)
        s.taker.speed = SPRINT
      }
      for (const m of s.box) {
        m.p.tx = m.at.x
        m.p.ty = m.at.y
        m.p.speed = JOG + 1.4
        if (m.marker) {
          m.marker.tx = m.at.x + d * 0.9
          m.marker.ty = m.at.y + 0.5
          m.marker.speed = SPRINT - 1
        }
      }
      if (gk) {
        gk.tx = gx - d * 0.8
        gk.ty = W / 2 + (s.cornerSpot.y > W / 2 ? 1.2 : -1.2)
      }
      const ready = !s.taker || dist(s.taker, { x: s.taker.tx, y: s.taker.ty }) < 1
      if ((ready && s.t > 3) || s.t > 6.5) {
        // a saída do goleiro é decidida no cruzamento (ele só sai se a bola cai perto do gol)
        const close = rnd() < 0.5
        s.crossTo = { x: gx - d * (close ? 4.5 + rnd() * 2 : 7.5 + rnd() * 4), y: W / 2 + (rnd() - 0.5) * 9 }
        s.claim = close && gk ? rnd() < 0.6 : false
        kick({ x: b.x, y: b.y }, s.crossTo, { speed: 19, peak: 5.5, z1: s.claim ? 2.3 : 1.6, kicker: s.taker })
        s.phase = 'c_cross'
        s.t = 0
      }
      return
    }
    if (s.phase === 'c_cross') {
      // todos atacam a bola; o goleiro que vai sair corre para o ponto e salta no tempo da bola
      const header = nearest(outfield(s.side).filter((p) => p !== s.taker), s.crossTo)
      const clearer = nearest(outfield(s.opp), s.crossTo)
      for (const p of [header, clearer]) {
        if (!p) continue
        p.tx = s.crossTo.x
        p.ty = s.crossTo.y
        p.speed = SPRINT
      }
      if (s.claim && gk) {
        gk.tx = s.crossTo.x
        gk.ty = s.crossTo.y
        gk.speed = SPRINT
        const left = b.flight ? b.flight.dur - b.flight.t : 0
        if (left < 0.45 && !s.leapt) {
          s.leapt = true
          play(gk, 'catch_high', 0.9, { hold: true })
          gk.anim.h = 2.3
        }
      }
      if (b.flight) return
      const r = rnd()
      if (s.claim && gk && dist(gk, b) < 1.8) {
        // o goleiro sobe e encaixa no alto: a bola fica nas mãos
        b.owner = gk.id
        b.held = true
        b.hidden = false
        s.thrown = false
        s.phase = 'keeper'
        s.t = 0
        fx('save')
      } else if (r < 0.25 && header && !s.claim) {
        // cabeçada por cima: tiro de meta
        s.target = { x: gx + d * 2, y: W / 2 + (rnd() - 0.5) * 9 }
        kick({ x: b.x, y: b.y }, s.target, { speed: 20, peak: 1.5, z1: 3.4, kicker: header })
        s.placed = false
        s.kicked = false
        s.fired = false
        s.timers = null
        s.phase = 'c_over'
        s.t = 0
      } else if (clearer) {
        // a zaga afasta de cabeça
        const mate = outfield(s.opp).filter((p) => p !== clearer).sort((a, c) => Math.abs(a.x - gx) - Math.abs(c.x - gx)).slice(-4)[Math.floor(rnd() * 4)]
        const to = mate ? { x: mate.x, y: mate.y } : { x: gx - d * 32, y: W / 2 }
        kick({ x: b.x, y: b.y }, to, { speed: 20, peak: 4.5, kicker: clearer, receiver: mate?.id })
        st.poss = s.opp
        st.hold = 0.8
        st.script = null
      } else st.script = null
      return
    }
    if (s.phase === 'c_over' && !b.flight) {
      s.phase = 'goalkick'
      s.t = 0
    }
  }

  // ---------- falta com cartão: sempre uma disputa de bola ----------
  function stepFoul(s) {
    const b = st.ball
    if (s.phase === 'setup') {
      // quem sofre a falta precisa estar com a bola: se ela está com o time do infrator, o adversário recupera antes
      s.win.t = s.t
      if (b.flight && s.t < 3) return
      const owner = b.owner ? byId(b.owner) : null
      if ((owner && owner.side === s.opp && !owner.gk) || (s.t > 5 && owner)) {
        s.victim = owner.side === s.opp ? owner : nearest(outfield(s.opp), b)
        // o infrator é quem o relato cita; só sem nome (ou fora de campo) vale o marcador mais próximo
        if (!s.named && (!s.culprit || s.culprit.gk || dist(s.culprit, s.victim) > 26)) s.culprit = nearest(outfield(s.side), s.victim)
        s.phase = 'approach'
        s.t = 0
        return
      }
      if (owner && owner.gk && owner.side === s.opp) {
        const mate = nearest(outfield(s.opp), owner)
        if (mate) pass(owner, mate, { lead: 0.2 })
        return
      }
      winBall(s.win)
      return
    }
    if (s.phase === 'approach') {
      const c = s.culprit
      const v = s.victim
      if (!c || !v) {
        release(s.ev)
        st.script = null
        return
      }
      // o jogador com a bola segue a jogada; o infrator chega atrasado no lance
      const dv = dirOf(v.side)
      v.tx = clamp(v.x + dv * 5, 4, L - 4)
      v.ty = v.y
      v.speed = JOG + 0.4
      c.tx = v.x
      c.ty = v.y
      c.speed = SPRINT + 0.6
      // infrator citado longe: quem tem a bola segura o passo e ele chega no bote (até ~10 s)
      if (s.named && dist(c, v) > 8) v.speed = 3.2
      if (dist(c, v) < 1.2 || s.t > (s.named ? 10 : 4.5)) {
        if (dist(c, v) > 1.2 && !s.named) {
          // não alcançou a tempo: o marcador mais próximo comete a falta no lance
          const close = nearest(outfield(s.side), v)
          if (close) s.culprit = close
        }
        play(v, 'stumble', 1.1)
        play(s.culprit, 'stumble', 0.5)
        fx('tackle', { hard: true })
        fx('whistle')
        v.vx = 0
        v.vy = 0
        s.culprit.vx *= 0.2
        s.culprit.vy *= 0.2
        b.flight = null
        b.owner = null
        s.spot = { x: v.x, y: v.y }
        // falta (não pênalti) nunca é cobrada dentro da área: o lance foi na entrada da área
        const gxF = goalX(s.opp)
        if (Math.abs(gxF - s.spot.x) < 18.5) s.spot.x = gxF - dirOf(s.opp) * 18.5
        Object.assign(b, { x: s.spot.x + dv * 0.6, y: s.spot.y, z: 0 })
        banner('foul', s.ev, { text: 'Falta' })
        s.phase = 'whistle'
        s.t = 0
      }
      return
    }
    // jogo parado: todos desaceleram
    for (const p of st.players) p.speed = Math.min(p.speed, 2.2)
    if (s.victim) {
      s.victim.tx = s.spot.x
      s.victim.ty = s.spot.y
    }
    if (s.phase === 'whistle') {
      if (s.culprit) {
        s.culprit.tx = s.spot.x - dirOf(s.side) * 2.5
        s.culprit.ty = s.spot.y + 1.5
      }
      if (s.t > 1) {
        banner(s.ev.kind, s.ev)
        release(s.ev)
        s.phase = 'card'
        s.t = 0
      }
      return
    }
    if (s.phase === 'card') {
      if (s.ev.kind !== 'yellow' && s.culprit) {
        // expulso: sai pela lateral
        s.culprit.tx = s.culprit.x
        s.culprit.ty = W + 4
        s.culprit.speed = 2.4
      }
      // barreira a 9 m da bola
      const wall = outfield(s.side).filter((p) => p !== s.culprit || s.ev.kind === 'yellow').sort((a, c) => dist(a, s.spot) - dist(c, s.spot)).slice(0, 2)
      wall.forEach((p, i) => {
        p.tx = s.spot.x + dirOf(s.opp) * 9
        p.ty = s.spot.y + (i ? 1 : -1) * 0.7
        p.speed = JOG
      })
      if (s.t > 1.9) {
        s.phase = 'freekick'
        s.t = 0
      }
      return
    }
    if (s.phase === 'freekick') {
      const taker = s.victim && !s.victim.gk ? s.victim : nearest(outfield(s.opp), b)
      if (!taker) {
        st.script = null
        return
      }
      taker.tx = b.x - dirOf(s.opp) * 0.7
      taker.ty = b.y
      taker.speed = JOG
      if (dist(taker, b) < 1.5 || s.t > 3) {
        b.owner = taker.id
        st.poss = s.opp
        const r = chooseReceiver(taker)
        if (r) pass(taker, r, { lead: 0.3, speed: dist(taker, r) > 24 ? 21 : PASS_SPEED, peak: dist(taker, r) > 24 ? 3.5 : 0.2 })
        st.hold = 0.9
        st.script = null
      }
    }
  }

  // ---------- impedimento: só existe com o time no ataque e um lançamento nas costas da defesa ----------
  function stepOffside(s) {
    const b = st.ball
    const d = dirOf(s.side)
    const gx = goalX(s.side)
    if (s.phase === 'win') {
      if (winBall(s) && !b.flight) {
        s.phase = 'advance'
        s.t = 0
      } else if (s.t > 8) {
        release(s.ev)
        st.script = null
      }
      return
    }
    if (s.phase === 'advance') {
      // o time leva a bola até o campo de ataque antes do lançamento
      const owner = b.owner ? byId(b.owner) : null
      if (b.flight) return
      if (!owner || owner.side !== s.side) {
        s.phase = 'win'
        return
      }
      const named = byId(s.ev.player)
      s.runner = named && named.side === s.side && !named.gk && named !== owner ? named : outfield(s.side).filter((p) => p !== owner).sort((a, c) => c.depth - a.depth)[0]
      const backs = outfield(s.opp)
      const lineX = backs.length ? (d === 1 ? Math.max(...backs.map((p) => p.x)) : Math.min(...backs.map((p) => p.x))) : gx - d * 20
      const inAttack = (owner.x - L / 2) * d > 4 && Math.abs(gx - lineX) < 42
      if (s.runner) {
        // o atacante espera na linha do último zagueiro
        s.runner.tx = lineX - d * 0.8
        s.runner.ty = clamp(s.runner.y, W / 2 - 18, W / 2 + 18)
        s.runner.speed = SPRINT - 1
      }
      owner.tx = clamp(owner.x + d * 5, 4, L - 4)
      owner.ty = owner.y + (W / 2 - owner.y) * 0.05
      owner.speed = JOG + 1.6
      const set = s.runner && Math.abs(s.runner.x - lineX) < 3.5
      if ((inAttack && set && s.t > 0.8) || s.t > 9) {
        if (!s.runner || !inAttack) {
          // o lance não se formou (time preso na defesa): segue o jogo sem encenar o impedimento
          release(s.ev)
          st.script = null
          return
        }
        // o atacante dispara um instante antes do passe: posição irregular
        const to = { x: clamp(lineX + d * 6, 9, L - 9), y: clamp(s.runner.y + (W / 2 - s.runner.y) * 0.3, 8, W - 8) }
        s.runner.x += d * 1.6
        kick(owner, to, { speed: 22, peak: dist(owner, to) > 24 ? 3.2 : 0.2, kicker: owner, receiver: s.runner.id })
        s.runner.tx = to.x
        s.runner.ty = to.y
        s.phase = 'through'
        s.t = 0
        return
      }
      if (s.t - (s.passedAt ?? 0) > 2.2 && !inAttack) {
        const r = chooseReceiver(owner)
        if (r && (r.x - owner.x) * d > 2) {
          s.passedAt = s.t
          pass(owner, r, { lead: 0.4 })
        }
      }
      return
    }
    if (s.phase === 'through') {
      if (s.runner) {
        s.runner.tx = b.flight ? b.flight.to.x : b.x
        s.runner.ty = b.flight ? b.flight.to.y : b.y
        s.runner.speed = SPRINT
      }
      if (b.flight && s.t < 3) return
      fx('whistle')
      banner('offside', s.ev)
      release(s.ev)
      b.flight = null
      b.owner = null
      s.phase = 'free'
      s.t = 0
      return
    }
    for (const p of st.players) p.speed = Math.min(p.speed, 3)
    const gk = keeper(s.opp)
    const taker = nearest(outfield(s.opp), b) || gk
    if (taker && !b.flight && s.t > 1.2) {
      taker.tx = b.x
      taker.ty = b.y
      taker.speed = s.t > 2.5 ? SPRINT : JOG
      if (dist(taker, b) < 1.2) {
        b.owner = taker.id
        st.poss = s.opp
        const r = chooseReceiver(taker)
        if (r) pass(taker, r, { lead: 0.3 })
        st.hold = 0.8
        st.script = null
      } else if (s.t - (s.rolledAt ?? 0) > 3.5) {
        s.rolledAt = s.t
        rollTo(taker, { k: 0.8 })
      }
    }
    if (s.t > 10) st.script = null
  }

  // ---------- jogo corrido ----------
  // onde a bola rolando vai parar (atrito constante): v² / 2a à frente
  function ballStop() {
    const b = st.ball
    const sp = Math.hypot(b.vx || 0, b.vy || 0)
    if (sp < 0.2) return { x: b.x, y: b.y }
    const s = (sp * sp) / (2 * ROLL_FRICTION)
    return { x: clamp(b.x + (b.vx / sp) * s, 0.3, L - 0.3), y: clamp(b.y + (b.vy / sp) * s, 0.3, W - 0.3) }
  }

  function openPlay(dt) {
    const b = st.ball
    if (b.flight) return
    let owner = b.owner ? byId(b.owner) : null
    if (!owner) {
      // bola solta: os dois mais próximos disputam, correndo para onde ela VAI parar (não para onde estava)
      const pt = ballStop()
      const h = nearest(outfield('h'), pt)
      const a = nearest(outfield('a'), pt)
      for (const p of [h, a]) {
        if (!p) continue
        // perto da bola, vai na bola; longe, no ponto onde ela vai estar quando ele chegar
        const k = clamp(dist(p, b) / 10, 0, 1)
        p.tx = lerp(b.x, pt.x, k)
        p.ty = lerp(b.y, pt.y, k)
        p.speed = SPRINT
      }
      const win = [h, a].filter(Boolean).sort((x, y) => dist(x, b) - dist(y, b))[0]
      if (win && dist(win, b) < 1) {
        // dividida: os dois chegam juntos → contato, e a bola espirra para quem estava melhor posicionado
        const rival = win === h ? a : h
        if (rival && dist(rival, b) < 1.1 && rnd() < 0.45) {
          fx('tackle')
          const ang = Math.atan2(b.y - rival.y, b.x - rival.x) + (rnd() - 0.5) * 0.8
          loose({ x: b.x + Math.cos(ang) * 3, y: b.y + Math.sin(ang) * 3 }, 8)
          return
        }
        b.owner = win.id
        st.poss = win.side
        st.hold = 0.6 + rnd() * 0.8
        fx('touch')
      }
      return
    }
    st.poss = owner.side
    const d = dirOf(owner.side)
    const opp = outfield(other(owner.side))
    // dentro da área adversária sem lance do motor não há finalização: em vez de tocar para trás na cara do
    // goleiro, ele perde a bola em até 1 s — o goleiro sai e pega (perto e pelo meio) ou o zagueiro desarma
    if (!owner.gk && Math.abs(goalX(owner.side) - owner.x) < 17) {
      if (st.boxOwner !== owner.id) {
        st.boxOwner = owner.id
        st.boxAt = st.t
      }
      const gkO = keeper(other(owner.side))
      const close = Math.abs(goalX(owner.side) - owner.x) < 11 && Math.abs(owner.y - W / 2) < 12
      const taker = close && gkO ? gkO : nearest(opp, owner)
      if (taker) {
        taker.tx = owner.x
        taker.ty = owner.y
        taker.speed = SPRINT
      }
      owner.tx = owner.x
      owner.ty = owner.y
      owner.speed = 2
      if (taker && (dist(taker, owner) < 1.4 || st.t - st.boxAt > 1)) {
        fx(taker.gk ? 'touch' : 'tackle')
        play(owner, 'stumble', 0.4)
        if (taker.gk) play(taker, 'catch_low', 0.5)
        b.owner = taker.id
        st.poss = taker.side
        st.turnoverAt = st.t
        st.hold = 0.8 + rnd() * 0.6
        st.boxOwner = null
      }
      return
    }
    const share = owner.side === 'h' ? st.possShare : 1 - st.possShare
    // conduz para a frente, desviando do marcador; não entra na área (finalização só vem de evento real)
    const limit = goalX(owner.side) - d * 24
    const marker = nearest(opp, owner)
    const md = marker ? dist(marker, owner) : 99
    // pressão: quanto mais perto o marcador, mais rápido o portador decide
    const pressure = clamp(1 - (md - 0.8) / 5, 0, 1)
    st.hold -= dt * (1 + pressure * 2)
    // protege a bola: gira para o lado oposto ao do marcador e reduz o passo
    const away = md < 5 ? Math.sign(owner.y - marker.y || 1) * (2 + pressure * 3) : 0
    const back = md < 2.2 && (marker.x - owner.x) * d > 0 ? -d * 2 : 0
    owner.tx = clamp((d === 1 ? Math.min(owner.x + 5, limit) : Math.max(owner.x - 5, limit)) + back, 2, L - 2)
    owner.ty = clamp(owner.y + away + (W / 2 - owner.y) * 0.04, 3, W - 3)
    owner.speed = md < 2.5 ? JOG - 0.6 : JOG + 0.6
    // duelo: marcador colado tenta o desarme; a chance depende do domínio real do jogo (posse do motor)
    if (marker && md < 1.15 && !marker.anim) {
      const rate = 0.35 + 1.0 * (1 - share)
      if (rnd() < rate * dt) {
        fx('tackle')
        play(owner, 'stumble', 0.45)
        st.turnoverAt = st.t
        if (rnd() < 0.55) {
          // desarme limpo: o marcador sai com a bola
          b.owner = marker.id
          st.poss = marker.side
          st.hold = 0.5 + rnd() * 0.6
        } else {
          // a bola espirra: dividida para quem chegar antes
          const ang = Math.atan2(marker.y - owner.y, marker.x - owner.x) + (rnd() - 0.5) * 1.6
          loose({ x: b.x + Math.cos(ang) * (2.5 + rnd() * 3), y: b.y + Math.sin(ang) * (2.5 + rnd() * 3) }, 8)
        }
        return
      }
    }
    const stuck = Math.abs(owner.x - limit) < 2
    if (st.hold <= 0 || stuck) {
      const r = chooseReceiver(owner)
      if (r) {
        const long = dist(owner, r) > 26
        pass(owner, r, { lead: 0.5, speed: long ? 21 : PASS_SPEED, peak: long ? 3.5 : 0.2 })
        // quem lê o passe corre para a linha dele; só intercepta se ALCANÇAR a bola (ver voo da bola)
        const cutter = nearest(opp, { x: (owner.x + r.x) / 2, y: (owner.y + r.y) / 2 })
        if (cutter && rnd() < 0.3 + 0.3 * (1 - share)) st.ball.flight.interceptBy = cutter.id
      }
      // livre, o portador conduz mais; pressionado, solta antes (o tempo cai mais rápido sob pressão)
      st.hold = 1.5 + rnd() * 2.2
    }
  }

  // linha mais recuada (fora o goleiro) de um time: referência de compactação e de impedimento
  function lastLine(side) {
    const list = outfield(side)
    if (!list.length) return goalX(other(side))
    const own = goalX(other(side)) // gol que o time defende
    return list.reduce((m, p) => (Math.abs(p.x - own) < Math.abs(m - own) ? p.x : m), list[0].x)
  }

  // Comportamento sem bola dos dois times: pressão ao portador, cobertura, marcação por zona, compactação,
  // recomposição na transição e desmarques/apoios de quem ataca. Os roteiros dos lances ajustam por cima.
  function teamPlay(dt) {
    const b = st.ball
    const s = st.script
    if (s && RESTART.test(s.phase)) return
    const owner = b.owner ? byId(b.owner) : null
    const att = owner ? owner.side : b.flight?.side || st.poss
    const def = other(att)
    if (att !== st.possSide) {
      st.possSide = att
      st.turnoverAt = st.t
    }
    const trans = st.t - st.turnoverAt < 2.6
    const ref = owner || (b.flight ? { x: b.flight.to.x, y: b.flight.to.y } : b) // defende onde a bola VAI estar
    const own = { x: goalX(att), y: W / 2 } // gol que a defesa protege
    const goalSide = (p, k) => {
      const gx = own.x - p.x
      const gy = own.y - p.y
      const gl = Math.hypot(gx, gy) || 1
      return { x: p.x + (gx / gl) * k, y: p.y + (gy / gl) * k }
    }

    // ---- defesa ----
    // quem sai na pressão é, de preferência, quem está entre a bola e o gol (correr atrás de quem já passou não marca)
    const behindBall = (p) => Math.abs(p.x - own.x) > Math.abs(ref.x - own.x) + 1.5
    const cost = (p) => dist(p, ref) + (behindBall(p) ? 9 : 0)
    const defs = outfield(def).sort((a, c) => cost(a) - cost(c))
    const presser = defs[0]
    const cover = defs[1]
    if (presser && dist(presser, ref) < 30) {
      const close = dist(presser, ref)
      // bola viajando: ataca o ponto de chegada para pegar o receptor no domínio
      const spot = goalSide(ref, b.flight ? 2.2 : close < 3 ? 0.9 : 1.6)
      presser.tx = spot.x
      presser.ty = spot.y
      presser.speed = close > 3 || trans || b.flight ? SPRINT : JOG + 2
    }
    if (cover) {
      const spot = goalSide(ref, 7)
      cover.tx = lerp(cover.tx, spot.x, 0.75)
      cover.ty = lerp(cover.ty, (spot.y + W / 2) / 2, 0.75)
      cover.speed = Math.max(cover.speed, JOG + 1.4)
    }
    // contra-pressão: logo após perder a bola, o segundo mais próximo também vai em cima
    if (trans && defs[2] && dist(defs[2], ref) < 14) {
      defs[2].tx = ref.x
      defs[2].ty = ref.y
      defs[2].speed = SPRINT
    }
    // marcação por zona: cada um encaixa no atacante mais próximo da sua zona, sempre entre ele e o gol;
    // quem ficou à frente da bola na transição recompõe em velocidade
    const atts = outfield(att).filter((p) => p !== owner)
    const taken = new Set()
    const ballToGoal = Math.abs(ref.x - own.x)
    for (const p of defs.slice(trans ? 3 : 2)) {
      const zone = { x: p.tx, y: p.ty }
      const m = atts.filter((a) => !taken.has(a.id)).sort((a, c) => dist(a, zone) - dist(c, zone))[0]
      if (m && dist(m, zone) < 11) {
        taken.add(m.id)
        const spot = goalSide(m, 1.6)
        const k = Math.abs(m.x - own.x) < 30 ? 0.75 : 0.5 // perto da área, marcação mais justa
        p.tx = lerp(p.tx, spot.x, k)
        p.ty = lerp(p.ty, spot.y, k)
      }
      // fora de posição, o bloco sobe/recompõe com intensidade proporcional à distância
      const gap = dist(p, { x: p.tx, y: p.ty })
      if (Math.abs(p.x - own.x) > ballToGoal + 3) p.speed = trans ? SPRINT : Math.max(p.speed, JOG + 1.6)
      if (gap > 14) p.speed = Math.max(p.speed, SPRINT - 0.4)
      else if (gap > 6) p.speed = Math.max(p.speed, JOG + 1.4)
    }
    // quem ataca também ocupa os espaços rápido quando está longe da sua posição
    for (const p of outfield(att)) {
      if (p === owner) continue
      if (dist(p, { x: p.tx, y: p.ty }) > 14) p.speed = Math.max(p.speed, SPRINT - 1)
    }

    // ---- ataque ----
    const da = dirOf(att)
    if (owner) {
      const mates = outfield(att)
        .filter((p) => p !== owner)
        .sort((a, c) => dist(a, owner) - dist(c, owner))
      // apoio: um oferece linha ao lado (um pouco atrás), outro na diagonal à frente
      const open = owner.y < W / 2 ? 1 : -1
      // os apoios ficam a uma distância de passe (13–15 m), não em cima do portador: o time se abre com a bola
      const sup = [
        { x: owner.x - da * 4, y: owner.y + open * 14 },
        { x: owner.x + da * 14, y: owner.y - open * 11 },
      ]
      mates.slice(0, 2).forEach((m, i) => {
        if (m.run) return
        m.tx = clamp(lerp(m.tx, sup[i].x, 0.7), 3, L - 3)
        m.ty = clamp(lerp(m.ty, sup[i].y, 0.7), 3, W - 3)
        m.speed = Math.max(m.speed, JOG + 0.8)
      })
    }
    // desmarques: os mais avançados atacam o espaço às costas da última linha, em diagonal
    const line = lastLine(def)
    for (const m of outfield(att)) {
      if (m === owner) continue
      if (m.run && (st.t > m.run.until || !owner)) {
        m.run = null
        m.runCd = st.t + 2.5 + rnd() * 4
      }
      if (!m.run && owner && m.depth > 0.62 && st.t > m.runCd && rnd() < dt * 0.45) {
        const runX = clamp(line + da * (3 + rnd() * 7), 6, L - 6)
        const gxR = goalX(att)
        m.run = { until: st.t + 2 + rnd() * 1.2, tx: da === 1 ? Math.min(runX, gxR - 17) : Math.max(runX, gxR + 17), ty: clamp(m.y + (W / 2 - m.y) * 0.4 + (rnd() - 0.5) * 14, 5, W - 5) }
      }
      if (m.run) {
        m.tx = m.run.tx
        m.ty = m.run.ty
        m.speed = SPRINT - 0.3
      } else if (trans && m.depth > 0.5) {
        // transição ofensiva: os da frente saem em velocidade
        m.tx = clamp(m.tx + da * 6, 3, L - 3)
        m.speed = Math.max(m.speed, SPRINT - 1)
      }
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
      // na bissetriz entre a bola e o centro do gol; a referência é sempre um ponto DENTRO do campo
      // (bola na rede ou fora não puxa o goleiro para trás da linha)
      const gx = d === 1 ? 0 : L
      const bx = clamp(b.x, 1, L - 1)
      const by = clamp(b.y, 0, W)
      const toBall = Math.hypot(bx - gx, by - W / 2) || 1
      const off = clamp(1 + (1 - progress) * 4, 1, 6)
      const x = gx + ((bx - gx) / toBall) * off
      // com a bola perto, ele fecha o ângulo sem sair da largura do gol (+ um passo)
      const y = clamp(W / 2 + ((by - W / 2) / toBall) * off * 0.9, W / 2 - GOAL_HALF - 1, W / 2 + GOAL_HALF + 1)
      return { x: d === 1 ? Math.max(0.6, x) : Math.min(L - 0.6, x), y, speed: JOG }
    }
    const shift = (st.lineShift[p.side] || 0) * (0.4 + 0.6 * p.depth)
    let x = base.x + d * ((progress - 0.45) * 36 + (inPoss ? 8 : -2) + shift)
    let y = base.y + (b.y - base.y) * (inPoss ? 0.1 : 0.32)
    if (inPoss) y = W / 2 + (y - W / 2) * 1.12
    else {
      // sem a bola: bloco compacto (~28 m de profundidade) atrás da linha da bola, fechado no lado dela
      const ref = b.flight ? b.flight.to : b
      const ownX = d === 1 ? 0 : L
      const behind = -2 + (1 - p.depth) * 27 - shift * 0.5
      const bx = ref.x - d * behind
      const floor = 4 + (1 - p.depth) * 3 + p.depth * 14 // ninguém se enfia dentro do próprio gol
      const xc = d === 1 ? Math.max(bx, ownX + floor) : Math.min(bx, ownX - floor)
      x = lerp(x, xc, 0.7)
      y = ref.y + (base.y - W / 2) * 0.72 + (W / 2 - ref.y) * 0.25
      y = lerp(base.y, y, 0.75)
    }
    x = clamp(x, 2, L - 2)
    return { x, y: clamp(y, 2, W - 2), speed: inPoss ? JOG + 0.4 : JOG + 0.6 }
  }

  function steer(p, dt) {
    // tempo de reação: o alvo percebido persegue o alvo real (mudanças bruscas viram curvas)
    if (p.rtx == null) {
      p.rtx = p.tx
      p.rty = p.ty
    }
    const urgent = p.id === st.ball.owner || p.id === st.ball.flight?.receiver
    const kr = 1 - Math.exp(-dt / (urgent ? p.react * 0.5 : p.react || 0.2))
    p.rtx += (p.tx - p.rtx) * kr
    p.rty += (p.ty - p.rty) * kr
    const dx = p.rtx - p.x
    const dy = p.rty - p.y
    const dd = Math.hypot(dx, dy)
    const top = p.speed * (p.pace || 1)
    // chega freando de forma física (v² = 2·a·d), sem parar de estalo
    const want = dd < 0.2 ? 0 : Math.min(top, Math.sqrt(2 * DECEL * 0.55 * dd))
    let vxT = dd > 0.01 ? (dx / dd) * want : 0
    let vyT = dd > 0.01 ? (dy / dd) * want : 0
    const sp0 = Math.hypot(p.vx, p.vy)
    // giro: em velocidade o corpo não muda de direção na hora — limita o ângulo por quadro e perde velocidade na curva
    if (sp0 > 1 && want > 0.5) {
      const cur = Math.atan2(p.vy, p.vx)
      let da = Math.atan2(vyT, vxT) - cur
      da = Math.atan2(Math.sin(da), Math.cos(da))
      const maxTurn = (TURN / (1 + sp0 * 0.32)) * dt
      if (Math.abs(da) > maxTurn) {
        const ang = cur + Math.sign(da) * maxTurn
        const sp2 = want * clamp(Math.cos(da) * 0.5 + 0.5, 0.35, 1)
        vxT = Math.cos(ang) * sp2
        vyT = Math.sin(ang) * sp2
      }
    }
    const ax = vxT - p.vx
    const ay = vyT - p.vy
    const a = Math.hypot(ax, ay)
    // arrancada forte parado, fraca perto da velocidade máxima; frear é sempre mais rápido
    const braking = Math.hypot(vxT, vyT) < sp0
    const maxA = (braking ? DECEL : ACCEL * clamp(1.25 - sp0 / (SPRINT * 1.3), 0.35, 1.25)) * dt
    const k = a > maxA ? maxA / a : 1
    p.vx += ax * k
    p.vy += ay * k
    // caído (mergulho) ou levantando: o corpo não corre
    if (p.anim && (p.anim.name.startsWith('dive') || p.anim.name === 'getup') && st.ball.owner !== p.id) {
      p.vx *= 0.85
      p.vy *= 0.85
    }
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
      if (p.anim.t >= p.anim.dur) {
        if (!p.anim.hold) p.anim = null
        // poses que "seguram" (mergulho, encaixe) duram só um instante depois do lance; do chão, o goleiro levanta
        else if (p.anim.t >= p.anim.dur + 0.35) p.anim = p.anim.name.startsWith('dive') ? { name: 'getup', t: 0, dur: 0.6, from: p.anim.name, dy: p.anim.dy, hold: false } : null
      }
    }
  }

  // Espaçamento: fora das áreas e de bola parada, só fica perto da bola (7 m) quem está na disputa — até 2 de quem
  // defende e 1 companheiro do portador, além de quem o lance roteirizado ou o passe chamou. Os demais seguram a
  // posição a pelo menos 10 m, como um time de verdade (sem o "bolo" em volta da bola).
  function declutter() {
    const b = st.ball
    const s = st.script
    if (s && (RESTART.test(s.phase) || s.kind === 'penalty')) return
    // bola solta: quem vai buscá-la não pode ser afastado
    if (!b.owner && !b.flight) return
    const ref = b.flight ? b.flight.to : b
    if (ref.x < 17 || ref.x > L - 17) return
    const keep = new Set([b.owner, b.flight?.receiver, b.flight?.interceptBy, b.flight?.kicker, s?.shooter?.id, s?.assist?.id, s?.steps?.[0]?.who?.id].filter(Boolean))
    const ownerSide = b.owner ? byId(b.owner)?.side : b.flight?.side || st.poss
    for (const side of ['h', 'a']) {
      const allow = side === ownerSide ? 1 : 2
      const list = outfield(side)
        .filter((p) => !keep.has(p.id))
        // quem o jogo corrido mandou para a bola (pressão, cobertura) tem o alvo mais perto dela: esses ficam
        .sort((x, y) => dist({ x: x.tx, y: x.ty }, ref) - dist({ x: y.tx, y: y.ty }, ref))
      list.forEach((p, i) => {
        if (i < allow) return
        const t = { x: p.tx, y: p.ty }
        const dd = dist(t, ref)
        if (dd >= 10) return
        // empurra o alvo para fora do círculo, do lado em que o jogador já está (ou da posição da forma)
        const from = dist(p, ref) > 0.5 ? p : t
        const ang = Math.atan2(from.y - ref.y, from.x - ref.x)
        p.tx = clamp(ref.x + Math.cos(ang) * 10, 2, L - 2)
        p.ty = clamp(ref.y + Math.sin(ang) * 10, 2, W - 2)
      })
    }
  }

  // A bola não atravessa ninguém. No jogo corrido, o adversário em quem a bola rasteira encosta fica com ela.
  // No lance do motor o resultado é fixo: o adversário sai da frente da bola (desvia o corpo).
  function ballContact() {
    const b = st.ball
    const f = b.flight
    if (!f || f.delay > 0 || (b.z || 0) > 1.1 || f.t < 0.08) return
    for (const p of st.players) {
      if (p.side === f.side || p.gk) continue
      const dd = Math.hypot(p.x - b.x, p.y - b.y)
      if (dd > 0.45) continue
      if (!st.script && f.receiver) {
        b.flight = null
        b.owner = p.id
        st.poss = p.side
        st.turnoverAt = st.t
        st.hold = 0.6 + rnd() * 0.6
        fx('touch')
        return
      }
      const k = (0.75 - dd) / Math.max(dd, 0.05)
      p.x += (p.x - b.x) * k
      p.y += (p.y - b.y) * k
    }
  }

  // Ponto do caminho da bola em voo que o jogador alcança primeiro (tempo de corrida ≤ tempo da bola até lá).
  // Sem nenhum a tempo, o ponto final. Usa a mesma curva de desaceleração do voo.
  function meetPoint(f, p) {
    const pos = (lin) => {
      const k = f.ground ? 1 - (1 - lin) * (1 - lin) * 0.35 - (1 - lin) * 0.65 : lin
      return { x: f.from.x + (f.to.x - f.from.x) * k, y: f.from.y + (f.to.y - f.from.y) * k }
    }
    const now = f.delay > 0 ? 0 : clamp(f.t / f.dur, 0, 1)
    const left = f.delay > 0 ? f.delay : 0
    for (let i = 1; i <= 10; i += 1) {
      const lin = now + ((1 - now) * i) / 10
      if (!f.ground && lin < 0.8) continue // bola alta: domina na descida
      const q = pos(lin)
      const tBall = left + (lin - now) * f.dur
      const tRun = dist(p, q) / (SPRINT * (p.pace || 1) * 0.72) + (p.react || 0.2) + 0.25
      if (tRun <= tBall) return q
    }
    return f.to
  }

  // ninguém atravessa ninguém: afasta quem está colado (o portador e o marcador podem encostar)
  function separate() {
    const ps = st.players
    for (let i = 0; i < ps.length; i += 1) {
      for (let j = i + 1; j < ps.length; j += 1) {
        const a = ps[i]
        const c = ps[j]
        const dx = c.x - a.x
        const dy = c.y - a.y
        const d2 = dx * dx + dy * dy
        const min = a.id === st.ball.owner || c.id === st.ball.owner ? 0.75 : 1.05
        if (d2 > min * min || d2 < 1e-6) continue
        const d = Math.sqrt(d2)
        const push = (min - d) / 2
        a.x -= (dx / d) * push
        a.y -= (dy / d) * push
        c.x += (dx / d) * push
        c.y += (dy / d) * push
      }
    }
    // o empurrão de quem encosta nunca leva o goleiro para trás da própria linha
    for (const p of ps) if (p.gk) p.x = clamp(p.x, 0.2, L - 0.2)
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
    // relógio que não espera (modo online): com muitos lances na fila, os menos importantes só aparecem no relato
    while (st.queue.length > 3) {
      const i = st.queue.findIndex((e) => e.kind !== 'goal' && e.kind !== 'pen_goal' && e.kind !== 'red' && e.kind !== 'second_yellow')
      if (i < 0) break
      release(st.queue[i])
      st.queue.splice(i, 1)
    }
    if (!st.script && st.queue.length) startScript(st.queue.shift())

    // velocidades padrão; roteiros e o jogo corrido ajustam depois
    for (const p of st.players) {
      const s = shape(p)
      p.tx = s.x
      p.ty = s.y
      p.speed = s.speed
    }
    // pressão, cobertura, marcação, compactação, desmarques e transição
    const b = st.ball
    const ownerNow = b.owner ? byId(b.owner) : null
    teamPlay(dt)
    // quem vai receber o passe vai AO ENCONTRO da bola: o primeiro ponto do caminho dela que ele alcança a tempo
    // (não espera no ponto final nem deixa a bola passar e voltar atrás dela)
    if (b.flight?.receiver) {
      const r = byId(b.flight.receiver)
      if (r) {
        const meet = meetPoint(b.flight, r)
        r.tx = meet.x
        r.ty = meet.y
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
    // dentro da jogada roteirizada o resultado é do motor, mas a marcação é de verdade: o marcador colado
    // tenta o bote e o portador escapa (drible/proteção), com contato e desequilíbrio de quem perdeu o duelo
    if (s && s.kind === 'attack' && ['build', 'carry', 'win'].includes(s.phase) && ownerNow && ownerNow.side === s.side) {
      const m = nearest(outfield(s.opp), ownerNow)
      if (m && !m.anim && dist(m, ownerNow) < 1.2 && rnd() < dt * 1.1) {
        fx('tackle')
        play(m, 'stumble', 0.5)
        m.vx *= 0.3
        m.vy *= 0.3
        const side = Math.sign(ownerNow.y - m.y || 1)
        ownerNow.vx += dirOf(s.side) * 1.5
        ownerNow.vy += side * 2.2
      }
    }
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
      if (st.script === s && s.t > 16 && s.phase !== 'reset') {
        release(s.ev)
        st.script = null
      }
    } else openPlay(dt)
    declutter()

    // bola em voo
    if (b.flight?.delay > 0) {
      // perna em movimento: a bola continua no pé do batedor até o contato
      const f = b.flight
      f.delay -= dt
      const kp = f.kicker ? byId(f.kicker) : null
      if (kp) {
        const a = Math.atan2(f.to.y - kp.y, f.to.x - kp.x)
        const reachK = 1 - Math.exp(-dt / 0.04)
        b.x += (kp.x + Math.cos(a) * 0.45 - b.x) * reachK
        b.y += (kp.y + Math.sin(a) * 0.45 - b.y) * reachK
      }
      if (f.delay <= 0) {
        // contato: a trajetória parte daqui, com o mesmo tempo de chegada planejado
        f.from = { x: b.x, y: b.y }
        f.z0 = b.z
        f.delay = 0
        fx(dist(f.from, f.to) / f.dur >= 23 ? 'shot' : f.kicker && byId(f.kicker)?.gk && b.z > 0.8 ? 'touch' : 'kick', { power: dist(f.from, f.to) / f.dur })
      }
    } else if (b.flight) {
      const f = b.flight
      f.t += dt
      // passe rasteiro desacelera; chute e lançamento seguem a parábola
      const lin = clamp(f.t / f.dur, 0, 1)
      const k = f.ground ? 1 - (1 - lin) * (1 - lin) * 0.35 - (1 - lin) * 0.65 : lin
      b.x = f.from.x + (f.to.x - f.from.x) * k
      b.y = f.from.y + (f.to.y - f.from.y) * k
      b.z = f.z0 + (f.z1 - f.z0) * lin + f.peak * 4 * lin * (1 - lin)
      b.spin += dt * 14
      // interceptação no caminho (só no jogo corrido): qualquer adversário que ALCANCE a bola baixa a corta;
      // às vezes só desvia (bola solta)
      if (!st.script && f.side && f.t > 0.12 && b.z < 1.3) {
        for (const c of outfield(other(f.side))) {
          if (dist(c, b) > 1.0) continue
          fx('touch')
          if (rnd() < 0.7) {
            b.flight = null
            b.owner = c.id
            st.poss = c.side
            st.hold = 0.6 + rnd() * 0.8
            b.z = 0
          } else {
            const ang = Math.atan2(f.to.y - f.from.y, f.to.x - f.from.x) + (rnd() < 0.5 ? 1 : -1) * (0.6 + rnd() * 0.8)
            b.flight = null
            loose({ x: b.x + Math.cos(ang) * 6, y: b.y + Math.sin(ang) * 6 }, 10)
          }
          break
        }
      }
      // domínio: o receptor que alcança a bola baixa a controla no caminho (não espera ela parar)
      const r = b.flight && f.receiver ? byId(f.receiver) : null
      if (r && lin > 0.15 && lin < 1 && b.z < 1.0 && dist(r, b) < 1.1) {
        b.flight = null
        b.owner = r.id
        b.z = 0
        fx('touch')
        if (!st.script) st.hold = 0.8 + rnd() * 1.4
        if (f.onEnd) f.onEnd()
      }
      if (b.flight && lin >= 1) {
        b.flight = null
        b.z = f.z1
        if (r && dist(r, b) < 1.6) {
          b.owner = r.id
          fx('touch')
        } else if (!st.script || (f.ground && !st.script.phase.match(/flight|c_/))) {
          // ninguém dominou: a bola SEGUE rolando com a velocidade que chegou (rasteira) ou do quique (alta)
          const sp = dist(f.from, f.to) / f.dur
          const keep = f.ground ? 0.35 : 0.3
          const ux = (f.to.x - f.from.x) / Math.max(0.01, dist(f.from, f.to))
          const uy = (f.to.y - f.from.y) / Math.max(0.01, dist(f.from, f.to))
          b.vx = ux * sp * keep
          b.vy = uy * sp * keep
          b.z = 0
        }
        if (r && !st.script) st.hold = 0.8 + rnd() * 1.4
        if (f.onEnd) f.onEnd()
      }
    } else if (!b.owner && (b.vx || b.vy)) {
      // bola solta rolando: atrito do gramado até parar (nada de parar de estalo)
      const sp = Math.hypot(b.vx, b.vy)
      const nsp = Math.max(0, sp - ROLL_FRICTION * dt)
      if (nsp < 0.15) {
        b.vx = 0
        b.vy = 0
      } else {
        b.vx *= nsp / sp
        b.vy *= nsp / sp
        b.x = clamp(b.x + b.vx * dt, 0.3, L - 0.3)
        b.y = clamp(b.y + b.vy * dt, 0.3, W - 0.3)
        b.spin += dt * nsp * 3
      }
    }

    for (const p of st.players) steer(p, dt)
    separate()
    ballContact()
    // torcida sobe quando o ataque chega perto da área (com intervalo, para não repetir)
    {
      const o = b.owner ? byId(b.owner) : null
      if (o && !o.gk && Math.abs(goalX(o.side) - b.x) < 24 && Math.abs(b.y - W / 2) < 22 && st.t - (st.swellAt ?? -99) > 8) {
        st.swellAt = st.t
        fx('swell', { side: o.side })
      }
    }

    // Condução: a bola vai À FRENTE do corpo, na direção em que ele corre (suavizada junto com o giro do corpo).
    // Parado, fica no pé, na direção em que ele estava indo — nunca troca de lado de estalo nem fica para trás.
    if (b.owner && !b.flight) {
      const o = byId(b.owner)
      if (o) {
        b.vx = 0
        b.vy = 0
        const sp = Math.hypot(o.vx, o.vy)
        const want = sp > 0.5 ? Math.atan2(o.vy, o.vx) : o.dribA ?? (dirOf(o.side) === 1 ? 0 : Math.PI)
        if (o.dribA == null) o.dribA = Math.atan2(b.y - o.y, b.x - o.x)
        let da = want - o.dribA
        da = Math.atan2(Math.sin(da), Math.cos(da))
        o.dribA += da * Math.min(1, dt * 11)
        const ux = Math.cos(o.dribA)
        const uy = Math.sin(o.dribA)
        let tx
        let ty
        let tz
        if (o.gk && b.held) {
          // nas mãos, na altura do peito
          tx = o.x + ux * 0.3
          ty = o.y + uy * 0.3
          tz = 1.05
        } else {
          // toque a cada passada: a bola se afasta um pouco e o corpo a alcança
          const touch = 0.5 + (sp > 1.2 ? 0.45 * Math.abs(Math.sin((o.stride * Math.PI) / 4)) * Math.min(1, sp / 5) : 0)
          tx = o.x + ux * touch
          ty = o.y + uy * touch
          tz = 0
        }
        // recepção (bola longe do pé): vem rolando até ele; depois acompanha sem atraso perceptível
        const gap = Math.hypot(tx - b.x, ty - b.y)
        const k = gap > 1.1 ? Math.min(1, ((sp + 8) * dt) / gap) : 1 - Math.exp(-dt / 0.04)
        b.x += (tx - b.x) * k
        b.y += (ty - b.y) * k
        b.z += (tz - b.z) * Math.min(1, dt * 12)
        if (sp > 0.3) b.spin += dt * sp * 2
      }
    }
  }

  // Menor minuto de um lance que ainda não foi mostrado: o relógio da partida espera até ele terminar.
  function holdMinute() {
    let m = null
    const s = st.script
    if (s?.ev && !st.released.has(s.ev.seq)) m = s.ev.minute
    // comemoração e volta ao meio-campo duram ~1 minuto de jogo: o relógio não dispara à frente do campo
    else if (s?.ev && (s.phase === 'celebrate' || s.phase === 'reset')) m = s.ev.minute + 1
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
    // seqs dos lances mostrados desde a última chamada (gol na rede, defesa, cartão, impedimento)
    takeRevealed() {
      if (!st.revealed.length) return null
      const out = st.revealed
      st.revealed = []
      return out
    },
    // sons do instante visual desde a última chamada (chute, contato, apito, rede, defesa, torcida)
    takeFx() {
      if (!st.fx.length) return null
      const out = st.fx
      st.fx = []
      return out
    },
    // libera tudo o que está pendente (campo indisponível): também conta como mostrado, para o relato seguir
    releaseAll() {
      for (const ev of st.queue) release(ev)
      if (st.script?.ev) release(st.script.ev)
    },
    setHalf(h) {
      if (h === st.half || st.pendingHalf === h) return
      if (st.script) st.pendingHalf = h
      else {
        st.half = h
        kickoff(h === 1 ? 'h' : 'a')
      }
    },
    // postura tática de cada lado ('attacking', 'defensive', 'counter' ou neutra): o bloco sobe ou recua
    setStyle(side, style) {
      st.lineShift[side] = style === 'attacking' ? 7 : style === 'defensive' ? -7 : style === 'counter' ? -4 : 0
    },
    setPossession(share) {
      st.possShare = Number.isFinite(share) ? share : 0.5
    },
    teamOf: team,
    goalX, // gol que o time ataca (muda no intervalo)
  }
}
