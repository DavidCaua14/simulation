import './AppShell.css'

/**
 * Casca do "aplicativo". Ocupa a tela inteira de cima a baixo, sem margens,
 * sem cantos arredondados e sem barra de rolagem — em qualquer tamanho de
 * tela deve parecer um celular real, nunca um cartão flutuando no desktop.
 *
 * `header` -> topo próprio (ex: <PlayerHeader />). Quando existe, substitui a barra padrão.
 * `left`   -> conteúdo à esquerda da barra padrão (ex: botão voltar)
 * `center` -> conteúdo central da barra padrão (ex: título ou pontos de etapa)
 * `right`  -> ação opcional à direita (o lado vazio mantém o título centralizado)
 *
 * O tema claro/escuro não fica mais no topo das telas: a escolha está no Perfil → Conta
 * (e no menu do avatar na Home).
 */
export default function AppShell({ header, left, center, right, title, children }) {
  return (
    <div className="app-viewport">
      <div className="app-frame">
        {header ?? (
          <header className="app-topbar">
            <div className="app-topbar-slot app-topbar-left">{left}</div>
            <div className="app-topbar-slot app-topbar-center">
              {center ?? <span className="app-topbar-title">{title}</span>}
            </div>
            <div className="app-topbar-slot app-topbar-right">{right}</div>
          </header>
        )}
        <main className="app-content">{children}</main>
      </div>
    </div>
  )
}
