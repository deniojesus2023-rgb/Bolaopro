// ── CONFIG ────────────────────────────────────────────────────────
// Substitua pelos seus dados do Supabase
const SUPABASE_URL = 'https://SEU_PROJETO.supabase.co'
const SUPABASE_ANON_KEY = 'SUA_ANON_KEY'

// Link de afiliado da Superbet (substitua pelo seu)
const SUPERBET_AFFILIATE_URL = 'https://superbet.com.br/?ref=SEU_CODIGO_AFILIADO'

// Valor mínimo de depósito exigido (em R$)
const DEPOSITO_MINIMO = 20

// ── SUPABASE CLIENT ───────────────────────────────────────────────
const _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
const sb = () => _sb

// ── AUTH HELPERS ──────────────────────────────────────────────────
async function getUser() {
  const { data: { user } } = await _sb.auth.getUser()
  return user
}

async function getProfile(userId) {
  const { data } = await _sb.from('profiles').select('*').eq('id', userId).single()
  return data
}

async function signOut() {
  await _sb.auth.signOut()
  window.location.href = 'index.html'
}

// Redireciona para login se não autenticado
async function requireAuth() {
  const user = await getUser()
  if (!user) { window.location.href = 'auth.html'; return null }
  return user
}

// Verifica se usuário já depositou
async function requireDeposit(user) {
  const profile = await getProfile(user.id)
  if (!profile?.deposit_verified) {
    window.location.href = 'deposito.html'
    return null
  }
  return profile
}

// ── DOM HELPERS ───────────────────────────────────────────────────
const $  = id => document.getElementById(id)
const setEl = (id, html) => { const e = $(id); if(e) e.innerHTML = html }
const showEl = id => { const e = $(id); if(e) e.style.display = '' }
const hideEl = id => { const e = $(id); if(e) e.style.display = 'none' }
const setText = (id, txt) => { const e = $(id); if(e) e.textContent = txt }

// ── FORMAT HELPERS ────────────────────────────────────────────────
const fmtBRL = v => 'R$ ' + Number(v ?? 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const fmtDate = d => d ? new Date(d).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) : '—'
const fmtDateTime = d => d ? new Date(d).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—'

function timeLeft(deadline) {
  const diff = new Date(deadline) - new Date()
  if (diff <= 0) return 'Encerrado'
  const h = Math.floor(diff / 3600000)
  const m = Math.floor((diff % 3600000) / 60000)
  if (h > 48) return `${Math.floor(h/24)} dias`
  if (h > 0) return `${h}h ${m}m`
  return `${m} minutos`
}

// ── TOAST ─────────────────────────────────────────────────────────
function toast(msg, type = 'success') {
  let el = document.getElementById('_toast')
  if (!el) {
    el = document.createElement('div')
    el.id = '_toast'
    el.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(100px);background:#1F2937;color:#fff;padding:12px 20px;border-radius:10px;font-size:13px;font-weight:500;z-index:9999;transition:transform .3s;max-width:320px;text-align:center;'
    document.body.appendChild(el)
  }
  el.textContent = msg
  el.style.borderLeft = type === 'error' ? '3px solid #EF4444' : '3px solid #00E676'
  el.style.transform = 'translateX(-50%) translateY(0)'
  setTimeout(() => { el.style.transform = 'translateX(-50%) translateY(100px)' }, 3000)
}
