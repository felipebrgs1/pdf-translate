<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import * as pdfjsLib from 'pdfjs-dist'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import 'pdfjs-dist/web/pdf_viewer.css'
import type { OutlineItem, SelectionRect } from '../pdf'

pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl

const props = defineProps<{
  zoom: number
  tool?: 'select' | 'highlight' | 'draw' | 'erase'
  color?: string
  storageKey?: string
}>()

type ToolMode = 'select' | 'highlight' | 'draw' | 'erase'

interface AnnotationStroke {
  t: 'highlight' | 'draw'
  c: string
  w: number // espessura normalizada (fração da altura da página)
  pts: [number, number][] // pontos normalizados 0..1
}

const emit = defineEmits<{
  select: [payload: { text: string; rect: SelectionRect }]
  pagechange: [page: number]
  loaded: [totalPages: number]
  outline: [items: OutlineItem[]]
  strokes: [delta: number]
}>()

const scrollContainer = ref<HTMLDivElement | null>(null)
const container = ref<HTMLDivElement | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)

let currentData: ArrayBuffer | null = null
let renderTask: pdfjsLib.RenderTask | null = null
let pdfDoc: pdfjsLib.PDFDocumentProxy | null = null
let pageEls: HTMLDivElement[] = []
let currentPage = 1
const renderedPages = new Set<number>()
let renderChain: Promise<void> = Promise.resolve()

function pageOffsetTop(pageEl: HTMLElement) {
  const sc = scrollContainer.value!
  return pageEl.getBoundingClientRect().top - sc.getBoundingClientRect().top + sc.scrollTop
}

function computeCurrentPage(): number {
  const sc = scrollContainer.value
  if (!sc || !pageEls.length) return 1
  const threshold = sc.scrollTop + sc.clientHeight * 0.4
  let page = 1
  for (let i = 0; i < pageEls.length; i++) {
    if (pageOffsetTop(pageEls[i]) <= threshold) page = i + 1
    else break
  }
  return page
}

function goToPage(page: number) {
  if (!pageEls.length) return
  const p = Math.min(Math.max(page, 1), pageEls.length)
  currentPage = p
  scrollToPage(p)
  scheduleRender()
}

function scrollToPage(page: number) {
  const sc = scrollContainer.value
  const target = pageEls[Math.min(Math.max(page, 1), pageEls.length) - 1]
  if (!sc || !target) return
  sc.scrollTo({ top: Math.max(pageOffsetTop(target) - 8, 0) })
}

// renderiza as páginas visíveis (+1 de margem acima/abaixo), sob demanda
function scheduleRender() {
  const sc = scrollContainer.value
  if (!sc || !pdfDoc || !pageEls.length) return

  let first = 1
  let last = pageEls.length
  for (let i = 0; i < pageEls.length; i++) {
    if (pageOffsetTop(pageEls[i]) + pageEls[i].offsetHeight >= sc.scrollTop) {
      first = i + 1
      break
    }
  }
  for (let i = pageEls.length - 1; i >= 0; i--) {
    if (pageOffsetTop(pageEls[i]) <= sc.scrollTop + sc.clientHeight) {
      last = i + 1
      break
    }
  }

  for (let p = Math.max(first - 1, 1); p <= Math.min(last + 1, pageEls.length); p++) {
    if (renderedPages.has(p)) continue
    renderedPages.add(p)
    renderChain = renderChain
      .then(() => renderPage(p))
      .catch(() => {})
  }
}

async function renderPage(pageNum: number) {
  if (!pdfDoc) return
  const page = await pdfDoc.getPage(pageNum)
  const wrapper = pageEls[pageNum - 1]
  if (!wrapper) return

  const scale = Number(wrapper.style.getPropertyValue('--scale-factor')) || 1
  const viewport = page.getViewport({ scale })

  const canvas = wrapper.querySelector('canvas')!
  renderTask = page.render({
    canvasContext: canvas.getContext('2d')!,
    viewport,
    transform:
      devicePixelRatio !== 1 ? [devicePixelRatio, 0, 0, devicePixelRatio, 0, 0] : undefined
  })
  await renderTask.promise

  const textLayerDiv = wrapper.querySelector('.textLayer') as HTMLDivElement
  const textLayer = new pdfjsLib.TextLayer({
    textContentSource: page.streamTextContent(),
    container: textLayerDiv,
    viewport
  })
  await textLayer.render()
  textReadyPages.add(pageNum)
}

