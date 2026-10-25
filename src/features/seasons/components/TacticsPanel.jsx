import { DEFAULT_TACTICS, MENTALITY, MENTALITY_EFFECT, TACTIC_GROUPS } from '../utils/managerUtils'

// Instruções do time. Cada escolha mostra o efeito principal — o mesmo que o motor aplica na partida.
export default function TacticsPanel({ tactics, onChange, compact = false }) {
  const t = { ...DEFAULT_TACTICS, ...(tactics || {}) }
  const set = (k, v) => onChange({ ...t, [k]: v })
  const ment = MENTALITY.find((m) => m.v === Number(t.mentality)) || MENTALITY[2]
  return (
    <div className={`tp ${compact ? 'is-compact' : ''}`}>
      <section className="tp-group tp-ment">
        <header>
          <b>Postura</b>
          <span className="tp-val">{ment.label}</span>
        </header>
        <div className="tp-ment-scale" role="radiogroup" aria-label="Postura">
          {MENTALITY.map((m) => (
            <button
              key={m.v}
              type="button"
              role="radio"
              aria-checked={Number(t.mentality) === m.v}
              className={`m${m.v + 2} ${Number(t.mentality) === m.v ? 'is-on' : ''}`}
              onClick={() => set('mentality', m.v)}
            >
              {m.short}
            </button>
          ))}
        </div>
        {!compact && <p>{MENTALITY_EFFECT}</p>}
      </section>

      {TACTIC_GROUPS.map((g) => {
        const cur = g.options.find((o) => o.v === t[g.id]) || g.options[1]
        return (
          <section key={g.id} className="tp-group">
            <header>
              <b>{g.label}</b>
            </header>
            <div className="tp-opts" role="radiogroup" aria-label={g.label}>
              {g.options.map((o) => (
                <button key={o.v} type="button" role="radio" aria-checked={t[g.id] === o.v} className={t[g.id] === o.v ? 'is-on' : ''} onClick={() => set(g.id, o.v)}>
                  {o.label}
                </button>
              ))}
            </div>
            <p>{cur.effect}</p>
          </section>
        )
      })}
    </div>
  )
}
