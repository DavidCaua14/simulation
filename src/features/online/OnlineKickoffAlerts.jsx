import { useCallback, useEffect, useRef, useState } from 'react'
import { Radio, X } from 'lucide-react'
import { useAudio } from '../audio/AudioContext'
import OnlineCrest from './components/OnlineCrest'
import { kickoffState } from './kickoffState'
import { fetchOnlineStatus } from './services/onlineApi'
import './online.css'

const MARKS = [10, 5] // minutos antes do pontapé
const seenKey = (id, m) => `on.kick.${id}.${m}`
const wasSeen = (id, m) => {
  try {
    return window.sessionStorage.getItem(seenKey(id, m)) === '1'
  } catch {
    return false
  }
}
const markSeen = (id, m) => {
  try {
    window.sessionStorage.setItem(seenKey(id, m), '1')
  } catch {
    /* sem armazenamento: o aviso pode repetir */
  }
}

// Aviso em qualquer tela do jogo: o jogo do modo Online começa em 10 minutos e, de novo, em 5.
// Consulta o próximo jogo ao abrir, a cada 5 minutos e quando a aba volta a ficar visível.
export default function OnlineKickoffAlerts({ onOpen }) {
  const [next, setNext] = useState(null) // { id, kickoffMs (relógio do aparelho), club, opp, at_home }
  const [alert, setAlert] = useState(null)
  const { playSfx } = useAudio()
  const sfx = useRef(playSfx)
  useEffect(() => {
    sfx.current = playSfx
  }, [playSfx])

  const load = useCallback(() => {
    fetchOnlineStatus()
      .then((s) => {
        if (s?.access !== 'playing' || !s.next || s.club?.draft_step < 3) return setNext(null)
        const offset = new Date(s.server_now).getTime() - Date.now()
        setNext({ id: s.next.id, kickoffMs: new Date(s.next.kickoff).getTime() - offset, club: s.club, opp: s.next.opp, at_home: s.next.at_home })
      })
      .catch(() => {})
  }, [])
  useEffect(() => {
    load()
    const id = setInterval(load, 300000)
    const onVisible = () => document.visibilityState === 'visible' && load()
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      clearInterval(id)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [load])

  useEffect(() => {
    if (!next) return undefined
    const fire = (mark) => {
      const left = next.kickoffMs - Date.now()
      if (left <= 0 || wasSeen(next.id, mark)) return
      markSeen(next.id, mark)
      if (kickoffState.inMatchRoom) return
      setAlert({ ...next, minutes: Math.max(1, Math.ceil(left / 60000)) })
      sfx.current?.('open')
    }
    const timers = MARKS.map((mark, i) => {
      const wait = next.kickoffMs - mark * 60000 - Date.now()
      // já dentro da janela deste aviso (e ainda fora da do próximo): avisa agora
      const floor = MARKS[i + 1] ?? 0
      if (wait <= 0) return next.kickoffMs - Date.now() > floor * 60000 ? setTimeout(() => fire(mark), 400) : null
      return wait < 2 ** 31 - 1 ? setTimeout(() => fire(mark), wait) : null
    })
    // no pontapé: busca o jogo seguinte
    const after = next.kickoffMs - Date.now() + 15000
    const reload = after > 0 && after < 2 ** 31 - 1 ? setTimeout(load, after) : null
    return () => [...timers, reload].forEach((t) => t && clearTimeout(t))
  }, [next, load])

  useEffect(() => {
    if (!alert) return undefined
    const t = setTimeout(() => setAlert(null), 25000)
    return () => clearTimeout(t)
  }, [alert])

  if (!alert) return null
  const home = alert.at_home ? alert.club : alert.opp
  const away = alert.at_home ? alert.opp : alert.club
  return (
    <div className="on-kick" role="alert">
      <button type="button" className="on-kick-main" onClick={() => { setAlert(null); onOpen?.(alert.id) }}>
        <span className="on-kick-teams"><OnlineCrest club={home} size={30} /><i>×</i><OnlineCrest club={away} size={30} /></span>
        <span className="on-kick-text">
          <small><Radio size={11} /> Liga Online</small>
          <strong>Seu jogo começa em {alert.minutes} min</strong>
        </span>
        <b>Vestiário</b>
      </button>
      <button type="button" className="on-kick-x" onClick={() => setAlert(null)} aria-label="Fechar aviso"><X size={16} /></button>
    </div>
  )
}
