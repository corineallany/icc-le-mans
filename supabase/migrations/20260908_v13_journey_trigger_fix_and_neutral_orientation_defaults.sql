-- V13: fix member journey trigger ordering and remove guessed orientation age criteria.

DROP TRIGGER IF EXISTS trg_member_journey_status ON public.members;

CREATE OR REPLACE FUNCTION public.prepare_member_journey_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.journey_status='membre_integre'
     AND (TG_OP='INSERT' OR NEW.journey_status IS DISTINCT FROM OLD.journey_status)
     AND NEW.integrated_at IS NULL THEN
    NEW.integrated_at := now();
    NEW.integration_confirmed_by := coalesce(NEW.integration_confirmed_by, auth.uid());
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.log_member_journey_status_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='INSERT' OR NEW.journey_status IS DISTINCT FROM OLD.journey_status THEN
    INSERT INTO public.member_journey_history(member_id, from_status, to_status, changed_by)
    VALUES (NEW.id, CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.journey_status END, NEW.journey_status, auth.uid());
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_prepare_member_journey_status
BEFORE INSERT OR UPDATE OF journey_status ON public.members
FOR EACH ROW EXECUTE FUNCTION public.prepare_member_journey_status();

CREATE TRIGGER trg_log_member_journey_status
AFTER INSERT OR UPDATE OF journey_status ON public.members
FOR EACH ROW EXECUTE FUNCTION public.log_member_journey_status_change();

UPDATE public.organization_integration_profiles p
SET min_age=NULL,
    max_age=NULL,
    age_required=false,
    gender_required=false,
    updated_at=now()
FROM public.organization_units ou
WHERE ou.id=p.organization_unit_id
  AND coalesce((p.rules->>'seeded')::boolean,false)=true;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.signature);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.signature);
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.can_manage_organization_unit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_unit_people(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_integration_unit_recommendations(uuid) TO authenticated;
