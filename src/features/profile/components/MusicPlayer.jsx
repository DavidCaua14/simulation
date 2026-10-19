import { useAudio } from '../../audio/AudioContext'
import { MusicIcon, NextIcon, PauseIcon, PlayIcon, PrevIcon, VolumeIcon, VolumeLowIcon, VolumeOffIcon } from './ProfileIcons'

export default function MusicPlayer() {
  const a = useAudio()
  const silent = a.muted || a.volume === 0
  const shown = silent ? 0 : a.volume
  const VolIcon = silent ? VolumeOffIcon : a.volume < 50 ? VolumeLowIcon : VolumeIcon

  return (
    <section className="pf-panel" aria-labelledby="pf-sound-title">
      <header className="pf-panel-head">
        <h2 id="pf-sound-title">
          <MusicIcon size={16} />
          Som do jogo
        </h2>
      </header>

      {!a.hasTracks ? (
        <p className="pf-hint">Nenhuma música configurada. Edite <code>src/features/audio/playlist.js</code>.</p>
      ) : (
        <>
          <div className="pf-now">
            <span className={`pf-eq ${a.playing && !silent ? 'is-playing' : ''}`} aria-hidden="true">
              <i />
              <i />
              <i />
              <i />
            </span>
            <span className="pf-now-text">
              <small>
                Faixa {a.index + 1} de {a.tracks.length}
              </small>
              <strong>{a.track?.title}</strong>
            </span>
          </div>

          <div className="pf-transport">
            <button type="button" className="pf-icon-btn" onClick={a.prev} aria-label="Faixa anterior" disabled={!a.ready}>
              <PrevIcon size={18} />
            </button>
            <button
              type="button"
              className="pf-play"
              onClick={a.togglePlay}
              aria-label={a.playing ? 'Pausar música' : 'Tocar música'}
              disabled={!a.ready}
            >
              {a.playing ? <PauseIcon size={22} /> : <PlayIcon size={22} />}
            </button>
            <button type="button" className="pf-icon-btn" onClick={a.next} aria-label="Próxima faixa" disabled={!a.ready}>
              <NextIcon size={18} />
            </button>
          </div>
        </>
      )}

      <div className="pf-volume">
        <button type="button" className="pf-icon-btn" onClick={a.toggleMute} aria-label={silent ? 'Ativar som' : 'Silenciar'} aria-pressed={silent}>
          <VolIcon size={18} />
        </button>
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          value={shown}
          style={{ '--fill': `${shown}%` }}
          onChange={(e) => a.setVolume(Number(e.target.value))}
          aria-label="Volume da música"
        />
        <output className="pf-vol-value">{shown}%</output>
      </div>
    </section>
  )
}
