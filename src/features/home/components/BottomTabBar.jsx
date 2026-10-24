import { TAB_ITEMS } from '../data/tabs'
import './tab-bar.css'

// Menu fixo embaixo (Home e Perfil). Itens bloqueados aparecem apagados com "em breve".
export default function BottomTabBar({ active = 'home', onSelect }) {
  return (
    <nav className="tab-bar">
      {TAB_ITEMS.map(({ id, label, Icon, locked }) => (
        <button
          type="button"
          key={id}
          className={`tab-item ${active === id ? 'is-active' : ''}`}
          disabled={locked}
          onClick={() => onSelect?.(id)}
          title={locked ? `${label} — em breve` : label}
          aria-current={active === id ? 'page' : undefined}
        >
          <Icon />
          <span>{label}</span>
        </button>
      ))}
    </nav>
  )
}
