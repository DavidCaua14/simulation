import { useState } from 'react'
import { Building2, CalendarDays, ChevronRight, Clock, Dumbbell, Gavel, LogOut, MapPin, Radio, Shirt, Trophy, X } from 'lucide-react'
import OnlineCrest from './components/OnlineCrest'
import OnlinePrep from './OnlinePrep'
import { OvrBadge, PlayerFace } from './components/PlayerFut'
import { markOnlineNewsSeen } from './services/onlineApi'
import { kickoffDay, kickoffTime, money, moneyShort, timeLeft, untilKickoff } from './onlineUtils'

const ordinal = (n) => (n ? `${n}º` : '–')
const FORM = { W: 'V', D: 'E', L: 'D' }

// Resultado dos leilões que o técnico disputou: aparece para o vencedor e para quem perdeu.
function AuctionResults({ results, onSeen }) {
  const [i, setI] = useState(0)
  const r = results[i]
  if (!r) return null
  const d = r.data || {}
  const next = () => (i + 1 < results.length ? setI(i + 1) : onSeen(results.map((x) => x.id)))
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label="Leilão encerrado">
      <div className={`on-result ${d.won ? 'is-won' : 'is-lost'}`}>
        <button type="button" className="on-result-x" onClick={() => onSeen(results.map((x) => x.id))} aria-label="Fechar"><X size={16} /></button>
        <small><Gavel size={13} /> Leilão encerrado{results.length > 1 ? ` · ${i + 1}/${results.length}` : ''}</small>
        <h3>{d.won ? 'Contratado!' : 'Você perdeu a disputa'}</h3>
        <div className="on-result-player">
          <PlayerFace seed={d.player?.name} colors={d.winner?.colors} size={84} />
          {d.player && <OvrBadge p={d.player} />}
          <strong>{d.player?.name}</strong>
        </div>
        <div className="on-result-winner">
          <OnlineCrest club={d.winner} size={34} />
          <span><small>Vencedor</small><b>{d.winner?.name}</b></span>
          <em>{money(d.price)}</em>
        </div>
        <button type="button" className="gx-btn" onClick={next}>{i + 1 < results.length ? 'Próximo' : 'Continuar'}</button>
      </div>
    </div>
  )
}

function BidRow({ lot, now, onOpen }) {
  const left = new Date(lot.ends_at).getTime() - now
  const state = lot.mine ? 'sell' : lot.leading ? 'lead' : 'out'
  return (
    <button type="button" className={`on-bidrow is-${state}`} onClick={onOpen}>
      <OvrBadge p={lot.player} small />
      <span className="on-bidrow-who">
        <strong>{lot.player.name}</strong>
        <small>{state === 'sell' ? 'À venda' : state === 'lead' ? 'Você lidera' : 'Lance superado'}</small>
      </span>
      <span className="on-bidrow-val"><b>{moneyShort(lot.best_bid || lot.start_price)}</b><small><Clock size={10} /> {timeLeft(left)}</small></span>
      <ChevronRight size={16} />
    </button>
  )
}

