-- Run this whole file once in the Supabase SQL editor.

create table areas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  latitude double precision not null,
  longitude double precision not null,
  radius_m integer not null default 100
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'trainee' check (role in ('trainee','supervisor','admin')),
  area_id uuid references areas(id)
);

create table attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  area_id uuid not null references areas(id),
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  distance_m double precision not null,
  photo_path text not null,
  type text not null check (type in ('time_in','time_out')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  submitted_at timestamptz not null default now()   -- server time
);

alter table areas enable row level security;
alter table profiles enable row level security;
alter table attendance enable row level security;

-- Helper: is the current user a supervisor/admin? (security definer avoids RLS loops)
create or replace function public.is_supervisor() returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('supervisor','admin'));
$$;

-- Read rules. There is NO insert/update policy on attendance:
-- the browser cannot write to it directly, only through the functions below.
create policy "own profile or supervisor" on profiles for select
  using (auth.uid() = id or public.is_supervisor());
create policy "read areas" on areas for select to authenticated using (true);
create policy "own attendance or supervisor" on attendance for select
  using (auth.uid() = user_id or public.is_supervisor());

-- Submit attendance: runs on the server, checks the geofence, uses server time.
create or replace function public.submit_attendance(
  p_lat double precision, p_lng double precision, p_accuracy double precision,
  p_type text, p_photo_path text
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_area areas%rowtype;
  v_dist double precision;
begin
  if v_uid is null then raise exception 'Not logged in'; end if;
  if p_type not in ('time_in','time_out') then raise exception 'Invalid type'; end if;
  if p_photo_path is null or p_photo_path not like v_uid::text || '/%' then
    raise exception 'Invalid photo path';
  end if;

  select a.* into v_area
  from profiles p join areas a on a.id = p.area_id
  where p.id = v_uid;
  if not found then raise exception 'No assigned area. Contact your supervisor.'; end if;

  -- Haversine distance in meters
  v_dist := 2 * 6371000 * asin(sqrt(
    power(sin(radians(p_lat - v_area.latitude) / 2), 2) +
    cos(radians(v_area.latitude)) * cos(radians(p_lat)) *
    power(sin(radians(p_lng - v_area.longitude) / 2), 2)
  ));

  if v_dist > v_area.radius_m then
    raise exception 'You are % m from %. Allowed radius is % m.',
      round(v_dist), v_area.name, v_area.radius_m;
  end if;

  -- One time-in and one time-out per day (Philippine time)
  if exists (
    select 1 from attendance
    where user_id = v_uid and type = p_type
      and (submitted_at at time zone 'Asia/Manila')::date = (now() at time zone 'Asia/Manila')::date
  ) then
    raise exception 'You already submitted % today.', replace(p_type, '_', ' ');
  end if;

  insert into attendance (user_id, area_id, latitude, longitude, accuracy_m, distance_m, photo_path, type)
  values (v_uid, v_area.id, p_lat, p_lng, p_accuracy, v_dist, p_photo_path, p_type);

  return json_build_object('distance_m', round(v_dist));
end;
$$;

-- Approve or reject (supervisors only)
create or replace function public.review_attendance(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_supervisor() then raise exception 'Not allowed'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Invalid status'; end if;
  update attendance set status = p_status where id = p_id;
end;
$$;

revoke execute on function public.submit_attendance from anon, public;
revoke execute on function public.review_attendance from anon, public;
grant execute on function public.submit_attendance to authenticated;
grant execute on function public.review_attendance to authenticated;

-- Private photo bucket (5 MB limit, images only) and its rules
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dtr-photos', 'dtr-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "upload own photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'dtr-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own photos" on storage.objects for delete to authenticated
  using (bucket_id = 'dtr-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "read own photos or supervisor" on storage.objects for select to authenticated
  using (bucket_id = 'dtr-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_supervisor()));
