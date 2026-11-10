import { useEffect, useState } from 'react'
import { Star } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import { fetchDraft, pickDraft } from './services/onlineApi'
import { LINE_LABEL, POS_LABEL, money } from './onlineUtils'

// Escolha dos três craques: uma linha por vez (defesa, meio-campo, ataque), três opções em cada.
// O resto do elenco é genérico e igual em força para todos.
export default function OnlineDraft({ onDone }) {
  const [draft, setDraft] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(null)

  useEffect(() => {
    fetchDraft().then(setDraft).catch((e) => setError(e.message))
  }, [])
  useEffect(() => {
    if (draft?.done) onDone?.()
  }, [draft?.done]) // eslint-disable-line react-hooks/exhaustive-deps

  const pick = (idx) => {
    if (busy != null) return
    setBusy(idx)
    setError('')
    pickDraft(draft.step, idx).then(setDraft).catch((e) => setError(e.message)).finally(() => setBusy(null))
  }

  if (!draft) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={3} variant="grid" />
  return (
    <section className="on-draft">
      <ol className="on-draft-steps" aria-label="Etapas da escolha">
        {['DEF', 'MID', 'ATT'].map((line, i) => (
          <li key={line} className={i < draft.step ? 'is-done' : i === draft.step ? 'is-now' : ''}>
            <b>{i + 1}</b>
            <span>{LINE_LABEL[line]}</span>
            <small>{draft.picked[i]?.name || (i === draft.step ? 'escolha agora' : 'a seguir')}</small>
          </li>
        ))}
      </ol>

      <header className="on-draft-head">
        <h2 className="gx-title">Escolha seu craque: {LINE_LABEL[draft.line]}</h2>
        <p>Um dos três entra no seu elenco. Os outros dois somem. O restante do time é genérico: reforce pelo mercado.</p>
      </header>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}

      <div className="on-draft-options">
        {draft.options.map((o) => (
          <button key={o.idx} type="button" className="on-star" disabled={busy != null} onClick={() => pick(o.idx)}>
            <span className="on-star-ovr"><b>{o.ovr}</b><small>{o.pos}</small></span>
            <Star className="on-star-icon" size={18} aria-hidden="true" />
            <strong>{o.name}</strong>
            <span className="on-star-pos">{POS_LABEL[o.pos]}</span>
            <dl>
              <div><dt>Idade</dt><dd>{o.age}</dd></div>
              <div><dt>Potencial</dt><dd>{o.pot}</dd></div>
              <div><dt>Valor</dt><dd>{money(o.value)}</dd></div>
            </dl>
            <span className="gx-btn on-star-cta">{busy === o.idx ? 'Contratando...' : 'Escolher'}</span>
          </button>
        ))}
      </div>
    </section>
  )
}
