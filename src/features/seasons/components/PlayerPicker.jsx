import { useMemo, useState } from 'react'
import { Ambulance, Ban, Info } from 'lucide-react'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import PositionFilter from './PositionFilter'
import Sheet from '../ui/Sheet'
import { POS_NAME, condTone, fitTone, POS_ORDER, posFit } from '../utils/managerUtils'

// Escolher quem joga numa vaga (ou no banco). Ordena pela nota NAQUELA posição e mostra
// adequação, condição física e disponibilidade — para comparar atletas antes de decidir.
export default function PlayerPicker({ target, players, slots, bench, onPick, onRemove, onInfo, onClose }) {
  const [positionFilter, setPositionFilter] = useState('')
  const [onlyAvail, setOnlyAvail] = useState(true)
  const isBench = target.kind === 'bench'
  const pos = target.pos
  const where = useMemo(() => {
    const m = {}
    Object.entries(slots || {}).forEach(([slot, pid]) => (m[pid] = `Titular · ${slot}`))
    ;(bench || []).forEach((pid) => (m[pid] = 'Banco'))
    return m
  }, [slots, bench])

  const list = useMemo(() => {
    const score = (p) => (isBench ? p.overall : p.ratings?.[pos] ?? 0) * (p.available ? 1 : 0.5)
    return players
      .filter((p) => !positionFilter || p.position === positionFilter)
      .filter((p) => !onlyAvail || p.available)
      .filter((p) => !isBench || !Object.values(slots || {}).includes(p.id))
      .sort((a, b) => POS_ORDER.indexOf(a.position) - POS_ORDER.indexOf(b.position) || score(b) - score(a))
  }, [players, onlyAvail, isBench, pos, slots, positionFilter])

  const current = target.current
  return (
    <Sheet
      kicker={isBench ? 'Banco de reservas' : `Vaga ${target.slot}`}
      title={isBench ? 'Escolher reserva' : POS_NAME[pos] || pos}
      onClose={onClose}
      tall
    >
      <div className="pk">
        <div className="pk-bar">
          <label className="pk-toggle">
            <input type="checkbox" checked={onlyAvail} onChange={(e) => setOnlyAvail(e.target.checked)} /> Só disponíveis
          </label>
          {current && onRemove && (
            <button type="button" className="gx-btn-ghost pk-remove" onClick={onRemove}>
              Tirar {isBench ? 'do banco' : 'da vaga'}
            </button>
          )}
        </div>
        {current && players.find((p) => p.id === current) && <button type="button" className="gx-btn-ghost" onClick={() => onInfo(players.find((p) => p.id === current))}>Ver ficha do jogador atual</button>}
        <PositionFilter id="picker-position" value={positionFilter} onChange={setPositionFilter} />
        <ul className="pk-list">
          {list.map((p) => {
            const r = Math.round(isBench ? p.overall : p.ratings?.[pos] ?? 0)
            const fit = isBench ? 1 : posFit(p, pos)
            const isCur = p.id === current
            return (
              <li key={p.id} className={`pk-row ${isCur ? 'is-cur' : ''} ${p.available ? '' : 'is-out'}`}>
                <button type="button" className="pk-main" onClick={() => onPick(p.id)} disabled={isCur}>
                  <BasePlayerCard player={p} position={isBench ? p.position : pos} overall={r} width={64} />
                  <span className="pk-txt">
                    <b>
                      {p.number != null && <em>{p.number}</em>} {p.short_name}
                    </b>
                    <small>
                      <i className={`pk-pos fit-${fitTone(fit)}`}>{p.position}</i>
                      {!isBench && fit < 0.97 && <span className={`pk-fit fit-${fitTone(fit)}`}>{fit >= 0.86 ? 'adaptado' : 'fora de posição'}</span>}
                      {where[p.id] && <span className="pk-where">{where[p.id]}</span>}
                    </small>
                  </span>
                  <span className="pk-state">
                    {p.injured_days > 0 ? (
                      <span className="pk-flag bad">
                        <Ambulance size={12} /> {p.injured_days}d
                      </span>
                    ) : p.suspended > 0 ? (
                      <span className="pk-flag bad">
                        <Ban size={12} /> susp.
                      </span>
                    ) : (
                      <span className={`pk-cond ${condTone(p.condition)}`} title="Condição física">
                        <i style={{ width: `${p.condition}%` }} />
                        <small>{p.condition}%</small>
                      </span>
                    )}
                  </span>
                </button>
                <button type="button" className="pk-info" onClick={() => onInfo(p)} aria-label={`Ver ficha de ${p.short_name}`}>
                  <Info size={16} />
                </button>
              </li>
            )
          })}
        </ul>
        {!list.length && <p className="sn-muted sn-center">Ninguém disponível com esse filtro.</p>}
      </div>
    </Sheet>
  )
}
