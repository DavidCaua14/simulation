import { ArrowLeftRight, CalendarDays, House, Trophy, User } from 'lucide-react'

export const NAV = [
  { id: 'home', label: 'Início', Icon: House },
  { id: 'matches', label: 'Jogos', Icon: CalendarDays },
  { id: 'comps', label: 'Torneios', Icon: Trophy },
  { id: 'market', label: 'Mercado', Icon: ArrowLeftRight },
  { id: 'career', label: 'Carreira', Icon: User },
]

// Navegação inferior do modo Temporadas (sempre visível, ao alcance do polegar).
export default function BottomNav({ active, onChange, badges = {} }) {
  return (
    <nav className="sn-nav" aria-label="Seções do modo Temporadas">
      {NAV.map(({ id, label, Icon }) => (
        <button key={id} type="button" className={active === id ? 'is-on' : ''} aria-current={active === id ? 'page' : undefined} onClick={() => onChange(id)}>
          <span className="sn-nav-icon">
            <Icon size={22} strokeWidth={active === id ? 2.4 : 2} />
            {badges[id] > 0 && <em aria-label={`${badges[id]} pendente(s)`}>{badges[id]}</em>}
          </span>
          <small>{label}</small>
        </button>
      ))}
    </nav>
  )
}
