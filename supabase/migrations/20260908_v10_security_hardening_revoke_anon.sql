-- V10 — Durcissement de sécurité
-- Aucune fonction SECURITY DEFINER du schéma public ne doit être
-- exécutable par le rôle anonyme.

do $$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as identity_args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
  loop
    execute format(
      'revoke execute on function %I.%I(%s) from anon',
      r.schema_name,
      r.function_name,
      r.identity_args
    );
  end loop;
end $$;
