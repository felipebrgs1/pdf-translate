<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from 'vue'
import type { SelectionRect } from '../pdf'

const props = defineProps<{
  rect: SelectionRect
  original: string
  translated: string
  loading: boolean
  error: string | null
}>()

const emit = defineEmits<{ close: [] }>()

const popupEl = ref<HTMLDivElement | null>(null)
const pos = ref({ left: 0, top: 0, below: false })
const arrowX = ref(0)

const MARGIN = 8
const GAP = 12

// posiciona o card dentro do viewport: centraliza na seleção, prefere acima,
// vira pra baixo se não couber e trava nas bordas
function place() {
  const el = popupEl.value
  if (!el) return
  const w = el.offsetWidth
  const h = el.offsetHeight
  const vw = window.innerWidth
  const vh = window.innerHeight

  const cx = props.rect.left + props.rect.width / 2
  const maxLeft = Math.max(vw - w - MARGIN, MARGIN)
  const left = Math.min(Math.max(cx, MARGIN + w / 2), maxLeft)

  let top = props.rect.top - h - GAP
  let below = false
  if (top < MARGIN) {
    top = props.rect.bottom + GAP
    below = true
  }
  top = Math.min(Math.max(top, MARGIN), Math.max(vh - h - MARGIN, MARGIN))

  // seta aponta pro centro da seleção (acompanha se o card foi empurrado)
  arrowX.value = Math.min(Math.max(cx - left, 14), Math.max(w - 14, 14))

  pos.value = { left, top, below }
}

onMounted(place)
watch(
  () => [props.loading, props.translated, props.error],
  () => nextTick(place)
)
</script>

<template>
  <div
    ref="popupEl"
    class="popup fixed z-50 w-80 max-w-[90vw] rounded-lg border border-zinc-700 bg-zinc-900 p-3 shadow-2xl shadow-black/60"
    :class="{ below: pos.below }"
    :style="{ left: `${pos.left}px`, top: `${pos.top}px`, '--arrow-x': `${arrowX}px` }"
    @mousedown.stop
  >
    <button
      class="absolute right-2 top-1 text-lg leading-none text-zinc-500 transition hover:text-white"
      @click="emit('close')"
    >
      ×
    </button>
    <div class="mb-2 max-h-20 overflow-y-auto pr-4 text-xs text-zinc-500">{{ original }}</div>
    <div class="text-sm leading-relaxed text-white">
      <span v-if="loading" class="text-zinc-500">Traduzindo…</span>
      <span v-else-if="error" class="text-red-400">{{ error }}</span>
      <span v-else>{{ translated }}</span>
    </div>
  </div>
</template>

<style scoped>
.popup {
  transition: top 0.12s ease, left 0.12s ease;
}
.popup::before {
  content: '';
  position: absolute;
  left: var(--arrow-x);
  transform: translateX(-50%);
  border: 6px solid transparent;
}
.popup.below::before {
  top: -12px;
  border-bottom-color: #3f3f46;
}
.popup:not(.below)::before {
  bottom: -12px;
  border-top-color: #3f3f46;
}
</style>
