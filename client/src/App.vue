<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, type Book } from './api'
import LibraryView from './components/LibraryView.vue'
import LoginView from './components/LoginView.vue'
import ReaderView from './components/ReaderView.vue'

type View = 'checking' | 'login' | 'library' | 'reader'

const view = ref<View>('checking')
const userEmail = ref('')
const currentBook = ref<Book | null>(null)

onMounted(async () => {
  try {
    const me = await api.me()
    userEmail.value = me.email
    view.value = 'library'
  } catch {
    view.value = 'login'
  }
})

function onLogin(email: string) {
  userEmail.value = email
  view.value = 'library'
}

function onLogout() {
  userEmail.value = ''
  currentBook.value = null
  view.value = 'login'
}

function openBook(book: Book) {
  currentBook.value = book
  view.value = 'reader'
}
</script>

<template>
  <div v-if="view === 'checking'" class="flex flex-1 items-center justify-center bg-black">
    <span class="text-sm text-zinc-500">Carregando…</span>
  </div>

  <LoginView v-else-if="view === 'login'" @success="onLogin" />

  <LibraryView
    v-else-if="view === 'library'"
    :user-email="userEmail"
    @open="openBook"
    @logout="onLogout"
  />

  <ReaderView v-else-if="currentBook" :book="currentBook" @back="view = 'library'" />
</template>
