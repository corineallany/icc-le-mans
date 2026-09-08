alter table public.members add column if not exists discovery_source text;
alter table public.members add column if not exists invited_by_member_id uuid references public.members(id) on delete set null;
alter table public.members add column if not exists discovery_details text;

create index if not exists members_invited_by_member_id_idx on public.members(invited_by_member_id);

comment on column public.members.discovery_source is 'How the person first discovered ICC Le Mans';
comment on column public.members.invited_by_member_id is 'Church member who personally invited this person';
comment on column public.members.discovery_details is 'Optional precision about discovery source';