import { EnergyIcon, CoinsIcon, GemIcon } from './ui/icons'

const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('pt-BR'))

// Moedas, energia e diamantes. Versão compacta do topo (HUD): sem botão de compra, que ainda não existe.
// Diamantes só aparecem quando o valor já chegou do banco.
export default function CurrencyRow({ coins, energy, diamonds }) {
  return (
    <div className="hud-currencies">
      <div className="hud-pill energy" title="Energia" aria-label={`Energia: ${fmt(energy)}`}>
        <EnergyIcon />
        <span>{fmt(energy)}</span>
      </div>
      <div className="hud-row">
        <div className="hud-pill coins" title="Moedas" aria-label={`Moedas: ${fmt(coins)}`}>
          <CoinsIcon />
          <span>{fmt(coins)}</span>
        </div>
        {diamonds != null && (
          <div className="hud-pill gems" title="Diamantes" aria-label={`Diamantes: ${fmt(diamonds)}`}>
            <GemIcon />
            <span>{fmt(diamonds)}</span>
          </div>
        )}
      </div>
    </div>
  )
}
