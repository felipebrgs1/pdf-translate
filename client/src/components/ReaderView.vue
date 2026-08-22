<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { api, type Book, type DayStats } from '../api'
import { makeThumbnail, type OutlineItem, type SelectionRect } from '../pdf'
import PdfViewer from './PdfViewer.vue'
import TranslatePopup from './TranslatePopup.vue'

const LANGUAGES = [
  { code: 'pt', label: 'Português' },
  { code: 'en', label: 'English' },
  { code: 'es', label: 'Español' },
  { code: 'fr', label: 'Français' },
  { code: 'de', label: 'Deutsch' },
  { code: 'it', label: 'Italiano' },
  { code: 'ja', label: '日本語' },
  { code: 'ko', label: '한국어' },
  { code: 'zh-CN', label: '中文 (简体)' },
  { code: 'ru', label: 'Русский' }
]

const props = defineProps<{ book: Book }>()

const emit = defineEmits<{ back: [] }>()

const viewer = ref<InstanceType<typeof PdfViewer> | null>(null)
const targetLang = ref('pt')

// ─── Ferramentas de anotação ──────────────
type ToolMode = 'select' | 'highlight' | 'draw' | 'erase'

const ANNOTATION_COLORS = ['#fde047', '#86efac', '#fca5a5', '#93c5fd']
const tool = ref<ToolMode>('select')
const color = ref(ANNOTATION_COLORS[0])

function undoAnnotation() {
  viewer.value?.undoPage()
}

function clearAnnotations() {
  if (confirm(`Apagar todas as anotações da página ${currentPage.value}?`)) {
    viewer.value?.clearPage()
  }
}
const zoom = ref(1)
const loadError = ref<string | null>(null)

const pageStorageKey = () => `pdf-translate:page:${props.book.key}`

function readSavedPage(): number {
  try {
    const saved = Number(localStorage.getItem(pageStorageKey()))
    return Number.isInteger(saved) && saved >= 1 ? saved : 1
  } catch {
    return 1
  }
}

// lido no setup (antes do PdfViewer montar) pra a página salva valer no 1º load
const currentPage = ref(readSavedPage())
const totalPages = ref(0)
const outline = ref<OutlineItem[]>([])
const showOutline = ref(false)

let saveTimer: ReturnType<typeof setTimeout> | null = null

function saveToServer(page: number, total: number) {
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    api.saveProgress(props.book.key, page, total).catch(() => {})
  }, 800)
}

const popup = ref<{ rect: SelectionRect; original: string } | null>(null)
const translated = ref('')
const translating = ref(false)
const translateError = ref<string | null>(null)

let abort: AbortController | null = null

const ZOOM_STEPS = [0.5, 0.75, 1, 1.25, 1.5, 2, 3]

function zoomIn() {
  const next = ZOOM_STEPS.find((z) => z > zoom.value)
  if (next) zoom.value = next
}

function zoomOut() {
  const prev = [...ZOOM_STEPS].reverse().find((z) => z < zoom.value)
  if (prev) zoom.value = prev
}

