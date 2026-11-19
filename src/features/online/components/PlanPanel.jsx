import { useState } from 'react'
import { Crosshair, Info, Trash2, X } from 'lucide-react'
import { INSTRUCTIONS, MAX_MARKS, PLANS, PLAN_BY_ID, planLabel, planOf } from '../plans'
import './plan-panel.css'

// Encaixe do elenco no estilo (1 a 3 bolinhas): vem da vantagem dos atributos-chave sobre o adversário (on_plan_fit).
const fitDots = (edge) => (edge == null ? 0 : edge >= 0.4 ? 3 : edge > -0.4 ? 2 : 1)
const FIT_LABEL = { 1: 'Encaixe baixo', 2: 'Encaixe bom', 3: 'Encaixe ótimo' }

function Dots({ n }) {
  return (
    <span className="pln-dots" aria-label={FIT_LABEL[n]}>
      {[1, 2, 3].map((i) => <i key={i} className={i <= n ? 'is-on' : ''} />)}
    </span>
  )
}

// Explicação de um estilo (abre pelo ícone de informação do card).
function PlanInfo({ plan, dots, onClose, onPick, picked }) {
  return (
    <div className="pln-modal" role="dialog" aria-modal="true" aria-label={plan.label} onClick={onClose}>
      <div className="pln-modal-card" onClick={(e) => e.stopPropagation()}>
        <header>
          <span className="pln-modal-ic"><plan.Icon size={22} /></span>
          <h4>{plan.label}</h4>
          <button type="button" className="pln-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
        </header>
        <p className="pln-what">{plan.what}</p>
        <h5>Principais atributos influenciados</h5>
        <ul className="pln-attrs">{plan.attrs.map((a) => <li key={a}>{a}</li>)}</ul>
        <dl>
          <div><dt>Encaixe do elenco</dt><dd>{plan.keys}</dd></div>
          {plan.strong.length > 0 && <div><dt>Leva vantagem contra</dt><dd>{plan.strong.map(planLabel).join(' · ')}</dd></div>}
          {dots > 0 && <div><dt>Seu elenco hoje</dt><dd className="pln-fitline"><Dots n={dots} /> {FIT_LABEL[dots]}</dd></div>}
        </dl>
        <button type="button" className="gx-btn" disabled={picked} onClick={() => { onPick(); onClose() }}>{picked ? 'Estilo atual' : 'Usar este estilo'}</button>
      </div>
    </div>
  )
}

// Marcação individual (como no eFootball): escolha quem do seu time gruda em quem do adversário. Até 2 pares.
function Marking({ marks, mine, theirs, onChange, compact }) {
  const usedBy = new Set(marks.map((m) => m.by))
  const usedOn = new Set(marks.map((m) => m.on))
  const nameOf = (list, id) => list.find((p) => p.id === id)
  const setPair = (i, patch) => onChange(marks.map((m, j) => (j === i ? { ...m, ...patch } : m)).filter((m) => m.by && m.on))
  const [draftOn, setDraftOn] = useState('')
  const outfield = mine.filter((p) => p.pos !== 'GOL')
  return (
    <section className="pln-ins pln-mark">
      <h5><Crosshair size={14} /> Marcação individual</h5>
      {marks.map((m, i) => {
        const t = nameOf(theirs, m.on)
        return (
          <div key={`${m.on}-${i}`} className="pln-pair">
            <span className="pln-pair-on"><small>{t?.pos || '–'}</small><b>{t?.name || 'Fora do time'}</b><em>{t ? Math.round(t.ovr) : ''}</em></span>
            <span className="pln-pair-by-l">marcado por</span>
            <select value={m.by} onChange={(e) => setPair(i, { by: e.target.value })} aria-label={`Marcador de ${t?.name || 'adversário'}`}>
              {outfield.filter((p) => p.id === m.by || !usedBy.has(p.id)).map((p) => <option key={p.id} value={p.id}>{p.name} · {p.pos} {Math.round(p.ovr)}</option>)}
            </select>
            <button type="button" className="pln-pair-x" onClick={() => onChange(marks.filter((_, j) => j !== i))} aria-label="Tirar marcação"><Trash2 size={15} /></button>
          </div>
        )
      })}
      {marks.length < MAX_MARKS && (
        <div className="pln-pair is-new">
          <select value={draftOn} onChange={(e) => setDraftOn(e.target.value)} aria-label="Jogador do adversário">
            <option value="">Escolher jogador do adversário…</option>
            {theirs.filter((p) => !usedOn.has(p.id)).map((p) => <option key={p.id} value={p.id}>{p.name} · {p.pos} {Math.round(p.ovr)}</option>)}
          </select>
          <select
            value=""
            disabled={!draftOn}
            onChange={(e) => {
              if (!e.target.value) return
              onChange([...marks, { by: e.target.value, on: draftOn }])
              setDraftOn('')
            }}
            aria-label="Seu marcador"
          >
            <option value="">Quem marca…</option>
            {outfield.filter((p) => !usedBy.has(p.id)).map((p) => <option key={p.id} value={p.id}>{p.name} · {p.pos} {Math.round(p.ovr)}</option>)}
          </select>
        </div>
      )}
      {!compact && <p>O marcador gruda no alvo: ele recebe menos e finaliza pior (quanto melhores a defesa, o desarme e a velocidade do marcador). O marcador ajuda menos no ataque e cansa um pouco mais.</p>}
    </section>
  )
}

