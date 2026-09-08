-- V11: configurable church organization + shared programs/calendar/coordination

WITH root AS (
  SELECT id FROM public.organization_units WHERE code = 'ICC_LE_MANS' LIMIT 1
), ministries AS (
  INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
  SELECT id, 'CAT_MINISTERES', 'Ministères', 'groupe', 'referentiel_simple', 10, '{"category":"ministeres","container":true}'::jsonb FROM root
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, parent_id = EXCLUDED.parent_id, active = true, metadata = EXCLUDED.metadata
  RETURNING id
), dynamics AS (
  INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
  SELECT id, 'CAT_DYNAMIQUES', 'Dynamiques', 'groupe', 'referentiel_simple', 20, '{"category":"dynamiques","container":true}'::jsonb FROM root
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, parent_id = EXCLUDED.parent_id, active = true, metadata = EXCLUDED.metadata
  RETURNING id
), departments AS (
  INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
  SELECT id, 'CAT_DEPARTEMENTS', 'Départements', 'groupe', 'referentiel_simple', 30, '{"category":"departements","container":true}'::jsonb FROM root
  ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, parent_id = EXCLUDED.parent_id, active = true, metadata = EXCLUDED.metadata
  RETURNING id
)
SELECT 1;

INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
SELECT c.id, v.code, v.name, 'ministere'::public.organization_unit_type, 'pilotage_complet'::public.organization_management_mode, v.ord, jsonb_build_object('category','ministeres')
FROM public.organization_units c
CROSS JOIN (VALUES ('MHI','MHI',10),('MFI','MFI',20),('EJP','EJP',30),('JKIDS_MINISTERE','JKIDS',40)) AS v(code,name,ord)
WHERE c.code='CAT_MINISTERES'
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id, name=EXCLUDED.name, active=true, display_order=EXCLUDED.display_order;

UPDATE public.organization_units SET parent_id=(SELECT id FROM public.organization_units WHERE code='CAT_DYNAMIQUES'), name='FI — Familles d’Impact', display_order=10, metadata=coalesce(metadata,'{}'::jsonb)||'{"category":"dynamiques"}'::jsonb WHERE code='FAMILLES_IMPACT';
UPDATE public.organization_units SET parent_id=(SELECT id FROM public.organization_units WHERE code='CAT_DYNAMIQUES'), name='FIJ — Familles d’Impact Jeunes', display_order=20, metadata=coalesce(metadata,'{}'::jsonb)||'{"category":"dynamiques"}'::jsonb WHERE code='FAMILLES_IMPACT_JEUNES';
INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
SELECT id,'FAMILLES_DISCIPLES','Familles de disciples','groupe','pilotage_complet',30,'{"category":"dynamiques"}'::jsonb FROM public.organization_units WHERE code='CAT_DYNAMIQUES'
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id,name=EXCLUDED.name,active=true;

INSERT INTO public.organization_units (parent_id, code, name, unit_type, management_mode, display_order, metadata)
SELECT c.id,v.code,v.name,'departement'::public.organization_unit_type,v.mode::public.organization_management_mode,v.ord,jsonb_build_object('category','departements')
FROM public.organization_units c
CROSS JOIN (VALUES
 ('ACCUEIL','Accueil','pilotage_complet',10),('COMMUNICATION','Communication','gestion_legere',20),('COORDINATION','Coordination','pilotage_complet',30),('FINANCES','Finances','pilotage_complet',40),('NAVETTE','Navette','pilotage_complet',50),('SECURITE','Sécurité','pilotage_complet',60),('JKIDS_DEPARTEMENT','JKIDS','pilotage_complet',70),('INTEGRATION','Intégration','pilotage_complet',80),('MLA','MLA','pilotage_complet',90),('MODERATION','Modération','pilotage_complet',100),('FORMATION','Formation','pilotage_complet',110)
) AS v(code,name,mode,ord)
WHERE c.code='CAT_DEPARTEMENTS'
ON CONFLICT (code) DO UPDATE SET parent_id=EXCLUDED.parent_id,name=EXCLUDED.name,active=true,management_mode=EXCLUDED.management_mode,display_order=EXCLUDED.display_order;

