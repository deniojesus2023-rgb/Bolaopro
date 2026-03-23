-- ================================================================
-- BOLÃOPRO — Desafios com Influenciadores
-- Schema completo para o sistema de challenges
--
-- Como usar:
--   Supabase → SQL Editor → New Query → Cole → Run
--
-- Este arquivo é idempotente: pode ser executado múltiplas vezes
-- sem causar erros (usa IF NOT EXISTS em todas as definições).
-- ================================================================

-- Extensão UUID (já deve existir, mas garantindo)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ================================================================
-- SEÇÃO 1 — ALTER TABLE profiles
-- Adiciona coluna de saldo à tabela existente
-- ================================================================

-- Adiciona coluna saldo se ainda não existir
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'profiles'
      AND column_name  = 'saldo'
  ) THEN
    ALTER TABLE public.profiles
      ADD COLUMN saldo DECIMAL(10,2) DEFAULT 0;
  END IF;
END;
$$;

COMMENT ON COLUMN public.profiles.saldo IS
  'Saldo disponível do usuário para entrar em desafios (em R$)';


-- ================================================================
-- SEÇÃO 2 — TABELA influencer_profiles
-- Perfil estendido para influenciadores que criam desafios
-- ================================================================

CREATE TABLE IF NOT EXISTS public.influencer_profiles (
  id                UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id           UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  bio               TEXT,
  instagram_handle  TEXT,
  verified          BOOLEAN     DEFAULT false,
  total_challenges  INTEGER     DEFAULT 0,
  total_earned      DECIMAL(10,2) DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT influencer_profiles_user_id_unique UNIQUE (user_id)
);

COMMENT ON TABLE public.influencer_profiles IS
  'Perfis de influenciadores que podem criar e participar de desafios pagos';
COMMENT ON COLUMN public.influencer_profiles.verified IS
  'Indica se o influenciador foi verificado pela equipe BolãoPro';
COMMENT ON COLUMN public.influencer_profiles.total_challenges IS
  'Contador denormalizado do total de desafios criados pelo influenciador';
COMMENT ON COLUMN public.influencer_profiles.total_earned IS
  'Total acumulado de comissões recebidas pelo influenciador (em R$)';


-- ================================================================
-- SEÇÃO 3 — TABELA wallet_transactions
-- Histórico completo de movimentações da carteira de cada usuário
-- ================================================================

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tipo         TEXT        NOT NULL
                             CHECK (tipo IN (
                               'entrada_desafio',
                               'premio',
                               'comissao_influencer',
                               'taxa_plataforma',
                               'deposito',
                               'saque'
                             )),
  valor        DECIMAL(10,2) NOT NULL,
  descricao    TEXT,
  challenge_id UUID,       -- nullable: nem toda transação está ligada a um desafio
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE public.wallet_transactions IS
  'Histórico de todas as movimentações financeiras da carteira do usuário';
COMMENT ON COLUMN public.wallet_transactions.tipo IS
  'Tipo da transação: entrada_desafio | premio | comissao_influencer | taxa_plataforma | deposito | saque';
COMMENT ON COLUMN public.wallet_transactions.valor IS
  'Valor da movimentação em R$ (positivo = crédito, negativo = débito)';
COMMENT ON COLUMN public.wallet_transactions.challenge_id IS
  'Referência ao desafio relacionado (nullable)';


-- ================================================================
-- SEÇÃO 4 — TABELA challenges
-- Desafios criados por influenciadores
-- ================================================================

