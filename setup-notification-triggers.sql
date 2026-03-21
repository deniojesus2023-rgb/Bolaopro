-- ================================================================
-- BolãoPro — Triggers de Notificações Automáticas
-- Cole no SQL Editor do Supabase e clique em RUN
-- ================================================================

-- ================================================================
-- TRIGGER 1: Notificar criador quando alguém entra no bolão
-- ================================================================
create or replace function public.notify_new_participant()
returns trigger as $$
declare
  v_bolao   record;
  v_user    record;
begin
  -- Não notificar se o próprio criador entrou
  select * into v_bolao from public.boloes where id = new.bolao_id;
  if not found then return new; end if;
  if v_bolao.owner_id = new.user_id then return new; end if;

  select username into v_user from public.profiles where id = new.user_id;

  insert into public.notifications (user_id, bolao_id, type, title, body)
  values (
    v_bolao.owner_id,
    new.bolao_id,
    'join',
    'Novo participante no seu bolão!',
    '@' || coalesce(v_user.username, 'alguém') || ' entrou no bolão "' || v_bolao.name || '".'
  );

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_new_participant on public.participants;
create trigger trg_notify_new_participant
  after insert on public.participants
  for each row execute function public.notify_new_participant();

-- ================================================================
-- TRIGGER 2: Notificar todos participantes quando bolão começa
-- (quando status muda de 'open' para 'active')
-- ================================================================
create or replace function public.notify_bolao_started()
returns trigger as $$
begin
  if old.status = 'open' and new.status = 'active' then
    insert into public.notifications (user_id, bolao_id, type, title, body)
    select
      p.user_id,
      new.id,
      'match',
      'Seu bolão começou!',
      'O bolão "' || new.name || '" está ativo. Faça seus palpites antes dos jogos!'
    from public.participants p
    where p.bolao_id = new.id
      and p.payment_status = 'paid';
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_bolao_started on public.boloes;
create trigger trg_notify_bolao_started
  after update on public.boloes
  for each row execute function public.notify_bolao_started();

-- ================================================================
-- TRIGGER 3: Notificar participantes quando jogo é adicionado ao bolão
-- ================================================================
create or replace function public.notify_match_added()
returns trigger as $$
declare
  v_bolao record;
  v_match record;
begin
  select * into v_bolao from public.boloes where id = new.bolao_id;
  select home_team, away_team into v_match from public.matches where id = new.match_id;
  if not found then return new; end if;

  insert into public.notifications (user_id, bolao_id, type, title, body)
  select
    p.user_id,
    new.bolao_id,
    'match',
    'Novo jogo no bolão!',
    v_match.home_team || ' x ' || v_match.away_team || ' foi adicionado ao bolão "' || v_bolao.name || '".'
  from public.participants p
  where p.bolao_id = new.bolao_id
    and p.payment_status = 'paid';

  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_match_added on public.bolao_matches;
create trigger trg_notify_match_added
  after insert on public.bolao_matches
  for each row execute function public.notify_match_added();

-- ================================================================
-- TRIGGER 4: Notificar participantes quando bolão é finalizado
-- (ganhador e perdedores)
-- ================================================================
create or replace function public.notify_bolao_finished()
returns trigger as $$
declare
  v_winner_id uuid;
  v_prize     decimal;
begin
  if old.status != 'finished' and new.status = 'finished' then
    -- Buscar ganhador
    select user_id, prize_won into v_winner_id, v_prize
    from public.participants
    where bolao_id = new.id and position = 1
    limit 1;

    -- Notificar não-ganhadores
    insert into public.notifications (user_id, bolao_id, type, title, body)
    select
      p.user_id,
      new.id,
      'result',
      'Bolão finalizado!',
      'O bolão "' || new.name || '" foi encerrado. Confira o resultado!'
    from public.participants p
    where p.bolao_id = new.id
      and p.user_id != coalesce(v_winner_id, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_notify_bolao_finished on public.boloes;
create trigger trg_notify_bolao_finished
  after update on public.boloes
  for each row execute function public.notify_bolao_finished();

-- ================================================================
-- Verificar triggers criados
-- ================================================================
select trigger_name, event_object_table, action_timing
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name like 'trg_notify_%'
order by trigger_name;
