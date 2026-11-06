import { POS_LINE, POS_NAME, POS_ORDER } from '../utils/managerUtils'
import './position-filter.css'

// Filtro de posição no padrão do jogo: fichas coloridas por setor (goleiro, defesa, meio, ataque).
// Toque de novo na posição marcada para voltar a "Todas".
export default function PositionFilter({ value, onChange, allLabel = 'Todas', label = 'Posição' }) {
  return (
    <div className="pf-chips" role="radiogroup" aria-label={label}>
      <button type="button" role="radio" aria-checked={!value} className={!value ? 'is-on' : ''} onClick={() => onChange('')}>
        {allLabel}
      </button>
      {POS_ORDER.map((pos) => (
        <button
          key={pos}
          type="button"
          role="radio"
          aria-checked={value === pos}
          className={`l-${POS_LINE[pos]} ${value === pos ? 'is-on' : ''}`}
          title={POS_NAME[pos]}
          onClick={() => onChange(value === pos ? '' : pos)}
        >
          {pos}
        </button>
      ))}
    </div>
  )
}
