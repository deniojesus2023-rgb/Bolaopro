-- ================================================================
-- BOLÃOPRO — SQL Completo
-- Cole TUDO isso no SQL Editor do Supabase e clique em RUN
-- supabase.com → SQL Editor → New Query → Cole → Run
-- ================================================================

-- EXTENSÕES
create extension if not exists "uuid-ossp";

-- ================================================================
-- PROFILES
-- ================================================================
create table if not exists public.profiles (
  id            uuid references auth.users on delete cascade primary key,
  username      text unique not null,
  full_name     text,
  avatar_url    text,
  phone         text,
  pix_key       text,
  total_boloes  integer default 0,
  total_wins    integer default 0,
  total_points  integer default 0,
  total_earned  decimal(10,2) default 0,
  plan          text default 'free',
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- ================================================================
-- COMPETITIONS
-- ================================================================
create table if not exists public.competitions (
  id         uuid default uuid_generate_v4() primary key,
  api_id     integer unique,
  name       text not null,
  short_name text not null,
  country    text default 'Brasil',
  logo_url   text,
  season     text not null,
  is_active  boolean default true,
  created_at timestamptz default now()
);

insert into public.competitions (api_id, name, short_name, country, season) values
  (71,  'Brasileirão Série A',   'BRAS-A',  'Brasil',         '2025'),
  (13,  'CONMEBOL Libertadores', 'LIBERT',  'América do Sul', '2025'),
  (73,  'Copa do Brasil',        'COPA-BR', 'Brasil',         '2025'),
  (39,  'Premier League',        'PL',      'Inglaterra',     '2025')
on conflict (api_id) do nothing;

-- ================================================================
-- MATCHES
-- ================================================================
create table if not exists public.matches (
  id                         uuid default uuid_generate_v4() primary key,
  api_fixture_id             integer unique,
  competition_id             uuid references public.competitions(id),
  home_team                  text not null,
  away_team                  text not null,
  home_team_logo             text,
  away_team_logo             text,
  round_name                 text,
  match_date                 timestamptz not null,
  status                     text default 'scheduled'
                               check (status in ('scheduled','live','finished','cancelled')),
  home_score                 integer,
  away_score                 integer,
  top_scorer                 text,
  odd_home_sportingbet       decimal(5,2) default 2.00,
  odd_draw_sportingbet       decimal(5,2) default 3.20,
  odd_away_sportingbet       decimal(5,2) default 3.50,
  odd_home_superbet          decimal(5,2) default 2.05,
  odd_draw_superbet          decimal(5,2) default 3.25,
  odd_away_superbet          decimal(5,2) default 3.45,
  created_at                 timestamptz default now(),
  updated_at                 timestamptz default now()
);

-- ================================================================
-- BOLOES
-- ================================================================
create table if not exists public.boloes (
  id                uuid default uuid_generate_v4() primary key,
  code              text unique not null
                      default upper(substring(md5(random()::text), 1, 6)),
  owner_id          uuid references public.profiles(id) on delete cascade,
  name              text not null,
  description       text,
  competicao        text,
  time_casa         text,
  time_fora         text,
  data_partida      timestamptz,
  status            text default 'open'
                      check (status in ('open','active','finished','cancelled')),
  cota_value        decimal(10,2) not null default 0,
  platform_fee_pct  decimal(5,2) default 5.0,
  prize_split       text default '100% ao 1º',
  total_collected   decimal(10,2) default 0,
  total_prize       decimal(10,2) default 0,
  platform_earned   decimal(10,2) default 0,
  is_paid_out       boolean default false,
  max_participants  integer default 50,
  deadline          timestamptz,
  pts_result        integer default 3,
  pts_exact_score   integer default 8,
  pts_top_scorer    integer default 5,
  pts_bonus_upset   integer default 5,
  pts_bonus_perfect integer default 20,
  participant_count integer default 0,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

-- ================================================================
-- BOLAO_MATCHES
-- ================================================================
create table if not exists public.bolao_matches (
  id         uuid default uuid_generate_v4() primary key,
  bolao_id   uuid references public.boloes(id) on delete cascade,
  match_id   uuid references public.matches(id) on delete cascade,
  created_at timestamptz default now(),
  unique (bolao_id, match_id)
);

-- ================================================================
-- PARTICIPANTS
-- ================================================================
create table if not exists public.participants (
  id              uuid default uuid_generate_v4() primary key,
  bolao_id        uuid references public.boloes(id) on delete cascade,
  user_id         uuid references public.profiles(id) on delete cascade,
  payment_status  text default 'pending'
                    check (payment_status in ('pending','paid','refunded')),
  payment_id      text,
  paid_at         timestamptz,
  amount_paid     decimal(10,2) default 0,
  total_points    integer default 0,
  predicted_result text,
  position        integer,
  prize_won       decimal(10,2) default 0,
  prize_paid      boolean default false,
  joined_at       timestamptz default now(),
  unique (bolao_id, user_id)
);

-- ================================================================
-- PREDICTIONS
-- ================================================================
create table if not exists public.predictions (
  id                    uuid default uuid_generate_v4() primary key,
  bolao_id              uuid references public.boloes(id) on delete cascade,
  match_id              uuid references public.matches(id) on delete cascade,
  user_id               uuid references public.profiles(id) on delete cascade,
  predicted_result      text check (predicted_result in ('home','draw','away')),
  predicted_home_score  integer,
  predicted_away_score  integer,
  predicted_top_scorer  text,
  points_result         integer default 0,
  points_exact_score    integer default 0,
  points_top_scorer     integer default 0,
  points_bonus          integer default 0,
  total_points          integer default 0,
  is_calculated         boolean default false,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now(),
  unique (bolao_id, match_id, user_id)
);

-- ================================================================
-- PAYMENTS
-- ================================================================
create table if not exists public.payments (
  id              uuid default uuid_generate_v4() primary key,
  bolao_id        uuid references public.boloes(id),
  user_id         uuid references public.profiles(id),
  participant_id  uuid references public.participants(id),
  type            text check (type in ('entry','prize_payout','platform_fee')),
  amount          decimal(10,2) not null,
  status          text default 'pending'
                    check (status in ('pending','confirmed','failed','refunded')),
  pix_txid        text unique,
  pix_qr_code     text,
  pix_copy_paste  text,
  pix_expiration  timestamptz,
  confirmed_at    timestamptz,
  webhook_data    jsonb,
  created_at      timestamptz default now()
);

-- ================================================================
-- AFFILIATE CLICKS
-- ================================================================
create table if not exists public.affiliate_clicks (
  id         uuid default uuid_generate_v4() primary key,
  user_id    uuid references public.profiles(id),
  bolao_id   uuid references public.boloes(id),
  match_id   uuid references public.matches(id),
  partner    text check (partner in ('sportingbet','superbet')),
  source     text,
  clicked_at timestamptz default now()
);

-- ================================================================
-- NOTIFICATIONS
-- ================================================================
create table if not exists public.notifications (
  id         uuid default uuid_generate_v4() primary key,
  user_id    uuid references public.profiles(id) on delete cascade,
  bolao_id   uuid references public.boloes(id),
  type       text,
  title      text not null,
  body       text,
  is_read    boolean default false,
  created_at timestamptz default now()
);

-- ================================================================
-- COMUNIDADE: POSTS
-- ================================================================
create table if not exists public.posts (
  id            uuid default uuid_generate_v4() primary key,
  user_id       uuid references public.profiles(id) on delete cascade,
  content       text not null check (char_length(content) <= 500),
  type          text default 'tip'
                  check (type in ('tip','invite','result','general')),
  bolao_id      uuid references public.boloes(id) on delete set null,
  likes_count   integer default 0,
  replies_count integer default 0,
  created_at    timestamptz default now()
);

-- ================================================================
-- COMUNIDADE: POST_LIKES
-- ================================================================
create table if not exists public.post_likes (
  id         uuid default uuid_generate_v4() primary key,
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique (post_id, user_id)
);

-- ================================================================
-- COMUNIDADE: POST_REPLIES
-- ================================================================
create table if not exists public.post_replies (
  id         uuid default uuid_generate_v4() primary key,
  post_id    uuid references public.posts(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  content    text not null check (char_length(content) <= 300),
  created_at timestamptz default now()
);

-- ================================================================
-- COMUNIDADE: CONVERSATIONS (DM)
-- ================================================================
create table if not exists public.conversations (
  id              uuid default uuid_generate_v4() primary key,
  user_a          uuid references public.profiles(id) on delete cascade,
  user_b          uuid references public.profiles(id),
  invite_code     text unique default upper(substring(md5(random()::text), 1, 10)),
  invite_status   text default 'pending'
                    check (invite_status in ('pending','accepted','declined')),
  last_message    text,
  last_message_at timestamptz,
  unread_a        integer default 0,
  unread_b        integer default 0,
  created_at      timestamptz default now()
);

-- ================================================================
-- COMUNIDADE: MESSAGES (DM)
-- ================================================================
create table if not exists public.messages (
  id              uuid default uuid_generate_v4() primary key,
  conversation_id uuid references public.conversations(id) on delete cascade,
  sender_id       uuid references public.profiles(id) on delete cascade,
  content         text not null check (char_length(content) <= 1000),
  type            text default 'text'
                    check (type in ('text','bolao_invite','system')),
  bolao_id        uuid references public.boloes(id) on delete set null,
  is_read         boolean default false,
  created_at      timestamptz default now()
);

-- ================================================================
-- COMUNIDADE: BOLAO_CHAT (chat em grupo)
-- ================================================================
create table if not exists public.bolao_chat (
  id         uuid default uuid_generate_v4() primary key,
  bolao_id   uuid references public.boloes(id) on delete cascade,
  user_id    uuid references public.profiles(id) on delete cascade,
  content    text not null check (char_length(content) <= 500),
  type       text default 'message'
               check (type in ('message','system','bolao_invite')),
  created_at timestamptz default now()
);

-- ================================================================
-- TRIGGER: criar perfil ao cadastrar
-- ================================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ================================================================
-- TRIGGER: atualizar last_message na conversa
-- ================================================================
create or replace function update_conversation_last_message()
returns trigger as $$
begin
  update public.conversations set
    last_message    = left(NEW.content, 60),
    last_message_at = NEW.created_at,
    unread_a = case when NEW.sender_id != user_a then unread_a + 1 else 0 end,
    unread_b = case when user_b is not null and NEW.sender_id != user_b then unread_b + 1 else 0 end
  where id = NEW.conversation_id;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_update_last_message on public.messages;
create trigger trg_update_last_message
  after insert on public.messages
  for each row execute function update_conversation_last_message();

-- ================================================================
-- TRIGGER: likes e replies count
-- ================================================================
create or replace function update_post_counts()
returns trigger as $$
begin
  if TG_TABLE_NAME = 'post_likes' then
    if TG_OP = 'INSERT' then
      update public.posts set likes_count = likes_count + 1 where id = NEW.post_id;
    elsif TG_OP = 'DELETE' then
      update public.posts set likes_count = greatest(0, likes_count - 1) where id = OLD.post_id;
    end if;
  elsif TG_TABLE_NAME = 'post_replies' then
    if TG_OP = 'INSERT' then
      update public.posts set replies_count = replies_count + 1 where id = NEW.post_id;
    end if;
  end if;
  return coalesce(NEW, OLD);
end;
$$ language plpgsql security definer;

drop trigger if exists trg_post_likes   on public.post_likes;
drop trigger if exists trg_post_replies on public.post_replies;
create trigger trg_post_likes   after insert or delete on public.post_likes   for each row execute function update_post_counts();
create trigger trg_post_replies after insert           on public.post_replies  for each row execute function update_post_counts();

-- ================================================================
-- FUNÇÃO: criar/buscar conversa DM
-- ================================================================
create or replace function get_or_create_conversation(p_user_a uuid, p_user_b uuid)
returns uuid as $$
declare v_id uuid; v_a uuid; v_b uuid;
begin
  v_a := least(p_user_a, p_user_b);
  v_b := greatest(p_user_a, p_user_b);
  select id into v_id from public.conversations where user_a = v_a and user_b = v_b;
  if v_id is null then
    insert into public.conversations (user_a, user_b, invite_status)
    values (v_a, v_b, 'accepted') returning id into v_id;
  end if;
  return v_id;
end;
$$ language plpgsql security definer;

-- ================================================================
-- FUNÇÃO: criar convite por link
-- ================================================================
create or replace function create_dm_invite(p_from_user uuid)
returns text as $$
declare v_code text;
begin
  v_code := upper(substring(md5(p_from_user::text || now()::text), 1, 10));
  insert into public.conversations (user_a, invite_code, invite_status)
  values (p_from_user, v_code, 'pending')
  on conflict do nothing;
  return v_code;
end;
$$ language plpgsql security definer;

-- ================================================================
-- VIEW: ranking global
-- ================================================================
create or replace view public.global_ranking as
select
  u.id, u.username, u.avatar_url, u.full_name,
  u.total_points, u.total_boloes, u.total_wins, u.total_earned,
  case when u.total_boloes > 0
    then round((u.total_wins::decimal / u.total_boloes) * 100, 1)
    else 0
  end as win_rate,
  rank() over (order by u.total_points desc) as position
from public.profiles u
order by u.total_points desc;

-- ================================================================
-- ROW LEVEL SECURITY
-- ================================================================
alter table public.profiles          enable row level security;
alter table public.boloes            enable row level security;
alter table public.participants      enable row level security;
alter table public.predictions       enable row level security;
alter table public.payments          enable row level security;
alter table public.notifications     enable row level security;
alter table public.posts             enable row level security;
alter table public.post_likes        enable row level security;
alter table public.post_replies      enable row level security;
alter table public.conversations     enable row level security;
alter table public.messages          enable row level security;
alter table public.bolao_chat        enable row level security;
alter table public.affiliate_clicks  enable row level security;

-- Profiles
create policy "profiles_select" on public.profiles for select using (true);
create policy "profiles_insert" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update" on public.profiles for update using (auth.uid() = id);

-- Bolões
create policy "boloes_select" on public.boloes for select using (true);
create policy "boloes_insert" on public.boloes for insert with check (auth.uid() = owner_id);
create policy "boloes_update" on public.boloes for update using (auth.uid() = owner_id);

-- Participants
create policy "participants_select" on public.participants for select using (true);
create policy "participants_insert" on public.participants for insert with check (auth.uid() = user_id);
create policy "participants_update" on public.participants for update using (auth.uid() = user_id);

-- Predictions
create policy "predictions_select" on public.predictions for select using (true);
create policy "predictions_insert" on public.predictions for insert with check (auth.uid() = user_id);
create policy "predictions_update" on public.predictions for update using (auth.uid() = user_id);

-- Payments
create policy "payments_select" on public.payments for select using (auth.uid() = user_id);
create policy "payments_insert" on public.payments for insert with check (auth.uid() = user_id);

-- Notifications
create policy "notifications_select" on public.notifications for select using (auth.uid() = user_id);
create policy "notifications_update" on public.notifications for update using (auth.uid() = user_id);

-- Posts
create policy "posts_select" on public.posts for select using (true);
create policy "posts_insert" on public.posts for insert with check (auth.uid() = user_id);
create policy "posts_delete" on public.posts for delete using (auth.uid() = user_id);

-- Post likes
create policy "likes_select" on public.post_likes for select using (true);
create policy "likes_insert" on public.post_likes for insert with check (auth.uid() = user_id);
create policy "likes_delete" on public.post_likes for delete using (auth.uid() = user_id);

-- Post replies
create policy "replies_select" on public.post_replies for select using (true);
create policy "replies_insert" on public.post_replies for insert with check (auth.uid() = user_id);

-- Conversations
create policy "conv_select" on public.conversations for select
  using (auth.uid() = user_a or auth.uid() = user_b);
create policy "conv_insert" on public.conversations for insert
  with check (auth.uid() = user_a);
create policy "conv_update" on public.conversations for update
  using (auth.uid() = user_a or auth.uid() = user_b);

-- Messages
create policy "msg_select" on public.messages for select
  using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id
    and (c.user_a = auth.uid() or c.user_b = auth.uid())
  ));
create policy "msg_insert" on public.messages for insert
  with check (auth.uid() = sender_id);

-- Bolao chat
create policy "bchat_select" on public.bolao_chat for select using (true);
create policy "bchat_insert" on public.bolao_chat for insert with check (auth.uid() = user_id);

-- Affiliate clicks
create policy "aff_insert" on public.affiliate_clicks for insert with check (true);

-- Matches e competitions são públicos (sem RLS)