// TÁTICAS DO MODO ONLINE: estilo de jogo, instruções e marcação individual.
// fit (opcional) vem de on_plan_fit: encaixe de cada estilo e o provável time do adversário (fit.mark).
// mine: titulares do meu time ({id, name, pos, ovr}) para escolher os marcadores.
export default function PlanPanel({ tactics = {}, onChange, fit = null, compact = false, mine = null }) {
  const plan = planOf(tactics)
  const cur = PLAN_BY_ID[plan]
  const [info, setInfo] = useState(null)
  const set = (patch) => onChange({ ...tactics, plan, ...patch })
  const dotsOf = (id) => fitDots(fit?.plans?.[id]?.edge)
  const marks = (tactics.marks || []).filter((m) => m?.by && m?.on)
  const theirs = fit?.mark || []

  return (
    <div className={`pln ${compact ? 'is-compact' : ''}`}>
      <h5 className="pln-h">Estilo de jogo</h5>
      <div className="pln-grid" role="radiogroup" aria-label="Estilo de jogo">
        {PLANS.map((p) => {
          const n = dotsOf(p.id)
          return (
            <div key={p.id} className={`pln-card ${plan === p.id ? 'is-on' : ''}`}>
              <button type="button" role="radio" aria-checked={plan === p.id} className="pln-card-pick" onClick={() => set({ plan: p.id })}>
                <span className="pln-card-top"><p.Icon size={18} />{n > 0 && <Dots n={n} />}</span>
                <strong>{p.label}</strong>
              </button>
              <button type="button" className="pln-card-info" onClick={() => setInfo(p.id)} aria-label={`O que é ${p.label}`}><Info size={16} /></button>
            </div>
          )
        })}
      </div>

      {!compact && (
        <section className="pln-info" aria-live="polite">
          <h4><cur.Icon size={18} /> {cur.label}</h4>
          <p className="pln-what">{cur.what}</p>
          <p className="pln-attrline">{cur.attrs.join(' · ')}</p>
        </section>
      )}
      {fit?.plans && <p className="pln-legend"><Dots n={3} /> Encaixe: quanto o seu elenco combina com o estilo, comparado ao adversário.</p>}

      {INSTRUCTIONS.map((g) => {
        const def = g.def || g.options[1].v
        const on = g.options.find((o) => o.v === (tactics[g.id] || def)) || g.options.find((o) => o.v === def)
        return (
          <section key={g.id} className="pln-ins" role="radiogroup" aria-label={g.label}>
            <h5>{g.label}</h5>
            <div className="pln-opts">
              {g.options.map((o) => (
                <button key={o.v} type="button" role="radio" aria-checked={on.v === o.v} className={on.v === o.v ? 'is-on' : ''} onClick={() => set({ [g.id]: o.v })}>{o.label}</button>
              ))}
            </div>
            {!compact && <p>{on.effect}</p>}
          </section>
        )
      })}

      {mine && theirs.length > 0 && <Marking marks={marks} mine={mine} theirs={theirs} compact={compact} onChange={(m) => set({ marks: m })} />}

      {info && (
        <PlanInfo plan={PLAN_BY_ID[info]} dots={dotsOf(info)} picked={plan === info} onPick={() => set({ plan: info })} onClose={() => setInfo(null)} />
      )}
    </div>
  )
}
