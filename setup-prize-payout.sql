-- ================================================================
-- BolãoPro — Setup: Controle de Pagamento de Premiações
-- Cole no SQL Editor do Supabase e clique em RUN
-- ================================================================

-- 1. Adicionar colunas de controle de prêmio nos participantes
alter table public.participants
  add column if not exists prize_paid       boolean default false,
  add column if not exists prize_paid_at    timestamptz,
  add column if not exists prize_paid_by    uuid references public.profiles(id);

-- 2. Política RLS: admin pode atualizar status de pagamento
drop policy if exists "participants_admin_update" on public.participants;
create policy "participants_admin_update"
  on public.participants for update
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and plan = 'admin'
    )
  );

-- 3. Função para admin marcar prêmio como pago
create or replace function public.admin_mark_prize_paid(
  p_participant_id uuid,
  p_admin_id       uuid
)
returns void as $$
declare
  v_participant record;
  v_bolao_name  text;
begin
  -- Verificar se admin
  if not exists (
    select 1 from public.profiles where id = p_admin_id and plan = 'admin'
  ) then
    raise exception 'Acesso negado: usuário não é admin';
  end if;

  select p.*, b.name as bolao_name
  into v_participant
  from public.participants p
  join public.boloes b on b.id = p.bolao_id
  where p.id = p_participant_id;

  if not found then
    raise exception 'Participante não encontrado';
  end if;

  -- Marcar como pago
  update public.participants
  set
    prize_paid    = true,
    prize_paid_at = now(),
    prize_paid_by = p_admin_id
  where id = p_participant_id;

  -- Inserir registro na tabela payments
  insert into public.payments (
    bolao_id, user_id, participant_id,
    type, amount, status, confirmed_at
  ) values (
    v_participant.bolao_id,
    v_participant.user_id,
    p_participant_id,
    'prize_payout',
    coalesce(v_participant.prize_won, 0),
    'confirmed',
    now()
  );

  -- Notificar ganhador que o Pix foi enviado
  insert into public.notifications (user_id, bolao_id, type, title, body)
  values (
    v_participant.user_id,
    v_participant.bolao_id,
    'prize',
    'Prêmio enviado via Pix!',
    'R$ ' || v_participant.prize_won::text || ' foram enviados para sua chave Pix. Verifique seu banco!'
  );
end;
$$ language plpgsql security definer;

-- 4. View para admin ver premiações pendentes
create or replace view public.prize_payouts_pending as
select
  pa.id as participant_id,
  pa.bolao_id,
  b.name as bolao_name,
  b.status as bolao_status,
  pa.user_id,
  pr.username,
  pr.full_name,
  pr.pix_key,
  pa.prize_won,
  pa.position,
  pa.total_points,
  pa.prize_paid,
  pa.prize_paid_at,
  b.updated_at as finished_at
from public.participants pa
join public.boloes b on b.id = pa.bolao_id
join public.profiles pr on pr.id = pa.user_id
where pa.prize_won > 0
  and pa.position = 1
  and b.status = 'finished'
order by b.updated_at desc;

-- Verificar
select count(*) as participantes_com_premio from public.prize_payouts_pending;