// extrai o índice (outline) do PDF e resolve cada item pra página
async function loadOutline() {
  const doc = pdfDoc
  if (!doc) return
  const items: OutlineItem[] = []
  try {
    const raw = await doc.getOutline()
    if (!raw?.length) {
      emit('outline', [])
      return
    }
    const walk = async (list: typeof raw, depth: number) => {
      for (const item of list) {
        let page = 0
        try {
          if (item.url) {
            // link externo — sem página pra pular
          } else if (typeof item.dest === 'string') {
            const dest = await doc.getDestination(item.dest)
            if (dest?.[0]) page = (await doc.getPageIndex(dest[0])) + 1
          } else if (Array.isArray(item.dest)) {
            if (item.dest[0]) page = (await doc.getPageIndex(item.dest[0])) + 1
          } else if (item.dest) {
            page = (await doc.getPageIndex(item.dest)) + 1
          }
        } catch {
          // destino não resolve — pula o item
        }
        if (page >= 1 && item.title.trim()) items.push({ title: item.title, page, depth })
        if (item.items?.length) await walk(item.items, depth + 1)
      }
    }
    await walk(raw, 0)
  } catch {
    // sem outline ou falha ao ler
  }
  emit('outline', items)
}

async function loadPdf(data: ArrayBuffer) {
  loading.value = true
  error.value = null
  try {
    pdfDoc = await pdfjsLib.getDocument({ data: data.slice(0) }).promise
    emit('loaded', pdfDoc.numPages)
    loadOutline()

    const el = container.value!
    el.innerHTML = ''
    pageEls = []
    renderedPages.clear()
    textReadyPages.clear()
    pageSpansCache.clear()
    overlays.clear()
    loadAnnotations()

    const target = Math.min(Math.max(currentPage, 1), pdfDoc.numPages)

    // fase 1: monta todos os wrappers (rápido, tamanho inline) —
    // a posição de scroll já fica final e pode ser restaurada na hora
    for (let pageNum = 1; pageNum <= pdfDoc.numPages; pageNum++) {
      const page = await pdfDoc.getPage(pageNum)
      const baseViewport = page.getViewport({ scale: 1 })
      const fitScale = Math.max((el.clientWidth - 32) / baseViewport.width, 0.5)
      // 100% = metade da largura ajustada (tamanho confortável de leitura);
      // 200% = largura ajustada ao container
      const scale = (fitScale * props.zoom) / 2
      const viewport = page.getViewport({ scale })

      const wrapper = document.createElement('div')
      wrapper.className = 'pdf-page'
      wrapper.style.width = `${viewport.width}px`
      wrapper.style.height = `${viewport.height}px`
      wrapper.style.setProperty('--scale-factor', String(scale))
      wrapper.dataset.page = String(pageNum)

      const canvas = document.createElement('canvas')
      canvas.width = Math.floor(viewport.width * devicePixelRatio)
      canvas.height = Math.floor(viewport.height * devicePixelRatio)
      canvas.style.width = `${viewport.width}px`
      canvas.style.height = `${viewport.height}px`
      wrapper.appendChild(canvas)

      const textLayerDiv = document.createElement('div')
      textLayerDiv.className = 'textLayer'
      wrapper.appendChild(textLayerDiv)

      setupOverlay(wrapper, pageNum)

      pageEls.push(wrapper)
      el.appendChild(wrapper)

      if (pageNum === target) scrollToPage(target)
    }

    // fase 2: renderiza só o que está visível
    scheduleRender()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Erro ao abrir o PDF'
  } finally {
    loading.value = false
  }
}

function closestPage(node: Node | null): HTMLElement | null {
  const root = container.value
  let el: Node | null = node
  while (el && el !== root) {
    if (el instanceof Element && el.classList.contains('pdf-page')) return el as HTMLElement
    el = el.parentNode
  }
  return null
}

interface DragLine {
  pageEl: HTMLElement
  spans: HTMLSpanElement[]
  top: number
  bottom: number
}

let dragging = false
let dragStart = { x: 0, y: 0 }
let dragStartTarget: Node | null = null
const pageSpansCache = new Map<HTMLElement, HTMLSpanElement[]>()
const textReadyPages = new Set<number>()

