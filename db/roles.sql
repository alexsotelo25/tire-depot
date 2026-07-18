-- ============================================================
-- TIRE DEPOT — Roles, dashboard access & sign-up lockdown
-- Run this in Supabase → SQL Editor AFTER schema.sql. Safe to re-run.
--
-- What it does:
--   • Adds a `staff` table that decides who can open a dashboard
--     and at what level: 'owner', 'shop', or 'admin'.
--   • Replaces the old "any logged-in user sees everything" rule.
--       - Not in staff  -> sees NOTHING (locks out random sign-ups).
--       - 'shop'        -> only today + upcoming, can block/cancel,
--                          CANNOT delete or see old history.
--       - 'owner'/'admin' -> full access (history + everything).
--   • The public booking flow (get_taken / create_booking) is
--     untouched — it never reads the table directly.
-- ============================================================

-- ---- 1) STAFF table ----------------------------------------
create table if not exists public.staff (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null default 'shop' check (role in ('owner','shop','admin')),
  name       text,
  created_at timestamptz not null default now()
);
alter table public.staff enable row level security;

-- ---- 2) Role helpers (SECURITY DEFINER = bypass RLS, no recursion)
create or replace function public.is_staff() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where id = auth.uid());
$$;

create or replace function public.is_owner() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where id = auth.uid() and role in ('owner','admin'));
$$;

-- returns 'owner' | 'shop' | 'admin' | null  (the dashboards call this)
create or replace function public.my_role() returns text
  language sql stable security definer set search_path = public as $$
  select role from public.staff where id = auth.uid();
$$;

revoke all on function public.is_staff()  from public;
revoke all on function public.is_owner()  from public;
revoke all on function public.my_role()   from public;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.my_role()  to authenticated;

-- ---- 3) STAFF policies -------------------------------------
-- a signed-in user may read ONLY their own row (to learn their role)
drop policy if exists "staff read own" on public.staff;
create policy "staff read own" on public.staff
  for select to authenticated using (id = auth.uid());

-- owners/admins may read the full staff list
drop policy if exists "owner read staff" on public.staff;
create policy "owner read staff" on public.staff
  for select to authenticated using (public.is_owner());

-- owners/admins may add / edit / remove staff members
drop policy if exists "owner manage staff" on public.staff;
create policy "owner manage staff" on public.staff
  for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- ---- 4) BOOKINGS policies (replace the insecure one) -------
drop policy if exists "owner full access"     on public.bookings;
drop policy if exists "staff select bookings" on public.bookings;
drop policy if exists "staff insert bookings" on public.bookings;
drop policy if exists "staff update bookings" on public.bookings;
drop policy if exists "owner delete bookings" on public.bookings;

-- SELECT: owner/admin see everything; shop sees only recent + upcoming
create policy "staff select bookings" on public.bookings
  for select to authenticated
  using ( public.is_owner() or (public.is_staff() and slot_date >= current_date - 1) );

-- INSERT: any staff can block a bay / add a walk-in
create policy "staff insert bookings" on public.bookings
  for insert to authenticated with check ( public.is_staff() );

-- UPDATE: any staff can cancel / unblock (soft status change)
create policy "staff update bookings" on public.bookings
  for update to authenticated using ( public.is_staff() ) with check ( public.is_staff() );

-- DELETE: only owner/admin (the app uses soft-cancel, so this is a backstop)
create policy "owner delete bookings" on public.bookings
  for delete to authenticated using ( public.is_owner() );

-- ============================================================
-- 5) CREATE THE PEOPLE  (do this AFTER running the SQL above)
--
--   a) In Supabase → Authentication → Users → "Add user",
--      create each login (owner, each shop worker, and the admin).
--      Turn OFF "Auto-confirm" only if you want email confirmation;
--      for a shop, auto-confirm ON is easiest.
--
--   b) Copy each new user's UUID (User ID) and run one line per person,
--      e.g. (replace the UUIDs + names):
--
--      insert into public.staff (id, role, name) values
--        ('00000000-owner-uuid', 'owner', 'Depot Owner')
--      on conflict (id) do update set role = excluded.role, name = excluded.name;
--
--      insert into public.staff (id, role, name) values
--        ('11111111-shop-uuid',  'shop',  'Front Counter')
--      on conflict (id) do update set role = excluded.role, name = excluded.name;
--
--      insert into public.staff (id, role, name) values
--        ('22222222-admin-uuid', 'admin', 'Alex (web admin)')
--      on conflict (id) do update set role = excluded.role, name = excluded.name;
--
-- 6) LOCK DOWN SIGN-UPS (belt & suspenders — RLS already blocks non-staff):
--      Supabase → Authentication → Providers → Email → turn OFF
--      "Allow new users to sign up".  Only people you add can log in.
-- ============================================================