export default function OnlineHome({ status, now, go, onOpenMatch, onExit, onReload, notify }) {
  const { club, next, position, last, standing, form = [], bids = [], results = [], news = [], featured, train } = status
  const live = next && new Date(next.kickoff).getTime() <= now
  const homeClub = next ? (next.at_home ? club : next.opp) : null
  const awayClub = next ? (next.at_home ? next.opp : club) : null
  const seen = (ids) => markOnlineNewsSeen(ids).catch(() => {}).finally(onReload)
  const stadium = next ? (next.at_home ? club : next.opp).colors?.stadium : null

  return (
    <section className="on-home">
      <div className="on-hero" style={{ '--a': club.colors?.a, '--b': club.colors?.b }}>
        <div className="on-hero-main">
          <OnlineCrest club={club} size={74} />
          <div className="on-hero-id">
            <strong>{club.name}</strong>
            <small><MapPin size={11} /> {club.colors?.stadium || `Arena ${club.short}`}</small>
            <span className="on-form" aria-label="Últimos jogos">
              {form.length === 0 && <i className="is-none" />}
              {form.map((r, i) => <i key={i} className={`is-${r}`}>{FORM[r]}</i>)}
            </span>
          </div>
          <div className="on-hero-pos"><b>{ordinal(position)}</b><small>Liga</small></div>
        </div>
        <dl className="on-hero-stats">
          <div><dt>Pontos</dt><dd>{standing?.pts ?? 0}</dd></div>
          <div><dt>Jogos</dt><dd>{standing?.p ?? 0}</dd></div>
          <div><dt>V · E · D</dt><dd>{standing ? `${standing.w}·${standing.d}·${standing.l}` : '0·0·0'}</dd></div>
          <div><dt>Força</dt><dd>{club.strength != null ? Math.round(club.strength) : '–'}</dd></div>
        </dl>
      </div>

      {next ? (
        <div className={`on-match-card ${live ? 'is-live' : ''}`}>
          <div className="on-match-head">
            <span className="on-match-comp">{next.comp === 'C' ? <><Trophy size={12} /> Copa Online</> : `Liga · Rodada ${next.round}`}</span>
            {live ? <span className="on-live-dot"><Radio size={12} /> AO VIVO</span> : <span className="on-when">{kickoffDay(next.kickoff)} · {kickoffTime(next.kickoff)}</span>}
          </div>
          <div className="on-match-teams">
            <span className={next.at_home ? 'is-mine' : ''}><OnlineCrest club={homeClub} size={58} /><b>{homeClub.name}</b></span>
            <span className="on-match-mid">
              {live ? <Radio size={22} /> : <><small>Começa</small><b>{untilKickoff(next.kickoff, now).replace(/^em /, '')}</b></>}
            </span>
            <span className={!next.at_home ? 'is-mine' : ''}><OnlineCrest club={awayClub} size={58} /><b>{awayClub.name}</b></span>
          </div>
          {stadium && <small className="on-match-venue"><MapPin size={11} /> {stadium}</small>}
          <button type="button" className={`gx-btn on-match-cta ${live ? 'is-live' : ''}`} onClick={() => onOpenMatch(next.id)}>
            {live ? <><Radio size={18} /> Assumir o comando</> : 'Vestiário'}
          </button>
        </div>
      ) : (
        <div className="on-match-card is-empty"><CalendarDays size={22} /><b>Temporada encerrada</b></div>
      )}

      {next && !live && <OnlinePrep prep={status.prep} go={go} notify={notify} onReload={onReload} />}

      {bids.length > 0 && (
        <div className="on-block">
          <h3 className="on-h"><Gavel size={14} /> Seus leilões</h3>
          <div className="on-bidrows">{bids.map((l) => <BidRow key={l.id} lot={l} now={now} onOpen={() => go('market')} />)}</div>
        </div>
      )}

      <div className="on-tiles">
        <button type="button" className="on-tile t-market" onClick={() => go('market')}>
          <Gavel size={22} />
          <strong>Leilões</strong>
          <small>{featured?.count ? `${featured.count} em disputa · ${timeLeft(new Date(featured.ends_at).getTime() - now)}` : 'Em breve'}</small>
        </button>
        <button type="button" className="on-tile t-train" onClick={() => go('club', 'train')}>
          <Dumbbell size={22} />
          <strong>Treino</strong>
          <small>{train ? `${Math.max(0, train.max - train.used)} grátis · ${train.energy ?? 0} de energia` : ''}</small>
        </button>
        <button type="button" className="on-tile t-squad" onClick={() => go('squad')}>
          <Shirt size={22} />
          <strong>Elenco</strong>
          <small>{club.roster} jogadores</small>
        </button>
        <button type="button" className="on-tile t-club" onClick={() => go('club', 'identity')}>
          <Building2 size={22} />
          <strong>Meu clube</strong>
          <small>{moneyShort(club.cash - club.reserved)} livres</small>
        </button>
      </div>

      {last && (
        <button type="button" className="on-last" onClick={() => onOpenMatch(last.id)}>
          <small>Último jogo</small>
          <span><OnlineCrest club={last.at_home ? club : last.opp} size={24} /> <b>{last.hg}</b><i>×</i><b>{last.ag}</b> <OnlineCrest club={last.at_home ? last.opp : club} size={24} /></span>
          <ChevronRight size={16} />
        </button>
      )}

      {news.length > 0 && (
        <div className="on-block">
          <h3 className="on-h">Notícias do clube</h3>
          <ul className="on-news">
            {news.map((n) => (
              <li key={n.id} className={`k-${n.kind}`}>
                <time>{new Date(n.at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</time>
                {n.text}
              </li>
            ))}
          </ul>
        </div>
      )}

      <button type="button" className="on-exit" onClick={onExit}><LogOut size={16} /> Sair do modo Online</button>

      {results.length > 0 && <AuctionResults key={results[0].id} results={results} onSeen={seen} />}
    </section>
  )
}
