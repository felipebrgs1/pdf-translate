<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api, type DayStats } from '../api'

const emit = defineEmits<{ close: [] }>()

const loading = ref(true)
const error = ref<string | null>(null)
const days = ref<Record<string, DayStats>>({})
const selectedYear = ref(new Date().getFullYear())

function localDateKey(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

onMounted(async () => {
  try {
    const res = await api.getStats()
    days.value = res.days ?? {}
    const years = Object.keys(days.value).map((k) => Number(k.slice(0, 4)))
    if (years.length && !years.includes(selectedYear.value)) {
      selectedYear.value = Math.max(...years)
    }
  } catch {
    error.value = 'Não foi possível carregar as estatísticas'
  } finally {
    loading.value = false
  }
})

const availableYears = computed(() => {
  const set = new Set<number>([new Date().getFullYear()])
  for (const k of Object.keys(days.value)) set.add(Number(k.slice(0, 4)))
  return [...set].sort((a, b) => b - a)
})

function sumDays(filter: (date: string) => boolean) {
  let pages = 0
  let minutes = 0
  let highlights = 0
  for (const [date, s] of Object.entries(days.value)) {
    if (!filter(date)) continue
    pages += s.pages ?? 0
    minutes += s.minutes ?? 0
    highlights += s.highlights ?? 0
  }
  return { pages, minutes, highlights }
}

const yearStats = computed(() => sumDays((d) => d.startsWith(String(selectedYear.value))))
const totalStats = computed(() => sumDays(() => true))

const activeDaysYear = computed(
  () => Object.entries(days.value).filter(([d, s]) => d.startsWith(String(selectedYear.value)) && s.pages > 0).length
)

const streak = computed(() => {
  let n = 0
  const d = new Date()
  // se hoje ainda não tem leitura, começa de ontem
  const todayKey = localDateKey(d)
  if (!days.value[todayKey]?.pages) d.setDate(d.getDate() - 1)
  while (true) {
    const k = localDateKey(d)
    if ((days.value[k]?.pages ?? 0) > 0) {
      n++
      d.setDate(d.getDate() - 1)
    } else break
    if (n > 3650) break
  }
  return n
})

function intensity(pages: number) {
  if (pages === 0) return 'bg-zinc-800'
  if (pages <= 2) return 'bg-emerald-950'
  if (pages <= 6) return 'bg-emerald-800'
  if (pages <= 12) return 'bg-emerald-600'
  return 'bg-emerald-400'
}

interface HeatCell {
  date: string
  stats: DayStats
  inYear: boolean
}

const heatWeeks = computed<HeatCell[][]>(() => {
  const year = selectedYear.value
  const first = new Date(year, 0, 1)
  const last = new Date(year, 11, 31)
  const start = new Date(first)
  start.setDate(first.getDate() - first.getDay()) // domingo
  const end = new Date(last)
  end.setDate(last.getDate() + (6 - last.getDay()))
  const weeks: HeatCell[][] = []
  const cur = new Date(start)
  while (cur <= end) {
    const week: HeatCell[] = []
    for (let i = 0; i < 7; i++) {
      const iso = localDateKey(cur)
      week.push({
        date: iso,
        stats: days.value[iso] ?? { pages: 0, minutes: 0, highlights: 0 },
        inYear: iso.startsWith(String(year))
      })
      cur.setDate(cur.getDate() + 1)
    }
    weeks.push(week)
  }
  return weeks
})

const monthLabels = computed(() => {
  const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
  // pega o mês do primeiro dia de cada semana que está no ano selecionado
  const labels: string[] = []
  let lastMonth = -1
  for (const week of heatWeeks.value) {
    const cell = week.find((c) => c.inYear)
    if (!cell) {
      labels.push('')
      continue
    }
    const m = Number(cell.date.slice(5, 7)) - 1
    if (m !== lastMonth) {
      labels.push(months[m])
      lastMonth = m
    } else labels.push('')
  }
  return labels
})

function formatHours(minutes: number) {
  if (minutes < 60) return `${minutes} min`
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  return m ? `${h}h ${m}min` : `${h}h`
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm" @click.self="emit('close')">
    <div class="flex max-h-[90vh] w-full max-w-3xl flex-col overflow-hidden rounded-xl border border-zinc-800 bg-zinc-950 shadow-2xl">
      <!-- header -->
      <div class="flex items-center justify-between border-b border-zinc-800 px-5 py-4">
        <h2 class="text-sm font-semibold text-white">Estatísticas de leitura</h2>
        <div class="flex items-center gap-2">
          <select
            v-model="selectedYear"
            class="rounded-md border border-zinc-800 bg-black px-2 py-1 text-sm text-zinc-300 outline-none"
          >
            <option v-for="y in availableYears" :key="y" :value="y">{{ y }}</option>
          </select>
          <button
            class="rounded-md p-1.5 text-zinc-500 transition hover:bg-zinc-800 hover:text-white"
            title="Fechar"
            @click="emit('close')"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto px-5 py-5">
        <div v-if="loading" class="py-16 text-center text-sm text-zinc-500">Carregando…</div>
        <p v-else-if="error" class="py-10 text-center text-sm text-red-400">{{ error }}</p>

        <template v-else>
          <!-- cards -->
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div class="rounded-lg border border-zinc-800 bg-zinc-900/60 px-4 py-3">
              <p class="text-[11px] font-medium uppercase tracking-widest text-zinc-500">Páginas em {{ selectedYear }}</p>
              <p class="mt-1 text-2xl font-semibold tabular-nums text-white">{{ yearStats.pages }}</p>
              <p class="text-xs text-zinc-500">{{ activeDaysYear }} dias com leitura</p>
            </div>
            <div class="rounded-lg border border-zinc-800 bg-zinc-900/60 px-4 py-3">
              <p class="text-[11px] font-medium uppercase tracking-widest text-zinc-500">Tempo em {{ selectedYear }}</p>
              <p class="mt-1 text-2xl font-semibold tabular-nums text-white">{{ formatHours(yearStats.minutes) }}</p>
              <p class="text-xs text-zinc-500">{{ yearStats.highlights }} marcações</p>
            </div>
            <div class="rounded-lg border border-zinc-800 bg-zinc-900/60 px-4 py-3">
              <p class="text-[11px] font-medium uppercase tracking-widest text-zinc-500">Sequência atual</p>
              <p class="mt-1 text-2xl font-semibold tabular-nums text-white">
                {{ streak }} <span class="text-sm font-normal text-zinc-400">{{ streak === 1 ? 'dia' : 'dias' }}</span>
              </p>
              <p class="text-xs text-zinc-500">dias seguidos lendo</p>
            </div>
            <div class="rounded-lg border border-zinc-800 bg-zinc-900/60 px-4 py-3">
              <p class="text-[11px] font-medium uppercase tracking-widest text-zinc-500">Total geral</p>
              <p class="mt-1 text-2xl font-semibold tabular-nums text-white">{{ totalStats.pages }}</p>
              <p class="text-xs text-zinc-500">{{ formatHours(totalStats.minutes) }} · {{ totalStats.highlights }} marcações</p>
            </div>
          </div>

          <!-- heatmap -->
          <div class="mt-6">
            <div class="mb-2 flex items-center justify-between">
              <h3 class="text-xs font-medium uppercase tracking-widest text-zinc-400">Atividade · {{ selectedYear }}</h3>
              <div class="flex items-center gap-1.5 text-[11px] text-zinc-500">
                <span>Menos</span>
                <span class="h-2.5 w-2.5 rounded-sm bg-zinc-800"></span>
                <span class="h-2.5 w-2.5 rounded-sm bg-emerald-950"></span>
                <span class="h-2.5 w-2.5 rounded-sm bg-emerald-800"></span>
                <span class="h-2.5 w-2.5 rounded-sm bg-emerald-600"></span>
                <span class="h-2.5 w-2.5 rounded-sm bg-emerald-400"></span>
                <span>Mais</span>
              </div>
            </div>

            <div class="overflow-x-auto rounded-lg border border-zinc-800 bg-black p-3">
              <!-- meses -->
              <div class="mb-1 flex gap-[3px] pl-[28px]">
                <span
                  v-for="(label, i) in monthLabels"
                  :key="i"
                  class="w-[13px] shrink-0 text-[10px] text-zinc-600"
                  :class="{ 'w-auto flex-1': false }"
                  style="min-width: 13px"
                >
                  {{ label }}
                </span>
              </div>
              <div class="flex gap-[3px]">
                <!-- dias da semana -->
                <div class="flex w-7 shrink-0 flex-col gap-[3px] pr-1 text-[10px] leading-[13px] text-zinc-600">
                  <span class="h-[13px]"></span>
                  <span class="h-[13px]">seg</span>
                  <span class="h-[13px]"></span>
                  <span class="h-[13px]">qua</span>
                  <span class="h-[13px]"></span>
                  <span class="h-[13px]">sex</span>
                  <span class="h-[13px]"></span>
                </div>
                <!-- semanas -->
                <div v-for="(week, wi) in heatWeeks" :key="wi" class="flex flex-col gap-[3px]">
                  <span
                    v-for="cell in week"
                    :key="cell.date"
                    class="h-[13px] w-[13px] rounded-sm border border-transparent transition"
                    :class="[intensity(cell.stats.pages), cell.inYear ? '' : 'opacity-30']"
                    :title="`${cell.date} · ${cell.stats.pages} pág · ${cell.stats.minutes} min · ${cell.stats.highlights} marcações`"
                  ></span>
                </div>
              </div>
            </div>
            <p class="mt-2 text-[11px] text-zinc-600">Passe o mouse sobre os quadrados para ver o detalhe do dia. A cor reflete páginas lidas.</p>
          </div>

          <p v-if="!Object.keys(days).length" class="mt-8 rounded-lg border border-dashed border-zinc-800 px-4 py-6 text-center text-sm text-zinc-500">
            Comece a ler para ver suas estatísticas aqui — páginas e tempo são registrados automaticamente.
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
