import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { useTheme } from '../context/ThemeContext'
import { LogOutIcon } from './ui/icons'
import { PLACEHOLDER_XP_TO_NEXT_LEVEL } from '../features/player/data/gameConstants'
import CurrencyRow from './CurrencyRow'
import ThemeToggle from './ThemeToggle'
import './player-hud.css'

// Topo da tela inicial (HUD): perfil à esquerda, moedas e energia à direita.
// avatarSrc: URL da foto do jogador (sem ela, mostra a inicial do nome).
// wallet: { coins, energy }
export default function PlayerHeader({ player, wallet, avatarSrc }) {
  const { signOut } = useAuth()
  const { theme, toggleTheme } = useTheme()
  const [menuOpen, setMenuOpen] = useState(false)
  const rootRef = useRef(null)

  // Fecha o menu ao clicar fora ou apertar Esc
  useEffect(() => {
    if (!menuOpen) return undefined
    const onDown = (e) => {
      if (rootRef.current && !rootRef.current.contains(e.target)) setMenuOpen(false)
    }
    const onKey = (e) => e.key === 'Escape' && setMenuOpen(false)
    document.addEventListener('pointerdown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [menuOpen])

  const xp = player.xp ?? 0
  // A curva real de XP por nível ainda não existe: a barra usa o valor provisório.
  const pct = Math.max(0, Math.min(100, (xp / PLACEHOLDER_XP_TO_NEXT_LEVEL) * 100))

  return (
    <header className="hud" ref={rootRef}>
      <button
        type="button"
        className="hud-profile"
        onClick={() => setMenuOpen((open) => !open)}
        aria-haspopup="menu"
        aria-expanded={menuOpen}
        aria-label="Abrir menu do perfil"
      >
        <span className="hud-avatar" style={{ '--xp': pct }}>
          <span className="hud-avatar-inner">
            {avatarSrc ? (
              <img src={avatarSrc} alt="" />
            ) : (
              <span className="hud-initial">{player.nickname.charAt(0).toUpperCase()}</span>
            )}
          </span>
          <span className="hud-level">{player.level}</span>
        </span>

        <span className="hud-info">
          <strong className="hud-name">{player.nickname}</strong>
          <span className="hud-xp" aria-hidden="true">
            <i style={{ width: `${pct}%` }} />
          </span>
          <small>
            Nível {player.level} · {xp.toLocaleString('pt-BR')} XP
          </small>
        </span>
      </button>

      <CurrencyRow coins={wallet?.coins} energy={wallet?.energy} />

      {menuOpen && (
        <div className="hud-menu" role="menu">
          <div className="hud-menu-row">
            <span>Tema {theme === 'dark' ? 'escuro' : 'claro'}</span>
            <ThemeToggle isDark={theme === 'dark'} onToggle={toggleTheme} />
          </div>
          <button type="button" role="menuitem" className="hud-menu-item" onClick={signOut}>
            <LogOutIcon />
            Sair da conta
          </button>
        </div>
      )}
    </header>
  )
}
