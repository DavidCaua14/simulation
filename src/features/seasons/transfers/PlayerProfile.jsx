import { useEffect, useState } from 'react'
import { ArrowLeftRight, FileSignature, Handshake, ListPlus, Tag, Users, X } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { fetchPlayer } from '../services/managerApi'
import { dateLabel, weekly } from '../services/careerWorldApi'
import { clubMoneyShort } from '../utils/clubMoney'
import { ATTR_GROUPS } from '../utils/managerUtils'
import { isSessionError } from '../../../lib/sessionRecovery'

const tone = (v) => (v >= 80 ? 'a-elite' : v >= 70 ? 'a-good' : v >= 55 ? 'a-mid' : 'a-low')
const stars = (v) => (v >= 80 ? 3 : v >= 68 ? 2 : v >= 55 ? 1 : 0)

// PERFIL DO ATLETA no formato do CM17: números da temporada, posições, atributos, condição/moral/contrato,
// bolas paradas e as ações de transferência (ou de contrato, se o atleta é seu).
export default function PlayerProfile({ player, own, busy, shortlisted, onClose, onOffer, onLoan, onShortlist, onRenew, onList, onLoanList, onSquad }) {
  const [detail, setDetail] = useState(null)
  useEffect(() => {
    let alive = true
    fetchPlayer(player.id)
      .then((d) => alive && setDetail(d))
      .catch((e) => alive && !isSessionError(e) && setDetail({}))
    return () => {
      alive = false
    }
  }, [player.id])
  const p = { ...player, ...(detail || {}) }
  const mine = player.club_id === own
  const st = p.stats || {}
  const attrs = p.attrs || {}
  const isGk = p.position === 'GOL'
  const groups = ATTR_GROUPS.filter((g) => (isGk ? g.id !== 'att' : g.id !== 'gk'))
  const positions = [p.position, ...(p.secondary || [])].filter(Boolean)
  const club = getClubById(player.club_id)

  return (
    <div className="pp-overlay" role="dialog" aria-modal="true" aria-label={p.name}>
      <section className="pp">
        <header className="pp-head">
          <b>{p.name}</b>
          <span className="pp-club">
            {club ? club.name : 'Sem clube'}
            {club && <ClubCrest clubId={player.club_id} size={30} />}
          </span>
          <button type="button" className="kp-x" aria-label="Fechar" onClick={onClose}>
            <X size={18} />
          </button>
        </header>

        <div className="pp-stats">
          {[
            ['Nac', p.nationality || '—'],
            ['Grl', p.overall ?? '—'],
            ['Idade', p.age ?? '—'],
            ['Jogos', st.apps ?? 0],
            ['Gols', st.goals ?? 0],
            ['Assist.', st.assists ?? 0],
            ['Craque', st.motm ?? 0],
            ['Amar.', st.yellows ?? 0],
            ['Verm.', st.reds ?? 0],
            ['Clas. méd.', st.rating ? Number(st.rating).toFixed(1) : '-'],
          ].map(([k, v]) => (
            <span key={k}>
              <small>{k}</small>
              <b>{v}</b>
            </span>
          ))}
        </div>
        <div className="pp-pos">
          {positions.map((pos, i) => (
            <em key={pos} className={i ? '' : 'is-main'}>
              {pos}
            </em>
          ))}
        </div>

        <div className="pp-body">
          <div className="pp-attrs">
            {groups.flatMap((g) => g.attrs).map(([key, label]) => (
              <span key={key}>
                {label}
                <b className={tone(attrs[key])}>{attrs[key] ?? '—'}</b>
              </span>
            ))}
            {!isGk &&
              [
                ['pace', 'Ritmo'],
                ['stamina', 'Energia'],
                ['strength', 'Força'],
              ].map(([key, label]) => (
                <span key={key}>
                  {label}
                  <b className={tone(attrs[key])}>{attrs[key] ?? '—'}</b>
                </span>
              ))}
          </div>
          <dl className="pp-status">
            <div>
              <dt>Condição</dt>
              <dd>
                <i className="pp-cond">
                  <em style={{ width: `${Math.max(3, Math.min(100, p.condition ?? 100))}%` }} />
                  <b>{Math.round(p.condition ?? 100)}%</b>
                </i>
              </dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>{p.injured_days > 0 ? 'Lesionado' : p.suspended > 0 ? 'Suspenso' : 'OK'}</dd>
            </div>
            <div>
              <dt>Fim do contrato</dt>
              <dd>{player.expires_on || p.contract_expires ? dateLabel(player.expires_on || p.contract_expires) : '—'}</dd>
            </div>
            <div>
              <dt>Salários semanais</dt>
              <dd>{player.monthly_salary != null || p.monthly_salary != null ? clubMoneyShort(weekly(player.monthly_salary ?? p.monthly_salary)) : '—'}</dd>
            </div>
            <div>
              <dt>Valor</dt>
              <dd>{player.value != null ? clubMoneyShort(player.value) : '—'}</dd>
            </div>
            {[
              ['Pênaltis', (attrs.finishing || 0) * 0.6 + (attrs.technique || 0) * 0.4],
              ['Tiros livres', (attrs.technique || 0) * 0.5 + (attrs.passing || 0) * 0.5],
              ['Escanteios', (attrs.passing || 0) * 0.6 + (attrs.vision || 0) * 0.4],
            ].map(([k, v]) => (
              <div key={k} className="pp-sp">
                <dt>{k}</dt>
                <dd aria-label={`${stars(v)} de 3`}>
                  {[0, 1, 2].map((i) => (
                    <i key={i} className={i < stars(v) ? 'is-on' : ''}>⚽</i>
                  ))}
                </dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="pp-actions">
          {mine ? (
            <>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onRenew}>
                <FileSignature size={16} /> Renovar contrato
              </button>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onList}>
                <Tag size={16} /> {p.transfer_listed || player.transfer_listed ? 'Tirar da lista de transferência' : 'Lista de transferência'}
              </button>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onLoanList}>
                <ArrowLeftRight size={16} /> Lista de empréstimo
              </button>
            </>
          ) : (
            <>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onOffer}>
                <Handshake size={16} /> {player.club_id ? 'Fazer oferta de transferência' : 'Oferecer contrato'}
              </button>
              {player.club_id && (
                <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onLoan}>
                  <ArrowLeftRight size={16} /> Fazer oferta de empréstimo
                </button>
              )}
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onShortlist}>
                <ListPlus size={16} /> {shortlisted ? 'Remover da pré-seleção' : 'Adicionar à pré-seleção'}
              </button>
              {player.club_id && onSquad && (
                <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onSquad}>
                  <Users size={16} /> Ver elenco
                </button>
              )}
            </>
          )}
        </div>
      </section>
    </div>
  )
}
