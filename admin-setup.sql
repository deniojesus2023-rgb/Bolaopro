-- ================================================================
-- BolãoPro — Admin Setup
-- Execute no SQL Editor do Supabase para configurar o painel admin
-- supabase.com → SQL Editor → New Query → Cole → Run
-- ================================================================

-- ── 1. PROMOVER USUÁRIO A ADMIN ───────────────────────────────
-- Substitua 'seu_username' pelo username do administrador
UPDATE public.profiles
SET plan = 'admin'
WHERE username = 'seu_username';

-- Verificar se foi aplicado:
-- SELECT id, username, plan FROM public.profiles WHERE plan = 'admin';

-- ── 2. REVOGAR ADMIN ──────────────────────────────────────────
-- Para remover privilégios de admin:
-- UPDATE public.profiles SET plan = 'free' WHERE username = 'seu_username';

-- ── 3. BANIR USUÁRIO ──────────────────────────────────────────
-- Para banir um usuário via SQL (o painel faz isso automaticamente):
-- UPDATE public.profiles SET plan = 'banned' WHERE username = 'usuario_banido';

-- ── 4. TABELA DE CONFIGURAÇÕES GLOBAIS (OPCIONAL) ─────────────
-- Se quiser persistir configs no banco em vez de localStorage:
CREATE TABLE IF NOT EXISTS public.app_config (
  key   text primary key,
  value text not null,
  updated_at timestamptz default now()
);

-- Inserir valores padrão
INSERT INTO public.app_config (key, value) VALUES
  ('platform_fee_pct',      '5'),
  ('pts_result',            '3'),
  ('pts_exact_score',       '8'),
  ('pts_top_scorer',        '5'),
  ('pts_bonus_upset',       '5'),
  ('pts_bonus_perfect',     '20'),
  ('max_participants',      '50'),
  ('min_hours_before_match','24'),
  ('maintenance_mode',      'false'),
  ('affiliate_sportingbet', 'true'),
  ('affiliate_superbet',    'true')
ON CONFLICT (key) DO NOTHING;

-- RLS: apenas admins podem ler/escrever
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins_can_read_config"
ON public.app_config FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND plan = 'admin'
  )
);

CREATE POLICY "admins_can_update_config"
ON public.app_config FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND plan = 'admin'
  )
);

-- ── 5. ADICIONAR COLUNA is_banned A PROFILES (ALTERNATIVA) ────
-- Se preferir usar is_banned em vez de plan='banned':
-- ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_banned boolean default false;
-- ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_admin  boolean default false;

-- ── 6. VERIFICAÇÕES ÚTEIS ─────────────────────────────────────

-- Ver todos os admins:
-- SELECT username, full_name, plan, created_at FROM public.profiles WHERE plan = 'admin';

-- Ver usuários banidos:
-- SELECT username, full_name, plan FROM public.profiles WHERE plan = 'banned';

-- Estatísticas gerais:
-- SELECT
--   COUNT(*) FILTER (WHERE plan = 'free')    AS usuarios_free,
--   COUNT(*) FILTER (WHERE plan = 'admin')   AS admins,
--   COUNT(*) FILTER (WHERE plan = 'banned')  AS banidos,
--   COUNT(*) AS total
-- FROM public.profiles;

-- Receita da plataforma:
-- SELECT SUM(platform_earned) as receita_total FROM public.boloes WHERE is_paid_out = true;

-- ── FIM ───────────────────────────────────────────────────────
