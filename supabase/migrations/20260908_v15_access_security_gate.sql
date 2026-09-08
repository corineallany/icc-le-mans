create or replace function public.current_user_role()
returns public.app_role
language sql stable security definer set search_path = '' as $$
 select p.role from public.profiles p where p.id=auth.uid() and p.active=true and p.access_status='approved';
$$;