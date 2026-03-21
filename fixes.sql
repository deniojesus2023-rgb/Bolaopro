-- ================================================================
-- BolãoPro — Fixes & Funções Necessárias
-- Execute este arquivo no SQL Editor do Supabase
-- ================================================================

-- 1. Adicionar coluna pix_key em profiles se não existir
alter table public.profiles add column if not exists pix_key text;
alter table public.profiles add column if not exists phone text;

-- 2. As funções calculate_prediction_points e finalize_bolao
--    estão no arquivo funcoes-faltando.sql
--    Execute aquele arquivo ANTES deste

-- 3. Índices de performance
create index if not exists idx_predictions_match on public.predictions(match_id);
create index if not exists idx_predictions_bolao on public.predictions(bolao_id);
create index if not exists idx_participants_bolao on public.participants(bolao_id);
create index if not exists idx_participants_prize on public.participants(prize_won) where prize_won > 0;
create index if not exists idx_notifications_user on public.notifications(user_id, is_read);
create index if not exists idx_matches_status on public.matches(status, match_date);
create index if not exists idx_affiliate_clicks_user on public.affiliate_clicks(user_id);

-- 4. RLS: permitir usuários autenticados inserirem notificações para outros usuários
--    (necessário para notificações de like/comentário funcionar no frontend)
do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename='notifications' and policyname='notifications_insert'
  ) then
    execute 'create policy "notifications_insert" on public.notifications for insert with check (auth.uid() is not null)';
  end if;
end $$;
