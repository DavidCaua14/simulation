import { useAuth } from '../../context/AuthContext'
import { LogOutIcon } from './icons'

export default function SignOutButton() {
  const { signOut } = useAuth()
  return (
    <button
      type="button"
      className="icon-btn"
      onClick={signOut}
      aria-label="Sair da conta"
      title="Sair da conta"
    >
      <LogOutIcon />
    </button>
  )
}
