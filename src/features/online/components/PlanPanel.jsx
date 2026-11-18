import { Crosshair } from 'lucide-react'
import { INSTRUCTIONS, PLANS, PLAN_BY_ID, planLabel, planOf } from '../plans'
import './plan-panel.css'

// Encaixe do elenco no plano (1 a 3 bolinhas): vem da vantagem do atributo-chave sobre o adversário (on_plan_fit).
const fitDots = (edge) => (edge == null ? 0 : edge >= 0.4 ? 3 : edge > -0.4 ? 2 : 1)
const FIT_LABEL = { 1: 'Encaixe baixo', 2: 'Encaixe bom', 3: 'Encaixe ótimo' }

function Dots({ n }) {
  return (
    <span className="pln-dots" aria-label={FIT_LABEL[n]}>
      {[1, 2, 3].map((i) => <i key={i} className={i <= n ? 'is-on' : ''} />)}
    </span>
  )
}

// TÁTICAS DO MODO ONLINE: escolha do plano de jogo e instruções. Só o que funciona, em frases curtas.
// fit (opcional) vem de on_plan_fit: encaixe de cada plano com o seu elenco e quem dá para marcar.
export default function PlanPanel({ tactics = {}, onChange, fit = null, compact = false }) {
  const plan = planOf(tactics)
  const cur = PLAN_BY_ID[plan]
  const set = (patch) => onChange({ ...tactics, plan, ...patch })
  const curDots = plan === 'equilibrado' ? 0 : fitDots(fit?.plans?.[plan]?.edge)

  return (
    <div className={`pln ${compact ? 'is-compact' : ''}`}>
      <div className="pln-grid" role="radiogroup" aria-label="Plano de jogo">
        {PLANS.map((p) => {
          const n = p.id === 'equilibrado' ? 0 : fitDots(fit?.plans?.[p.id]?.edge)
          return (
            <button key={p.id} type="button" role="radio" aria-checked={plan === p.id} className={`pln-card ${plan === p.id ? 'is-on' : ''}`} onClick={() => set({ plan: p.id })}>
              <span className="pln-card-top"><p.Icon size={18} />{n > 0 && <Dots n={n} />}</span>
              <strong>{p.label}</strong>
            </button>
          )
        })}
      </div>

      <section className="pln-info" aria-live="polite">
        <h4><cur.Icon size={18} /> {cur.label}</h4>
        <p className="pln-what">{cur.what}</p>
        <ul>
          <li><span>Funciona com</span><b>{cur.needs}</b></li>
          {cur.strong.length > 0 && <li><span>Melhor contra</span><b>{cur.strong.map(planLabel).join(', ')}</b></li>}
          {curDots > 0 && <li><span>Seu elenco</span><b className="pln-fitline"><Dots n={curDots} /> {FIT_LABEL[curDots]}</b></li>}
        </ul>
      </section>
      {fit?.plans && <p className="pln-legend"><Dots n={3} /> Encaixe: quanto o seu elenco combina com o plano, comparado ao adversário.</p>}

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

      {fit?.mark?.length > 0 && (
        <section className="pln-ins">
          <h5><Crosshair size={14} /> Marcar o craque</h5>
          <select value={tactics.mark || ''} onChange={(e) => set({ mark: e.target.value || null })}>
            <option value="">Ninguém</option>
            {fit.mark.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.pos} {Math.round(p.ovr)}</option>)}
          </select>
          {!compact && <p>Um marcador colado no craque: ele finaliza pior.</p>}
        </section>
      )}
    </div>
  )
}
