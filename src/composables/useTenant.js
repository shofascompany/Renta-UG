import { computed } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useRentalStore } from '@/stores/rental'
import { rentEnded } from '@/lib/now'

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
  const timeEnded = computed(() => rentEnded(tenant.value))

  // What they owe: the same total their landlord sees (utils/payState.js). firstRent = the part that is not charged
  // yet: the first month of a new tenant, or every month begun since their paid time ran out.
  const pay = computed(() => (tenant.value ? rental.payStateFor(id.value) : null))
  const charged = computed(() => dues.value.filter((p) => p.balance > 0))
  const firstRent = computed(() => Math.max(0, (pay.value?.owed ?? 0) - charged.value.reduce((s, p) => s + p.balance, 0)))
  const firstMonths = computed(() => (firstRent.value ? Math.max(1, pay.value.months.length - charged.value.length) : 0))
  const firstSince = computed(() => (firstRent.value && timeEnded.value ? pay.value.months[charged.value.length]?.from : null))
  const balance = computed(() => charged.value.reduce((s, p) => s + p.balance, 0) + firstRent.value)

  return { rental, id, tenant, property, payments, dues, notifications, unread, balance, rent, notStarted, timeEnded, firstRent, firstMonths, firstSince }
}
