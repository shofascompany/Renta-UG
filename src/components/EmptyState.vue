<script setup>
defineProps({ title: String, text: String, icon: [Object, Function] })
</script>

<template>
  <div class="flex flex-col items-center justify-center px-6 py-12 text-center">
    <div v-if="icon" class="mb-3 flex size-10 items-center justify-center rounded-full bg-slate-50">
      <component :is="icon" class="size-5 text-slate-400" />
    </div>
    <p class="text-sm font-medium text-slate-900">{{ title }}</p>
    <p v-if="text" class="mt-1 text-sm text-slate-500">{{ text }}</p>
  </div>
</template>