// ─── Estatísticas de leitura (páginas, minutos, marca-textos) ─────────
function localDateKey(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

let pendingPages = 0
let pendingMinutes = 0
let pendingHighlights = 0
let statsFlushTimer: ReturnType<typeof setTimeout> | null = null
let readingClock: ReturnType<typeof setInterval> | null = null
let lastStatPage = currentPage.value

function queueStats(delta: { pages?: number; minutes?: number; highlights?: number }) {
  pendingPages += delta.pages ?? 0
  pendingMinutes += delta.minutes ?? 0
  pendingHighlights += delta.highlights ?? 0
  if (statsFlushTimer) return
  statsFlushTimer = setTimeout(flushStats, 5000)
}

async function flushStats() {
  if (statsFlushTimer) {
    clearTimeout(statsFlushTimer)
    statsFlushTimer = null
  }
  if (!pendingPages && !pendingMinutes && !pendingHighlights) return
  const payload = {
    date: localDateKey(),
    pages: pendingPages,
    minutes: Math.round(pendingMinutes),
    highlights: pendingHighlights
  }
  pendingPages = 0
  pendingMinutes = 0
  pendingHighlights = 0
  try {
    await api.addStats(payload)
  } catch {
    // falha ao sincronizar — segue; o próximo delta envia a data atual
  }
}

// marca-textos/desenhos criados no visualizador
function onStrokes(delta: number) {
  if (delta > 0) queueStats({ highlights: delta })
}

// conta 1 minuto de leitura por minuto com a aba visível
readingClock = setInterval(() => {
  if (document.visibilityState === 'visible') queueStats({ minutes: 1 })
}, 60_000)

// ─── Estimador de tempo (livro / capítulo) ──────────────────────
const statsDays = ref<Record<string, DayStats>>({})
const statsTotalPages = computed(() => Object.values(statsDays.value).reduce((s, d) => s + (d.pages ?? 0), 0))
const statsTotalMinutes = computed(() => Object.values(statsDays.value).reduce((s, d) => s + (d.minutes ?? 0), 0))
// histórico suficiente? precisa de pelo menos 10 pág e 5 min pra confiar
const avgMinutesPerPage = computed(() => {
  const p = statsTotalPages.value + pendingPages
  const m = statsTotalMinutes.value + pendingMinutes
  if (p >= 10 && m >= 5) return m / p
  return 2 // fallback: 2 min/pág (~30 pág/h)
})
const bookRemaining = computed(() => Math.max(0, totalPages.value - currentPage.value))
// capítulos reais = itens de menor profundidade no índice (ignora tópicos/seções)
// ex: "GROUP BY e ORDER BY" (p.48) é o capítulo 6; "Agrupando registros"/"Funções de agregação" são seções filhas e não devem entrar aqui
const chapters = computed(() => {
  if (!outline.value.length) return []
  const minD = Math.min(...outline.value.map((o) => o.depth))
  const minCount = outline.value.filter((o) => o.depth === minD).length
  // heurística: se o nível 0 tem 1–3 itens (ex: "Parte I/II"), o nível 1 é que contém os capítulos de verdade
  if (minCount <= 3) {
    const next = outline.value.filter((o) => o.depth === minD + 1)
    if (next.length >= minCount * 3) return next
  }
  return outline.value.filter((o) => o.depth === minD)
})
const currentChapter = computed(() => {
  const chs = chapters.value
  if (!chs.length || !totalPages.value) return null
  let idx = -1
  for (let i = 0; i < chs.length; i++) if (chs[i].page <= currentPage.value) idx = i
  if (idx === -1) return null
  const cur = chs[idx]
  const next = chs[idx + 1]
  const end = next ? Math.max(cur.page, next.page - 1) : totalPages.value
  return { title: cur.title, start: cur.page, end, nextPage: next?.page ?? null }
})
const chapterRemaining = computed(() => {
  const ch = currentChapter.value
  if (!ch) return null
  return Math.max(0, ch.end - currentPage.value)
})
const bookEtaMinutes = computed(() => Math.round(bookRemaining.value * avgMinutesPerPage.value))
const chapterEtaMinutes = computed(() => (chapterRemaining.value === null ? null : Math.round(chapterRemaining.value * avgMinutesPerPage.value)))
function formatEta(min: number | null) {
  if (min === null) return '—'
  if (min < 1) return '< 1 min'
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m ? `${h}h ${m}min` : `${h}h`
}

async function translateDirect(text: string): Promise<string> {
  const params = new URLSearchParams({
    client: 'gtx',
    sl: 'auto',
    tl: targetLang.value,
    dt: 't',
    q: text
  })
  const res = await fetch(`https://translate.googleapis.com/translate_a/single?${params}`, {
    signal: abort?.signal
  })
  if (!res.ok) throw new Error('direct failed')
  const data = await res.json()
  return (data?.[0] ?? []).map((part: [string]) => part[0]).join('')
}

async function translateViaProxy(text: string): Promise<string> {
  const params = new URLSearchParams({ q: text, target: targetLang.value })
  const res = await fetch(`/api/translate?${params}`, { signal: abort?.signal })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error ?? 'proxy failed')
  return data.translated
}

async function onSelect(payload: { text: string; rect: SelectionRect }) {
  popup.value = { rect: payload.rect, original: payload.text }
  translated.value = ''
  translateError.value = null
  translating.value = true

  abort?.abort()
  abort = new AbortController()

  try {
    translated.value = await translateDirect(payload.text).catch(() =>
      translateViaProxy(payload.text)
    )
  } catch (e) {
    if ((e as Error).name !== 'AbortError') {
      translateError.value = 'Não foi possível traduzir'
    }
  } finally {
    translating.value = false
  }
}

function closePopup() {
  popup.value = null
  abort?.abort()
  window.getSelection()?.removeAllRanges()
}

