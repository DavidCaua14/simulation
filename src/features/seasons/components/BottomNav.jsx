import { CalendarDays, House, Shirt, Trophy, User } from 'lucide-react'

export const NAV = [
  { id: 'home', label: 'Início', Icon: House },
  { id: 'team', label: 'Time', Icon: Shirt },
  { id: 'matches', label: 'Jogos', Icon: CalendarDays },
  { id: 'comps', label: 'Torneios', Icon: Trophy },
  { id: 'career', label: 'Carreira', Icon: User },
]

// Navegação inferior do modo Carreira (sempre visível, ao alcance do polegar).
export default function BottomNav({ active, onChange, badges = {} }) {
  return (
    <nav className="sn-nav" aria-label="Seções do modo Carreira">
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
