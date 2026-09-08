alter table public.profiles add column if not exists access_status text not null default 'pending' check (access_status in ('pending','approved','suspended','rejected'));
alter table public.profiles add column if not exists member_id uuid null references public.members(id) on delete set null;
alter table public.profiles add column if not exists requested_at timestamptz not null default now();
alter table public.profiles add column if not exists approved_at timestamptz null;
alter table public.profiles add column if not exists approved_by uuid null references public.profiles(id) on delete set null;
alter table public.profiles alter column active set default false;

update public.profiles set access_status='approved', active=true, approved_at=coalesce(approved_at, now()) where access_status='pending';

create or replace function public.icc_create_pending_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, first_name, last_name, role, active, access_status, requested_at)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'first_name',''),
    nullif(new.raw_user_meta_data->>'last_name',''),
    'copilote'::public.app_role,
    false,
    'pending',
    now()
  )
  on conflict (id) do update
    set first_name = coalesce(excluded.first_name, public.profiles.first_name),
        last_name = coalesce(excluded.last_name, public.profiles.last_name),
        active = false,
        access_status = case when public.profiles.access_status='approved' then 'approved' else 'pending' end,
        requested_at = coalesce(public.profiles.requested_at, now());
  return new;
end;
$$;

drop trigger if exists icc_auth_user_pending_profile on auth.users;
create trigger icc_auth_user_pending_profile
after insert on auth.users
for each row execute function public.icc_create_pending_profile();

create or replace function public.has_app_access()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.active = true
      and p.access_status = 'approved'
  );
$$;

revoke all on function public.icc_create_pending_profile() from public, anon, authenticated;
revoke all on function public.has_app_access() from public, anon;
grant execute on function public.has_app_access() to authenticated;

create index if not exists idx_profiles_access_status on public.profiles(access_status, active);
create index if not exists idx_profiles_member_id on public.profiles(member_id);
