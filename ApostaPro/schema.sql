-- ================================================================
-- APOSTAPRO — Schema do Banco de Dados
-- Execute no Supabase → SQL Editor → New Query → Run
-- Idempotente: pode rodar múltiplas vezes sem erro
-- ================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ================================================================
-- TABELA: profiles
-- ================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id                UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username          TEXT        NOT NULL,
  email             TEXT,
  deposit_verified  BOOLEAN     DEFAULT false,
  deposited_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON COLUMN public.profiles.deposit_verified IS
  'TRUE quando o usuário confirmou o depósito na Superbet';

-- ================================================================
-- TABELA: boloes
-- ================================================================
CREATE TABLE IF NOT EXISTS public.boloes (
  id                  UUID          DEFAULT uuid_generate_v4() PRIMARY KEY,
  name                TEXT          NOT NULL,
  description         TEXT,
  prize               DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (prize >= 0),
  status              TEXT          DEFAULT 'aberto'
                                      CHECK (status IN ('aberto','em_andamento','finalizado','cancelado')),
  deadline            TIMESTAMPTZ   NOT NULL,
  max_participants    INTEGER       DEFAULT 100 CHECK (max_participants >= 2),
  participant_count   INTEGER       DEFAULT 0,
  winner_user_id      UUID          REFERENCES public.profiles(id),
  created_at          TIMESTAMPTZ   DEFAULT NOW()
);

COMMENT ON COLUMN public.boloes.deadline IS 'Prazo final para enviar palpites';
COMMENT ON COLUMN public.boloes.prize IS 'Valor do prêmio em R$';

-- ================================================================
-- TABELA: bolao_matches (jogos de cada bolão)
-- ================================================================
CREATE TABLE IF NOT EXISTS public.bolao_matches (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  bolao_id     UUID        NOT NULL REFERENCES public.boloes(id) ON DELETE CASCADE,
  home_team    TEXT        NOT NULL,
  away_team    TEXT        NOT NULL,
  match_date   TIMESTAMPTZ NOT NULL,
  home_score   INTEGER,    -- preenchido após o jogo
  away_score   INTEGER,    -- preenchido após o jogo
  finished     BOOLEAN     DEFAULT false,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- TABELA: bolao_participants (quem entrou em cada bolão)
-- ================================================================
CREATE TABLE IF NOT EXISTS public.bolao_participants (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  bolao_id     UUID        NOT NULL REFERENCES public.boloes(id) ON DELETE CASCADE,
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pontuacao    INTEGER     DEFAULT 0,
  posicao      INTEGER,
  joined_at    TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT bolao_participants_unique UNIQUE (bolao_id, user_id)
);

-- ================================================================
-- TABELA: predictions (palpites)
-- ================================================================
CREATE TABLE IF NOT EXISTS public.predictions (
  id             UUID    DEFAULT uuid_generate_v4() PRIMARY KEY,
  participant_id UUID    NOT NULL REFERENCES public.bolao_participants(id) ON DELETE CASCADE,
  bolao_id       UUID    NOT NULL REFERENCES public.boloes(id) ON DELETE CASCADE,
  match_id       UUID    NOT NULL REFERENCES public.bolao_matches(id) ON DELETE CASCADE,
  home_score     INTEGER NOT NULL DEFAULT 0,
  away_score     INTEGER NOT NULL DEFAULT 0,
  pontos_ganhos  INTEGER DEFAULT 0,
  created_at     TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT predictions_unique UNIQUE (participant_id, match_id)
);

-- ================================================================
-- TABELA: deposit_clicks (tracking de cliques no link afiliado)
-- ================================================================
CREATE TABLE IF NOT EXISTS public.deposit_clicks (
  id         UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  clicked_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- TABELA: deposit_conversions (usuários que confirmaram depósito)
-- ================================================================
CREATE TABLE IF NOT EXISTS public.deposit_conversions (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  verified_at  TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT deposit_conversions_user_unique UNIQUE (user_id)
);

-- ================================================================
-- INDEXES
-- ================================================================
CREATE INDEX IF NOT EXISTS idx_profiles_deposit    ON public.profiles(deposit_verified);
CREATE INDEX IF NOT EXISTS idx_boloes_status        ON public.boloes(status);
CREATE INDEX IF NOT EXISTS idx_boloes_deadline      ON public.boloes(deadline);
CREATE INDEX IF NOT EXISTS idx_bolao_matches_bolao  ON public.bolao_matches(bolao_id);
CREATE INDEX IF NOT EXISTS idx_participants_bolao   ON public.bolao_participants(bolao_id);
CREATE INDEX IF NOT EXISTS idx_participants_user    ON public.bolao_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_predictions_part     ON public.predictions(participant_id);
CREATE INDEX IF NOT EXISTS idx_predictions_match    ON public.predictions(match_id);
CREATE INDEX IF NOT EXISTS idx_clicks_user          ON public.deposit_clicks(user_id);
CREATE INDEX IF NOT EXISTS idx_clicks_date          ON public.deposit_clicks(clicked_at DESC);

-- ================================================================
-- ROW LEVEL SECURITY
-- ================================================================
ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.boloes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bolao_matches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bolao_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predictions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_clicks     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_conversions ENABLE ROW LEVEL SECURITY;

-- profiles: usuário lê/atualiza o próprio perfil
DROP POLICY IF EXISTS "profiles_select_own"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"  ON public.profiles;

CREATE POLICY "profiles_select_own"  ON public.profiles FOR SELECT  USING (auth.uid() = id);
CREATE POLICY "profiles_insert_own"  ON public.profiles FOR INSERT  WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update_own"  ON public.profiles FOR UPDATE  USING (auth.uid() = id);

-- boloes: leitura pública
DROP POLICY IF EXISTS "boloes_select_public" ON public.boloes;
CREATE POLICY "boloes_select_public" ON public.boloes FOR SELECT USING (true);

-- bolao_matches: leitura pública
DROP POLICY IF EXISTS "matches_select_public" ON public.bolao_matches;
CREATE POLICY "matches_select_public" ON public.bolao_matches FOR SELECT USING (true);

-- bolao_participants: leitura pública | insert/update próprio
DROP POLICY IF EXISTS "participants_select_public" ON public.bolao_participants;
DROP POLICY IF EXISTS "participants_insert_own"    ON public.bolao_participants;
DROP POLICY IF EXISTS "participants_update_own"    ON public.bolao_participants;

CREATE POLICY "participants_select_public" ON public.bolao_participants FOR SELECT USING (true);
CREATE POLICY "participants_insert_own"    ON public.bolao_participants FOR INSERT  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "participants_update_own"    ON public.bolao_participants FOR UPDATE  USING (auth.uid() = user_id);

-- predictions: acesso pelo próprio participante
DROP POLICY IF EXISTS "predictions_own" ON public.predictions;
DROP POLICY IF EXISTS "predictions_insert_own" ON public.predictions;
DROP POLICY IF EXISTS "predictions_upsert_own" ON public.predictions;

CREATE POLICY "predictions_own" ON public.predictions FOR SELECT
  USING (EXISTS (SELECT 1 FROM bolao_participants bp WHERE bp.id = participant_id AND bp.user_id = auth.uid()));

CREATE POLICY "predictions_insert_own" ON public.predictions FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM bolao_participants bp WHERE bp.id = participant_id AND bp.user_id = auth.uid()));

