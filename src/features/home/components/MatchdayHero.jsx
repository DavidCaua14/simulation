import { useEffect, useState } from 'react'
import { Briefcase, Play } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { fetchCoachStatus } from '../../seasons/services/managerApi'
import { CountryFlag } from '../../player/components/flags'
import heroBg from '../assets/hero-bg.webp'

// Banner principal: o clube que o TREINADOR comanda agora (pode mudar durante a carreira: demissão,
// proposta aceita). As cores do clube tingem o estádio e o botão leva ao modo Temporadas.
export default function MatchdayHero({ club: initialClub, player, onPlay }) {
  const [status, setStatus] = useState(null)
  useEffect(() => {
    let alive = true
    fetchCoachStatus()
      .then((s) => alive && setStatus(s))
      .catch(() => {})
    return () => {
      alive = false
    }
  }, [])
  const unemployed = status?.started && status.status === 'unemployed'
  const club = status?.started ? (status.club_id ? getClubById(status.club_id) : null) : initialClub
  const [c1, c2] = club?.colors || ['#1b3566', '#f5b800']
  return (
    <section className="hm-hero" style={{ '--c1': c1, '--c2': c2 }}>
      <img className="hm-hero-bg" src={heroBg} alt="" />
      <span className="hm-hero-tint" aria-hidden="true" />
      <span className="hm-hero-beam" aria-hidden="true" />

      <div className="hm-hero-top">
        <span className="gx-tag is-live">
          <span className="gx-dot" /> Temporadas · modo treinador
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
          <small>{unemployed ? 'Treinador' : 'Seu clube'}</small>
          <h1>{club?.name || 'Sem clube'}</h1>
          <p>
            Treinador · Nível {player.level}
            {status?.pending_offers > 0 ? ` · ${status.pending_offers} proposta${status.pending_offers > 1 ? 's' : ''}` : ''}
          </p>
        </div>
      </div>

      <div className="hm-hero-cta">
        <p>
          {unemployed ? (
            <>
              Você está <b>sem clube</b>. Avance os dias e aguarde propostas.
            </>
          ) : (
            <>
              Escale o time, defina a tática e <b>comande a próxima partida</b>.
            </>
          )}
        </p>
        <button type="button" className="gx-btn hm-hero-btn" onClick={onPlay}>
          {unemployed ? <Briefcase size={18} /> : <Play size={18} fill="currentColor" />} {unemployed ? 'Carreira' : 'Jogar'}
        </button>
      </div>
    </section>
  )
}
