// Fala do empresário. A foto e o nome ficam no cartão do topo da tela; aqui só o balão.
export default function ChatBubble({ text, tone = 'agent' }) {
  return (
    <div className={`of-bubble ${tone === 'me' ? 'is-me' : ''}`}>
      <p>{text}</p>
    </div>
  )
}
