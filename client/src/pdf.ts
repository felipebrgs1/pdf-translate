import * as pdfjsLib from 'pdfjs-dist'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'

pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl

export interface OutlineItem {
  title: string
  page: number
  depth: number
}

export interface SelectionRect {
  top: number
  bottom: number
  left: number
  right: number
  width: number
  height: number
}

const THUMB_WIDTH = 480

export async function makeThumbnail(data: ArrayBuffer): Promise<Blob | null> {
  try {
    const pdf = await pdfjsLib.getDocument({ data }).promise
    const page = await pdf.getPage(1)
    const base = page.getViewport({ scale: 1 })
    const viewport = page.getViewport({ scale: THUMB_WIDTH / base.width })

    const canvas = document.createElement('canvas')
    canvas.width = Math.floor(viewport.width)
    canvas.height = Math.floor(viewport.height)
    const ctx = canvas.getContext('2d')!
    ctx.fillStyle = '#fff'
    ctx.fillRect(0, 0, canvas.width, canvas.height)

    await page.render({ canvasContext: ctx, viewport }).promise

    return await new Promise((resolve) => canvas.toBlob(resolve, 'image/webp', 0.82))
  } catch {
    return null
  }
}
