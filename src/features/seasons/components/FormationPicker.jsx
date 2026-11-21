import { useEffect, useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { ChevronDown, Check, X } from 'lucide-react'
import '@fontsource/press-start-2p/400.css'
import '@fontsource/pixelify-sans/600.css'
import '@fontsource/silkscreen/700.css'
import './formationPicker.css'

// SELETOR DE FORMAÇÃO (Online, Temporadas e partida ao vivo): o botão mostra a formação atual num minicampo; a janela
// lista todas as formações do catálogo (sim_formations) com o desenho das vagas, filtro pela linha de defesa e o
// perfil (ofensiva, equilibrada, defensiva) calculado pelas vagas.

const LINE = (s) => (s.pos === 'GOL' ? 'gk' : s.y >= 62 ? 'def' : s.y >= 28 ? 'mid' : 'att')
function profileOf(f) {
  const slots = f?.slots || []
  const n = { def: 0, mid: 0, att: 0 }
  for (const s of slots) if (s.pos !== 'GOL') n[LINE(s)] += 1
  const back = slots.filter((s) => ['ZAG', 'LD', 'LE'].includes(s.pos) && s.y >= 58).length
  // ofensiva: 3+ atacantes no alto; defensiva: linha de 5 ou só um atacante sem meias perto da área
  const support = slots.filter((s) => s.pos !== 'GOL' && s.y >= 28 && s.y < 36).length
  const style = n.att >= 3 ? 'Ofensiva' : back >= 5 || (n.att <= 1 && support === 0) ? 'Defensiva' : 'Equilibrada'
  return { back: Math.min(5, Math.max(3, back)), style, n }
}

export function FormationMini({ formation, size = 58, active = false }) {
  const slots = formation?.slots || []
  const h = Math.round(size * 1.32)
  return (
    <svg className={`fp-mini ${active ? 'is-on' : ''}`} width={size} height={h} viewBox="0 0 100 132" aria-hidden="true" shapeRendering="crispEdges">
      <rect width="100" height="132" fill="#1f7a3a" />
      {[0, 1, 2, 3, 4, 5].map((i) => <rect key={i} y={i * 22} width="100" height="11" fill="#1b6e34" />)}
      <rect x="3" y="3" width="94" height="126" fill="none" stroke="rgba(255,255,255,.55)" strokeWidth="2" />
      <line x1="3" y1="66" x2="97" y2="66" stroke="rgba(255,255,255,.45)" strokeWidth="2" />
      <rect x="28" y="3" width="44" height="18" fill="none" stroke="rgba(255,255,255,.45)" strokeWidth="2" />
      <rect x="28" y="111" width="44" height="18" fill="none" stroke="rgba(255,255,255,.45)" strokeWidth="2" />
      {slots.map((s) => {
        const line = LINE(s)
        const x = 6 + (s.x / 100) * 88
        const y = 6 + (s.y / 100) * 120
        return <rect key={s.slot} className={`fp-dot is-${line}`} x={x - 5} y={y - 5} width="10" height="10" />
      })}
    </svg>
  )
}

const FILTERS = [
  ['all', 'Todas'],
  [4, 'Linha de 4'],
  [3, 'Linha de 3'],
  [5, 'Linha de 5'],
]

export default function FormationPicker({ formations = [], value, onChange, disabled = false, label = 'Formação', compact = false }) {
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('all')
  const current = formations.find((f) => f.id === value) || null
  const list = useMemo(() => formations.map((f) => ({ f, ...profileOf(f) })), [formations])
  const shown = list.filter((x) => filter === 'all' || x.back === filter)
  useEffect(() => {
    if (!open) return undefined
    const onKey = (e) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])
  const pick = (id) => {
    setOpen(false)
    if (id !== value) onChange?.(id)
  }
  const cur = current ? profileOf(current) : null
  return (
    <>
      <button type="button" className={`fp-trigger ${compact ? 'is-compact' : ''}`} disabled={disabled} onClick={() => setOpen(true)} aria-haspopup="dialog" aria-label={`${label}: ${current?.name || value}. Trocar formação`}>
        <FormationMini formation={current} size={compact ? 26 : 32} />
        <span className="fp-trigger-txt">
          <small>{label}</small>
          <b>{current?.name || value}</b>
          {!compact && cur && <em>{cur.style}</em>}
        </span>
        <ChevronDown size={16} className="fp-trigger-chev" />
      </button>
      {open && createPortal(
        <div className="fp-back" role="presentation" onClick={() => setOpen(false)}>
          <div className="fp-sheet" role="dialog" aria-modal="true" aria-label="Escolher formação" onClick={(e) => e.stopPropagation()}>
            <header className="fp-head">
              <div>
                <small>Escalação</small>
                <h3>Escolha a formação</h3>
              </div>
              <button type="button" className="fp-x" onClick={() => setOpen(false)} aria-label="Fechar"><X size={18} /></button>
            </header>
            <div className="fp-filters" role="tablist" aria-label="Linha de defesa">
              {FILTERS.map(([id, txt]) => (
                <button key={id} type="button" role="tab" aria-selected={filter === id} className={filter === id ? 'is-on' : ''} onClick={() => setFilter(id)}>{txt}</button>
              ))}
            </div>
            <div className="fp-grid">
              {shown.map(({ f, style, n }) => (
                <button key={f.id} type="button" className={`fp-card ${f.id === value ? 'is-on' : ''}`} onClick={() => pick(f.id)} aria-pressed={f.id === value}>
                  {f.id === value && <i className="fp-check" aria-hidden="true"><Check size={12} /></i>}
                  <FormationMini formation={f} size={74} active={f.id === value} />
                  <b>{f.name}</b>
                  <span className={`fp-style s-${style.toLowerCase()}`}>{style}</span>
                  <small>{n.def} def · {n.mid} meio · {n.att} at</small>
                </button>
              ))}
            </div>
            <p className="fp-legend"><i className="is-def" /> Defesa <i className="is-mid" /> Meio <i className="is-att" /> Ataque <i className="is-gk" /> Goleiro</p>
          </div>
        </div>,
        document.body,
      )}
    </>
  )
}
