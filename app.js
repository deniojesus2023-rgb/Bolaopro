// ============================================================
// BolãoPro — app.js
// Funções globais: Supabase, auth, utils
// ============================================================

// ── Supabase client ──────────────────────────────────────────
function sb() {
  if (!window._sb) {
    window._sb = window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY)
  }
  return window._sb
}

// ── Auth ─────────────────────────────────────────────────────
async function getUser() {
  try {
    const { data: { session } } = await sb().auth.getSession()
    return session?.user ?? null
  } catch { return null }
}

async function getProfile(userId) {
  const { data } = await sb().from('profiles').select('*').eq('id', userId).single()
  return data
}

async function initAuth(opts = {}) {
  const user = await getUser()
  if (!user && opts.requireAuth) { location.href = 'login.html'; return null }
  if (user) {
    const p = await getProfile(user.id)
    const name = p?.username ?? user.email?.split('@')[0] ?? '?'
    const av   = name.slice(0, 2).toUpperCase()
    // Sidebar desktop
    setEl('sideAv',    av)
    setEl('sideName',  name)
    setEl('sideEmail', user.email ?? '')
    showEl('userCard'); hideEl('sideLogin')
    // Drawer
    setEl('drawerAv',   av)
    setEl('drawerName', name)
    showEl('drawerUserCard'); hideEl('drawerLogin')
    showEl('drawerLogout')
    if (p?.plan === 'admin') { showEl('sideAdmin'); showEl('drawerAdmin'); showEl('topAdminBtn') }
    // Topbar
    hideEl('topLoginBtn')
    showEl('topUserBtn')
    setEl('topUserAv', av)
  }
  return user
}

async function signOut() {
  await sb().auth.signOut()
  location.href = 'login.html'
}

// ── Bolões ───────────────────────────────────────────────────
async function getBoloes(filter = '') {
  let q = sb().from('boloes')
    .select('*, owner:profiles!owner_id(username), participants(count)')
    .order('created_at', { ascending: false })
    .limit(20)
  if (filter) q = q.eq('status', filter)
  const { data } = await q
  return data ?? []
}

async function getBolao(id) {
  const { data } = await sb().from('boloes')
    .select(`*, owner:profiles!owner_id(username,avatar_url),
      participants(*, profile:profiles(username)),
      bolao_matches(match:matches(*)),
      predictions(user_id, predicted_result)`)
    .eq('id', id).single()
  return data
}

async function criarBolao(dados, userId) {
  if (!dados.nome?.trim()) return { error: 'Nome do bolão é obrigatório.' }
  if (!dados.cota || dados.cota < 5) return { error: 'Cota mínima: R$ 5,00.' }
  if (!dados.max || dados.max < 2) return { error: 'Mínimo de 2 participantes.' }
  if (dados.deadline && new Date(dados.deadline) < new Date()) return { error: 'Prazo deve ser uma data futura.' }
  const { data, error } = await sb().from('boloes').insert({
    owner_id: userId, name: dados.nome.trim(),
    cota_value: dados.cota, max_participants: dados.max,
    prize_split: dados.split, deadline: dados.deadline || null,
    competicao: dados.competicao, status: 'open',
  }).select('id, code').single()
  if (error) return { error: error.message }
  const paymentStatus = dados.cota > 0 ? 'pending' : 'paid'
  const { error: partErr } = await sb().from('participants').insert({ bolao_id: data.id, user_id: userId, payment_status: paymentStatus, amount_paid: 0 })
  if (partErr) console.error('Erro ao inserir participante criador:', partErr)
  return { data }
}

async function salvarPalpite(bolaoId, matchId, userId, result, homeScore, awayScore, topScorer) {
  const { error } = await sb().from('predictions').upsert({
    bolao_id: bolaoId, match_id: matchId, user_id: userId,
    predicted_result: result,
    predicted_home_score: homeScore ? parseInt(homeScore) : null,
    predicted_away_score: awayScore ? parseInt(awayScore) : null,
    predicted_top_scorer: topScorer || null,
  }, { onConflict: 'bolao_id,match_id,user_id' })
  if (!error && navigator.vibrate) navigator.vibrate(50)
  return !error
}

