import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'

// Everything the signed-in tenant needs (their CURRENT stay only), derived from the rental store.
export function useTenant() {
  const auth = useAuthStore()
  const rental = useRentalStore()

  const tenant = computed(() => rental.tenantForUser(auth.user?.id))
  const id = computed(() => tenant.value?.id)
  // A room in a rental shows as "Room 3 · Kira Rentals" everywhere on the tenant's pages
  const property = computed(() => {
    const p = tenant.value?.propertyId && rental.propertyById(tenant.value.propertyId)
    return p ? { ...p, name: rental.placeName(p.id) } : p
  })
  const payments = computed(() => rental.paymentsForTenant(id.value))
  const dues = computed(() => rental.duesForTenant(id.value))
  const notifications = computed(() => rental.notificationsForTenant(id.value).filter((n) => !n.tenantHidden))
  const unread = computed(() => notifications.value.filter((n) => !n.read))
  const balance = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))

  return { rental, id, tenant, property, payments, dues, notifications, unread, balance }
}
