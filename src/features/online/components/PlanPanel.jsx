import { Crosshair } from 'lucide-react'
import { INSTRUCTIONS, PLANS, PLAN_BY_ID, planLabel, planOf } from '../plans'
import './plan-panel.css'

// Aderência do elenco ao plano: vantagem do atributo-chave sobre o adversário (−1,5 a +1,5 em unidades de 10 pontos).
function fitTone(edge) {
  if (edge == null) return null
  if (edge >= 0.4) return ['Alta', 'is-good']
  if (edge <= -0.4) return ['Baixa', 'is-bad']
  return ['Média', 'is-mid']
}

// TÁTICAS DO MODO ONLINE: um plano de jogo e instruções por cima dele.
// fit (opcional) vem de on_plan_fit: aderência de cada plano contra os jogadores do adversário e quem marcar.
// O plano do adversário nunca aparece: como no futebol de verdade, só se descobre jogando.
export default function PlanPanel({ tactics = {}, onChange, fit = null, compact = false }) {
  const plan = planOf(tactics)
  const cur = PLAN_BY_ID[plan]
  const set = (patch) => onChange({ ...tactics, plan, ...patch })

  return (
    <div className={`pln ${compact ? 'is-compact' : ''}`}>
      <p className="pln-opp">O plano do adversário só se descobre jogando. A aderência compara os seus jogadores com os dele.</p>
      <div className="pln-grid" role="radiogroup" aria-label="Plano de jogo">
        {PLANS.map((p) => {
          const f = fit?.plans?.[p.id]
          const tone = p.id === 'equilibrado' ? null : fitTone(f?.edge)
          return (
            <button key={p.id} type="button" role="radio" aria-checked={plan === p.id} className={`pln-card ${plan === p.id ? 'is-on' : ''}`} onClick={() => set({ plan: p.id })}>
              <p.Icon size={18} />
              <strong>{p.label}</strong>
              {tone && (
                <span className={`pln-fit ${tone[1]}`} title="Aderência do seu elenco a este plano contra este adversário">
                  <i style={{ width: `${Math.round(((f.edge + 1.5) / 3) * 100)}%` }} />
                  <small>Aderência {tone[0]}</small>
                </span>
              )}
            </button>
          )
        })}
      </div>

      <section className="pln-info" aria-live="polite">
        <h4><cur.Icon size={16} /> {cur.label}</h4>
        <p>{cur.what}</p>
        <dl>
          <dt>Exige</dt><dd>{cur.needs}</dd>
          {cur.strong.length > 0 && (<><dt>Forte contra</dt><dd>{cur.strong.map(planLabel).join(', ')}</dd></>)}
          {cur.weak.length > 0 && (<><dt>Fraco contra</dt><dd>{cur.weak.map(planLabel).join(', ')}</dd></>)}
        </dl>
      </section>

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
            <option value="">Ninguém (marcação por zona)</option>
            {fit.mark.map((p) => <option key={p.id} value={p.id}>{p.name} · {p.pos} {Math.round(p.ovr)}</option>)}
          </select>
          {!compact && <p>Um marcador colado no jogador escolhido: ele finaliza pior e o time rival cria um pouco menos. O seu time cansa um pouco mais.</p>}
        </section>
      )}
    </div>
  )
}
