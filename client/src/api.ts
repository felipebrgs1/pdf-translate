export interface BookProgress {
  page: number
  totalPages: number
  percent: number
  updatedAt: string
}

export interface DayStats {
  pages: number
  minutes: number
  highlights: number
}

export interface Book {
  key: string
  name: string
  size: number
  uploaded: string
  progress?: BookProgress | null
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, init)
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data as { error?: string }).error ?? 'request failed')
  return data as T
}

export const api = {
  me: () => request<{ email: string }>('/api/me'),
  login: (email: string, password: string) =>
    request<{ ok: true }>('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    }),
  logout: () => request<{ ok: true }>('/api/logout', { method: 'POST' }),
  listBooks: () => request<Book[]>('/api/books'),
  getProgress: (key: string) => request<BookProgress>(`/api/progress/${key}`),
  saveProgress: (key: string, page: number, totalPages: number) =>
    request<BookProgress>(`/api/progress/${key}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ page, totalPages })
    }),
  uploadBook: (file: File) =>
    request<Book>('/api/books', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/pdf',
        'x-file-name': encodeURIComponent(file.name.replace(/\.pdf$/i, ''))
      },
      body: file
    }),
  deleteBook: (key: string) => request<{ ok: true }>(`/api/books/${key}`, { method: 'DELETE' }),
  getStats: () => request<{ days: Record<string, DayStats> }>('/api/stats'),
  addStats: (delta: { date: string; pages?: number; minutes?: number; highlights?: number }) =>
    request<DayStats>('/api/stats', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(delta)
    }),
  uploadThumb: (bookKey: string, thumb: Blob) =>
    request<{ ok: true }>('/api/thumbs', {
      method: 'POST',
      headers: { 'Content-Type': 'image/webp', 'x-book-key': bookKey },
      body: thumb
    })
}
