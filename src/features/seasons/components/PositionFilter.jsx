import { POS_NAME, POS_ORDER } from '../utils/managerUtils'

export default function PositionFilter({ value, onChange, id = 'squad-position' }) {
  return (
    <label className="base-position-filter" htmlFor={id}>
      Posição
      <select id={id} value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="">Todas as posições</option>
        {POS_ORDER.map((pos) => <option key={pos} value={pos}>{pos} · {POS_NAME[pos]}</option>)}
      </select>
    </label>
  )
}
