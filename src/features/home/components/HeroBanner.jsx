import { RankingIcon } from '../../../components/ui/icons'
import { CountryFlag } from '../../player/components/flags'
import ClubCrest from '../../club/components/ClubCrest'
import heroBg from '../assets/hero-bg.webp'

function PitchLines() {
  return (
    <svg className="hero-pitch-lines" viewBox="0 0 360 140" preserveAspectRatio="none" aria-hidden="true">
      <g fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="8" y="8" width="344" height="124" rx="2" />
        <line x1="180" y1="8" x2="180" y2="132" />
        <circle cx="180" cy="70" r="26" />
        <rect x="8" y="38" width="46" height="64" />
        <rect x="306" y="38" width="46" height="64" />
        <rect x="8" y="54" width="18" height="32" />
        <rect x="334" y="54" width="18" height="32" />
      </g>
      <circle cx="180" cy="70" r="2.5" fill="currentColor" />
    </svg>
  )
}

export default function HeroBanner({ club, countryId }) {
  return (
    <section className="hero-banner">
      <img className="hero-banner-bg" src={heroBg} alt="" />
      <div className="hero-banner-scrim" />
      <div className="hero-pitch-stripes" />
      <PitchLines />
      <span className="hero-light hero-light-left" />
      <span className="hero-light hero-light-right" />

      <div className="hero-banner-content">
        <span className="hero-kicker">
          <RankingIcon size={12} />
          Modo carreira
        </span>
        <h1 className="heading hero-banner-title">
          Evolua seu jogador,
          <br />
          <span>conquiste seu time!</span>
        </h1>
        <p className="hero-banner-sub">Treine, jogue, evolua e mostre do que é capaz.</p>
      </div>

      {club && (
        <div className="hero-scoreboard">
          <span className="hero-club-shield">
            {club.shield ? <img src={club.shield} alt="" /> : <ClubCrest clubId={club.id} size={30} />}
          </span>
          <span className="hero-scoreboard-text">
            <small>Seu time</small>
            <strong>{club.name}</strong>
          </span>
          {countryId && <CountryFlag countryId={countryId} />}
          <span className="hero-live">
            <span className="live-dot" aria-hidden="true" />
            Em campo
          </span>
        </div>
      )}
    </section>
  )
}
