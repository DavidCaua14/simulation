import { useState } from 'react'
import { X } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import TeamTab from '../tabs/TeamTab'
import PreMatchVS from './PreMatchVS'
import FunctionsPanel from './FunctionsPanel'
import { COMP_SHORT } from '../utils/seasonUtils'
import './matchflow.css'

const TITLES = { lineup: 'Formação', tactics: 'Instruções táticas', roles: 'Funções', vs: 'Pré-jogo' }

// FLUXO DA PARTIDA (CM17): JOGAR → Formação → CONFIRMAR → pré-jogo (VS) → Pontapé inicial.
// Nada aqui volta ao Início no meio do caminho: Escalação, Instruções e Funções sempre retornam ao pré-jogo.
// Enquanto o servidor resolve a rodada até o dia do jogo (em segundo plano), o Pontapé fica em espera.
export default function MatchFlow({ hub, next, myClub, myPos, ready, waitingText, attention, canPlay, blockedText, starting, notify, drills, onAttention, onLater, onSaved, onStart, onClose }) {
  const [step, setStep] = useState('lineup')
  const m = next.match
  const oppId = m.home === myClub ? m.away : m.home
  const toVs = () => setStep('vs')

  return (
    <div className="mf" role="dialog" aria-modal="true" aria-label="Partida">
      <header className="mf-head">
        <span className="mf-title">
          <small>Gestão do time</small>
          <b>{TITLES[step]}</b>
        </span>
        <span className="mf-opp">
          <ClubCrest clubId={oppId} size={22} />
          <span>
            <b>
              {getClubById(oppId)?.name} ({m.home === myClub ? 'C' : 'F'})
            </b>
            <small>
              {COMP_SHORT[next.competition] || next.competition} · {ready ? 'hoje' : 'próximo jogo'}
            </small>
          </span>
        </span>
        <button type="button" className="mf-close" aria-label="Fechar e voltar ao Início" disabled={starting} onClick={onClose}>
          <X size={18} />
        </button>
      </header>

      {attention && (
        <div className="mf-mail" role="status">
          <b>Novo e-mail importante</b>
          <span>Há uma proposta, resposta de negociação ou contrato perto do fim. Você pode ver agora ou depois do jogo.</span>
          <div>
            <button type="button" className="gx-btn-ghost" onClick={onAttention}>
              Ver agora
            </button>
            <button type="button" className="gx-btn" onClick={onLater}>
              Depois
            </button>
          </div>
        </div>
      )}

      <div className="mf-body">
        {(step === 'lineup' || step === 'tactics') && (
          <TeamTab
            key={step}
            hub={hub}
            notify={notify}
            onSaved={onSaved}
            initialView={step}
            flow={{ onConfirm: toVs, onBack: step === 'lineup' ? onClose : toVs, onRoles: () => setStep('roles') }}
          />
        )}
        {step === 'roles' && <FunctionsPanel notify={notify} onDone={toVs} />}
        {step === 'vs' && (
          <PreMatchVS
            next={next}
            myClub={myClub}
            myPos={myPos}
            today={hub.world?.today}
            ready={ready}
            waitingText={waitingText}
            canPlay={canPlay}
            blockedText={blockedText}
            starting={starting}
            engineVersion={hub.simulation_version ?? 1}
            drills={drills}
            onLineup={() => setStep('lineup')}
            onTactics={() => setStep('tactics')}
            onRoles={() => setStep('roles')}
            onStart={onStart}
          />
        )}
      </div>
    </div>
  )
}
