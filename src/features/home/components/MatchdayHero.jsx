import { Play } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { CountryFlag } from '../../player/components/flags'
import heroBg from '../assets/hero-bg.webp'

// Banner principal: o clube do jogador "em dia de jogo". As cores do clube tingem o estádio,
// e o botão leva direto para a próxima partida (modo Temporadas).
export default function MatchdayHero({ club, player, onPlay }) {
  const [c1, c2] = club?.colors || ['#1b3566', '#f5b800']
  return (
    <section className="hm-hero" style={{ '--c1': c1, '--c2': c2 }}>
      <img className="hm-hero-bg" src={heroBg} alt="" />
      <span className="hm-hero-tint" aria-hidden="true" />
      <span className="hm-hero-beam" aria-hidden="true" />

      <div className="hm-hero-top">
        <span className="gx-tag is-live">
          <span className="gx-dot" /> Temporadas · modo carreira
        </span>
        {player.country && <CountryFlag countryId={player.country} />}
      </div>

      <div className="hm-hero-club">
        {club && (
          <span className="hm-hero-crest">
            <ClubCrest clubId={club.id} size={58} />
          </span>
        )}
        <div className="hm-hero-text">
          <small>Seu clube</small>
          <h1>{club?.name || 'Sem clube'}</h1>
          <p>
            {player.position ? `${player.position} · ` : ''}
            {player.jerseyNumber ? `Camisa ${player.jerseyNumber} · ` : ''}Nível {player.level}
          </p>
        </div>
      </div>

      <div className="hm-hero-cta">
        <p>
          Próximo objetivo: <b>vencer a próxima partida</b> e subir na temporada.
        </p>
        <button type="button" className="gx-btn hm-hero-btn" onClick={onPlay}>
          <Play size={18} fill="currentColor" /> Jogar
        </button>
      </div>
    </section>
  )
}