CREATE TABLE IF NOT EXISTS public.challenges (
  id                    UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  nome                  TEXT        NOT NULL,
  descricao             TEXT,
  influencer_id         UUID        NOT NULL REFERENCES public.influencer_profiles(id) ON DELETE RESTRICT,
  valor_entrada         DECIMAL(10,2) NOT NULL CHECK (valor_entrada >= 0),
  premio                DECIMAL(10,2) NOT NULL CHECK (premio >= 0),
  limite_participantes  INTEGER     DEFAULT 50 CHECK (limite_participantes >= 2),
  participantes_atuais  INTEGER     DEFAULT 0,
  data_inicio           TIMESTAMPTZ NOT NULL,
  data_fim              TIMESTAMPTZ NOT NULL,
  status                TEXT        DEFAULT 'aberto'
                                      CHECK (status IN ('aberto','em_andamento','finalizado','cancelado')),
  tipo                  TEXT        DEFAULT 'ranking'
                                      CHECK (tipo IN ('ranking','vencer_influencer')),
  regras                TEXT,
  imagem_url            TEXT,
  created_at            TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT challenges_datas_validas CHECK (data_fim > data_inicio)
);

COMMENT ON TABLE public.challenges IS
  'Desafios de palpites criados por influenciadores para seus seguidores';
COMMENT ON COLUMN public.challenges.valor_entrada IS
  'Valor em R$ que cada participante paga para entrar no desafio';
COMMENT ON COLUMN public.challenges.premio IS
  'Valor total do prêmio a ser distribuído ao(s) vencedor(es)';
COMMENT ON COLUMN public.challenges.status IS
  'aberto = aceitando inscrições | em_andamento = jogos em curso | finalizado = encerrado | cancelado';
COMMENT ON COLUMN public.challenges.tipo IS
  'ranking = quem pontuar mais vence | vencer_influencer = participante precisa superar o influenciador';


-- ================================================================
-- SEÇÃO 5 — TABELA challenge_matches
-- Jogos (matches) incluídos em cada desafio
-- ================================================================

CREATE TABLE IF NOT EXISTS public.challenge_matches (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  challenge_id UUID        NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  match_id     UUID        NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT challenge_matches_unique UNIQUE (challenge_id, match_id)
);

COMMENT ON TABLE public.challenge_matches IS
  'Associação entre desafios e os jogos que fazem parte de cada desafio';


-- ================================================================
-- SEÇÃO 6 — TABELA challenge_participants
-- Participantes inscritos em cada desafio
-- ================================================================

CREATE TABLE IF NOT EXISTS public.challenge_participants (
  id           UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
  challenge_id UUID        NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  user_id      UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pontuacao    INTEGER     DEFAULT 0,
  posicao      INTEGER,    -- preenchido após finalização do desafio
  is_influencer BOOLEAN    DEFAULT false,
  paid_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT challenge_participants_unique UNIQUE (challenge_id, user_id)
);

COMMENT ON TABLE public.challenge_participants IS
  'Usuários participantes de cada desafio, incluindo o próprio influenciador';
COMMENT ON COLUMN public.challenge_participants.posicao IS
  'Classificação final do participante (preenchido ao finalizar o desafio)';
COMMENT ON COLUMN public.challenge_participants.is_influencer IS
  'TRUE quando este participante é o influenciador criador do desafio';
COMMENT ON COLUMN public.challenge_participants.paid_at IS
  'Data/hora em que o pagamento da entrada foi confirmado';


-- ================================================================
-- SEÇÃO 7 — TABELA challenge_predictions
-- Palpites feitos por cada participante dentro de um desafio
-- ================================================================

CREATE TABLE IF NOT EXISTS public.challenge_predictions (
  id             UUID    DEFAULT uuid_generate_v4() PRIMARY KEY,
  challenge_id   UUID    NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  participant_id UUID    NOT NULL REFERENCES public.challenge_participants(id) ON DELETE CASCADE,
  match_id       UUID    NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  resultado      TEXT    CHECK (resultado IN ('home','away','draw')),
  placar_home    INTEGER,
  placar_away    INTEGER,
  pontos_ganhos  INTEGER DEFAULT 0,
  created_at     TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT challenge_predictions_unique UNIQUE (challenge_id, participant_id, match_id)
);

COMMENT ON TABLE public.challenge_predictions IS
  'Palpites individuais de cada participante para cada jogo dentro de um desafio';
COMMENT ON COLUMN public.challenge_predictions.resultado IS
  'Resultado previsto: home = vitória do mandante | away = visitante | draw = empate';
