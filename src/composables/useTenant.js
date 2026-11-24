import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { daysUntil } from '@/utils/format'

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
  const unread = computed(() => notifications.value.filter((n) => !n.tenantHidden && !n.read))

  // Rental time: starts the day they first pay (part of the rent buys days), so a new tenant has none yet
  const rent = computed(() => Number(property.value?.rent ?? 0))
  const notStarted = computed(() => Boolean(tenant.value?.propertyId) && !tenant.value?.leaseEnd)
  const timeEnded = computed(() => Boolean(tenant.value?.leaseEnd) && daysUntil(tenant.value.leaseEnd) < 0)

  // A tenant with nothing charged yet (just moved in, or their paid time ran out) owes one month's rent
  const firstRent = computed(() => (!dues.value.length && (notStarted.value || timeEnded.value) ? rent.value : 0))
  const balance = computed(() => dues.value.reduce((s, p) => s + p.balance, 0) + firstRent.value)

  return { rental, id, tenant, property, payments, dues, notifications, unread, balance, rent, notStarted, timeEnded, firstRent }
}
