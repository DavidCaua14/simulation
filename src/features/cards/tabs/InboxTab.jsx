import { sourceLabel, tierOf } from '../data/tiers'

const ago = (iso) => {
  const m = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000))
  if (m < 1) return 'agora'
  if (m < 60) return `há ${m} min`
  const h = Math.round(m / 60)
  if (h < 24) return `há ${h} h`
  return `há ${Math.round(h / 24)} d`
}

// Caixa de entrada: toque numa caixa para abri-la; ou abra todas.
export default function InboxTab({ boxes, onOpenOne, onOpenSequence, onOpenAll, busy }) {
  if (!boxes.length) {
    return (
      <div className="cx-empty">
        <img src={tierOf('basica').open} alt="" draggable="false" />
        <h3>Nenhuma caixa por aqui</h3>
        <p>Entre todo dia para receber as caixas diárias e ganhe uma caixa a cada vitória no modo Temporadas.</p>
      </div>
    )
  }
  // as mais raras primeiro; empate = mais antiga primeiro
  const sorted = [...boxes].sort((a, b) => tierOf(b.tier).rank - tierOf(a.tier).rank || a.created_at.localeCompare(b.created_at))

  return (
    <div className="cx-inbox">
      <div className="cx-inbox-actions">
        <button type="button" className="bx-btn" disabled={busy} onClick={() => onOpenSequence([...sorted].reverse())}>
          Abrir uma a uma ({boxes.length})
        </button>
        {boxes.length > 1 && (
          <button type="button" className="bx-btn ghost" disabled={busy} onClick={() => onOpenAll(sorted)}>
            {busy ? 'Abrindo…' : 'Abrir todas de uma vez'}
          </button>
        )}
      </div>
      <div className="cx-box-grid">
        {sorted.map((b) => {
          const t = tierOf(b.tier)
          return (
            <button key={b.id} type="button" className="cx-box" style={{ '--tier': t.color, '--glow': t.glow }} onClick={() => onOpenOne(b)} disabled={busy}>
              <img src={t.closed} alt={`Caixa ${t.label}`} draggable="false" loading="lazy" />
              <b>{t.label}</b>
              <small>
                {sourceLabel(b.source)} · {ago(b.created_at)}
              </small>
            </button>
          )
        })}
      </div>
    </div>
  )
}