async function getRanking(limit = 50) {
  const { data } = await sb().from('global_ranking').select('*').limit(limit)
  return data ?? []
}

async function getMeusBoloes(userId) {
  const { data } = await sb().from('participants')
    .select('bolao_id, boloes(*, participants(count))')
    .eq('user_id', userId).order('joined_at', { ascending: false })
  return data ?? []
}

// ── Afiliados ────────────────────────────────────────────────
async function trackAffiliateClick(userId, partner, matchId = null, bolaoId = null) {
  if (!userId) return
  await sb().from('affiliate_clicks').insert({
    user_id: userId,
    partner,
    match_id: matchId || null,
    bolao_id: bolaoId || null,
    source: document.referrer || 'direct',
  })
}

// ── Comunidade ───────────────────────────────────────────────
async function getPosts(limit = 20) {
  const { data, error } = await sb().from('posts')
    .select('*')
    .order('created_at', { ascending: false }).limit(limit)
  if (error) { console.error('getPosts error:', error); return [] }
  if (!data || !data.length) return []
  // Fetch author usernames separately (avoids FK join issues)
  const userIds = [...new Set(data.map(p => p.user_id).filter(Boolean))]
  let profileMap = {}
  if (userIds.length) {
    const { data: profs } = await sb().from('profiles').select('id,username').in('id', userIds)
    ;(profs ?? []).forEach(p => { profileMap[p.id] = p })
  }
  // Fetch like counts
  const postIds = data.map(p => p.id)
  let likeMap = {}, replyMap = {}
  if (postIds.length) {
    const { data: lks } = await sb().from('post_likes').select('post_id').in('post_id', postIds)
    ;(lks ?? []).forEach(l => { likeMap[l.post_id] = (likeMap[l.post_id] ?? 0) + 1 })
    const { data: rps } = await sb().from('post_replies').select('post_id').in('post_id', postIds)
    ;(rps ?? []).forEach(r => { replyMap[r.post_id] = (replyMap[r.post_id] ?? 0) + 1 })
  }
  return data.map(p => ({
    ...p,
    author: profileMap[p.user_id] ?? null,
    likes_count: likeMap[p.id] ?? 0,
    replies_count: replyMap[p.id] ?? 0,
  }))
}

async function publishPost(userId, content, type, bolaoId) {
  const { error } = await sb().from('posts').insert({
    user_id: userId, content, type, bolao_id: bolaoId || null,
  })
  return !error
}

async function getConversations(userId) {
  const { data } = await sb().from('conversations')
    .select('*, ua:profiles!user_a(id,username), ub:profiles!user_b(id,username)')
    .or(`user_a.eq.${userId},user_b.eq.${userId}`)
    .eq('invite_status', 'accepted')
    .order('last_message_at', { ascending: false })
  return data ?? []
}

async function getMessages(convId, limit = 50) {
  const { data } = await sb().from('messages')
    .select('*, sender:profiles!sender_id(username)')
    .eq('conversation_id', convId)
    .order('created_at', { ascending: true }).limit(limit)
  return data ?? []
}

async function sendMessage(convId, senderId, content, type = 'text', bolaoId = null) {
  const { error } = await sb().from('messages').insert({
    conversation_id: convId, sender_id: senderId,
    content, type, bolao_id: bolaoId || null,
  })
  return !error
}

async function getOrCreateConv(userA, userB) {
  const { data } = await sb().rpc('get_or_create_conversation', { p_user_a: userA, p_user_b: userB })
  return data
}

async function getGroupChat(bolaoId, limit = 50) {
  const { data } = await sb().from('bolao_chat')
    .select('*, sender:profiles!user_id(username)')
    .eq('bolao_id', bolaoId)
    .order('created_at', { ascending: true }).limit(limit)
  return data ?? []
}

