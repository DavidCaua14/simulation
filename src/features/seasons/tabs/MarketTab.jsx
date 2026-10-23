import OffersPanel from '../components/OffersPanel'

// MERCADO: propostas de outros clubes (com prazo), histórico e a sua popularidade.
export default function MarketTab({ ctx, busyId, onRespond, onExpired }) {
  const { hub, myClub } = ctx
  return (
    <div className="sn-page">
      <OffersPanel
        offers={hub.offers}
        history={hub.offer_history}
        currentClub={myClub}
        popularity={hub.stats.popularity}
        busyId={busyId}
        onRespond={onRespond}
        onExpired={onExpired}
      />
    </div>
  )
}
