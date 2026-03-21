-- ================================================================
-- DEPRECATED — Este arquivo está obsoleto.
-- Use funcoes-faltando.sql em vez deste.
-- funcoes-faltando.sql contém a versão mais recente de todas as
-- funções definidas aqui. Não execute este arquivo em produção.
-- ================================================================

-- ================================================================
-- BOLAOPRO — Funções SQL Faltando
-- Cole no SQL Editor do Supabase e execute
-- Essas funções são chamadas pela Edge Function após jogos
-- ================================================================

-- ================================================================
-- FUNÇÃO 1: calculate_prediction_points
-- Chamada quando um jogo termina
-- Calcula e distribui pontos para todos os palpites daquele jogo
-- ================================================================
create or replace function public.calculate_prediction_points(p_match_id uuid)
returns integer as $$
declare
  v_match      record;
  v_pred       record;
  v_result     text;
  v_is_upset   boolean;
  v_total      integer := 0;
  v_pts_result   integer;
  v_pts_score    integer;
  v_pts_scorer   integer;
  v_pts_bonus    integer;
begin
  select * into v_match from public.matches where id = p_match_id;
  if not found then return 0; end if;
  if v_match.status != 'finished' then return 0; end if;
  if v_match.home_score is null then return 0; end if;

  -- Resultado real
  if    v_match.home_score > v_match.away_score then v_result := 'home';
  elsif v_match.home_score < v_match.away_score then v_result := 'away';
  else  v_result := 'draw';
  end if;

  -- E zebra? (favorito perdeu — odd do vencedor era alta)
  v_is_upset := (
    (v_result = 'home' and coalesce(v_match.odd_home_sportingbet, 2.0) >= 3.0) or
    (v_result = 'away' and coalesce(v_match.odd_away_sportingbet, 3.5) >= 3.0)
  );

  -- Processar cada palpite ainda nao calculado
  for v_pred in
    select p.*, b.pts_result, b.pts_exact_score, b.pts_top_scorer, b.pts_bonus_upset
    from public.predictions p
    join public.boloes b on b.id = p.bolao_id
    where p.match_id = p_match_id
      and p.is_calculated = false
  loop
    v_pts_result := 0;
    v_pts_score  := 0;
    v_pts_scorer := 0;
    v_pts_bonus  := 0;

    -- 3 pts: resultado certo
    if v_pred.predicted_result = v_result then
      v_pts_result := coalesce(v_pred.pts_result, 3);
    end if;

    -- 8 pts: placar exato
    if v_pred.predicted_home_score = v_match.home_score
    and v_pred.predicted_away_score = v_match.away_score then
      v_pts_score := coalesce(v_pred.pts_exact_score, 8);
    end if;

    -- 5 pts: artilheiro certo (compara sobrenome)
    if v_pred.predicted_top_scorer is not null
    and v_match.top_scorer is not null
    and lower(v_pred.predicted_top_scorer) like
        '%' || lower(split_part(v_match.top_scorer, ' ', 2)) || '%'
    then
      v_pts_scorer := coalesce(v_pred.pts_top_scorer, 5);
    end if;

    -- +5 pts bonus zebra
    if v_pts_result > 0 and v_is_upset then
      v_pts_bonus := coalesce(v_pred.pts_bonus_upset, 5);
    end if;

    -- Atualizar prediction
    update public.predictions set
      points_result      = v_pts_result,
      points_exact_score = v_pts_score,
      points_top_scorer  = v_pts_scorer,
      points_bonus       = v_pts_bonus,
      total_points       = v_pts_result + v_pts_score + v_pts_scorer + v_pts_bonus,
      is_calculated      = true,
      updated_at         = now()
    where id = v_pred.id;

    -- Atualizar pontos do participante no bolao
    update public.participants
    set total_points = total_points + v_pts_result + v_pts_score + v_pts_scorer + v_pts_bonus
    where bolao_id = v_pred.bolao_id
      and user_id  = v_pred.user_id;

    -- Atualizar pontos globais do perfil
    update public.profiles
    set total_points = total_points + v_pts_result + v_pts_score + v_pts_scorer + v_pts_bonus,
        updated_at   = now()
    where id = v_pred.user_id;

    v_total := v_total + 1;
  end loop;

  return v_total;
end;
$$ language plpgsql security definer;

-- ================================================================
-- FUNÇÃO 2: finalize_bolao
-- Chamada quando todos os jogos de um bolao terminam
-- Determina vencedor e distribui premio
-- ================================================================
create or replace function public.finalize_bolao(p_bolao_id uuid)
returns void as $$
declare
  v_bolao  record;
  v_winner record;
  v_pos    integer := 1;
  v_prize  decimal(10,2);
begin
  select * into v_bolao from public.boloes where id = p_bolao_id;
  if not found then return; end if;
  if v_bolao.status = 'finished' then return; end if;

  -- Verificar se TODOS os jogos do bolao terminaram
  if exists (
    select 1
    from public.bolao_matches bm
    join public.matches m on m.id = bm.match_id
    where bm.bolao_id = p_bolao_id
      and m.status != 'finished'
  ) then
    return; -- ainda tem jogo em andamento
  end if;

  -- Calcular posicoes pelo ranking de pontos
  for v_winner in
    select user_id, total_points
    from public.participants
    where bolao_id      = p_bolao_id
      and payment_status = 'paid'
    order by total_points desc
  loop
    update public.participants
    set position = v_pos
    where bolao_id = p_bolao_id
      and user_id  = v_winner.user_id;
    v_pos := v_pos + 1;
  end loop;

  -- Premio total (ja descontada a taxa de 5%)
  v_prize := coalesce(v_bolao.total_prize, 0);

  -- Marcar premio do 1o lugar
  if v_prize > 0 then
    update public.participants
    set prize_won = v_prize
    where bolao_id = p_bolao_id
      and position  = 1;
  end if;

  -- Finalizar bolao
  update public.boloes
  set status     = 'finished',
      updated_at = now()
  where id = p_bolao_id;

  -- Notificar vencedor
  insert into public.notifications (user_id, bolao_id, type, title, body)
  select
    p.user_id,
    p_bolao_id,
    'prize',
    'Voce ganhou o bolao!',
    'Parabens! Voce ganhou R$ ' || v_prize::text || '. Informe sua chave Pix para receber.'
  from public.participants p
  where p.bolao_id = p_bolao_id
    and p.position = 1
  limit 1;

  -- Atualizar stats do vencedor no perfil
  update public.profiles
  set total_wins    = total_wins + 1,
      total_earned  = total_earned + v_prize,
      updated_at    = now()
  where id = (
    select user_id from public.participants
    where bolao_id = p_bolao_id and position = 1
    limit 1
  );

  -- Atualizar total_boloes de todos os participantes
  update public.profiles
  set total_boloes = total_boloes + 1,
      updated_at   = now()
  where id in (
    select user_id from public.participants
    where bolao_id      = p_bolao_id
      and payment_status = 'paid'
  );

end;
$$ language plpgsql security definer;

-- ================================================================
-- VERIFICAR SE AS FUNÇÕES FORAM CRIADAS
-- ================================================================
select routine_name, routine_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('calculate_prediction_points', 'finalize_bolao', 'handle_new_user', 'get_or_create_conversation', 'create_dm_invite');
