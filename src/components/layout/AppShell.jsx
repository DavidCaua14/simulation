import { useTheme } from '../../context/ThemeContext'
import './AppShell.css'

function SunIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  )
}

function MoonIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
    </svg>
  )
}

/**
 * Casca do "aplicativo". Ocupa a tela inteira de cima a baixo, sem margens,
 * sem cantos arredondados e sem barra de rolagem — em qualquer tamanho de
 * tela deve parecer um celular real, nunca um cartão flutuando no desktop.
 *
 * `left`   -> conteúdo à esquerda do topo (ex: botão voltar)
 * `center` -> conteúdo central do topo (ex: título ou pontos de etapa)
 */
export default function AppShell({ left, center, title, children }) {
  const { theme, toggleTheme } = useTheme()

  return (
    <div className="app-viewport">
      <div className="app-frame">
        <header className="app-topbar">
          <div className="app-topbar-slot app-topbar-left">{left}</div>
          <div className="app-topbar-slot app-topbar-center">
            {center ?? <span className="app-topbar-title">{title}</span>}
          </div>
          <div className="app-topbar-slot app-topbar-right">
            <button
              type="button"
              className="icon-btn"
              onClick={toggleTheme}
              aria-label="Alternar tema"
              title={theme === 'light' ? 'Ativar modo escuro' : 'Ativar modo claro'}
            >
              {theme === 'light' ? <MoonIcon /> : <SunIcon />}
            </button>
          </div>
        </header>
        <main className="app-content">{children}</main>
      </div>
    </div>
  )
}
