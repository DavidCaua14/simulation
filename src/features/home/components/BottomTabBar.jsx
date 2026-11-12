import { Lock } from 'lucide-react'
import { useAuth } from '../../../context/AuthContext'
import { isLockedFor } from '../data/access'
import { TAB_ITEMS } from '../data/tabs'
import './tab-bar.css'

// Menu fixo embaixo (Home e Perfil). Itens bloqueados aparecem apagados com "em breve".
export default function BottomTabBar({ active = 'home', onSelect }) {
  const { user } = useAuth()
  return (
    <nav className="tab-bar">
      {TAB_ITEMS.map((item) => ({ ...item, locked: isLockedFor(item, user) })).map(({ id, label, Icon, locked }) => (
        <button
          type="button"
          key={id}
          className={`tab-item ${active === id ? 'is-active' : ''}`}
          disabled={locked}
          onClick={() => onSelect?.(id)}
          title={locked ? `${label} — Indisponível` : label}
          aria-label={locked ? `${label} — Indisponível` : label}
          aria-current={active === id ? 'page' : undefined}
        >
          {locked ? <Lock size={20} /> : <Icon />}
          <span>{label}</span>
        </button>
      ))}
    </nav>
  )
}
