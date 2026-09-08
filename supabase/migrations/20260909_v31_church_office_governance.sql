create table if not exists public.church_office_members (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  office_role text not null default 'membre',
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(member_id)
);

create index if not exists church_office_members_active_idx on public.church_office_members(active);

alter table public.church_office_members enable row level security;

drop policy if exists church_office_members_read on public.church_office_members;
create policy church_office_members_read on public.church_office_members
for select to authenticated using (public.has_app_access());

drop policy if exists church_office_members_manage on public.church_office_members;
create policy church_office_members_manage on public.church_office_members
for all to authenticated
using (public.is_pasteur_or_admin())
with check (public.is_pasteur_or_admin());

grant select,insert,update,delete on public.church_office_members to authenticated;
