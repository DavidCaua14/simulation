import { CLUB_MONEY_SCALE, fromClubReais, toClubReais } from '../utils/clubMoney'

export default function ClubMoneyInput({ value, onChange, min = 0, max = 100000000, ...props }) {
  return <input {...props} type="number" inputMode="numeric" min={min * CLUB_MONEY_SCALE} max={max * CLUB_MONEY_SCALE}
    step={CLUB_MONEY_SCALE} required value={toClubReais(value)} onChange={(e) => onChange(fromClubReais(e.target.value))} />
}
