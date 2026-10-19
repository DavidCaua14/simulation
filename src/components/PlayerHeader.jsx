import { useState } from 'react'
import { useAuth } from '../../../context/AuthContext'
import { LogOutIcon } from '../../../components/ui/icons'
import CurrencyRow from './CurrencyRow'

// avatar: nó React com a foto (você resolve o photo_id); sem ele, mostra a inicial do nome.
// themeToggle: <ThemeToggle isDark={...} onToggle={...} /> ligado ao seu tema atual.
export default function PlayerHeader({ player, wallet, avatar, themeToggle }) {
  const { signOut } = useAuth()
  const [menuOpen, setMenuOpen] = useState(false)

  return (
    <header className="player-header">
      <div className="player-header-main">
        <button
          type="button"
          className="player-avatar"
          onClick={() => setMenuOpen((open) => !open)}
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          aria-label="Abrir menu do perfil"
        >
          {avatar ?? <span className="player-avatar-initial">{player.nickname.charAt(0).toUpperCase()}</span>}
          <span className="player-level-chip">{player.level}</span>
        </button>

        <div className="player-info">
          <strong>{player.nickname}</strong>
          <span className="player-info-level">
            Nível {player.level}
            <span className="player-info-xp"> · {player.xp.toLocaleString('pt-BR')} XP</span>
          </span>
        </div>

        {themeToggle}
      </div>

      <CurrencyRow coins={wallet.coins} energy={wallet.energy} />

      {menuOpen && (
        <div className="player-menu" role="menu">
          <button type="button" role="menuitem" onClick={signOut}>
            <LogOutIcon />
            Sair da conta
          </button>
        </div>
      )}
    </header>
  )
}
