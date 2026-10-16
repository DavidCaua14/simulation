import { TAB_ITEMS } from '../data/tabs'

export default function BottomTabBar({ active = 'home' }) {
  return (
    <nav className="tab-bar">
      {TAB_ITEMS.map(({ id, label, Icon, locked }) => (
        <button
          type="button"
          key={id}
          className={`tab-item ${active === id ? 'is-active' : ''}`}
          disabled={locked}
          title={locked ? `${label} — em breve` : label}
        >
          <Icon />
          <span>{label}</span>
        </button>
      ))}
    </nav>
  )
}