// fecha o card ao clicar fora, apertar Esc ou rolar o PDF
function onDocMouseDown() {
  if (popup.value) closePopup()
}

function onDocKeyDown(e: KeyboardEvent) {
  if (e.key === 'Escape' && popup.value) closePopup()
}

function onDocScroll() {
  if (popup.value) closePopup()
}

onMounted(async () => {
  document.addEventListener('mousedown', onDocMouseDown)
  document.addEventListener('keydown', onDocKeyDown)
  document.addEventListener('scroll', onDocScroll, true)
  try {
    const bookUrl = `/api/books/${props.book.key}`

    // página inicial: servidor (sincronizado entre dispositivos) > localStorage > 1
    let startPage = readSavedPage()
    try {
      const server = await api.getProgress(props.book.key)
      if (server?.page >= 1) startPage = server.page
    } catch {
      // sem progresso no servidor — usa o local
    }

    // download único do PDF (sem Range) e abertura no cliente
    const res = await fetch(bookUrl)
    if (!res.ok) throw new Error()
    const data = await res.arrayBuffer()
    viewer.value?.openData(data, startPage)
    lastStatPage = startPage

    api.getStats().then((r) => {
      statsDays.value = r.days ?? {}
    }).catch(() => {})

    const thumbRes = await fetch(`/api/thumbs/${props.book.key}`)
    if (!thumbRes.ok) {
      const thumb = await makeThumbnail(data)
      if (thumb) await api.uploadThumb(props.book.key, thumb).catch(() => {})
    }
  } catch {
    loadError.value = 'Não foi possível carregar o livro'
  }
})

function onLoaded(total: number) {
  totalPages.value = total
  if (totalPages.value >= 1) saveToServer(currentPage.value, totalPages.value)
}

function onOutline(items: OutlineItem[]) {
  outline.value = items
}

function jumpTo(item: OutlineItem) {
  viewer.value?.goToPage(item.page)
}

function onPageChange(page: number) {
  const prev = currentPage.value
  currentPage.value = page
  if (page > lastStatPage) queueStats({ pages: Math.min(page - lastStatPage, 100) })
  // se o usuário voltou páginas, não subtrai; só corrige a referência
  if (page < prev) lastStatPage = page
  else lastStatPage = page
  try {
    localStorage.setItem(pageStorageKey(), String(page))
  } catch {
    // storage indisponível — segue sem persistir
  }
  if (totalPages.value >= 1) saveToServer(page, totalPages.value)
}

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onDocMouseDown)
  document.removeEventListener('keydown', onDocKeyDown)
  document.removeEventListener('scroll', onDocScroll, true)
  if (readingClock) clearInterval(readingClock)
  void flushStats()
  try {
    localStorage.setItem(pageStorageKey(), String(currentPage.value))
  } catch {
    // storage indisponível
  }
  if (totalPages.value >= 1) saveToServer(currentPage.value, totalPages.value)
})
</script>

