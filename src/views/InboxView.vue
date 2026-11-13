<script setup>
import { computed } from 'vue'
import { CheckCheck, Inbox } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import PageHeader from '@/components/PageHeader.vue'
import EmptyState from '@/components/EmptyState.vue'
import PushPrompt from '@/components/PushPrompt.vue'
import NotificationItem from '@/components/NotificationItem.vue'

// Inbox for landlords and the main admin: payments received, tenants connecting, sign-in alerts.
const rental = useRentalStore()
const auth = useAuthStore()
const items = computed(() => [...rental.staff_notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
const unread = computed(() => items.value.filter((n) => !n.read).length)
</script>

<template>
  <PageHeader
    title="Inbox"
    :subtitle="auth.isSuperadmin ? 'Payments received across all landlords, and account security alerts.' : 'Payments from your tenants, tenant connections and account security alerts.'"
  >
    <button class="btn-secondary" :disabled="!unread" @click="rental.markAllStaffRead()">
      <CheckCheck class="size-4" /> Mark all as read
    </button>
  </PageHeader>

  <PushPrompt class="mb-6" always />

  <section class="card overflow-hidden">
    <div v-if="items.length" class="divide-y divide-slate-100">
      <NotificationItem v-for="n in items" :key="n.id" :notification="n" @read="rental.markStaffRead" />
    </div>
    <EmptyState v-else :icon="Inbox" title="No messages yet" text="Payment confirmations, tenant connections and security alerts will appear here." />
  </section>
</template>
