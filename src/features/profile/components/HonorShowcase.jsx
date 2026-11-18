import { Crown } from 'lucide-react'
import { HONOR_ART } from '../../online/honors'
import './honors.css'

// Vitrine do topo do perfil: títulos do modo Online (insígnias de campeão). Fica acima de tudo e com brilho,
// para quem visita o perfil ver primeiro. As de primeiro campeão são únicas no jogo.
export default function HonorShowcase({ honors }) {
  if (!honors?.length) return null
  return (
    <section className="hs" aria-label="Títulos do modo Online">
      <header><Crown size={14} /> Títulos Online</header>
      <ul>
        {honors.map((h) => (
          <li key={h.id} className={h.first ? 'is-first' : ''}>
            <span className="hs-art">
              <span className="hs-shine" aria-hidden="true" />
              <img src={HONOR_ART[h.id]} alt="" />
              {h.n > 1 && <em>×{h.n}</em>}
            </span>
            <b>{h.label}</b>
            <small>{h.first ? 'Única no jogo' : (h.seasons || []).map((x) => `T${x.season}`).join(' · ')}</small>
          </li>
        ))}
      </ul>
    </section>
  )
}
