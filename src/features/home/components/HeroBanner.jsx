import { CountryFlag } from '../../player/components/flags'
import heroBg from '../assets/hero-bg.webp'

export default function HeroBanner({ club, countryId }) {
  return (
    <div className="hero-banner">
      <img className="hero-banner-bg" src={heroBg} alt="" />
      <div className="hero-banner-scrim" />
      <div className="hero-banner-content">
        <h1 className="heading hero-banner-title">
          Evolua seu jogador,
          <br />
          <span>conquiste seu time!</span>
        </h1>
        <p className="hero-banner-sub">Treine, jogue, evolua e mostre do que é capaz.</p>
      </div>

      {club && (
        <div className="hero-club-badge">
          <span className="hero-club-label">Seu time</span>
          <span className="hero-club-shield">
            <img src={club.shield} alt="" />
          </span>
          <strong>{club.name}</strong>
          {countryId && <CountryFlag countryId={countryId} />}
        </div>
      )}
    </div>
  )
}
