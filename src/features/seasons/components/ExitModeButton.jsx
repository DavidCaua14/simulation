import { LogOut } from 'lucide-react'

// Saída do modo Temporadas (o voltar do topo só navega dentro do modo). O progresso fica salvo no servidor.
export default function ExitModeButton({ onExit }) {
  if (!onExit) return null
  return (
    <div className="sn-exit">
      <button type="button" className="gx-btn-ghost" onClick={onExit}>
        <LogOut size={16} /> Sair do modo Temporadas
      </button>
      <small>Seu progresso fica salvo. Você volta de onde parou.</small>
    </div>
  )
}
