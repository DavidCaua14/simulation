import { useMemo, useState } from 'react'
import { X } from 'lucide-react'
import EfTile from './EfTile'

const GROUPS = [
  ['all', 'Todos', null],
  ['gk', 'GOL', ['GOL']],
  ['def', 'DEF', ['ZAG', 'LD', 'LE']],
  ['mid', 'MEI', ['VOL', 'MC', 'MEI']],
  ['att', 'ATA', ['PD', 'PE', 'ATA']],
]
const SORTS = [
  ['ovr', 'Nota'],
  ['arrow', 'Condição'],
  ['pos', 'Posição'],
]
const POS_ORDER = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, MC: 5, MEI: 6, PD: 7, PE: 7, ATA: 8 }
const BADGE = { slot: 'T', bench: 'R' }

// GAVETA DO ELENCO (estilo eFootball): todos os jogadores em cartas, com filtro por setor e ordenação.
// statusOf(id) devolve 'slot' (titular), 'bench' (reserva) ou 'out'. onPick(id) abre a ficha ou completa a troca.
export default function SquadDrawer({ players, statusOf, colors, onPick, onClose, swapping = null, bind = null }) {
  const [group, setGroup] = useState('all')
  const [sort, setSort] = useState('ovr')
  const list = useMemo(() => {
    const allowed = GROUPS.find((g) => g[0] === group)?.[2]
    const rows = players.filter((p) => !allowed || allowed.includes(p.pos))
    const key = {
      ovr: (p) => -p.ovr,
      arrow: (p) => -(p.arrow ?? 3) * 100 - p.ovr / 100,
      pos: (p) => (POS_ORDER[p.pos] || 9) * 1000 - p.ovr,
    }[sort]
    return [...rows].sort((a, b) => key(a) - key(b))
  }, [players, group, sort])
  return (
    <div className="ef-drawer-veil" role="dialog" aria-modal="true" aria-label="Jogadores do elenco" onClick={onClose}>
      <aside className="ef-drawer" onClick={(e) => e.stopPropagation()}>
        <header>
          <div className="ef-drawer-filters" role="group" aria-label="Filtro">
            {GROUPS.map(([id, label]) => (
              <button key={id} type="button" className={group === id ? 'is-on' : ''} onClick={() => setGroup(id)}>{label}</button>
            ))}
          </div>
          <button type="button" className="ef-drawer-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
        </header>
        <div className="ef-drawer-sort" role="group" aria-label="Ordenar">
          <small>Ordenar</small>
          {SORTS.map(([id, label]) => (
            <button key={id} type="button" className={sort === id ? 'is-on' : ''} onClick={() => setSort(id)}>{label}</button>
          ))}
        </div>
        {swapping && <p className="ef-drawer-hint">Escolha quem troca com <b>{swapping}</b></p>}
        <div className="ef-drawer-grid">
          {list.map((p) => {
            const st = statusOf(p.id)
            return (
              <div key={p.id} className="ef-dslot" {...(bind ? bind(`p:${p.id}`, p.id) : {})}>
                <EfTile player={p} colors={colors} badge={BADGE[st]} dim={st === 'out'} onClick={() => onPick(p.id)} />
              </div>
            )
          })}
        </div>
        <p className="ef-drawer-legend"><b>T</b> titular · <b>R</b> reserva · apagado: fora da lista · segure e arraste uma carta até o campo</p>
      </aside>
    </div>
  )
}
