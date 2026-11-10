import { useState } from 'react'
import { ArrowLeftRight, Building2, Dumbbell, Home, Inbox, Info, LogOut, RotateCcw, Settings, Shirt, Trophy, UserRound, Wallet, X } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import './clubCentral.css'

// CENTRAL DO CLUBE: o menu em grade do Championship Manager. Cada botão leva à tela onde aquilo é feito.
// embedded: versão dentro do Início (sem o botão Início nem o cabeçalho de janela).
export default function ClubCentral({ hub, actions, embedded = false, onClose }) {
  const [settings, setSettings] = useState(false)
  const employed = hub.coach?.status === 'employed'
  const clubId = employed ? hub.coach.club_id : null
  const world = !!hub.world
  const go = (fn) => () => {
    onClose?.()
    fn()
  }

  const tiles = [
    !embedded && { id: 'home', label: 'Início', Icon: Home, run: actions.goHome },
    { id: 'team', label: 'Time', Icon: Shirt, run: () => actions.openTeam('lineup'), off: !employed },
    { id: 'training', label: 'Treino', Icon: Dumbbell, run: () => actions.openTeam('club', 'training'), off: !employed },
    { id: 'market', label: 'Transferências', Icon: ArrowLeftRight, run: () => actions.goTab('world', 'market'), off: !world || !employed },
    { id: 'club', label: 'Info do clube', Icon: Info, run: () => actions.openTeam('club'), off: !employed },
    { id: 'inbox', label: 'Caixa de entrada', Icon: Inbox, run: () => actions.openInbox(), badge: hub.unread },
    { id: 'facilities', label: 'Melhorias', Icon: Building2, run: () => actions.openTeam('club', 'facilities'), off: !employed },
    { id: 'coach', label: 'Técnico', Icon: UserRound, run: () => actions.goTab('career', 'profile'), badge: hub.offers?.length },
    { id: 'comps', label: 'Competições', Icon: Trophy, run: () => actions.goTab('comps') },
    { id: 'finance', label: 'Finanças', Icon: Wallet, run: () => actions.goTab('world', 'finance'), off: !world || !employed },
  ].filter(Boolean)

  const grid = (
    <div className="ctl-grid">
      {tiles.map(({ id, label, Icon, run, off, badge }) => (
        <button key={id} type="button" className={`ctl-tile t-${id}`} disabled={off} onClick={go(run)}>
          <Icon size={26} strokeWidth={2.2} />
          <span>{label}</span>
          {badge > 0 && <em>{badge}</em>}
        </button>
      ))}
      <button type="button" className={`ctl-tile t-settings ${settings ? 'is-on' : ''}`} aria-expanded={settings} onClick={() => setSettings((s) => !s)}>
        <Settings size={26} strokeWidth={2.2} />
        <span>Configurações</span>
      </button>
    </div>
  )

  const settingsPanel = settings && (
    <div className="ctl-settings">
      {actions.restartAssistant && (
        <button type="button" className="gx-btn-ghost" onClick={go(actions.restartAssistant)}>
          <RotateCcw size={15} /> Rever o assistente
        </button>
      )}
      <button type="button" className="gx-btn-ghost" onClick={go(actions.exit)}>
        <LogOut size={15} /> Sair do modo
      </button>
    </div>
  )

  if (embedded)
    return (
      <section className="ctl is-embedded" aria-label="Central do clube">
        <h2 className="ctl-title">Central do clube</h2>
        {grid}
        {settingsPanel}
      </section>
    )

  return (
    <div className="ctl-overlay" role="dialog" aria-modal="true" aria-label="Central do clube">
      <section className="ctl">
        <header className="ctl-head">
          {clubId && <ClubCrest clubId={clubId} size={40} />}
          <span>
            <small>Central do clube</small>
            <b>{clubId ? getClubById(clubId)?.name : 'Sem clube'}</b>
          </span>
          <button type="button" className="ctl-close" aria-label="Fechar" onClick={onClose}>
            <X size={20} />
          </button>
        </header>
        {grid}
        {settingsPanel}
      </section>
    </div>
  )
}
