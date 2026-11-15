// Sons do CAMPO no instante visual: o diretor da transmissão marca cada contato (chute, bote, defesa, rede, apito)
// e a tela toca aqui no mesmo quadro em que o desenho mostra. Placar e narração dos lances continuam no
// useMatchAudio (revelação), que nesse modo deixa os apitos de campo para cá.
import { ambienceSwell, play } from './sfx'

const MAP = {
  touch: 'touch',
  kick: 'kick',
  shot: 'shot',
  tackle: 'tackle',
  whistle: 'whistle_short',
  net: 'net',
  save: 'save',
  ooh: 'ooh',
}

// Cria o tocador de uma partida: limita sons repetidos (4x pode gerar vários contatos por quadro)
// e controla a expectativa da torcida pela posição da bola.
export function createFieldAudio() {
  let lastKick = 0
  let swell = 0
  let lastSwellSent = -1
  return {
    // fx: lista de efeitos do diretor (takeFx) · now: performance.now()
    play(list, now = performance.now()) {
      if (!list) return
      for (const f of list) {
        if (f.type === 'swell') {
          swell = 1
          continue
        }
        const id = MAP[f.type]
        if (!id) continue
        if ((id === 'kick' || id === 'touch') && now - lastKick < 110) continue
        if (id === 'kick' || id === 'touch') lastKick = now
        play(id)
      }
    },
    // chamado a cada quadro: danger 0..1 (bola perto do gol com o time atacando)
    tick(dt, danger) {
      const target = Math.max(danger, swell)
      swell = Math.max(0, swell - dt * 0.35)
      const v = Math.round(target * 10) / 10
      if (v !== lastSwellSent) {
        lastSwellSent = v
        ambienceSwell(v)
      }
    },
    stop() {
      ambienceSwell(0)
    },
  }
}

// perigo do lance para a torcida: bola com um time, perto do gol que ele ataca
export function dangerOf(st, goalXOf) {
  const b = st.ball
  const owner = b.owner ? st.players.find((p) => p.id === b.owner) : null
  const side = owner ? owner.side : b.flight?.side
  if (!side || owner?.gk) return 0
  const dx = Math.abs(goalXOf(side) - b.x)
  return Math.max(0, Math.min(1, (32 - dx) / 20)) * (Math.abs(b.y - 34) < 24 ? 1 : 0.5)
}
