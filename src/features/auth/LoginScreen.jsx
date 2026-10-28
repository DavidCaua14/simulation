import { CrownIcon, EvolveIcon, TeamIcon, RankIcon, LockIcon, AlertIcon } from '../../components/ui/icons'
import SoccerBallIcon from './components/SoccerBallIcon'
import { useAuth } from '../../context/AuthContext'
import loginBg from './assets/login-bg.webp'
import './login-screen.css'

const FEATURES = [
  { Icon: EvolveIcon, top: 'EVOLUA', bottom: 'SEU TÉCNICO' },
  { Icon: TeamIcon, top: 'COMANDE', bottom: 'SEU TIME' },
  { Icon: RankIcon, top: 'CONQUISTE', bottom: 'TÍTULOS' },
  { Icon: SoccerBallIcon, top: 'FAÇA', bottom: 'HISTÓRIA' },
]

export default function LoginScreen() {
  const { signInWithGoogle, authError } = useAuth()

  return (
    <div className="app-viewport">
      <div className="app-frame login-frame">
        <img className="login-bg" src={loginBg} alt="" />
        <div className="login-scrim" />
        <div className="login-corner login-corner-left" />
        <div className="login-corner login-corner-right" />

        <div className="login-content">
          <div className="login-brand">
            <div className="brand-badge">
              <CrownIcon className="brand-crown" />
              <SoccerBallIcon size={26} className="brand-ball" />
            </div>
            <h1 className="brand-title">
              <span className="brand-line-1">SEU CLUBE</span>
              <span className="brand-line-2">SUA HISTÓRIA</span>
            </h1>
            <div className="brand-tagline">
              <span className="tagline-rule" />
              <span>GESTÃO + FUTEBOL</span>
              <span className="tagline-rule" />
            </div>
          </div>

          <div className="login-bottom">
            <h2 className="login-headline">ASSUMA O COMANDO</h2>
            <p className="login-subline">
              COMANDE <strong>SEU TIME</strong>. CONQUISTE <strong>TÍTULOS</strong>.
            </p>

            <div className="feature-row">
              {FEATURES.map(({ Icon, top, bottom }, i) => (
                <div className="feature-item" key={i}>
                  <span className="feature-icon">
                    <Icon size={22} />
                  </span>
                  <span className="feature-label">
                    {top}
                    <br />
                    {bottom}
                  </span>
                </div>
              ))}
            </div>

            {authError && (
              <p className="login-error">
                <AlertIcon /> {authError}
              </p>
            )}

            <button type="button" className="google-btn" onClick={signInWithGoogle}>
              <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
                <path
                  fill="#4285F4"
                  d="M19.6 10.23c0-.68-.06-1.36-.17-2H10v3.79h5.38a4.6 4.6 0 0 1-2 3.02v2.5h3.24c1.9-1.75 2.98-4.33 2.98-7.31Z"
                />
                <path
                  fill="#34A853"
                  d="M10 20c2.7 0 4.96-.89 6.62-2.42l-3.24-2.5c-.9.6-2.05.96-3.38.96-2.6 0-4.8-1.75-5.59-4.11H1.06v2.59A10 10 0 0 0 10 20Z"
                />
                <path
                  fill="#FBBC05"
                  d="M4.41 11.93A5.99 5.99 0 0 1 4.09 10c0-.67.12-1.32.32-1.93V5.48H1.06A10 10 0 0 0 0 10c0 1.61.39 3.14 1.06 4.52l3.35-2.59Z"
                />
                <path
                  fill="#EA4335"
                  d="M10 3.96c1.47 0 2.79.5 3.82 1.5l2.87-2.87C14.95.98 12.7 0 10 0 6.09 0 2.7 2.24 1.06 5.48l3.35 2.59C5.2 5.71 7.4 3.96 10 3.96Z"
                />
              </svg>
              <span>Entrar com o Google</span>
            </button>

            <div className="login-disclaimer">
              <p>
                <LockIcon /> Sua conta Google é a única forma de acessar o jogo.
              </p>
              <p>É rápido, seguro e fácil!</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
