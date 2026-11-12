import { useEffect, useState } from 'react'
import { Check, ChevronRight } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import { FutCard, PlayerFace } from './components/PlayerFut'
import { fetchDraft, pickDraft } from './services/onlineApi'
import { LINE_LABEL, POS_LABEL, moneyShort } from './onlineUtils'

// Contratação dos três craques: uma linha por vez (defesa, meio-campo, ataque), três cartas em cada.
export default function OnlineDraft({ onDone }) {
  const [draft, setDraft] = useState(null)
  const [error, setError] = useState('')
  const [focus, setFocus] = useState(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    fetchDraft().then(setDraft).catch((e) => setError(e.message))
  }, [])
  useEffect(() => {
    if (draft?.done) onDone?.()
  }, [draft?.done]) // eslint-disable-line react-hooks/exhaustive-deps

  const sign = () => {
    if (busy || focus == null) return
    setBusy(true)
    setError('')
    pickDraft(draft.step, focus)
      .then((d) => {
        setFocus(null)
        setDraft(d)
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }

  if (!draft) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={3} variant="grid" />
  const chosen = draft.options.find((o) => o.idx === focus)
  return (
    <section className="on-draft">
      <ol className="on-draft-steps" aria-label="Etapas">
        {['DEF', 'MID', 'ATT'].map((line, i) => {
          const done = draft.picked[i]
          return (
            <li key={line} className={i < draft.step ? 'is-done' : i === draft.step ? 'is-now' : ''}>
              {done ? <PlayerFace seed={done.name} colors={draft.club?.colors} size={34} /> : <b>{i + 1}</b>}
              <span>{LINE_LABEL[line]}<small>{done ? done.name : '—'}</small></span>
              {done && <Check size={14} />}
            </li>
          )
        })}
      </ol>

      <header className="on-draft-head">
        <small>Reforço {Math.min(draft.step + 1, 3)} de 3</small>
        <h2>{LINE_LABEL[draft.line]}</h2>
      </header>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}

      <div className={`on-draft-options ${focus != null ? 'has-pick' : ''}`} key={draft.step}>
        {draft.options.map((o, i) => (
          <FutCard key={o.idx} p={o} club={draft.club} delay={i * 110} selected={focus === o.idx} disabled={busy} onClick={() => setFocus(o.idx)} />
        ))}
      </div>

      <div className={`on-draft-sign ${chosen ? 'is-open' : ''}`}>
        {chosen ? (
          <>
            <div className="on-draft-sign-info">
              <strong>{chosen.name}</strong>
              <span>{POS_LABEL[chosen.pos]} · {chosen.age} anos</span>
              <dl>
                <div><dt>Valor</dt><dd>{moneyShort(chosen.value)}</dd></div>
                <div><dt>Salário</dt><dd>{moneyShort(chosen.wage)}</dd></div>
                <div><dt>Potencial</dt><dd>{chosen.pot}</dd></div>
              </dl>
            </div>
            <button type="button" className="gx-btn on-draft-go" disabled={busy} onClick={sign}>
              {busy ? 'Assinando…' : 'Contratar'} <ChevronRight size={18} />
            </button>
          </>
        ) : (
          <span className="on-draft-wait">Selecione um jogador</span>
        )}
      </div>
    </section>
  )
}
