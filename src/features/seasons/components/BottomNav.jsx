import { ArrowLeftRight, CalendarDays, Home, Trophy, User } from 'lucide-react'

export const NAV = [
  { id: 'home', label: 'Início', Icon: Home },
  { id: 'matches', label: 'Jogos', Icon: CalendarDays },
  { id: 'comps', label: 'Torneios', Icon: Trophy },
  { id: 'market', label: 'Mercado', Icon: ArrowLeftRight },
  { id: 'career', label: 'Carreira', Icon: User },
]

// Navegação inferior do modo Temporadas (fica sempre visível, ao alcance do polegar).
export default function BottomNav({ active, onChange, badges = {} }) {
  return (
    <nav className="sn-nav" aria-label="Seções do modo Temporadas">
      {NAV.map(({ id, label, Icon }) => (
        <button key={id} type="button" className={active === id ? 'is-on' : ''} aria-current={active === id ? 'page' : undefined} onClick={() => onChange(id)}>
          <span className="sn-nav-icon">
            <Icon size={21} />
            {badges[id] > 0 && <em>{badges[id]}</em>}
          </span>
          <small>{label}</small>
        </button>
      ))}
    </nav>
  )
}
