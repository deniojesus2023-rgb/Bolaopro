-- ================================================================
-- BolãoPro — Cron Jobs Automáticos
-- Cole no SQL Editor do Supabase após o deploy da Edge Function
-- ================================================================

-- Ativar extensões necessárias
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ================================================================
-- CRON 1: Buscar novos jogos todo dia às 08h
-- ================================================================
select cron.schedule(
  'bolaopro-sync-daily',
  '0 8 * * *',
  $$
  select net.http_post(
    url     := 'https://nfqvwegyqtwbuvyfbsbe.supabase.co/functions/v1/sync-matches',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mcXZ3ZWd5cXR3YnV2eWZic2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4ODU0NTMsImV4cCI6MjA4OTQ2MTQ1M30.j6b363y0fJTGcHo9uvYr-Y9a8kqRqQR12hfk0sq84xg"}'::jsonb,
    body    := '{}'::jsonb
  )
  $$
);

-- ================================================================
-- CRON 2: Atualizar placares a cada 5 minutos (tempo real)
-- ================================================================
select cron.schedule(
  'bolaopro-sync-live',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := 'https://nfqvwegyqtwbuvyfbsbe.supabase.co/functions/v1/sync-matches',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mcXZ3ZWd5cXR3YnV2eWZic2JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4ODU0NTMsImV4cCI6MjA4OTQ2MTQ1M30.j6b363y0fJTGcHo9uvYr-Y9a8kqRqQR12hfk0sq84xg"}'::jsonb,
    body    := '{}'::jsonb
  )
  $$
);

-- ================================================================
-- VERIFICAR SE OS CRONS FORAM CRIADOS
-- ================================================================
-- select * from cron.job;

-- ================================================================
-- PARA REMOVER OS CRONS (se precisar):
-- ================================================================
-- select cron.unschedule('bolaopro-sync-daily');
-- select cron.unschedule('bolaopro-sync-live');
