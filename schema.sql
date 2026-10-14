-- 即時行程板 schema
-- 在 Supabase Dashboard → SQL Editor 貼上整份，按 Run 一次即可。可重複執行。
--
-- 設計原則
--   1. 個別登記（intents）任何人都讀不到，連其他登入者也不行；每人只能讀寫自己那一筆。
--   2. 對外只開放聚合函式 board_counts / board_total，少於 3 人的時段在資料庫端就隱藏。
--   3. 同一時段內，人數少於 3 的交通方式併入「other」，避免單一方式反推出個人。

-- ── 地點（時段板）──────────────────────────────────────────
create table if not exists public.boards (
  id          text primary key,
  name        text not null,
  place       text,
  day         text,
  start_time  time not null,
  end_time    time not null,
  sort        int  not null default 0,
  created_at  timestamptz not null default now(),
  constraint boards_window check (end_time > start_time)
);

alter table public.boards enable row level security;

drop policy if exists "boards are public" on public.boards;
create policy "boards are public" on public.boards
  for select to anon, authenticated using (true);

grant select on public.boards to anon, authenticated;
-- 新增／修改地點只透過 Dashboard 或 SQL，前端沒有寫入權限。

-- ── 個別登記 ──────────────────────────────────────────────
create table if not exists public.intents (
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  board_id    text not null references public.boards (id) on delete cascade,
  slot        time not null,
  mode        text not null check (mode in ('car', 'moto', 'mrt', 'bus', 'walk')),
  updated_at  timestamptz not null default now(),
  primary key (user_id, board_id),
  constraint intents_quarter check (extract(minute from slot)::int % 15 = 0 and extract(second from slot) = 0)
);

alter table public.intents enable row level security;

drop policy if exists "read own intent"   on public.intents;
drop policy if exists "insert own intent" on public.intents;
drop policy if exists "update own intent" on public.intents;
drop policy if exists "delete own intent" on public.intents;

create policy "read own intent" on public.intents
  for select to authenticated using (user_id = auth.uid());
create policy "insert own intent" on public.intents
  for insert to authenticated with check (user_id = auth.uid());
create policy "update own intent" on public.intents
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete own intent" on public.intents
  for delete to authenticated using (user_id = auth.uid());

revoke all on public.intents from anon;
grant select, insert, update, delete on public.intents to authenticated;

-- 時段必須落在地點的時間窗內
create or replace function public.check_intent_slot()
returns trigger language plpgsql set search_path = public as $$
declare b public.boards;
begin
  select * into b from public.boards where id = new.board_id;
  if not found then raise exception 'unknown board'; end if;
  if new.slot < b.start_time or new.slot >= b.end_time then
    raise exception 'slot outside board window';
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists intents_check_slot on public.intents;
create trigger intents_check_slot
  before insert or update on public.intents
  for each row execute function public.check_intent_slot();

-- ── 聚合（唯一對外的讀取管道）─────────────────────────────
-- 每個時段一列：total 少於 3 時為 null、small = true、不給 modes。
create or replace function public.board_counts(p_board text)
returns table (slot time, total int, small boolean, modes jsonb)
language sql stable security definer set search_path = public as $$
  with c as (
    select i.slot as s, i.mode as m, count(*)::int as n
    from public.intents i
    where i.board_id = p_board
    group by i.slot, i.mode
  ),
  t as (select c.s, sum(c.n)::int as tot from c group by c.s),
  mm as (
    select c.s, case when c.n >= 3 then c.m else 'other' end as m, sum(c.n)::int as n
    from c group by 1, 2
  )
  select t.s,
         case when t.tot >= 3 then t.tot end,
         t.tot < 3,
         case when t.tot >= 3 then (select jsonb_object_agg(mm.m, mm.n) from mm where mm.s = t.s) end
  from t
  order by t.s;
$$;

create or replace function public.board_total(p_board text)
returns int
language sql stable security definer set search_path = public as $$
  select case when count(*) >= 3 then count(*)::int end
  from public.intents where board_id = p_board;
$$;

revoke all on function public.board_counts(text) from public;
revoke all on function public.board_total(text)  from public;
grant execute on function public.board_counts(text) to anon, authenticated;
grant execute on function public.board_total(text)  to anon, authenticated;

-- ── 第一個地點 ────────────────────────────────────────────
insert into public.boards (id, name, place, day, start_time, end_time, sort)
values ('neihu-am', '內湖科學園區・平日晨間到達', '內湖科學園區', '平日', '07:00', '10:00', 1)
on conflict (id) do nothing;
