import { formatPeriod } from '@/utils/format'

// Where "Pay" goes: the mobile money page, with the amount and what it is for.
// p: a rent charge ({ balance, period }) or { recharge: { total }, label }
// complete: topping up a part payment (the pay page then shows what is remaining)
export const payRoute = (p) => ({
  name: 'tenant-pay',
  query: {
    amount: Math.round(Number(p.recharge ? p.recharge.total : p.balance) || 0),
    label: p.label ?? `Rent for ${formatPeriod(p.period)}`,
    ...(p.complete ? { complete: '1' } : {}),
  },
})
