import { PitchCard } from '../../online/components/PlayerFut'

// Carta do campo nas Temporadas: a mesma do modo online (nota na vaga, posição, retrato, nome e a condição
// física embaixo), sempre como carta normal, porque nas Temporadas só existem cartas base.
export default function SeasonPitchCard(props) {
  return <PitchCard {...props} tier="normal" />
}
