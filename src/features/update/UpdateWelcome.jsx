import { useState } from 'react'
import { ChevronLeft, ChevronRight, X } from 'lucide-react'
import GameIcon from '../../components/ui/GameIcon'
import { LevelBurst } from '../progress/LevelUpOverlay'
import { AVATAR_ART } from '../profile/data/avatars'
import { setAvatar } from '../profile/services/profileApi'
import './update.css'

const TIER = { destaque: 'Destaque', epica: 'Épica', lenda: 'Lenda', basica: 'Base' }
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')

// NOVIDADES DA ATUALIZAÇÃO — só para quem já jogava antes dela (o banco decide). Aparece na primeira entrada
// depois da atualização e pode ser revista no Perfil. gift = resposta de release_gift_claim.
export default function UpdateWelcome({ gift, onClose, replay = false }) {
  const [page, setPage] = useState(0)
  const [avatarState, setAvatarState] = useState('idle') // idle | saving | done | error
  const pages = ['Presentes', 'O que mudou', 'Modo Temporadas']
  const special = (gift.compensation || []).filter((c) => c.tier !== 'basica')
  const total = special.reduce((a, c) => ({ coins: a.coins + c.coins, energy: a.energy + c.energy, diamonds: a.diamonds + c.diamonds }), { coins: 0, energy: 0, diamonds: 0 })
  const avatar = gift.avatar

  async function useAvatar() {
    setAvatarState('saving')
    try {
      await setAvatar(`avatar:${avatar.id}`)
      setAvatarState('done')
    } catch {
      setAvatarState('error')
    }
  }

  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades da atualização">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades da atualização' : 'Obrigado por testar!'}</small>
            <h2>{pages[page]}</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-dots" aria-hidden="true">
          {pages.map((p, i) => <i key={p} className={i === page ? 'is-on' : ''} />)}
        </div>

        <div className="uw-body">
          {page === 0 && (
            <>
              <LevelBurst from={gift.level_before} to={gift.level_after ?? gift.level} compact />
              <p className="uw-lead">Você jogou a fase de testes e ganhou estes presentes:</p>
              <ul className="uw-gifts">
                <li><GameIcon name="highlight" size={30} /><b>+1.000 de XP</b><small>Subiu para o nível {gift.level_after ?? gift.level}</small></li>
                <li><GameIcon name="energy" size={30} /><b>+20 de energia</b><small>Energia bônus: nunca zera</small></li>
              </ul>
              {avatar && (
                <div className="uw-avatar">
                  {AVATAR_ART[avatar.id] && <img src={AVATAR_ART[avatar.id]} alt="" width={132} height={132} />}
                  <div>
                    <small>Avatar exclusivo</small>
                    <b>{avatar.label}</b>
                    <span>Fica no seu perfil. Use como foto quando quiser (Perfil → Foto).</span>
                    <button type="button" className="gx-btn" disabled={avatarState === 'saving' || avatarState === 'done'} onClick={useAvatar}>
                      {avatarState === 'done' ? 'Foto do perfil atualizada' : avatarState === 'saving' ? 'Salvando…' : 'Usar como foto'}
                    </button>
                    {avatarState === 'error' && <em>Não foi possível agora. Tente pelo Perfil.</em>}
                  </div>
                </div>
              )}
            </>
          )}

          {page === 1 && (
            <>
              <section className="uw-sec">
                <h3><GameIcon name="coins" size={20} /> Cartas especiais viraram moedas e energia</h3>
                <p>As cartas <b>Destaque</b>, <b>Épica</b> e <b>Lenda</b> (e as caixas delas) saíram do jogo. Quem tinha recebeu o valor em moedas e energia, sem perder nada. Agora todo atleta é uma carta <b>Base</b>: a carta mostra o clube e o número atuais e a nota vem do rendimento na posição.</p>
                {special.length > 0 && (
                  <div className="uw-comp">
                    <small>Sua conversão</small>
                    <ul>
                      {special.map((c) => (
                        <li key={c.tier}>{c.qty}× {TIER[c.tier] || c.tier} → <GameIcon name="coins" size={14} /> {fmt(c.coins)}{c.energy > 0 && <> · <GameIcon name="energy" size={14} /> {fmt(c.energy)}</>}{c.diamonds > 0 && <> · <GameIcon name="diamond" size={14} /> {fmt(c.diamonds)}</>}</li>
                      ))}
                    </ul>
                    <b>Total: {fmt(total.coins)} moedas{total.energy > 0 ? ` · ${fmt(total.energy)} de energia` : ''}{total.diamonds > 0 ? ` · ${fmt(total.diamonds)} diamantes` : ''}</b>
                  </div>
                )}
              </section>
              <section className="uw-sec">
                <h3><GameIcon name="crown" size={20} /> Também nesta atualização</h3>
                <ul className="uw-list">
                  <li><b>Insígnias novas</b> com arte própria no Perfil e ícones do jogo redesenhados.</li>
                  <li><b>Avatares de lendas</b> para usar como foto de perfil.</li>
                  <li><b>Animação de nível</b> toda vez que você sobe de nível.</li>
                  <li><b>Caixa de mensagens por assunto</b> (Elenco, Mercado, Clube, Carreira) com atalhos.</li>
                  <li><b>Loja</b> com vitrine nova e <b>Mundo</b> com visual novo.</li>
                </ul>
              </section>
            </>
          )}

          {page === 2 && (
            <div className="uw-how">
              <section>
                <h3>Você é o treinador</h3>
                <p>Comande um clube real. Escale o time, defina a tática e acompanhe a partida ao vivo — dá para mexer no time durante o jogo. Cada partida usa <b>1 de energia</b>.</p>
              </section>
              <section>
                <h3>Calendário e mundo</h3>
                <p>Brasil e Europa jogam no mesmo calendário. Em dia sem jogo, toque em <b>Avançar para a próxima partida</b>: as outras competições são simuladas até a data do seu jogo. No dia do jogo, o <b>pré-jogo</b> mostra as escalações e a análise do adversário.</p>
              </section>
              <section>
                <h3>Elenco e satisfação</h3>
                <p>O rostinho ao lado da carta mostra a satisfação. Quem tem papel de titular e não joga fica insatisfeito, rende menos e pode pedir para sair. Ajuste o <b>papel prometido</b>, dê minutos ou negocie.</p>
              </section>
              <section>
                <h3>Mercado e contratos</h3>
                <p>Compras com clube vendedor só com a <b>janela aberta</b>; atletas livres a qualquer momento. Contratos de até <b>5 anos</b>; nos 6 meses finais outros clubes oferecem pré-contrato. O elenco tem limite de <b>30 atletas com 21 anos ou mais</b> (sub-21 livres).</p>
              </section>
              <section>
                <h3>Carreira</h3>
                <p>Diretoria, torcida e reputação reagem aos resultados. Com boa reputação chegam propostas do Brasil e da Europa; ao trocar de clube a temporada continua de onde está. Resultados ruins ou o clube à beira da falência levam à demissão.</p>
              </section>
              <section>
                <h3>Mensagens</h3>
                <p>Propostas, respostas de negociações, pedidos de saída e avisos da diretoria chegam na caixa de mensagens, separados por assunto e com atalho para a tela certa.</p>
              </section>
            </div>
          )}
        </div>

        <footer className="uw-foot">
          <button type="button" className="gx-btn-ghost" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
            <ChevronLeft size={16} /> Voltar
          </button>
          {page < pages.length - 1 ? (
            <button type="button" className="gx-btn" onClick={() => setPage((p) => p + 1)}>
              Próximo <ChevronRight size={16} />
            </button>
          ) : (
            <button type="button" className="gx-btn" onClick={onClose}>
              Começar a jogar
            </button>
          )}
        </footer>
      </div>
    </div>
  )
}
