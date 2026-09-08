create or replace function public.icc_create_pending_profile()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into public.profiles(id,first_name,last_name,role,active,access_status,requested_at)
  values(new.id,nullif(trim(coalesce(new.raw_user_meta_data->>'first_name','')),''),nullif(trim(coalesce(new.raw_user_meta_data->>'last_name','')),''),'copilote'::public.app_role,false,'pending',now())
  on conflict(id) do update set
    first_name=coalesce(excluded.first_name,public.profiles.first_name),
    last_name=coalesce(excluded.last_name,public.profiles.last_name),
    active=case when public.profiles.access_status='approved' then true else false end,
    access_status=case when public.profiles.access_status='approved' then 'approved' else 'pending' end,
    requested_at=coalesce(public.profiles.requested_at,now());

  insert into public.notifications(recipient_profile_id,type,title,body,link,metadata)
  select p.id,'access_request','Nouvelle demande d’accès',
         coalesce(nullif(trim(concat_ws(' ',new.raw_user_meta_data->>'first_name',new.raw_user_meta_data->>'last_name')),''),new.email,'Une personne') || ' demande l’accès à l’application.',
         '#settings',jsonb_build_object('profile_id',new.id,'email',new.email)
  from public.profiles p
  where p.active=true and p.access_status='approved' and p.role='admin'::public.app_role;
  return new;
end;
$$;
revoke all on function public.icc_create_pending_profile() from public,anon,authenticated;
revoke all on function public.admin_list_access_requests() from public,anon;
grant execute on function public.admin_list_access_requests() to authenticated;
revoke all on function public.admin_set_access_request(uuid,text,public.app_role,uuid) from public,anon;
grant execute on function public.admin_set_access_request(uuid,text,public.app_role,uuid) to authenticated;
