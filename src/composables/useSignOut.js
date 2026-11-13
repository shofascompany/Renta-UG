import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'

// Shared sign-out: clears loaded data, ends the session and returns to the right login page.
export function useSignOut() {
  const auth = useAuthStore()
  const rental = useRentalStore()
  const router = useRouter()

  return async function signOut() {
    const back = auth.isSuperadmin ? '/admin2026' : '/login'
    rental.clear()
    await auth.signOut()
    router.push(back)
  }
}
