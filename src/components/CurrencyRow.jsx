import { EnergyIcon, CoinsIcon, PlusIcon } from '../../../components/ui/icons'

// Só moedas e energia: não existe coluna de gemas no banco.
// Energia sem "/máx": o banco não define um teto.
export default function CurrencyRow({ coins, energy }) {
  const items = [
    { id: 'energy', Icon: EnergyIcon, value: energy },
    { id: 'coins', Icon: CoinsIcon, value: coins.toLocaleString('pt-BR') },
  ]

  return (
    <div className="currency-row">
      {items.map(({ id, Icon, value }) => (
        <div className="currency-pill" key={id}>
          <Icon />
          <span>{value}</span>
          <button type="button" className="currency-add" disabled aria-label="Comprar (em breve)">
            <PlusIcon size={12} />
          </button>
        </div>
      ))}
    </div>
  )
}
