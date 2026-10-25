import { Activity, Ambulance, Ban, Crown, Info, Shirt } from 'lucide-react'
import Sheet from '../ui/Sheet'
import { ATTR_GROUPS, POS_NAME, POS_ORDER, condTone, ovrTone } from '../utils/managerUtils'

const attrTone = (v) => (v >= 80 ? 'a-elite' : v >= 70 ? 'a-good' : v >= 55 ? 'a-mid' : 'a-low')

// Ficha completa do jogador: posição, atributos (estimativa de gameplay), notas por posição,
// condição física, disponibilidade e números da temporada.
export default function PlayerSheet({ player, onClose, clubName }) {
  if (!player) return null
  const p = player
  const isGk = p.position === 'GOL'
  const groups = ATTR_GROUPS.filter((g) => (isGk ? g.id !== 'att' : g.id !== 'gk'))
  const st = p.stats || {}
  return (
    <Sheet kicker={clubName || POS_NAME[p.position]} title={p.name} onClose={onClose} tall>
      <div className="ps">
        <section className="ps-head">
          <span className={`ps-ovr o-${ovrTone(p.overall)}`}>
            <b>{p.overall}</b>
            <small>{p.position}</small>
          </span>
          <div className="ps-id">
            <span className="ps-tags">
              {p.number != null && (
                <span className="ps-tag">
                  <Shirt size={12} /> {p.number}
                </span>
              )}
              {p.nationality && (
                <span className="ps-tag nat" title="Nacionalidade">
                  {p.nationality}
                </span>
              )}
              {p.captain && (
                <span className="ps-tag gold">
                  <Crown size={12} /> Capitão
                </span>
              )}
              {p.youth && <span className="ps-tag">Base</span>}
            </span>
            <span className="ps-pos">
              {POS_NAME[p.position]}
              {p.secondary?.length > 0 && <em> · também {p.secondary.join(', ')}</em>}
              {p.position_estimated && <em className="ps-est"> · posição estimada</em>}
            </span>
            <span className="ps-avail">
              {p.injured_days > 0 ? (
                <b className="bad">
                  <Ambulance size={13} /> {p.injury || 'Lesionado'} · volta em {p.injured_days} dia{p.injured_days > 1 ? 's' : ''}
                </b>
              ) : p.suspended > 0 ? (
                <b className="bad">
                  <Ban size={13} /> Suspenso ({Object.entries(p.susp || {}).map(([k, v]) => `${v} jogo${v > 1 ? 's' : ''} · ${k === 'brasileirao' ? 'Brasileirão' : k === 'copa_brasil' ? 'Copa do Brasil' : 'Libertadores'}`).join(' / ')})
                </b>
              ) : (
                <b className="ok">Disponível</b>
              )}
            </span>
          </div>
        </section>

        <section className="ps-bars">
          <div>
            <span>
              <Activity size={13} /> Condição física <b>{p.condition}%</b>
            </span>
            <i className={`ps-bar ${condTone(p.condition)}`}>
              <em style={{ width: `${p.condition}%` }} />
            </i>
          </div>
          <div>
            <span>
              Ritmo de jogo <b>{p.rhythm}%</b>
            </span>
            <i className="ps-bar rhythm">
              <em style={{ width: `${p.rhythm}%` }} />
            </i>
          </div>
        </section>

        <section className="ps-sec">
          <h3 className="gx-title">
            Atributos <small className="ps-est-tag">estimativa de gameplay</small>
          </h3>
          <div className="ps-attrs">
            {groups.map((g) => (
              <div key={g.id} className="ps-group">
                <h4>{g.label}</h4>
                {g.attrs.map(([k, label]) => (
                  <div key={k} className="ps-attr">
                    <span>{label}</span>
                    <i className={`ps-meter ${attrTone(p.attrs?.[k])}`}>
                      <em style={{ width: `${p.attrs?.[k] ?? 0}%` }} />
                    </i>
                    <b className={attrTone(p.attrs?.[k])}>{p.attrs?.[k] ?? '–'}</b>
                  </div>
                ))}
              </div>
            ))}
          </div>
        </section>

        <section className="ps-sec">
          <h3 className="gx-title">Rendimento por posição</h3>
          <div className="ps-posgrid">
            {POS_ORDER.map((pos) => {
              const v = p.ratings?.[pos] ?? 0
              return (
                <span key={pos} className={`ps-posc o-${ovrTone(v)} ${pos === p.position ? 'is-main' : ''}`} title={POS_NAME[pos]}>
                  <small>{pos}</small>
                  <b>{v}</b>
                </span>
              )
            })}
          </div>
          <p className="sn-hint">
            <Info size={12} /> Nota que ele rende em cada função: atributos da posição × adequação. Fora de posição o rendimento cai no jogo.
          </p>
        </section>

        <section className="ps-sec">
          <h3 className="gx-title">Temporada</h3>
          <div className="ps-stats">
            <span>
              <b>{st.apps ?? 0}</b>
              <small>Jogos</small>
            </span>
            <span>
              <b>{st.goals ?? 0}</b>
              <small>Gols</small>
            </span>
            <span>
              <b>{st.assists ?? 0}</b>
              <small>Assist.</small>
            </span>
            <span>
              <b>{st.rating ? Number(st.rating).toFixed(1) : '–'}</b>
              <small>Nota</small>
            </span>
            <span>
              <b>{st.yellows ?? 0}</b>
              <small>Amarelos</small>
            </span>
            <span>
              <b>{st.motm ?? 0}</b>
              <small>Craque</small>
            </span>
          </div>
        </section>
      </div>
    </Sheet>
  )
}
