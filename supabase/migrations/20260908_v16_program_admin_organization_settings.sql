create table if not exists public.church_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.program_team_members (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  profile_id uuid references public.profiles(id) on delete set null,
  organization_unit_id uuid references public.organization_units(id) on delete set null,
  role_label text not null,
  team_label text,
  call_time timestamptz,
  end_time timestamptz,
  status text not null default 'prevu' check (status in ('prevu','confirme','absent','remplace','termine')),
  notes text,
  display_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_program_team_members_program on public.program_team_members(program_id,display_order);
create index if not exists idx_program_team_members_member on public.program_team_members(member_id);

create table if not exists public.unit_leadership_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_unit_id uuid not null references public.organization_units(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  leadership_role public.organization_assignment_role not null check (leadership_role in ('responsable','responsable_adjoint')),
  active boolean not null default true,
  starts_at date,
  ends_at date,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_unit_id,member_id,leadership_role)
);

create index if not exists idx_unit_leadership_unit on public.unit_leadership_assignments(organization_unit_id,active);

alter table public.church_settings enable row level security;
alter table public.program_team_members enable row level security;
alter table public.unit_leadership_assignments enable row level security;

drop policy if exists church_settings_read on public.church_settings;
create policy church_settings_read on public.church_settings for select to authenticated using (public.has_app_access());
drop policy if exists church_settings_admin on public.church_settings;
create policy church_settings_admin on public.church_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists program_team_read on public.program_team_members;
create policy program_team_read on public.program_team_members for select to authenticated using (public.has_app_access());
drop policy if exists program_team_manage on public.program_team_members;
create policy program_team_manage on public.program_team_members for all to authenticated using (public.is_admin() or public.can_manage_program(program_id)) with check (public.is_admin() or public.can_manage_program(program_id));

drop policy if exists unit_leadership_read on public.unit_leadership_assignments;
create policy unit_leadership_read on public.unit_leadership_assignments for select to authenticated using (public.has_app_access());
drop policy if exists unit_leadership_admin on public.unit_leadership_assignments;
create policy unit_leadership_admin on public.unit_leadership_assignments for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.admin_set_church_setting(p_key text,p_value jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Accès administrateur requis'; end if;
 insert into public.church_settings(key,value,updated_by,updated_at)
 values(p_key,p_value,auth.uid(),now())
 on conflict(key) do update set value=excluded.value,updated_by=auth.uid(),updated_at=now();
end;$$;
revoke all on function public.admin_set_church_setting(text,jsonb) from public,anon;
grant execute on function public.admin_set_church_setting(text,jsonb) to authenticated;

create or replace function public.admin_set_unit_leader(p_unit_id uuid,p_member_id uuid,p_role public.organization_assignment_role)
returns void language plpgsql security definer set search_path='' as $$
declare v_profile uuid;
begin
 if not public.is_admin() then raise exception 'Accès administrateur requis'; end if;
 if p_role not in ('responsable','responsable_adjoint') then raise exception 'Rôle invalide'; end if;
 select id into v_profile from public.profiles where member_id=p_member_id and active=true and access_status='approved' limit 1;
 update public.unit_leadership_assignments set active=false,updated_at=now() where organization_unit_id=p_unit_id and leadership_role=p_role and active=true;
 insert into public.unit_leadership_assignments(organization_unit_id,member_id,profile_id,leadership_role,created_by)
 values(p_unit_id,p_member_id,v_profile,p_role,auth.uid())
 on conflict(organization_unit_id,member_id,leadership_role) do update set active=true,profile_id=excluded.profile_id,updated_at=now();
 if v_profile is not null then
   insert into public.profile_unit_assignments(profile_id,organization_unit_id,assignment_role,active,can_manage,can_view_sensitive)
   values(v_profile,p_unit_id,p_role,true,true,true)
   on conflict do nothing;
 end if;
end;$$;
revoke all on function public.admin_set_unit_leader(uuid,uuid,public.organization_assignment_role) from public,anon;
grant execute on function public.admin_set_unit_leader(uuid,uuid,public.organization_assignment_role) to authenticated;

insert into public.church_settings(key,value) values('organization',jsonb_build_object('pastor_member_id',null)) on conflict(key) do nothing;