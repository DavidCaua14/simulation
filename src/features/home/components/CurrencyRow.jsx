import { EnergyIcon, CoinsIcon, GemIcon, PlusIcon } from '../../../components/ui/icons'

const CURRENCIES = [
  { id: 'energy', Icon: EnergyIcon, value: '50/50' },
  { id: 'coins', Icon: CoinsIcon, value: '0' },
  { id: 'gems', Icon: GemIcon, value: '0' },
]

export default function CurrencyRow() {
  return (
    <div className="currency-row">
      {CURRENCIES.map(({ id, Icon, value }) => (
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