<template>
  <div class="relative flex min-h-0 flex-1 flex-col bg-black">
    <!-- HEADER -->
    <header class="flex items-center gap-3 border-b border-zinc-800 px-4 py-2.5">
      <!-- ESQUERDA -->
      <div class="flex min-w-0 items-center gap-2">
        <button
          class="flex shrink-0 items-center gap-1.5 rounded-md border border-zinc-800 px-3 py-1.5 text-sm text-zinc-400 transition hover:border-zinc-700 hover:text-white"
          @click="emit('back')"
        >
          <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </svg>
          Biblioteca
        </button>

        <button
          v-if="outline.length"
          class="flex shrink-0 items-center gap-1.5 rounded-md border px-2.5 py-1.5 text-sm transition"
          :class="showOutline ? 'border-zinc-600 bg-zinc-800 text-white' : 'border-zinc-800 text-zinc-300 hover:border-zinc-700 hover:text-white'"
          title="Índice"
          @click="showOutline = !showOutline"
        >
          <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5M3.75 17.25h16.5" />
          </svg>
          Índice
        </button>

        <span class="hidden max-w-[22ch] truncate text-sm text-zinc-400 md:block">{{ props.book.name }}</span>
        <span v-if="loadError" class="text-sm text-red-400">{{ loadError }}</span>
      </div>

      <!-- MEIO - contador de páginas -->
      <div class="flex flex-1 justify-center">
        <span
          v-if="totalPages > 0"
          class="rounded-full border border-zinc-800 bg-zinc-900 px-3 py-1 text-xs font-medium tabular-nums text-zinc-300"
        >
          {{ currentPage }} / {{ totalPages }}
        </span>
        <span v-else class="text-xs text-zinc-600">— / —</span>
      </div>

      <!-- DIREITA -->
      <div class="flex shrink-0 items-center gap-2">
        <!-- FERRAMENTAS DE ANOTAÇÃO -->
        <div class="flex items-center gap-1 rounded-md border border-zinc-800 p-0.5">
          <!-- seleção / cursor -->
          <button
            class="rounded px-1.5 py-1 transition"
            :class="tool === 'select' ? 'bg-zinc-700 text-white' : 'text-zinc-400 hover:text-white'"
            title="Selecionar texto"
            @click="tool = 'select'"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
              <path d="M5.5 2.5 19 9.75l-6 1.25-3 5.5-4.5-14Z" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linejoin="round" />
            </svg>
          </button>
          <!-- marca-texto -->
          <button
            class="rounded px-1.5 py-1 transition"
            :class="tool === 'highlight' ? 'bg-zinc-700 text-white' : 'text-zinc-400 hover:text-white'"
            title="Marca-texto"
            @click="tool = 'highlight'"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9.53 16.122a3 3 0 0 0-5.78 1.128 2.25 2.25 0 0 1-2.4 2.245 4.5 4.5 0 0 0 8.4-2.245c0-.399-.078-.78-.22-1.128Zm0 0a15.998 15.998 0 0 0 3.388-1.62m-5.043-.025a15.994 15.994 0 0 1 1.622-3.395m3.42 3.42a15.995 15.995 0 0 0 4.764-4.648l3.876-5.814a1.151 1.151 0 0 0-1.597-1.597L14.146 6.32a15.996 15.996 0 0 0-4.649 4.763m3.42 3.42a6.776 6.776 0 0 0-3.42-3.42" />
            </svg>
          </button>
          <!-- caneta -->
          <button
            class="rounded px-1.5 py-1 transition"
            :class="tool === 'draw' ? 'bg-zinc-700 text-white' : 'text-zinc-400 hover:text-white'"
            title="Desenhar"
            @click="tool = 'draw'"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
            </svg>
          </button>
          <!-- borracha -->
          <button
            class="rounded px-1.5 py-1 transition"
            :class="tool === 'erase' ? 'bg-zinc-700 text-white' : 'text-zinc-400 hover:text-white'"
            title="Borracha"
            @click="tool = 'erase'"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 20h16M4.97 13.72 12.72 5.97a2.25 2.25 0 0 1 3.182 0l2.148 2.148a2.25 2.25 0 0 1 0 3.182l-5.55 5.55a4.5 4.5 0 0 1-6.364 0l-.147-.147a2.25 2.25 0 0 1 0-3.182Z" />
            </svg>
          </button>
          <!-- cores -->
          <span v-if="tool === 'highlight' || tool === 'draw'" class="mx-1 h-4 w-px bg-zinc-800"></span>
          <template v-if="tool === 'highlight' || tool === 'draw'">
            <button
              v-for="c in ANNOTATION_COLORS"
              :key="c"
              class="h-4 w-4 rounded-full border transition"
              :style="{ backgroundColor: c }"
              :class="color === c ? 'border-white ring-1 ring-white' : 'border-transparent opacity-60 hover:opacity-100'"
              :title="`Cor ${c}`"
              @click="color = c"
            ></button>
          </template>
          <span v-if="tool !== 'select'" class="mx-1 h-4 w-px bg-zinc-800"></span>
          <button
            v-if="tool !== 'select'"
            class="rounded px-1.5 py-1 text-zinc-400 transition hover:text-white"
            title="Desfazer (nesta página)"
            @click="undoAnnotation"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3" />
            </svg>
          </button>
          <button
            v-if="tool !== 'select'"
            class="rounded px-1.5 py-1 text-zinc-400 transition hover:text-red-400"
            title="Limpar anotações desta página"
            @click="clearAnnotations"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
            </svg>
          </button>
        </div>

        <div class="flex items-center gap-1 text-sm text-zinc-400">
          <button
            class="rounded-md border border-zinc-800 px-2.5 py-1 transition hover:border-zinc-700 hover:text-white"
            @click="zoomOut"
          >
            −
          </button>
          <span class="w-12 text-center text-xs">{{ Math.round(zoom * 100) }}%</span>
          <button
            class="rounded-md border border-zinc-800 px-2.5 py-1 transition hover:border-zinc-700 hover:text-white"
            @click="zoomIn"
          >
            +
          </button>
        </div>

        <select
          v-model="targetLang"
          class="rounded-md border border-zinc-800 bg-black px-2 py-1.5 text-sm text-zinc-300 outline-none transition hover:border-zinc-700"
        >
          <option v-for="lang in LANGUAGES" :key="lang.code" :value="lang.code">
            {{ lang.label }}
          </option>
        </select>
      </div>
    </header>

    <!-- ESTIMADOR -->
    <div v-if="totalPages > 0" class="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-zinc-800 bg-zinc-950 px-4 py-1.5 text-xs">
      <span class="text-zinc-400">
        Livro: faltam <span class="font-medium tabular-nums text-zinc-200">{{ bookRemaining }}</span> pág
        · <span class="font-medium tabular-nums text-white">~{{ formatEta(bookEtaMinutes) }}</span>
        <span class="text-zinc-500"> para terminar</span>
      </span>
      <template v-if="currentChapter && chapterRemaining !== null && chapterRemaining > 0">
        <span class="hidden text-zinc-700 sm:inline">·</span>
        <span class="truncate text-zinc-400">
          Cap. <span class="font-medium text-zinc-300">"{{ currentChapter.title }}"</span>
          · faltam <span class="font-medium tabular-nums text-zinc-200">{{ chapterRemaining }}</span> pág
          · <span class="font-medium tabular-nums text-white">~{{ formatEta(chapterEtaMinutes) }}</span>
        </span>
      </template>
      <template v-else-if="currentChapter && chapterRemaining === 0">
        <span class="hidden text-zinc-700 sm:inline">·</span>
        <span class="text-emerald-400">Fim do capítulo "{{ currentChapter.title }}"</span>
      </template>
      <span class="ml-auto hidden items-center gap-1 text-[11px] text-zinc-600 md:inline-flex" :title="`Baseado em ${statsTotalPages} pág lidas em ${statsTotalMinutes} min`">
        <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/></svg>
        {{ avgMinutesPerPage.toFixed(1) }} min/pág
        <span v-if="statsTotalPages < 10" class="text-zinc-500">(estimativa padrão)</span>
      </span>
    </div>

    <!-- CONTEÚDO COM ÍNDICE À ESQUERDA -->
    <div class="flex min-h-0 flex-1">
      <!-- Sidebar índice esquerda -->
      <aside
        v-if="showOutline"
        class="flex w-72 shrink-0 flex-col border-r border-zinc-800 bg-zinc-950"
      >
        <header class="flex items-center justify-between border-b border-zinc-800 px-4 py-3">
          <span class="text-sm font-semibold text-white">Índice</span>
          <button
            class="rounded-md p-1 text-zinc-400 transition hover:bg-zinc-800 hover:text-white"
            title="Fechar"
            @click="showOutline = false"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </header>
        <div class="flex-1 overflow-y-auto p-2">
          <button
            v-for="(item, i) in outline"
            :key="i"
            class="flex w-full items-center justify-between gap-2 rounded-md px-3 py-2 text-left text-sm transition hover:bg-zinc-800"
            :style="{ paddingLeft: 12 + item.depth * 16 + 'px' }"
            :class="item.page === currentPage ? 'bg-zinc-800 text-white' : 'text-zinc-300'"
            @click="jumpTo(item)"
          >
            <span class="truncate">{{ item.title }}</span>
            <span class="shrink-0 text-xs text-zinc-500">{{ item.page }}</span>
          </button>
          <p v-if="!outline.length" class="p-4 text-sm text-zinc-500">Este livro não tem índice.</p>
        </div>
      </aside>

      <!-- PDF -->
      <div class="flex min-h-0 flex-1 flex-col">
        <PdfViewer
          ref="viewer"
          :zoom="zoom"
          :tool="tool"
          :color="color"
          :storage-key="props.book.key"
          @select="onSelect"
          @pagechange="onPageChange"
          @loaded="onLoaded"
          @outline="onOutline"
          @strokes="onStrokes"
        />
      </div>
    </div>

    <TranslatePopup
      v-if="popup"
      :rect="popup.rect"
      :original="popup.original"
      :translated="translated"
      :loading="translating"
      :error="translateError"
      @close="closePopup"
    />
  </div>
</template>