CREATE OR REPLACE FUNCTION public.can_manage_organization_unit(p_unit_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  WITH RECURSIVE ancestors AS (
    SELECT id,parent_id FROM public.organization_units WHERE id=p_unit_id
    UNION ALL SELECT ou.id,ou.parent_id FROM public.organization_units ou JOIN ancestors a ON a.parent_id=ou.id
  )
  SELECT public.is_pasteur_or_admin() OR EXISTS (
    SELECT 1 FROM public.profile_unit_assignments a JOIN ancestors x ON x.id=a.organization_unit_id
    WHERE a.profile_id=auth.uid() AND a.active AND (a.ends_at IS NULL OR a.ends_at>=current_date)
      AND (a.can_manage OR a.assignment_role IN ('responsable','responsable_adjoint','referent'))
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_unit_people(p_unit_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  WITH RECURSIVE ancestors AS (
    SELECT id,parent_id FROM public.organization_units WHERE id=p_unit_id
    UNION ALL SELECT ou.id,ou.parent_id FROM public.organization_units ou JOIN ancestors a ON a.parent_id=ou.id
  )
  SELECT public.is_pasteur_or_admin() OR EXISTS (
    SELECT 1 FROM public.profile_unit_assignments a JOIN ancestors x ON x.id=a.organization_unit_id
    WHERE a.profile_id=auth.uid() AND a.active AND (a.ends_at IS NULL OR a.ends_at>=current_date)
      AND (a.can_view_sensitive OR a.can_manage OR a.assignment_role IN ('responsable','responsable_adjoint','referent'))
  );
$$;

DROP POLICY IF EXISTS member_unit_affiliations_select ON public.member_unit_affiliations;
CREATE POLICY member_unit_affiliations_select ON public.member_unit_affiliations FOR SELECT TO authenticated USING (public.can_view_unit_people(organization_unit_id));

ALTER TABLE public.programs
  ADD COLUMN IF NOT EXISTS owner_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'eglise' CHECK (visibility IN ('eglise','unites_concernees','prive')),
  ADD COLUMN IF NOT EXISTS show_on_global_calendar boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_programs_owner_unit ON public.programs(owner_unit_id);
CREATE INDEX IF NOT EXISTS idx_programs_global_calendar ON public.programs(show_on_global_calendar,starts_at);

CREATE TABLE public.program_organization_units (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), program_id uuid NOT NULL REFERENCES public.programs(id) ON DELETE CASCADE,
 organization_unit_id uuid NOT NULL REFERENCES public.organization_units(id) ON DELETE CASCADE,
 relation_role text NOT NULL DEFAULT 'participant' CHECK (relation_role IN ('organisateur','participant','support','audience','beneficiaire')),
 can_edit_program boolean NOT NULL DEFAULT false, notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(program_id,organization_unit_id,relation_role)
);
CREATE INDEX idx_program_org_program ON public.program_organization_units(program_id);
CREATE INDEX idx_program_org_unit ON public.program_organization_units(organization_unit_id);

CREATE TABLE public.program_workstreams (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), program_id uuid NOT NULL REFERENCES public.programs(id) ON DELETE CASCADE,
 organization_unit_id uuid NOT NULL REFERENCES public.organization_units(id) ON DELETE CASCADE,
 title text NOT NULL, description text, responsible_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 status text NOT NULL DEFAULT 'a_preparer' CHECK (status IN ('a_preparer','en_cours','pret','bloque','termine','annule')),
 readiness_percent integer NOT NULL DEFAULT 0 CHECK (readiness_percent BETWEEN 0 AND 100), starts_at timestamptz, ends_at timestamptz, notes text,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_program_workstreams_program ON public.program_workstreams(program_id);
CREATE INDEX idx_program_workstreams_unit ON public.program_workstreams(organization_unit_id);
CREATE INDEX idx_program_workstreams_responsible ON public.program_workstreams(responsible_profile_id);

CREATE TABLE public.program_timeline_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), program_id uuid NOT NULL REFERENCES public.programs(id) ON DELETE CASCADE,
 workstream_id uuid REFERENCES public.program_workstreams(id) ON DELETE SET NULL, organization_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL,
 title text NOT NULL, description text, starts_at timestamptz, ends_at timestamptz, responsible_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 status text NOT NULL DEFAULT 'a_venir' CHECK (status IN ('a_venir','en_cours','termine','retard','annule')), display_order integer NOT NULL DEFAULT 0,
 instructions text, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at>=starts_at)
);
CREATE INDEX idx_timeline_program_order ON public.program_timeline_items(program_id,display_order);
CREATE INDEX idx_timeline_unit ON public.program_timeline_items(organization_unit_id);
CREATE INDEX idx_timeline_responsible ON public.program_timeline_items(responsible_profile_id);

