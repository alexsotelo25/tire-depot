-- ============================================================
-- TIRE DEPOT — Booking backend (Supabase / Postgres)
-- Paste this whole file into Supabase → SQL Editor → Run.
-- Safe to re-run.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---- bookings table ----
create table if not exists public.bookings (
  id          uuid primary key default gen_random_uuid(),
  bay         smallint not null check (bay in (1,2)),
  slot_date   date not null,
  slot_hour   smallint not null check (slot_hour between 8 and 17),  -- 8 = 8AM ... 17 = 5PM (last 1-hr slot)
  kind        text not null default 'booking' check (kind in ('booking','block')),
  name        text,
  phone       text,
  rig         text,
  note        text,
  ref         text,
  status      text not null default 'booked' check (status in ('booked','cancelled')),
  created_at  timestamptz not null default now()
);

-- one active reservation per bay / date / hour  (this is what makes double-booking impossible)
create unique index if not exists bookings_slot_unique
  on public.bookings (bay, slot_date, slot_hour)
  where status = 'booked';

-- ---- lock the table down ----
alter table public.bookings enable row level security;

-- Only a logged-in user (you, the owner) can read/manage the table directly.
drop policy if exists "owner full access" on public.bookings;
create policy "owner full access" on public.bookings
  for all to authenticated using (true) with check (true);

-- The public site NEVER reads the table directly (that would expose customer names/phones).
-- It uses the two safe functions below instead.

-- ---- availability (no personal info) ----
create or replace function public.get_taken(d date)
returns table (bay smallint, slot_hour smallint)
language sql security definer set search_path = public as $$
  select bay, slot_hour from public.bookings
  where slot_date = d and status = 'booked';
$$;

-- ---- create a booking safely (checks the slot is free) ----
create or replace function public.create_booking(
  p_bay smallint, p_date date, p_hour smallint,
  p_name text, p_phone text, p_rig text default null, p_note text default null
) returns json
language plpgsql security definer set search_path = public as $$
declare v_ref text; v_id uuid;
begin
  if p_bay not in (1,2) or p_hour < 8 or p_hour > 17 then
    return json_build_object('ok', false, 'error', 'Invalid slot');
  end if;
  if p_date < current_date then
    return json_build_object('ok', false, 'error', 'That day has passed');
  end if;
  if coalesce(length(trim(p_name)),0) = 0 or coalesce(length(trim(p_phone)),0) = 0 then
    return json_build_object('ok', false, 'error', 'Name and phone are required');
  end if;
  v_ref := 'TD-' || lpad(((extract(doy from p_date)::int * 20) + p_hour*2 + p_bay)::text, 4, '0');
  insert into public.bookings (bay, slot_date, slot_hour, kind, name, phone, rig, note, ref)
  values (p_bay, p_date, p_hour, 'booking', trim(p_name), trim(p_phone),
          nullif(trim(coalesce(p_rig,'')),''), nullif(trim(coalesce(p_note,'')),''), v_ref)
  returning id into v_id;
  return json_build_object('ok', true, 'ref', v_ref, 'id', v_id);
exception when unique_violation then
  return json_build_object('ok', false, 'error', 'That bay was just taken — pick another');
end;
$$;

-- let the public site call ONLY those two functions
grant execute on function public.get_taken(date) to anon, authenticated;
grant execute on function public.create_booking(smallint, date, smallint, text, text, text, text) to anon, authenticated;
