import { createContext, useContext, useEffect } from 'react'

const ThemeContext = createContext(null)

// O jogo tem um único visual: o escuro (pele CM). Não há troca de tema.
export function ThemeProvider({ children }) {
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', 'dark')
    try { localStorage.removeItem('simulation:theme') } catch { /* sem armazenamento */ }
  }, [])
  return <ThemeContext.Provider value={{ theme: 'dark' }}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme deve ser usado dentro de <ThemeProvider>')
  return ctx
}
