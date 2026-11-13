import { computed } from 'vue'
import { useRentalStore } from '@/stores/rental'

// Main admin: per-landlord figures computed from everything the store has loaded.
export function useLandlordStats() {
  const rental = useRentalStore()
  const month = new Date().toLocaleDateString('en-CA').slice(0, 7)

  function statsFor(landlordId) {
    const properties = rental.properties.filter((p) => p.landlordId === landlordId)
    const tenants = rental.tenants.filter((t) => t.landlordId === landlordId && t.propertyId)
    const payments = rental.payments.filter((p) => p.landlordId === landlordId)
    const occupied = new Set(tenants.map((t) => t.propertyId))
    return {
      properties: properties.length,
      occupied: properties.filter((p) => occupied.has(p.id)).length,
      tenants: tenants.length,
      connected: tenants.filter((t) => t.userId).length,
      collected: payments.filter((p) => p.period === month).reduce((s, p) => s + p.amountPaid, 0),
      outstanding: payments.reduce((s, p) => s + p.balance, 0),
      overdue: payments.filter((p) => p.status === 'overdue').length,
    }
  }

  const rows = computed(() => rental.landlords.map((l) => ({ ...l, ...statsFor(l.id) })))
  const landlordName = (id) => rental.landlords.find((l) => l.id === id)?.name ?? '—'

  return { rows, statsFor, landlordName }
}
