-- V10 — Socle organisationnel global ICC LE MANS

create type public.organization_unit_type as enum (
  'eglise',
  'ministere',
  'service',
  'departement',
  'equipe',
  'groupe',
  'famille_impact',
  'famille_impact_jeunes',
  'autre'
);

create type public.organization_management_mode as enum (
  'pilotage_complet',
  'gestion_legere',
  'statistiques_uniquement',
  'referentiel_simple'
);

create type public.organization_assignment_role as enum (
  'responsable',
  'responsable_adjoint',
  'referent',
  'membre_equipe',
  'observateur'
);

create table public.organization_units (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.organization_units(id) on delete restrict,
  code text unique,
  name text not null,
  unit_type public.organization_unit_type not null default 'autre',
  management_mode public.organization_management_mode not null default 'gestion_legere',
  description text,
  active boolean not null default true,
  display_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_units_no_self_parent check (parent_id is null or parent_id <> id)
);

create index organization_units_parent_idx on public.organization_units(parent_id);
create index organization_units_type_idx on public.organization_units(unit_type);
create index organization_units_active_idx on public.organization_units(active) where active = true;

create table public.organization_unit_capabilities (
  id uuid primary key default gen_random_uuid(),
  organization_unit_id uuid not null references public.organization_units(id) on delete cascade,
  capability_code text not null,
  enabled boolean not null default true,
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_unit_id, capability_code)
);

create table public.profile_unit_assignments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  organization_unit_id uuid not null references public.organization_units(id) on delete cascade,
  assignment_role public.organization_assignment_role not null default 'membre_equipe',
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  can_manage boolean not null default false,
  can_view_sensitive boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_unit_assignment_dates check (ends_at is null or ends_at >= starts_at)
);

create unique index profile_unit_assignments_active_unique
  on public.profile_unit_assignments(profile_id, organization_unit_id, assignment_role)
  where active = true and ends_at is null;
create index profile_unit_assignments_profile_idx on public.profile_unit_assignments(profile_id);
create index profile_unit_assignments_unit_idx on public.profile_unit_assignments(organization_unit_id);

create table public.member_unit_affiliations (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  organization_unit_id uuid not null references public.organization_units(id) on delete cascade,
  role_label text,
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_unit_affiliation_dates check (ends_at is null or ends_at >= starts_at)
);

create unique index member_unit_affiliations_active_unique
  on public.member_unit_affiliations(member_id, organization_unit_id)
  where active = true and ends_at is null;
create index member_unit_affiliations_member_idx on public.member_unit_affiliations(member_id);
create index member_unit_affiliations_unit_idx on public.member_unit_affiliations(organization_unit_id);

alter table public.families
  add column organization_unit_id uuid references public.organization_units(id) on delete set null;
create index families_organization_unit_idx on public.families(organization_unit_id);

create or replace function public.can_manage_organization_unit(p_unit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_pasteur_or_admin()
    or exists (
      select 1
      from public.profile_unit_assignments pua
      where pua.profile_id = auth.uid()
        and pua.organization_unit_id = p_unit_id
        and pua.active = true
        and (pua.ends_at is null or pua.ends_at >= current_date)
        and (
          pua.can_manage = true
          or pua.assignment_role in ('responsable', 'responsable_adjoint', 'referent')
        )
    );
$$;

create or replace function public.can_view_organization_unit(p_unit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is not null
    and (
      public.is_pasteur_or_admin()
      or exists (
        select 1
        from public.profile_unit_assignments pua
        where pua.profile_id = auth.uid()
          and pua.organization_unit_id = p_unit_id
          and pua.active = true
          and (pua.ends_at is null or pua.ends_at >= current_date)
      )
      or exists (
        select 1
        from public.organization_units ou
        where ou.id = p_unit_id and ou.active = true
      )
    );
$$;

alter table public.organization_units enable row level security;
alter table public.organization_unit_capabilities enable row level security;
alter table public.profile_unit_assignments enable row level security;
alter table public.member_unit_affiliations enable row level security;

create policy organization_units_select_authenticated
on public.organization_units for select
to authenticated
using (true);

create policy organization_units_manage_global
on public.organization_units for all
to authenticated
using (public.is_pasteur_or_admin() or public.can_manage_organization_unit(id))
with check (public.is_pasteur_or_admin() or (parent_id is not null and public.can_manage_organization_unit(parent_id)));

create policy organization_unit_capabilities_select_authenticated
on public.organization_unit_capabilities for select
to authenticated
using (true);

create policy organization_unit_capabilities_manage
on public.organization_unit_capabilities for all
to authenticated
using (public.can_manage_organization_unit(organization_unit_id))
with check (public.can_manage_organization_unit(organization_unit_id));

create policy profile_unit_assignments_select
on public.profile_unit_assignments for select
to authenticated
using (
  profile_id = auth.uid()
  or public.can_manage_organization_unit(organization_unit_id)
  or public.is_pasteur_or_admin()
);

create policy profile_unit_assignments_manage
on public.profile_unit_assignments for all
to authenticated
using (public.can_manage_organization_unit(organization_unit_id) or public.is_pasteur_or_admin())
with check (public.can_manage_organization_unit(organization_unit_id) or public.is_pasteur_or_admin());

create policy member_unit_affiliations_select
on public.member_unit_affiliations for select
to authenticated
using (public.can_view_organization_unit(organization_unit_id));

create policy member_unit_affiliations_manage
on public.member_unit_affiliations for all
to authenticated
using (public.can_manage_organization_unit(organization_unit_id))
with check (public.can_manage_organization_unit(organization_unit_id));

create trigger set_updated_at_organization_units
before update on public.organization_units
for each row execute function public.set_updated_at();

create trigger set_updated_at_organization_unit_capabilities
before update on public.organization_unit_capabilities
for each row execute function public.set_updated_at();

create trigger set_updated_at_profile_unit_assignments
before update on public.profile_unit_assignments
for each row execute function public.set_updated_at();

create trigger set_updated_at_member_unit_affiliations
before update on public.member_unit_affiliations
for each row execute function public.set_updated_at();

insert into public.organization_units (code, name, unit_type, management_mode, description, display_order)
values ('ICC_LE_MANS', 'ICC LE MANS', 'eglise', 'pilotage_complet', 'Racine organisationnelle de l’église ICC Le Mans.', 0);

insert into public.organization_units (parent_id, code, name, unit_type, management_mode, description, display_order)
select id, 'FAMILLES_IMPACT', 'Familles d’Impact', 'ministere', 'pilotage_complet', 'Module historique FI, conservant toutes les fonctionnalités existantes.', 10
from public.organization_units where code = 'ICC_LE_MANS';

insert into public.organization_units (parent_id, code, name, unit_type, management_mode, description, display_order)
select id, 'FAMILLES_IMPACT_JEUNES', 'Familles d’Impact Jeunes', 'ministere', 'pilotage_complet', 'Module historique FIJ, conservant toutes les fonctionnalités existantes.', 11
from public.organization_units where code = 'ICC_LE_MANS';

insert into public.organization_unit_capabilities (organization_unit_id, capability_code, enabled)
select id, capability, true
from public.organization_units
cross join lateral unnest(array['programmes','planning','presences','membres','integration','statistiques']) capability
where code in ('FAMILLES_IMPACT','FAMILLES_IMPACT_JEUNES');