COMMENT ON COLUMN public.challenge_predictions.pontos_ganhos IS
  'Pontos obtidos neste palpite após o resultado real ser apurado';


-- ================================================================
-- SEÇÃO 8 — INDEXES DE PERFORMANCE
-- ================================================================

-- influencer_profiles
CREATE INDEX IF NOT EXISTS idx_influencer_profiles_user_id
  ON public.influencer_profiles(user_id);

-- wallet_transactions
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id
  ON public.wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_challenge_id
  ON public.wallet_transactions(challenge_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_created_at
  ON public.wallet_transactions(created_at DESC);

-- challenges
CREATE INDEX IF NOT EXISTS idx_challenges_influencer_id
  ON public.challenges(influencer_id);
CREATE INDEX IF NOT EXISTS idx_challenges_status
  ON public.challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_data_fim
  ON public.challenges(data_fim);

-- challenge_matches
CREATE INDEX IF NOT EXISTS idx_challenge_matches_challenge_id
  ON public.challenge_matches(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_matches_match_id
  ON public.challenge_matches(match_id);

-- challenge_participants
CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge_id
  ON public.challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_user_id
  ON public.challenge_participants(user_id);

-- challenge_predictions
CREATE INDEX IF NOT EXISTS idx_challenge_predictions_challenge_id
  ON public.challenge_predictions(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_predictions_participant_id
  ON public.challenge_predictions(participant_id);
CREATE INDEX IF NOT EXISTS idx_challenge_predictions_match_id
  ON public.challenge_predictions(match_id);


-- ================================================================
-- SEÇÃO 9 — ROW LEVEL SECURITY (RLS)
-- ================================================================

-- Habilita RLS em todas as tabelas novas
ALTER TABLE public.influencer_profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenges             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_matches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_predictions  ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------
-- RLS: influencer_profiles
-- SELECT público | INSERT/UPDATE apenas pelo próprio usuário
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "influencer_profiles_select_public"  ON public.influencer_profiles;
DROP POLICY IF EXISTS "influencer_profiles_insert_own"     ON public.influencer_profiles;
DROP POLICY IF EXISTS "influencer_profiles_update_own"     ON public.influencer_profiles;

CREATE POLICY "influencer_profiles_select_public"
  ON public.influencer_profiles FOR SELECT
  USING (true);

CREATE POLICY "influencer_profiles_insert_own"
  ON public.influencer_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "influencer_profiles_update_own"
  ON public.influencer_profiles FOR UPDATE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- RLS: wallet_transactions
-- SELECT apenas pelo dono da transação
-- INSERT feito via funções SQL (SECURITY DEFINER), não diretamente
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "wallet_transactions_select_own" ON public.wallet_transactions;

CREATE POLICY "wallet_transactions_select_own"
  ON public.wallet_transactions FOR SELECT
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- RLS: challenges
-- SELECT público | INSERT/UPDATE apenas pelo influenciador dono
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "challenges_select_public"       ON public.challenges;
DROP POLICY IF EXISTS "challenges_insert_influencer"   ON public.challenges;
DROP POLICY IF EXISTS "challenges_update_influencer"   ON public.challenges;

CREATE POLICY "challenges_select_public"
  ON public.challenges FOR SELECT
  USING (true);

CREATE POLICY "challenges_insert_influencer"
  ON public.challenges FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.influencer_profiles ip
      WHERE ip.id = influencer_id
        AND ip.user_id = auth.uid()
    )
  );

CREATE POLICY "challenges_update_influencer"
  ON public.challenges FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.influencer_profiles ip
      WHERE ip.id = influencer_id
        AND ip.user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------
-- RLS: challenge_matches
-- SELECT público | INSERT/DELETE apenas pelo influenciador dono do desafio
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "challenge_matches_select_public"     ON public.challenge_matches;
DROP POLICY IF EXISTS "challenge_matches_insert_influencer" ON public.challenge_matches;

CREATE POLICY "challenge_matches_select_public"
  ON public.challenge_matches FOR SELECT
  USING (true);

CREATE POLICY "challenge_matches_insert_influencer"
  ON public.challenge_matches FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.challenges c
      JOIN public.influencer_profiles ip ON ip.id = c.influencer_id
      WHERE c.id = challenge_id
        AND ip.user_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------
-- RLS: challenge_participants
-- SELECT público | INSERT apenas pelo próprio usuário autenticado
-- UPDATE restrito: só o próprio usuário pode atualizar seus dados
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "challenge_participants_select_public" ON public.challenge_participants;
DROP POLICY IF EXISTS "challenge_participants_insert_own"    ON public.challenge_participants;
DROP POLICY IF EXISTS "challenge_participants_update_own"    ON public.challenge_participants;

CREATE POLICY "challenge_participants_select_public"
  ON public.challenge_participants FOR SELECT
  USING (true);

CREATE POLICY "challenge_participants_insert_own"
  ON public.challenge_participants FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "challenge_participants_update_own"
  ON public.challenge_participants FOR UPDATE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------
-- RLS: challenge_predictions
-- SELECT/INSERT/UPDATE apenas pelo participante dono do palpite
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS "challenge_predictions_select_own" ON public.challenge_predictions;
DROP POLICY IF EXISTS "challenge_predictions_insert_own" ON public.challenge_predictions;
DROP POLICY IF EXISTS "challenge_predictions_update_own" ON public.challenge_predictions;

CREATE POLICY "challenge_predictions_select_own"
  ON public.challenge_predictions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.challenge_participants cp
      WHERE cp.id = participant_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE POLICY "challenge_predictions_insert_own"
  ON public.challenge_predictions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.challenge_participants cp
      WHERE cp.id = participant_id
        AND cp.user_id = auth.uid()
    )
  );