async function sendGroupMsg(bolaoId, userId, content) {
  const { error } = await sb().from('bolao_chat').insert({
    bolao_id: bolaoId, user_id: userId, content,
  })
  return !error
}

// ── UI Helpers ───────────────────────────────────────────────
function setEl(id, val) { const e = document.getElementById(id); if (e) e.textContent = val }
function showEl(id) { const e = document.getElementById(id); if (e) e.style.display = '' }
function hideEl(id) { const e = document.getElementById(id); if (e) e.style.display = 'none' }

function showToast(msg, dur = 2600) {
  if (navigator.vibrate) navigator.vibrate(10)
  let t = document.getElementById('toast')
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'toast'; document.body.appendChild(t) }
  t.textContent = msg; t.classList.add('on')
  clearTimeout(t._t); t._t = setTimeout(() => t.classList.remove('on'), dur)
}

function openModal(id) {
  const e = document.getElementById(id)
  if (e) { e.classList.add('on'); document.body.style.overflow = 'hidden' }
}
function closeModal(id) {
  const e = document.getElementById(id)
  if (e) { e.classList.remove('on'); document.body.style.overflow = '' }
}
function ovlClose(e, id) { if (e.target === document.getElementById(id)) closeModal(id) }

function openDrawer() {
  document.getElementById('drawer')?.classList.add('on')
  document.getElementById('drawerOvl')?.classList.add('on')
  document.body.style.overflow = 'hidden'
}
function closeDrawer() {
  document.getElementById('drawer')?.classList.remove('on')
  document.getElementById('drawerOvl')?.classList.remove('on')
  document.body.style.overflow = ''
}

function fmtMoney(v) {
  return 'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 0 })
}
function fmtDate(s) {
  if (!s) return '—'
  return new Date(s).toLocaleString('pt-BR', { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' })
}
function timeAgo(s) {
  if (!s) return ''
  const d = Date.now() - new Date(s).getTime()
  const m = Math.floor(d / 60000), h = Math.floor(d / 3600000), dy = Math.floor(d / 86400000)
  if (m < 1) return 'agora'; if (m < 60) return `${m}min`; if (h < 24) return `${h}h`; return `${dy}d`
}
function esc(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/\n/g,'<br>')
}
function stLabel(s) { return {open:'Aberto',active:'Ao Vivo',finished:'Finalizado',cancelled:'Cancelado'}[s] ?? s }
function stClass(s)  { return {open:'st-open',active:'st-live',finished:'st-done',cancelled:'st-done'}[s] ?? 'st-done' }
function stDot(s)    { return {open:'dot-open',active:'dot-live',finished:'dot-done',cancelled:'dot-done'}[s] ?? 'dot-done' }

// ── NOTIF BADGE ──────────────────────────────────────────────
async function carregarNotifBadge() {
  const user = await getUser()
  if (!user) return
  const { count } = await sb().from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('is_read', false)
  const badge = document.getElementById('notifBadge')
  if (badge) {
    if (count > 0) {
      badge.textContent = count > 9 ? '9+' : count
      badge.style.display = 'flex'
    } else {
      badge.style.display = 'none'
    }
  }
}
let _notifChannel = null
async function subscribeNotifBadge() {
  const user = await getUser()
  if (!user || _notifChannel) return
  _notifChannel = sb().channel('notif_badge_' + user.id)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${user.id}` }, () => {
      carregarNotifBadge()
    })
    .subscribe()
}
function abrirNotifs() { location.href = 'configuracoes.html#notificacoes' }

// ── LUCIDE ICONS ─────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  if (window.lucide) lucide.createIcons()
  carregarNotifBadge()
  subscribeNotifBadge()
})

// ── CONECTIVIDADE ────────────────────────────────────────────
window.addEventListener('offline', () => {
  if (navigator.vibrate) navigator.vibrate([50, 30, 50])
  showToast('⚠️ Sem conexão — algumas funções indisponíveis', 5000)
})
window.addEventListener('online', () => {
  showToast('✅ Conexão restaurada')
})