function spansOfPage(pageEl: HTMLElement): HTMLSpanElement[] {
  // text layer ainda não renderizou (render assíncrono do pdf.js)
  if (!textReadyPages.has(Number(pageEl.dataset.page))) return []
  let spans = pageSpansCache.get(pageEl)
  if (!spans) {
    spans = Array.from(pageEl.querySelectorAll<HTMLSpanElement>('.textLayer span')).filter((s) => {
      if (!s.textContent?.trim()) return false
      const r = s.getBoundingClientRect()
      return r.width > 0 && r.height > 0
    })
    pageSpansCache.set(pageEl, spans)
  }
  return spans
}

// agrupa os spans por linha visual (mesma posição vertical)
function linesOfPage(pageEl: HTMLElement): DragLine[] {
  const lines: DragLine[] = []
  for (const span of spansOfPage(pageEl)) {
    const r = span.getBoundingClientRect()
    let line = lines.find((l) => Math.abs(l.top - r.top) < 3)
    if (!line) {
      line = { pageEl, spans: [], top: r.top, bottom: r.bottom }
      lines.push(line)
    }
    line.spans.push(span)
    line.bottom = Math.max(line.bottom, r.bottom)
  }
  return lines
}

// seleciona as linhas inteiras que intersectam a faixa vertical do arrasto
function selectLines(top: number, bottom: number, pageFilter: HTMLElement | null = null): DragLine[] {
  const touched: DragLine[] = []
  for (const pageEl of pageEls) {
    if (pageFilter && pageEl !== pageFilter) continue
    const pr = pageEl.getBoundingClientRect()
    if (pr.bottom < top || pr.top > bottom) continue
    for (const line of linesOfPage(pageEl)) {
      if (line.bottom >= top && line.top <= bottom) touched.push(line)
    }
  }

  const sel = window.getSelection()
  if (!touched.length) {
    sel?.removeAllRanges()
    return []
  }
  const firstSpan = touched[0].spans[0]
  const lastLine = touched[touched.length - 1]
  const lastSpan = lastLine.spans[lastLine.spans.length - 1]
  const range = document.createRange()
  range.setStart(firstSpan, 0)
  range.setEnd(lastSpan, lastSpan.childNodes.length)
  sel?.removeAllRanges()
  sel?.addRange(range)
  return touched
}

// assume o controle total da seleção: sem seleção nativa do browser (que vazava
// pro fim da página/parágrafo e selecionava blocos inteiros em clique duplo).
// com ferramenta de anotação ativa, a seleção fica desativada.
function onDocMouseDown(e: MouseEvent) {
  if (e.button !== 0) return
  if ((props.tool ?? 'select') !== 'select') return
  const root = container.value
  if (!root || !(e.target instanceof Node) || !root.contains(e.target)) return
  dragging = true
  dragStart = { x: e.clientX, y: e.clientY }
  dragStartTarget = e.target
  e.preventDefault()
}

function onDocMouseMove(e: MouseEvent) {
  if (!dragging) return
  const top = Math.min(dragStart.y, e.clientY)
  const bottom = Math.max(dragStart.y, e.clientY)
  selectLines(top, bottom)
}

function onDocMouseUp(e: MouseEvent) {
  if (!dragging) return
  dragging = false

  // clique simples (sem arrasto): limpa a seleção e não traduz
  if (Math.abs(e.clientX - dragStart.x) < 4 && Math.abs(e.clientY - dragStart.y) < 4) {
    window.getSelection()?.removeAllRanges()
    return
  }

  const top = Math.min(dragStart.y, e.clientY)
  const bottom = Math.max(dragStart.y, e.clientY)
  // arrasto cruzando páginas: mantém só as linhas da página onde soltou
  const targetPage = closestPage(e.target as Node) ?? closestPage(dragStartTarget)
  const touched = selectLines(top, bottom, targetPage)
  if (!touched.length) return

  const sel = window.getSelection()
  const range = sel?.getRangeAt(0)
  if (!range) return
  const text = sel?.toString().trim()
  if (!text) return
  const rect = range.getBoundingClientRect()
  if (!rect.width || !rect.height) return
  emit('select', {
    text,
    rect: {
      top: rect.top,
      bottom: rect.bottom,
      left: rect.left,
      right: rect.right,
      width: rect.width,
      height: rect.height
    }
  })
}

