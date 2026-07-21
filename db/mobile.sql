-- ============================================================
-- TIRE DEPOT — Mobile-service dispatch requests
-- Run in Supabase → SQL Editor AFTER roles.sql. Safe to re-run.
--
-- Captures the "come to me" requests from mobile.html so the shop
-- sees WHERE to send the truck (there's no phone on the site).
-- The public site inserts ONLY through create_mobile_request();
-- staff read/manage them from the dashboards.
-- ============================================================

create table if not exists public.mobile_requests (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  area       text,
  location   text,
  name       text,
  phone      text,
  rig        text,
  need       text,
  ref        text,
  status     text not null default 'new' check (status in ('new','dispatched','done','cancelled'))
);
alter table public.mobile_requests enable row level security;

-- staff read; owner/admin manage; public NEVER reads directly
drop policy if exists "staff read mobile"   on public.mobile_requests;
create policy "staff read mobile" on public.mobile_requests
  for select to authenticated using (public.is_staff());

drop policy if exists "staff update mobile" on public.mobile_requests;
create policy "staff update mobile" on public.mobile_requests
  for update to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "owner delete mobile" on public.mobile_requests;
create policy "owner delete mobile" on public.mobile_requests
  for delete to authenticated using (public.is_owner());

-- the public site calls ONLY this function to log a request
create or replace function public.create_mobile_request(
  p_area text, p_location text, p_name text, p_phone text,
  p_rig text default null, p_need text default null
) returns json
language plpgsql security definer set search_path = public as $$
declare v_ref text; v_id uuid;
begin
  if coalesce(length(trim(p_name)),0)=0 or coalesce(length(trim(p_phone)),0)=0
     or coalesce(length(trim(p_location)),0)=0 then
    return json_build_object('ok', false, 'error', 'Name, phone and location are required');
  end if;
  v_ref := 'MD-' || lpad((floor(random()*9000)+1000)::int::text, 4, '0');
  insert into public.mobile_requests (area, location, name, phone, rig, need, ref)
  values (nullif(trim(coalesce(p_area,'')),''), trim(p_location), trim(p_name), trim(p_phone),
          nullif(trim(coalesce(p_rig,'')),''), nullif(trim(coalesce(p_need,'')),''), v_ref)
  returning id into v_id;
  return json_build_object('ok', true, 'ref', v_ref, 'id', v_id);
end;
$$;

grant execute on function public.create_mobile_request(text,text,text,text,text,text) to anon, authenticated;