INSERT INTO public.organization_unit_capabilities (organization_unit_id,capability_code,enabled,configuration)
SELECT ou.id,c.code,true,'{}'::jsonb FROM public.organization_units ou CROSS JOIN (VALUES ('programmes'),('calendrier'),('liste_programmes'),('membres'),('statistiques')) c(code)
WHERE ou.code IN ('MHI','MFI','EJP','JKIDS_MINISTERE','FAMILLES_DISCIPLES','FAMILLES_IMPACT','FAMILLES_IMPACT_JEUNES') ON CONFLICT (organization_unit_id,capability_code) DO UPDATE SET enabled=true;
INSERT INTO public.organization_unit_capabilities (organization_unit_id,capability_code,enabled,configuration)
SELECT ou.id,c.code,true,'{}'::jsonb FROM public.organization_units ou CROSS JOIN (VALUES ('personnes'),('presences'),('orientation_integration'),('statistiques'),('calendrier'),('liste_programmes')) c(code) WHERE ou.code='ACCUEIL' ON CONFLICT (organization_unit_id,capability_code) DO UPDATE SET enabled=true;
INSERT INTO public.organization_unit_capabilities (organization_unit_id,capability_code,enabled,configuration)
SELECT ou.id,c.code,true,'{}'::jsonb FROM public.organization_units ou CROSS JOIN (VALUES ('suivi_integration'),('phoning'),('entretiens'),('orientations'),('recommandations'),('statistiques'),('personnes')) c(code) WHERE ou.code='INTEGRATION' ON CONFLICT (organization_unit_id,capability_code) DO UPDATE SET enabled=true;
INSERT INTO public.organization_unit_capabilities (organization_unit_id,capability_code,enabled,configuration)
SELECT ou.id,c.code,true,'{}'::jsonb FROM public.organization_units ou CROSS JOIN (VALUES ('demandes_communication'),('statistiques')) c(code) WHERE ou.code='COMMUNICATION' ON CONFLICT (organization_unit_id,capability_code) DO UPDATE SET enabled=true;
INSERT INTO public.organization_unit_capabilities (organization_unit_id,capability_code,enabled,configuration)
SELECT ou.id,c.code,true,'{}'::jsonb FROM public.organization_units ou CROSS JOIN (VALUES ('programmes'),('calendrier'),('liste_programmes'),('deroule_programmes'),('statistiques')) c(code) WHERE ou.code='COORDINATION' ON CONFLICT (organization_unit_id,capability_code) DO UPDATE SET enabled=true;

ALTER TABLE public.program_organization_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_workstreams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_timeline_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY program_org_select ON public.program_organization_units FOR SELECT TO authenticated USING (true);
CREATE POLICY program_org_manage ON public.program_organization_units FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR public.can_manage_organization_unit(organization_unit_id)) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR public.can_manage_organization_unit(organization_unit_id));
CREATE POLICY workstreams_select ON public.program_workstreams FOR SELECT TO authenticated USING (true);
CREATE POLICY workstreams_manage ON public.program_workstreams FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR public.can_manage_organization_unit(organization_unit_id)) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR public.can_manage_organization_unit(organization_unit_id));
CREATE POLICY timeline_select ON public.program_timeline_items FOR SELECT TO authenticated USING (true);
CREATE POLICY timeline_manage ON public.program_timeline_items FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR (organization_unit_id IS NOT NULL AND public.can_manage_organization_unit(organization_unit_id))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_program(program_id) OR (organization_unit_id IS NOT NULL AND public.can_manage_organization_unit(organization_unit_id)));
CREATE TRIGGER set_program_org_updated_at BEFORE UPDATE ON public.program_organization_units FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_program_workstreams_updated_at BEFORE UPDATE ON public.program_workstreams FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_program_timeline_updated_at BEFORE UPDATE ON public.program_timeline_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE VIEW public.global_program_calendar AS
SELECT p.id AS program_id,p.title,p.description,p.status,p.starts_at,p.ends_at,p.location_name,p.city,p.owner_unit_id,owner.name AS owner_unit_name,owner.code AS owner_unit_code,p.visibility,p.show_on_global_calendar,
 coalesce(jsonb_agg(DISTINCT jsonb_build_object('id',ou.id,'code',ou.code,'name',ou.name,'role',pou.relation_role)) FILTER (WHERE ou.id IS NOT NULL),'[]'::jsonb) AS organization_units
FROM public.programs p LEFT JOIN public.organization_units owner ON owner.id=p.owner_unit_id LEFT JOIN public.program_organization_units pou ON pou.program_id=p.id LEFT JOIN public.organization_units ou ON ou.id=pou.organization_unit_id
GROUP BY p.id,owner.id;

DO $$ DECLARE r record; BEGIN FOR r IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef LOOP EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',r.signature); EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon',r.signature); END LOOP; END $$;
GRANT EXECUTE ON FUNCTION public.can_manage_organization_unit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_unit_people(uuid) TO authenticated;
