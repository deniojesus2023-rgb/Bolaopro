-- ============================================================
-- FIX: Habilitar RLS nas tabelas públicas matches e competitions
-- Executar no Supabase SQL Editor
-- ============================================================

-- 1. Habilitar RLS
ALTER TABLE public.matches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitions ENABLE ROW LEVEL SECURITY;

-- 2. Policy de SELECT público (leitura para todos)
CREATE POLICY "matches_select_all"
  ON public.matches
  FOR SELECT
  USING (true);

CREATE POLICY "competitions_select_all"
  ON public.competitions
  FOR SELECT
  USING (true);

-- 3. Bloquear INSERT/UPDATE/DELETE de usuários não-service
-- (A Edge Function usa SERVICE_ROLE_KEY e bypassa RLS automaticamente)

-- Verificação após execução:
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('matches', 'competitions')
ORDER BY tablename, policyname;