// ─── Anotações: marca-texto, desenho livre e borracha ─────────────
const overlays = new Map<number, HTMLCanvasElement>()
let annotations: Record<string, AnnotationStroke[]> = {}
let drawingStroke: AnnotationStroke | null = null
let drawingPage = 0
let erasing = false
const ERASER_RADIUS = 12 // px na tela

function annStorageKey() {
  return `pdf-annotations:${props.storageKey ?? 'default'}`
}

function loadAnnotations() {
  try {
    annotations = JSON.parse(localStorage.getItem(annStorageKey()) ?? '{}') || {}
  } catch {
    annotations = {}
  }
}

function saveAnnotations() {
  try {
    localStorage.setItem(annStorageKey(), JSON.stringify(annotations))
  } catch {
    // storage indisponível — anotações só valem nesta sessão
  }
}

function strokesOf(page: number): AnnotationStroke[] {
  return annotations[String(page)] ?? []
}

// substitui os traços da página, persiste, redesenha e emite o delta (pra estatísticas)
function setPageStrokes(page: number, next: AnnotationStroke[]) {
  const before = strokesOf(page).length
  if (next.length) annotations[String(page)] = next
  else delete annotations[String(page)]
  saveAnnotations()
  redrawPage(page)
  const delta = next.length - before
  if (delta !== 0) emit('strokes', delta)
}

function setupOverlay(wrapper: HTMLDivElement, pageNum: number) {
  const w = parseFloat(wrapper.style.width)
  const h = parseFloat(wrapper.style.height)
  const canvas = document.createElement('canvas')
  canvas.className = 'anno-layer'
  canvas.width = Math.floor(w * devicePixelRatio)
  canvas.height = Math.floor(h * devicePixelRatio)
  wrapper.appendChild(canvas)
  overlays.set(pageNum, canvas)
  redrawPage(pageNum)
}

function drawStroke(ctx: CanvasRenderingContext2D, s: AnnotationStroke, w: number, h: number) {
  if (s.pts.length < 2) return
  ctx.save()
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.strokeStyle = s.c
  ctx.lineWidth = Math.max(2, s.w * h)
  if (s.t === 'highlight') {
    ctx.globalAlpha = 0.35
    ctx.globalCompositeOperation = 'multiply'
  }
  ctx.beginPath()
  ctx.moveTo(s.pts[0][0] * w, s.pts[0][1] * h)
  for (const [x, y] of s.pts.slice(1)) ctx.lineTo(x * w, y * h)
  ctx.stroke()
  ctx.restore()
}

function redrawPage(pageNum: number, live?: AnnotationStroke | null) {
  const canvas = overlays.get(pageNum)
  if (!canvas) return
  const ctx = canvas.getContext('2d')!
  const dpr = devicePixelRatio
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  const w = canvas.clientWidth
  const h = canvas.clientHeight
  ctx.clearRect(0, 0, w, h)
  for (const s of strokesOf(pageNum)) drawStroke(ctx, s, w, h)
  // traço em andamento (pré-visualização ao vivo)
  if (live && live.pts.length >= 2) drawStroke(ctx, live, w, h)
}

// converte o evento num ponto normalizado dentro de uma página
function pagePoint(e: PointerEvent): { page: number; x: number; y: number } | null {
  const pageEl = closestPage(e.target as Node)
  if (!pageEl) return null
  const r = pageEl.getBoundingClientRect()
  if (!r.width || !r.height) return null
  return {
    page: Number(pageEl.dataset.page),
    x: Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1),
    y: Math.min(Math.max((e.clientY - r.top) / r.height, 0), 1)
  }
}

function eraseAt(page: number, nx: number, ny: number) {
  const arr = annotations[String(page)]
  if (!arr?.length) return
  const canvas = overlays.get(page)
  if (!canvas) return
  const w = canvas.clientWidth
  const h = canvas.clientHeight
  const px = nx * w
  const py = ny * h
  const kept = arr.filter(
    (s) => !s.pts.some(([x, y]) => Math.hypot(x * w - px, y * h - py) < ERASER_RADIUS)
  )
  if (kept.length === arr.length) return
  setPageStrokes(page, kept)
}

