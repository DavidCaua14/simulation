import { TACTIC_GROUPS, cmOnly, toCM } from '../utils/managerUtils'

// INSTRUÇÕES TÁTICAS no formato do CM17: Estilo e Ataque em colunas, e as linhas Passe, Desarme, Ritmo,
// Marcação, Chutes longos, Bola parada e Cruzamento. Valem antes do jogo e durante a partida.
export default function TacticsPanel({ tactics, onChange, compact = false }) {
  const t = toCM(tactics)
  const set = (k, v) => onChange(cmOnly({ ...t, [k]: v }))
  const columns = TACTIC_GROUPS.filter((g) => g.column)
  const rows = TACTIC_GROUPS.filter((g) => !g.column)
  const effect = (g) => g.options.find((o) => o.v === t[g.id])?.effect

  return (
    <div className={`tpc ${compact ? 'is-compact' : ''}`}>
      <div className="tpc-cols">
        {columns.map((g) => (
          <section key={g.id} className="tpc-col" role="radiogroup" aria-label={g.label}>
            <h4>{g.label}</h4>
            {g.options.map((o) => (
              <button key={o.v} type="button" role="radio" aria-checked={t[g.id] === o.v} className={t[g.id] === o.v ? 'is-on' : ''} title={o.effect} onClick={() => set(g.id, o.v)}>
                {o.label}
              </button>
            ))}
            {!compact && <p>{effect(g)}</p>}
          </section>
        ))}
      </div>
      <div className="tpc-rows">
        {rows.map((g) => (
          <section key={g.id} className="tpc-row" role="radiogroup" aria-label={g.label}>
            <h4>{g.label}</h4>
            <div style={{ gridTemplateColumns: `repeat(${g.options.length}, minmax(0, 1fr))` }}>
              {g.options.map((o) => (
                <button key={o.v} type="button" role="radio" aria-checked={t[g.id] === o.v} className={t[g.id] === o.v ? 'is-on' : ''} title={o.effect} onClick={() => set(g.id, o.v)}>
                  {o.label}
                </button>
              ))}
            </div>
            {!compact && <p>{effect(g)}</p>}
          </section>
        ))}
      </div>
    </div>
  )
}
