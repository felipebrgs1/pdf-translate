<script setup lang="ts">
import { ref } from 'vue'
import { api } from '../api'

const emit = defineEmits<{ success: [email: string] }>()

const email = ref('')
const password = ref('')
const error = ref<string | null>(null)
const loading = ref(false)

async function submit() {
  error.value = null
  loading.value = true
  try {
    await api.login(email.value.trim(), password.value)
    emit('success', email.value.trim())
  } catch {
    error.value = 'Email ou senha incorretos'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="flex flex-1 items-center justify-center bg-black px-4">
    <div class="w-full max-w-sm">
      <div class="mb-8 text-center">
        <div
          class="mx-auto mb-4 flex h-11 w-11 items-center justify-center rounded-lg border border-zinc-800 bg-zinc-950"
        >
          <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
            />
          </svg>
        </div>
        <h1 class="text-xl font-semibold text-white">PDF Translate</h1>
        <p class="mt-1 text-sm text-zinc-500">Entre para acessar sua biblioteca</p>
      </div>

      <form
        class="space-y-4 rounded-xl border border-zinc-800 bg-zinc-950 p-6"
        @submit.prevent="submit"
      >
        <div>
          <label class="mb-1.5 block text-sm text-zinc-400" for="email">Email</label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            autocomplete="email"
            class="w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-white placeholder-zinc-600 outline-none transition focus:border-zinc-600"
            placeholder="voce@email.com"
          />
        </div>
        <div>
          <label class="mb-1.5 block text-sm text-zinc-400" for="password">Senha</label>
          <input
            id="password"
            v-model="password"
            type="password"
            required
            autocomplete="current-password"
            class="w-full rounded-md border border-zinc-800 bg-black px-3 py-2 text-sm text-white placeholder-zinc-600 outline-none transition focus:border-zinc-600"
            placeholder="••••••••"
          />
        </div>

        <p v-if="error" class="text-sm text-red-400">{{ error }}</p>

        <button
          type="submit"
          :disabled="loading"
          class="w-full rounded-md bg-white px-3 py-2 text-sm font-medium text-black transition hover:bg-zinc-200 disabled:opacity-50"
        >
          {{ loading ? 'Entrando…' : 'Entrar' }}
        </button>
      </form>
    </div>
  </div>
</template>
