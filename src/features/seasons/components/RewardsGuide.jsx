import { useState } from 'react'
import { ChevronDown, Coins, Medal, Sparkles, Target, Trophy, Users } from 'lucide-react'
import CompEmblem from '../ui/CompEmblem'
import { COMP_SHORT, REWARD_RULES, XP_PER_LEVEL, fmt } from '../utils/seasonUtils'

// Como evoluir: o que cada partida rende (XP/moedas), multiplicadores e bônus de campanha.
// Os números são os mesmos do banco; a tabela completa fica num painel expansível.
export default function RewardsGuide({ career }) {
  const [open, setOpen] = useState(false)
  const R = REWARD_RULES
  const toNext = XP_PER_LEVEL - career.xp
  const winsToLevel = Math.ceil(toNext / R.result[0].xp)

  return (
    <section className="rg">
      <div className="rg-next gx-panel">
        <Sparkles size={20} />
        <div>
          <b>Próximo nível: {career.level + 1}</b>
          <small>
            Faltam {fmt(toNext)} XP · cerca de {winsToLevel} vitória{winsToLevel > 1 ? 's' : ''} sem contar gols e assistências. Nível alto melhora seu
            desempenho em campo.
          </small>
        </div>
      </div>

      <h3 className="gx-title">Cada partida rende</h3>
      <div className="rg-results">
        {R.result.map((r) => (
          <div key={r.id} className={`rg-res ${r.id}`}>
            <small>{r.label}</small>
            <b>+{r.xp}</b>
            <span>XP</span>
            <em>
              <Coins size={11} /> +{r.coins}
            </em>
          </div>
        ))}
      </div>
      <div className="rg-extra">
        <div>
          <Target size={18} />
          <span>
            Gol seu <b>+{R.goal.xp} XP</b> · +{R.goal.coins} moedas
          </span>
        </div>
        <div>
          <Users size={18} />
          <span>
            Assistência <b>+{R.assist.xp} XP</b> · +{R.assist.coins} moedas
          </span>
        </div>
      </div>

      <h3 className="gx-title">Multiplicadores</h3>
      <div className="rg-mult">
        {Object.entries(R.compMult).map(([id, m]) => (
          <div key={id}>
            <CompEmblem comp={id} size={22} />
            <span>{COMP_SHORT[id]}</span>
            <b>x{String(m).replace('.', ',')}</b>
          </div>
        ))}
        {R.stageMult.map((s) => (
          <div key={s.label}>
            <Medal size={20} />
            <span>{s.label}</span>
            <b>x{String(s.mult).replace('.', ',')}</b>
          </div>
        ))}
      </div>

      <button type="button" className={`rg-more ${open ? 'is-open' : ''}`} onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        <Trophy size={16} /> Bônus por campanha <ChevronDown size={16} />
      </button>
      {open && (
        <div className="rg-camp">
          {R.campaign.map((c) => (
            <div key={c.label}>
              <span>{c.label}</span>
              <b>+{fmt(c.xp)} XP</b>
              <em>+{fmt(c.coins)}</em>
            </div>
          ))}
          <p className="sn-hint">Fases avançadas das copas também rendem bônus menores. O bônus só vale se você jogou pelo menos uma partida no torneio.</p>
        </div>
      )}
    </section>
  )
}
