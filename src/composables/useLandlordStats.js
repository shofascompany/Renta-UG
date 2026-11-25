import { computed } from 'vue'
import { useRentalStore } from '@/stores/rental'
import { monthOf } from '@/utils/format'

// Main admin: per-landlord figures computed from everything the store has loaded.
export function useLandlordStats() {
  const rental = useRentalStore()

  function statsFor(landlordId) {
    const properties = rental.properties.filter((p) => p.landlordId === landlordId)
    const tenants = rental.tenants.filter((t) => t.landlordId === landlordId && t.propertyId)
    const occupied = new Set(tenants.map((t) => t.propertyId))
    return {
      properties: properties.length,
      occupied: properties.filter((p) => occupied.has(p.id)).length,
      tenants: tenants.length,
      connected: tenants.filter((t) => t.usesApp).length,
      collected: rental.payment_receipts // received this calendar month
        .filter((r) => r.landlordId === landlordId && monthOf(r.receivedAt) === monthOf(new Date()))
        .reduce((s, r) => s + r.amount, 0),
      outstanding: rental.unpaidMonths.filter((m) => m.landlordId === landlordId).reduce((s, m) => s + m.amount, 0),
      overdue: tenants.filter((t) => rental.payStateFor(t.id)?.late).length, // tenants
    }
  }

  const rows = computed(() => rental.landlords.map((l) => ({ ...l, ...statsFor(l.id) })))
  const landlordName = (id) => rental.landlords.find((l) => l.id === id)?.name ?? '—'

  return { rows, statsFor, landlordName }
}
