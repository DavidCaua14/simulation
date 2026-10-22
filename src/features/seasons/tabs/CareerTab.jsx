import PlayerCard from '../components/PlayerCard'
import CareerPanel from '../components/CareerPanel'

// CARREIRA: ficha do jogador, números da carreira, histórico de temporadas e regras de prêmio.
export default function CareerTab({ ctx, onRecharged }) {
  const { hub } = ctx
  return (
    <div className="sn-page">
      <PlayerCard career={hub.career} stats={hub.stats} season={hub.season} onRecharged={onRecharged} />
      <CareerPanel stats={hub.stats} />
    </div>
  )
}
