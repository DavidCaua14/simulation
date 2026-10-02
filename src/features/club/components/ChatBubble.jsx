import agentPhoto from '../assets/agent-photo.webp'

export default function ChatBubble({ text, showAvatar = true }) {
  return (
    <div className="chat-row">
      <div className="chat-avatar" style={{ visibility: showAvatar ? 'visible' : 'hidden' }}>
        <img src={agentPhoto} alt="" />
      </div>
      <div className="chat-bubble">{text}</div>
    </div>
  )
}
