<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type Book } from '../api'
import { makeThumbnail } from '../pdf'
import StatsView from './StatsView.vue'

const props = defineProps<{ userEmail: string }>()

const emit = defineEmits<{
  open: [book: Book]
  logout: []
}>()

const books = ref<Book[]>([])
const loading = ref(true)
const uploading = ref(false)
const error = ref<string | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const brokenThumbs = ref<Set<string>>(new Set())
const showStats = ref(false)

async function refresh() {
  loading.value = true
  error.value = null
  try {
    books.value = await api.listBooks()
  } catch {
    error.value = 'Não foi possível carregar a biblioteca'
  } finally {
    loading.value = false
  }
}

async function onFileChange(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return
  uploading.value = true
  error.value = null
  try {
    const data = await file.arrayBuffer()
    const book = await api.uploadBook(file)
    const thumb = await makeThumbnail(data)
    if (thumb) {
      await api.uploadThumb(book.key, thumb).catch(() => {})
    }
    await refresh()
  } catch {
    error.value = 'Falha ao enviar o PDF'
  } finally {
    uploading.value = false
  }
}

async function remove(book: Book, e: MouseEvent) {
  e.stopPropagation()
  if (!confirm(`Remover "${book.name}"?`)) return
  try {
    await api.deleteBook(book.key)
    localStorage.removeItem(`pdf-translate:page:${book.key}`)
    books.value = books.value.filter((b) => b.key !== book.key)
  } catch {
    error.value = 'Falha ao remover o livro'
  }
}

async function doLogout() {
  await api.logout().catch(() => {})
  emit('logout')
}

function formatSize(bytes: number) {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

function formatPercent(percent: number) {
  return Number.isInteger(percent) ? String(percent) : percent.toFixed(1)
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric'
  })
}

function onThumbError(key: string) {
  brokenThumbs.value = new Set(brokenThumbs.value).add(key)
}

onMounted(refresh)
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col bg-black">
    <header class="flex items-center gap-4 border-b border-zinc-800 px-6 py-3">
      <div class="flex items-center gap-2">
        <div class="flex h-7 w-7 items-center justify-center rounded-md border border-zinc-800 bg-zinc-950">
          <svg class="h-3.5 w-3.5 text-white" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
            />
          </svg>
        </div>
        <span class="text-sm font-semibold text-white">PDF Translate</span>
      </div>
      <div class="flex-1"></div>
      <button
        class="rounded-md border border-zinc-800 px-3 py-1.5 text-sm text-zinc-400 transition hover:border-zinc-700 hover:text-white"
        @click="showStats = true"
      >
        Estatísticas
      </button>
      <span class="text-sm text-zinc-500">{{ props.userEmail }}</span>
      <button
        class="rounded-md border border-zinc-800 px-3 py-1.5 text-sm text-zinc-400 transition hover:border-zinc-700 hover:text-white"
        @click="doLogout"
      >
        Sair
      </button>
    </header>

    <main class="flex-1 overflow-y-auto px-6 py-8">
      <div class="mx-auto max-w-5xl">
        <div class="mb-6 flex items-center justify-between">
          <div>
            <h1 class="text-lg font-semibold text-white">Biblioteca</h1>
            <p class="text-sm text-zinc-500">{{ books.length }} {{ books.length === 1 ? 'livro' : 'livros' }}</p>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="rounded-md border border-zinc-800 px-3 py-2 text-sm text-zinc-300 transition hover:border-zinc-700 hover:text-white"
              @click="showStats = true"
            >
              Estatísticas
            </button>
            <button
              :disabled="uploading"
              class="rounded-md bg-white px-4 py-2 text-sm font-medium text-black transition hover:bg-zinc-200 disabled:opacity-50"
              @click="fileInput?.click()"
            >
              {{ uploading ? 'Enviando…' : 'Adicionar PDF' }}
            </button>
          </div>
          <input ref="fileInput" type="file" accept="application/pdf" hidden @change="onFileChange" />
        </div>

        <p v-if="error" class="mb-4 text-sm text-red-400">{{ error }}</p>

        <div v-if="loading" class="py-20 text-center text-sm text-zinc-500">Carregando…</div>

        <div
          v-else-if="!books.length"
          class="flex flex-col items-center rounded-xl border border-dashed border-zinc-800 py-20"
        >
          <svg class="mb-3 h-8 w-8 text-zinc-700" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
            />
          </svg>
          <p class="text-sm text-zinc-500">Nenhum livro ainda</p>
          <p class="mt-1 text-xs text-zinc-600">Envie um PDF para começar</p>
        </div>

        <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <div
            v-for="book in books"
            :key="book.key"
            class="group cursor-pointer"
            @click="emit('open', book)"
          >
            <div
              class="relative aspect-[3/4] overflow-hidden rounded-lg border border-zinc-800 bg-zinc-950 transition group-hover:border-zinc-500"
            >
              <img
                v-if="!brokenThumbs.has(book.key)"
                :src="`/api/thumbs/${book.key}`"
                :alt="book.name"
                class="h-full w-full object-cover"
                loading="lazy"
                @error="onThumbError(book.key)"
              />
              <div
                v-else
                class="flex h-full w-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-zinc-900 to-black p-4"
              >
                <svg class="h-8 w-8 text-zinc-700" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25"
                  />
                </svg>
                <span class="text-center text-xs text-zinc-600">{{ book.name }}</span>
              </div>
              <button
                class="absolute right-2 top-2 rounded-md bg-black/70 p-1.5 text-zinc-400 opacity-0 backdrop-blur transition group-hover:opacity-100 hover:text-red-400"
                title="Remover"
                @click="remove(book, $event)"
              >
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                  />
                </svg>
              </button>
            </div>
            <p class="mt-2 truncate text-sm font-medium text-white" :title="book.name">{{ book.name }}</p>
            <div v-if="book.progress" class="mt-1.5">
              <div class="flex items-center justify-between gap-2 text-[11px]">
                <span class="text-zinc-400">Página {{ book.progress.page }} de {{ book.progress.totalPages }}</span>
                <span class="font-semibold text-emerald-400">{{ formatPercent(book.progress.percent) }}% lido</span>
              </div>
              <div class="mt-1 h-1 overflow-hidden rounded-full bg-zinc-800">
                <div
                  class="h-full rounded-full bg-emerald-500 transition-all"
                  :style="{ width: Math.min(book.progress.percent, 100) + '%' }"
                ></div>
              </div>
            </div>
            <p class="text-xs text-zinc-500">{{ formatSize(book.size) }} · {{ formatDate(book.uploaded) }}</p>
          </div>
        </div>
      </div>
    </main>

    <StatsView v-if="showStats" @close="showStats = false" />
  </div>
</template>