CREATE POLICY "challenge_predictions_update_own"
  ON public.challenge_predictions FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.challenge_participants cp
      WHERE cp.id = participant_id
        AND cp.user_id = auth.uid()
    )
  );


-- ================================================================
-- SEÇÃO 10 — FUNÇÕES SQL
-- ================================================================

-- ----------------------------------------------------------------
-- FUNÇÃO: enter_challenge
-- Inscreve um usuário em um desafio:
--   1. Verifica se o desafio está aberto e com vagas
--   2. Verifica se o usuário tem saldo suficiente
--   3. Debita o saldo do usuário
--   4. Insere o participante
--   5. Registra a transação na wallet
--   6. Incrementa participantes_atuais do desafio
-- Retorna: TEXT com 'ok' ou mensagem de erro
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enter_challenge(
  p_challenge_id UUID,
  p_user_id      UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_challenge        challenges%ROWTYPE;
  v_saldo_atual      DECIMAL(10,2);
  v_participant_id   UUID;
BEGIN
  -- 1. Busca o desafio
  SELECT * INTO v_challenge
  FROM challenges
  WHERE id = p_challenge_id;

  IF NOT FOUND THEN
    RETURN 'erro: desafio não encontrado';
  END IF;

  -- 2. Verifica status
  IF v_challenge.status <> 'aberto' THEN
    RETURN 'erro: desafio não está aberto para inscrições';
  END IF;

  -- 3. Verifica vagas
  IF v_challenge.participantes_atuais >= v_challenge.limite_participantes THEN
    RETURN 'erro: desafio sem vagas disponíveis';
  END IF;

  -- 4. Verifica se já está inscrito
  IF EXISTS (
    SELECT 1 FROM challenge_participants
    WHERE challenge_id = p_challenge_id AND user_id = p_user_id
  ) THEN
    RETURN 'erro: usuário já inscrito neste desafio';
  END IF;

  -- 5. Verifica saldo
  SELECT saldo INTO v_saldo_atual
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE; -- bloqueia a linha para evitar race condition

  IF v_saldo_atual IS NULL THEN
    RETURN 'erro: perfil do usuário não encontrado';
  END IF;

  IF v_saldo_atual < v_challenge.valor_entrada THEN
    RETURN 'erro: saldo insuficiente';
  END IF;

  -- 6. Debita saldo do usuário
  UPDATE profiles
  SET saldo = saldo - v_challenge.valor_entrada
  WHERE id = p_user_id;

  -- 7. Insere participante
  INSERT INTO challenge_participants (challenge_id, user_id, paid_at)
  VALUES (p_challenge_id, p_user_id, NOW())
  RETURNING id INTO v_participant_id;

  -- 8. Registra transação na wallet
  INSERT INTO wallet_transactions (user_id, tipo, valor, descricao, challenge_id)
  VALUES (
    p_user_id,
    'entrada_desafio',
    -v_challenge.valor_entrada,  -- valor negativo = débito
    'Entrada no desafio: ' || v_challenge.nome,
    p_challenge_id
  );

  -- 9. Incrementa contador de participantes
  UPDATE challenges
  SET participantes_atuais = participantes_atuais + 1
  WHERE id = p_challenge_id;

  RETURN 'ok';

EXCEPTION
  WHEN unique_violation THEN
    RETURN 'erro: usuário já inscrito neste desafio';
  WHEN OTHERS THEN
    RETURN 'erro: ' || SQLERRM;
END;
$$;

COMMENT ON FUNCTION public.enter_challenge(UUID, UUID) IS
  'Inscreve um usuário em um desafio com validação de saldo e controle de vagas';


-- ----------------------------------------------------------------
-- FUNÇÃO: finalize_challenge
-- Finaliza um desafio e distribui os prêmios:
--   1. Calcula pontuação total de cada participante
--   2. Atribui posições no ranking
--   3. Paga o prêmio ao(s) vencedor(es)
--   4. Distribui comissões: 50% plataforma, 50% influenciador
--      (calculado sobre o lucro = total arrecadado - prêmio)
--   5. Atualiza status do desafio para 'finalizado'
-- Retorna: TEXT com 'ok' ou mensagem de erro
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalize_challenge(
  p_challenge_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_challenge          challenges%ROWTYPE;
  v_influencer_user_id UUID;
  v_total_arrecadado   DECIMAL(10,2);
  v_lucro              DECIMAL(10,2);
  v_comissao_plataforma DECIMAL(10,2);
  v_comissao_influencer DECIMAL(10,2);
  v_vencedor_user_id   UUID;
  v_vencedor_pontuacao INTEGER;
  v_pos                INTEGER;
  v_prev_pontuacao     INTEGER;
  r                    RECORD;
BEGIN
  -- 1. Busca o desafio
  SELECT * INTO v_challenge
  FROM challenges
  WHERE id = p_challenge_id;

  IF NOT FOUND THEN
    RETURN 'erro: desafio não encontrado';
  END IF;

  IF v_challenge.status IN ('finalizado', 'cancelado') THEN
    RETURN 'erro: desafio já finalizado ou cancelado';
  END IF;

  -- 2. Calcula pontuação total de cada participante
  --    (soma dos pontos_ganhos nos palpites do desafio)
  UPDATE challenge_participants cp
  SET pontuacao = COALESCE((
    SELECT SUM(pred.pontos_ganhos)
    FROM challenge_predictions pred
    WHERE pred.participant_id = cp.id
      AND pred.challenge_id   = p_challenge_id
  ), 0)
  WHERE cp.challenge_id = p_challenge_id;

  -- 3. Atribui posições (ranking denso: empates recebem a mesma posição)
  v_pos            := 0;
  v_prev_pontuacao := NULL;

  FOR r IN (
    SELECT id, user_id, pontuacao
    FROM challenge_participants
    WHERE challenge_id = p_challenge_id
    ORDER BY pontuacao DESC, created_at ASC
  ) LOOP
    IF v_prev_pontuacao IS NULL OR r.pontuacao <> v_prev_pontuacao THEN
      v_pos := v_pos + 1;
    END IF;

    UPDATE challenge_participants
    SET posicao = v_pos
    WHERE id = r.id;

    -- Guarda o vencedor (1ª posição)
    IF v_pos = 1 AND v_vencedor_user_id IS NULL THEN
      v_vencedor_user_id   := r.user_id;
      v_vencedor_pontuacao := r.pontuacao;
    END IF;

    v_prev_pontuacao := r.pontuacao;
  END LOOP;

  -- 4. Calcula valores financeiros
  v_total_arrecadado   := v_challenge.participantes_atuais * v_challenge.valor_entrada;
  v_lucro              := GREATEST(v_total_arrecadado - v_challenge.premio, 0);
  v_comissao_plataforma := ROUND(v_lucro * 0.5, 2);
  v_comissao_influencer := v_lucro - v_comissao_plataforma; -- garante que soma = v_lucro

  -- 5. Paga o prêmio ao vencedor (se houver participantes)
  IF v_vencedor_user_id IS NOT NULL AND v_challenge.premio > 0 THEN
    UPDATE profiles
    SET saldo = saldo + v_challenge.premio
    WHERE id = v_vencedor_user_id;

    INSERT INTO wallet_transactions (user_id, tipo, valor, descricao, challenge_id)
    VALUES (
      v_vencedor_user_id,
      'premio',
      v_challenge.premio,
      'Prêmio do desafio: ' || v_challenge.nome,
      p_challenge_id
    );
  END IF;

  -- 6. Paga comissão ao influenciador (se houver lucro)
  IF v_comissao_influencer > 0 THEN
    -- Busca user_id do influenciador
    SELECT ip.user_id INTO v_influencer_user_id
    FROM influencer_profiles ip
    WHERE ip.id = v_challenge.influencer_id;

    IF v_influencer_user_id IS NOT NULL THEN
      UPDATE profiles
      SET saldo = saldo + v_comissao_influencer
      WHERE id = v_influencer_user_id;

      UPDATE influencer_profiles
      SET total_earned = total_earned + v_comissao_influencer
      WHERE id = v_challenge.influencer_id;

      INSERT INTO wallet_transactions (user_id, tipo, valor, descricao, challenge_id)
      VALUES (
        v_influencer_user_id,
        'comissao_influencer',
        v_comissao_influencer,
        'Comissão (50% do lucro) do desafio: ' || v_challenge.nome,
        p_challenge_id
      );
    END IF;
  END IF;

  -- Nota: taxa_plataforma (v_comissao_plataforma) fica retida automaticamente
  -- por não ser creditada a nenhum usuário. Registra apenas para auditoria.
  IF v_comissao_plataforma > 0 THEN
    -- Registra como transação sem user_id usando o user_id do vencedor como referência
    -- (apenas para rastreabilidade; em produção pode ser um user_id da plataforma)
    INSERT INTO wallet_transactions (user_id, tipo, valor, descricao, challenge_id)
    VALUES (
      COALESCE(v_vencedor_user_id, v_influencer_user_id),
      'taxa_plataforma',
      v_comissao_plataforma,
      'Taxa da plataforma (50% do lucro) do desafio: ' || v_challenge.nome,
      p_challenge_id
    );
  END IF;

  -- 7. Atualiza status do desafio para finalizado
  UPDATE challenges
  SET status = 'finalizado'
  WHERE id = p_challenge_id;

  -- 8. Incrementa contador de desafios do influenciador
  UPDATE influencer_profiles
  SET total_challenges = total_challenges + 1
  WHERE id = v_challenge.influencer_id;

  RETURN 'ok';

EXCEPTION
  WHEN OTHERS THEN
    RETURN 'erro: ' || SQLERRM;
END;
$$;

COMMENT ON FUNCTION public.finalize_challenge(UUID) IS
  'Finaliza um desafio, calcula ranking, paga prêmio ao vencedor e comissões (50% plataforma, 50% influenciador do lucro)';


-- ================================================================
-- FIM DO SCHEMA
-- Tabelas criadas:
--   - influencer_profiles
--   - wallet_transactions
--   - challenges
--   - challenge_matches
--   - challenge_participants
--   - challenge_predictions
-- Alterações:
--   - profiles.saldo (coluna adicionada)
-- Funções:
--   - enter_challenge(challenge_id, user_id)
--   - finalize_challenge(challenge_id)
-- ================================================================
