-- ================================================================
-- BOLÃOPRO — Migration: Dados Completos de Futebol
-- Cole no SQL Editor do Supabase e clique em RUN
-- ================================================================

-- ── 1. Novas colunas na tabela matches ──────────────────────────
alter table public.matches
  add column if not exists referee        text,
  add column if not exists venue_name     text,
  add column if not exists venue_city     text,
  add column if not exists minute         integer,
  add column if not exists halftime_home  integer,
  add column if not exists halftime_away  integer,
  add column if not exists extratime_home integer,
  add column if not exists extratime_away integer,
  add column if not exists penalty_home   integer,
  add column if not exists penalty_away   integer;

-- ── 2. Estatísticas do jogo ──────────────────────────────────────
create table if not exists public.match_statistics (
  id                  uuid default uuid_generate_v4() primary key,
  match_id            uuid references public.matches(id) on delete cascade not null,
  team_type           text not null check (team_type in ('home','away')),
  possession          integer,
  shots_on_goal       integer,
  shots_off_goal      integer,
  shots_blocked       integer,
  shots_total         integer,
  fouls               integer,
  corners             integer,
  offsides            integer,
  yellow_cards        integer,
  red_cards           integer,
  goalkeeper_saves    integer,
  passes_total        integer,
  passes_accurate     integer,
  passes_percentage   integer,
  updated_at          timestamptz default now(),
  unique(match_id, team_type)
);

-- ── 3. Escalações ────────────────────────────────────────────────
create table if not exists public.match_lineups (
  id          uuid default uuid_generate_v4() primary key,
  match_id    uuid references public.matches(id) on delete cascade not null,
  team_type   text not null check (team_type in ('home','away')),
  team_name   text,
  formation   text,
  coach_name  text,
  players     jsonb default '[]',
  updated_at  timestamptz default now(),
  unique(match_id, team_type)
);

-- ── 4. Eventos do jogo (gols, cartões, substituições) ───────────
create table if not exists public.match_events (
  id            uuid default uuid_generate_v4() primary key,
  match_id      uuid references public.matches(id) on delete cascade not null,
  minute        integer,
  minute_extra  integer,
  team_type     text check (team_type in ('home','away')),
  team_name     text,
  player_name   text,
  assist_name   text,
  event_type    text,
  event_detail  text,
  comments      text,
  created_at    timestamptz default now()
);

create index if not exists match_events_match_id_idx on public.match_events(match_id);
create index if not exists match_stats_match_id_idx  on public.match_statistics(match_id);
create index if not exists match_lineups_match_id_idx on public.match_lineups(match_id);

-- ── 5. RLS ───────────────────────────────────────────────────────
alter table public.match_statistics enable row level security;
alter table public.match_lineups    enable row level security;
alter table public.match_events     enable row level security;

drop policy if exists "stats_read"   on public.match_statistics;
drop policy if exists "lineups_read" on public.match_lineups;
drop policy if exists "events_read"  on public.match_events;

create policy "stats_read"   on public.match_statistics for select using (true);
create policy "lineups_read" on public.match_lineups    for select using (true);
create policy "events_read"  on public.match_events     for select using (true);
