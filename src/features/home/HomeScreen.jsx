import AppShell from '../../components/layout/AppShell'
import SignOutButton from '../../components/ui/SignOutButton'
import { SettingsIcon, ChevronRightIcon, SunIcon, MoonIcon } from '../../components/ui/icons'
import { useTheme } from '../../context/ThemeContext'
import CharacterCard from '../player/components/CharacterCard'
import { getProfilePhotoById } from '../player/data/profilePhotos'
import { getClubById } from '../club/data/clubs'
import { PLACEHOLDER_XP_TO_NEXT_LEVEL } from '../player/data/gameConstants'
import CurrencyRow from './components/CurrencyRow'
import HeroBanner from './components/HeroBanner'
import ModeCard from './components/ModeCard'
import BottomTabBar from './components/BottomTabBar'
import { GAME_MODES } from './data/gameModes'
import './home-screen.css'

export default function HomeScreen({ career }) {
  const { player } = career
  const photo = getProfilePhotoById(player.photoId)
  const club = getClubById(player.clubId)
  const { theme, toggleTheme } = useTheme()

  return (
    <AppShell left={<SignOutButton />} title="Início">
      <div className="home-shell">
        <div className="home-scroll">
          <div className="home-top">
            <CharacterCard
              photo={photo}
              nickname={player.nickname}
              countryId={player.country}
              age={player.age}
              level={player.level}
              xp={player.xp}
              xpToNext={PLACEHOLDER_XP_TO_NEXT_LEVEL}
            />
            <CurrencyRow />
          </div>

          <HeroBanner club={club} countryId={player.country} />

          <div className="mode-grid">
            {GAME_MODES.map((mode) => (
              <ModeCard key={mode.id} mode={mode} />
            ))}
          </div>

          <div className="settings-row">
            <button type="button" className="settings-item" disabled>
              <SettingsIcon />
              <span>
                <strong>Configurações</strong>
                <span>Ajuste o jogo do seu jeito.</span>
              </span>
              <ChevronRightIcon className="mode-card-chevron" />
            </button>

            <button type="button" className="settings-item" onClick={toggleTheme}>
              {theme === 'light' ? <MoonIcon /> : <SunIcon />}
              <span>
                <strong>Tema</strong>
                <span>{theme === 'light' ? 'Claro' : 'Escuro'}</span>
              </span>
              <span className={`theme-switch ${theme === 'dark' ? 'is-on' : ''}`} />
            </button>
          </div>
        </div>

        <BottomTabBar active="home" />
      </div>
    </AppShell>
  )
}
