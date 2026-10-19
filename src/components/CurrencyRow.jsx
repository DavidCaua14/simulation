import { EnergyIcon, CoinsIcon } from './ui/icons'

const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('pt-BR'))

// Só moedas e energia: não existe coluna de gemas no banco.
// Versão compacta do topo (HUD): sem botão de compra, que ainda não existe.
export default function CurrencyRow({ coins, energy }) {
  return (
    <div className="hud-currencies">
      <div className="hud-pill energy" title="Energia" aria-label={`Energia: ${fmt(energy)}`}>
        <EnergyIcon />
        <span>{fmt(energy)}</span>
      </div>
      <div className="hud-pill coins" title="Moedas" aria-label={`Moedas: ${fmt(coins)}`}>
        <CoinsIcon />
        <span>{fmt(coins)}</span>
      </div>
    </div>
  )
}
