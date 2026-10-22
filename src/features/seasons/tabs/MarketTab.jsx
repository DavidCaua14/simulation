import OffersPanel from '../components/OffersPanel'

// MERCADO: propostas de outros clubes e a sua popularidade.
export default function MarketTab({ ctx, busyId, onRespond }) {
  const { hub, myClub } = ctx
  return (
    <div className="sn-page">
      <OffersPanel offers={hub.offers} currentClub={myClub} popularity={hub.stats.popularity} busyId={busyId} onRespond={onRespond} />
    </div>
  )
}
