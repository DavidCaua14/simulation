import SoccerBallIcon from '../../features/auth/components/SoccerBallIcon'
import './AppLoadingScreen.css'

export default function AppLoadingScreen({ label = 'Carregando...' }) {
  return (
    <div className="app-viewport">
      <div className="app-frame boot-frame">
        <div className="boot-spinner">
          <SoccerBallIcon size={30} />
        </div>
        <p className="boot-label">{label}</p>
      </div>
    </div>
  )
}