CREATE POLICY "predictions_upsert_own" ON public.predictions FOR UPDATE
  USING (EXISTS (SELECT 1 FROM bolao_participants bp WHERE bp.id = participant_id AND bp.user_id = auth.uid()));

-- deposit_clicks: apenas o próprio usuário insere
DROP POLICY IF EXISTS "clicks_insert_own" ON public.deposit_clicks;
CREATE POLICY "clicks_insert_own" ON public.deposit_clicks FOR INSERT WITH CHECK (auth.uid() = user_id);

-- deposit_conversions: usuário lê/insere o próprio
DROP POLICY IF EXISTS "conversions_own" ON public.deposit_conversions;
DROP POLICY IF EXISTS "conversions_insert_own" ON public.deposit_conversions;

CREATE POLICY "conversions_own"        ON public.deposit_conversions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "conversions_insert_own" ON public.deposit_conversions FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ================================================================
-- FUNÇÃO: calcular_pontuacao
-- Chamada após inserir resultado de um jogo
-- Regra: placar exato = 3 pts | acertou o vencedor = 1 pt
-- ================================================================
CREATE OR REPLACE FUNCTION public.calcular_pontuacao(p_match_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match  bolao_matches%ROWTYPE;
  r        RECORD;
  pts      INTEGER;
BEGIN
  SELECT * INTO v_match FROM bolao_matches WHERE id = p_match_id;
  IF NOT FOUND OR NOT v_match.finished THEN RETURN; END IF;

  FOR r IN (SELECT * FROM predictions WHERE match_id = p_match_id) LOOP
    -- Placar exato: 3 pts
    IF r.home_score = v_match.home_score AND r.away_score = v_match.away_score THEN
      pts := 3;
    -- Acertou o vencedor/empate: 1 pt
    ELSIF
      (r.home_score > r.away_score AND v_match.home_score > v_match.away_score) OR
      (r.home_score < r.away_score AND v_match.home_score < v_match.away_score) OR
      (r.home_score = r.away_score AND v_match.home_score = v_match.away_score)
    THEN
      pts := 1;
    ELSE
      pts := 0;
    END IF;

    UPDATE predictions SET pontos_ganhos = pts WHERE id = r.id;
  END LOOP;

  -- Recalcula pontuação total de cada participante do bolão
  UPDATE bolao_participants bp
  SET pontuacao = COALESCE((
    SELECT SUM(p.pontos_ganhos) FROM predictions p WHERE p.participant_id = bp.id
  ), 0)
  WHERE bp.bolao_id = v_match.bolao_id;

END;
$$;

COMMENT ON FUNCTION public.calcular_pontuacao(UUID) IS
  'Calcula pontos dos palpites após resultado de um jogo. Exato=3pts, Vencedor=1pt.';

-- ================================================================
-- DADOS DE EXEMPLO (opcional — remova se não quiser)
-- ================================================================
/*
INSERT INTO public.boloes (name, description, prize, deadline, max_participants, status)
VALUES
  ('Brasileirão — Rodada 15', 'Palpite nos 8 jogos da rodada 15 do Brasileirão Série A', 500, NOW() + INTERVAL '3 days', 100, 'aberto'),
  ('Copa do Brasil — Quartas', 'Semifinais da Copa do Brasil 2024', 300, NOW() + INTERVAL '5 days', 50, 'aberto'),
  ('Champions League', 'Semifinais da UEFA Champions League', 1000, NOW() + INTERVAL '7 days', 200, 'aberto')
ON CONFLICT DO NOTHING;
*/

-- ================================================================
-- FIM DO SCHEMA
-- Tabelas: profiles, boloes, bolao_matches, bolao_participants,
--          predictions, deposit_clicks, deposit_conversions
-- Funções: calcular_pontuacao(match_id)
-- ================================================================
