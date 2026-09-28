import { useTheme } from '../../context/ThemeContext'
import { SunIcon, MoonIcon } from '../ui/icons'
import './AppShell.css'

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
              {theme === 'light' ? <MoonIcon size={17} /> : <SunIcon size={17} />}
            </button>
          </div>
        </header>
        <main className="app-content">{children}</main>
      </div>
    </div>
  )
}
