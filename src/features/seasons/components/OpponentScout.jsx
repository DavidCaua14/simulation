import { useEffect, useState } from 'react'
import { fetchOpponentReport } from '../services/managerApi'
import { isSessionError } from '../../../lib/sessionRecovery'
import { TACTIC_GROUPS, toCM } from '../utils/managerUtils'
import './opponent-scout.css'

const STYLES = { possession: 'Posse de bola', press: 'Pressão intensa', counter: 'Contra-ataque', wide: 'Jogo pelas pontas', balanced: 'Equilibrado' }

export function OpponentTactics({ formation, tactics: raw, style, live = false }) {
  if (!raw) return null
  const tactics = toCM(raw)
  const posture = TACTIC_GROUPS[0].options.find((o) => o.v === tactics.style)?.label || 'Neutro'
  const advice = []
  if (tactics.marking === 'high') advice.push('Marcação alta: procure o espaço nas costas com atacantes rápidos e saia jogando com segurança.')
  if (tactics.style === 'counter') advice.push('O rival joga no contra-ataque: não deixe a defesa desprotegida.')
  if (tactics.passing === 'long') advice.push('Bola longa: proteja a profundidade e as disputas aéreas.')
  if (['byline', 'deep'].includes(tactics.crossing)) advice.push('Muitos cruzamentos: zagueiros fortes no jogo aéreo fazem diferença.')
  if (tactics.long_shots === 'often') advice.push('Chuta muito de fora: aproxime a marcação na entrada da área.')
  if (!advice.length) advice.push('Observe os primeiros minutos e ajuste seu time ao espaço que o rival oferecer.')
  return (
    <div className="opponent-analysis">
      <p><b>{formation || 'Formação a definir'}</b> · {STYLES[style] || posture}</p>
      <dl>
        {TACTIC_GROUPS.map((g) => (
          <div key={g.id}><dt>{g.label}</dt><dd>{g.options.find((o) => o.v === tactics[g.id])?.label || 'Normal'}</dd></div>
        ))}
      </dl>
      <p className="sn-hint">{live ? 'Plano atual em campo. O rival pode mudar as instruções durante a partida.' : 'Plano provável. O rival pode adaptar a estratégia ao placar, ao tempo e ao desgaste.'}</p>
      <ul>{advice.map((text) => <li key={text}>{text}</li>)}</ul>
    </div>
  )
}

export default function OpponentScout({ fixtureId }) {
  const [open, setOpen] = useState(false)
  const [result, setResult] = useState(null)
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    if (!open || !fixtureId) return undefined
    let cancelled = false
    fetchOpponentReport(fixtureId).then((data) => {
      if (!cancelled) setResult({ fixtureId, data })
    }).catch((error) => {
      if (!cancelled && !isSessionError(error)) setResult({ fixtureId, error: true })
    })
    return () => { cancelled = true }
  }, [fixtureId, open, attempt])
  const current = result?.fixtureId === fixtureId ? result : null
  return (
    <details className="opponent-scout" onToggle={(event) => { setOpen(event.currentTarget.open); setResult(null) }}>
      <summary>Analisar adversário</summary>
      {open && (!current ? <p role="status">Analisando o rival...</p> : current.error ? (
        <div><p role="alert">Não foi possível analisar o rival.</p><button type="button" className="gx-btn-ghost" onClick={() => { setResult(null); setAttempt((n) => n + 1) }}>Tentar novamente</button></div>
      ) : <OpponentTactics {...current.data} />)}
    </details>
  )
}
