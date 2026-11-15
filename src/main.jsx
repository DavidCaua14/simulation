import { StrictMode, Suspense, lazy } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/game-ui.css' // sistema visual base: carregado antes das telas, que podem sobrescrever
import App from './App.jsx'

// Laboratório local da partida (só em `npm run dev`): /#lab3d abre a tela de partida com um servidor falso
const LAB = import.meta.env.DEV && window.location.hash === '#lab3d'
const MatchLab = LAB ? lazy(() => import('./features/lab/MatchLab.jsx')) : null

createRoot(document.getElementById('root')).render(
  <StrictMode>
    {LAB ? (
      <Suspense fallback={null}>
        <MatchLab />
      </Suspense>
    ) : (
      <App />
    )}
  </StrictMode>,
)
