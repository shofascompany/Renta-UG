import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'

// Everything the signed-in tenant needs (their CURRENT stay only), derived from the rental store.
export function useTenant() {
  const auth = useAuthStore()
  const rental = useRentalStore()

  const tenant = computed(() => rental.tenantForUser(auth.user?.id))
  const id = computed(() => tenant.value?.id)
  const property = computed(() => tenant.value?.propertyId && rental.propertyById(tenant.value.propertyId))
  const payments = computed(() => rental.paymentsForTenant(id.value))
  const dues = computed(() => rental.duesForTenant(id.value))
  const notifications = computed(() => rental.notificationsForTenant(id.value))
  const unread = computed(() => notifications.value.filter((n) => !n.read))
  const balance = computed(() => dues.value.reduce((s, p) => s + p.balance, 0))

  return { rental, id, tenant, property, payments, dues, notifications, unread, balance }
}