function onPointerDown(e: PointerEvent) {
  const tool = props.tool ?? 'select'
  if (tool === 'select' || e.button !== 0) return
  e.preventDefault()
  const pt = pagePoint(e)
  if (!pt) return
  if (tool === 'erase') {
    erasing = true
    eraseAt(pt.page, pt.x, pt.y)
    return
  }
  drawingStroke = {
    t: tool === 'highlight' ? 'highlight' : 'draw',
    c: props.color ?? '#fde047',
    w: tool === 'highlight' ? 0.016 : 0.0035,
    pts: [[pt.x, pt.y]]
  }
  drawingPage = pt.page
}

function onPointerMove(e: PointerEvent) {
  if (!drawingStroke && !erasing) return
  const pt = pagePoint(e)
  if (!pt) return
  if (erasing) {
    eraseAt(pt.page, pt.x, pt.y)
    return
  }
  // ignora pontos fora da página onde o traço começou
  if (pt.page !== drawingPage) return
  const last = drawingStroke!.pts[drawingStroke!.pts.length - 1]
  if (Math.abs(last[0] - pt.x) < 0.0015 && Math.abs(last[1] - pt.y) < 0.0015) return
  drawingStroke!.pts.push([pt.x, pt.y])
  redrawPage(drawingPage, drawingStroke)
}

function onPointerUp() {
  if (drawingStroke) {
    if (drawingStroke.pts.length >= 2) {
      setPageStrokes(drawingPage, [...strokesOf(drawingPage), drawingStroke])
    }
    drawingStroke = null
  }
  erasing = false
}

function undoPage() {
  const arr = annotations[String(currentPage)]
  if (!arr?.length) return
  setPageStrokes(currentPage, arr.slice(0, -1))
}

function clearPage() {
  setPageStrokes(currentPage, [])
}

function openData(data: ArrayBuffer, initialPage?: number) {
  currentData = data
  if (Number.isInteger(initialPage) && (initialPage ?? 0) >= 1) currentPage = initialPage!
  loadPdf(data)
}

function onScroll() {
  scheduleRender()
  const page = computeCurrentPage()
  if (page !== currentPage) {
    currentPage = page
    emit('pagechange', page)
  }
}

watch(
  () => props.zoom,
  () => {
    if (currentData) loadPdf(currentData)
  }
)

onMounted(() => {
  document.addEventListener('mousedown', onDocMouseDown)
  document.addEventListener('mousemove', onDocMouseMove)
  document.addEventListener('mouseup', onDocMouseUp)
  scrollContainer.value?.addEventListener('scroll', onScroll, { passive: true })
  scrollContainer.value?.addEventListener('pointerdown', onPointerDown)
  document.addEventListener('pointermove', onPointerMove)
  document.addEventListener('pointerup', onPointerUp)
})
onBeforeUnmount(() => {
  document.removeEventListener('mousedown', onDocMouseDown)
  document.removeEventListener('mousemove', onDocMouseMove)
  document.removeEventListener('mouseup', onDocMouseUp)
  scrollContainer.value?.removeEventListener('scroll', onScroll)
  scrollContainer.value?.removeEventListener('pointerdown', onPointerDown)
  document.removeEventListener('pointermove', onPointerMove)
  document.removeEventListener('pointerup', onPointerUp)
  renderTask?.cancel()
})

defineExpose({ openData, goToPage, undoPage, clearPage })
</script>

<template>
  <div
    ref="scrollContainer"
    class="min-h-0 flex-1 overflow-auto bg-zinc-950 p-4"
    :class="{ 'cursor-crosshair': tool && tool !== 'select' }"
    @dragstart.prevent
  >
    <div v-if="loading" class="mt-10 text-center text-sm text-zinc-500">Carregando PDF…</div>
    <div v-else-if="error" class="mt-10 text-center text-sm text-red-400">{{ error }}</div>
    <div ref="container" class="pages"></div>
  </div>
</template>

<style scoped>
.pages {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: fit-content;
  min-width: 100%;
}

:deep(.pdf-page) {
  position: relative;
  margin: 0 auto;
  flex-shrink: 0;
  background: #fff;
  box-shadow: 0 2px 12px rgb(0 0 0 / 0.4);
}

:deep(.pdf-page canvas) {
  user-select: none;
  -webkit-user-select: none;
}

:deep(.textLayer) {
  position: absolute;
  inset: 0;
  overflow: hidden;
  line-height: 1;
}

:deep(.textLayer ::selection) {
  background: rgb(59 130 246 / 0.4);
}

:deep(.anno-layer) {
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
}
</style>
