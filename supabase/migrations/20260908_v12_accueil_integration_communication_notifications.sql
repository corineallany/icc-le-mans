-- V12: Accueil + Intégration + Communication + notifications
-- Applied to Supabase production. This tracked migration captures the complete data model introduced in V12.

DO $$ BEGIN
  CREATE TYPE public.person_journey_status AS ENUM ('nouveau','visiteur','visiteur_regulier','integration_en_cours','membre_integre','inactif','archive');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS journey_status public.person_journey_status NOT NULL DEFAULT 'nouveau',
  ADD COLUMN IF NOT EXISTS first_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS integrated_at timestamptz,
  ADD COLUMN IF NOT EXISTS integration_confirmed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS family_situation text,
  ADD COLUMN IF NOT EXISTS interests text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS skills text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS availability_tags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS engagement_preferences text[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS idx_members_journey_status ON public.members(journey_status);
CREATE INDEX IF NOT EXISTS idx_members_first_seen_at ON public.members(first_seen_at);
CREATE INDEX IF NOT EXISTS idx_members_integration_confirmed_by ON public.members(integration_confirmed_by);

ALTER TABLE public.external_visitors
  ADD COLUMN IF NOT EXISTS converted_member_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS first_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS source_program_id uuid REFERENCES public.programs(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_external_visitors_converted_member ON public.external_visitors(converted_member_id);
CREATE INDEX IF NOT EXISTS idx_external_visitors_source_program ON public.external_visitors(source_program_id);

CREATE TABLE public.member_journey_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  from_status public.person_journey_status, to_status public.person_journey_status NOT NULL, reason text,
  changed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL, changed_at timestamptz NOT NULL DEFAULT now(), metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX idx_member_journey_history_member ON public.member_journey_history(member_id,changed_at DESC);

CREATE OR REPLACE FUNCTION public.log_member_journey_status_change() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF TG_OP='INSERT' OR NEW.journey_status IS DISTINCT FROM OLD.journey_status THEN
    INSERT INTO public.member_journey_history(member_id,from_status,to_status,changed_by)
    VALUES (NEW.id,CASE WHEN TG_OP='INSERT' THEN NULL ELSE OLD.journey_status END,NEW.journey_status,auth.uid());
    IF NEW.journey_status='membre_integre' AND NEW.integrated_at IS NULL THEN
      NEW.integrated_at:=now(); NEW.integration_confirmed_by:=coalesce(NEW.integration_confirmed_by,auth.uid());
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_member_journey_status BEFORE INSERT OR UPDATE OF journey_status ON public.members FOR EACH ROW EXECUTE FUNCTION public.log_member_journey_status_change();

CREATE TABLE public.integration_referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE,
  member_id uuid REFERENCES public.members(id) ON DELETE CASCADE, external_visitor_id uuid REFERENCES public.external_visitors(id) ON DELETE CASCADE,
  program_id uuid REFERENCES public.programs(id) ON DELETE SET NULL, attendance_id uuid REFERENCES public.attendance(id) ON DELETE SET NULL,
  referred_from_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL, referred_to_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL,
  reason text, minimal_contact_only boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'envoye' CHECK (status IN ('envoye','recu','pris_en_charge','termine','annule')),
  referred_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT, received_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  referred_at timestamptz NOT NULL DEFAULT now(), received_at timestamptz, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (((member_id IS NOT NULL)::int+(external_visitor_id IS NOT NULL)::int)=1)
);
CREATE INDEX idx_integration_referrals_integration ON public.integration_referrals(integration_id);
CREATE INDEX idx_integration_referrals_member ON public.integration_referrals(member_id);
CREATE INDEX idx_integration_referrals_external ON public.integration_referrals(external_visitor_id);
CREATE INDEX idx_integration_referrals_program ON public.integration_referrals(program_id);
CREATE INDEX idx_integration_referrals_status ON public.integration_referrals(status,referred_at DESC);

ALTER TABLE public.integrations
  ADD COLUMN IF NOT EXISTS source_program_id uuid REFERENCES public.programs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS referred_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS referral_reason text,
  ADD COLUMN IF NOT EXISTS first_contact_at timestamptz,
  ADD COLUMN IF NOT EXISTS next_followup_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS assigned_integration_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_integrations_source_program ON public.integrations(source_program_id);
CREATE INDEX IF NOT EXISTS idx_integrations_next_followup ON public.integrations(next_followup_at);
CREATE INDEX IF NOT EXISTS idx_integrations_assigned_integration_profile ON public.integrations(assigned_integration_profile_id);

CREATE TABLE public.integration_person_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL UNIQUE REFERENCES public.integrations(id) ON DELETE CASCADE,
  family_situation text, interests text[] NOT NULL DEFAULT '{}', skills text[] NOT NULL DEFAULT '{}', availability_tags text[] NOT NULL DEFAULT '{}',
  engagement_preferences text[] NOT NULL DEFAULT '{}', stated_needs text[] NOT NULL DEFAULT '{}', aspirations text[] NOT NULL DEFAULT '{}',
  experience_notes text, notes text, updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.integration_interviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  program_id uuid REFERENCES public.programs(id) ON DELETE SET NULL, interviewer_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  scheduled_at timestamptz, happened boolean NOT NULL DEFAULT false, happened_at timestamptz, minimal_contact_only boolean NOT NULL DEFAULT false,
  non_interview_reason text, contact_phone_captured boolean NOT NULL DEFAULT false, contact_email_captured boolean NOT NULL DEFAULT false,
  outcome text, notes text, next_action text, next_action_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (happened OR non_interview_reason IS NOT NULL OR minimal_contact_only)
);
CREATE INDEX idx_integration_interviews_integration ON public.integration_interviews(integration_id,created_at DESC);
CREATE INDEX idx_integration_interviews_interviewer ON public.integration_interviews(interviewer_profile_id);
CREATE TABLE public.integration_followups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  activity_type text NOT NULL CHECK (activity_type IN ('appel','sms','whatsapp','email','entretien','rencontre','autre')),
  status text NOT NULL DEFAULT 'a_faire' CHECK (status IN ('a_faire','effectue','sans_reponse','a_rappeler','refuse','annule')),
  scheduled_at timestamptz, completed_at timestamptz, performed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  result text, notes text, next_action text, next_action_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_integration_followups_integration ON public.integration_followups(integration_id,created_at DESC);
CREATE INDEX idx_integration_followups_due ON public.integration_followups(status,scheduled_at);
CREATE INDEX idx_integration_followups_performed_by ON public.integration_followups(performed_by);

CREATE TABLE public.organization_integration_profiles (
  organization_unit_id uuid PRIMARY KEY REFERENCES public.organization_units(id) ON DELETE CASCADE,
  accepts_orientation boolean NOT NULL DEFAULT true, active boolean NOT NULL DEFAULT true,
  min_age integer CHECK (min_age IS NULL OR min_age>=0), max_age integer CHECK (max_age IS NULL OR max_age>=0), age_required boolean NOT NULL DEFAULT false,
  allowed_genders text[] NOT NULL DEFAULT '{}', gender_required boolean NOT NULL DEFAULT false, family_situations text[] NOT NULL DEFAULT '{}',
  preferred_interests text[] NOT NULL DEFAULT '{}', preferred_skills text[] NOT NULL DEFAULT '{}', preferred_availability text[] NOT NULL DEFAULT '{}',
  prerequisites text[] NOT NULL DEFAULT '{}', engagement_level text, current_need_score integer NOT NULL DEFAULT 0 CHECK (current_need_score BETWEEN 0 AND 100),
  current_needs text, orientation_description text, recommendation_weight numeric(5,2) NOT NULL DEFAULT 1.00 CHECK (recommendation_weight>0),
  rules jsonb NOT NULL DEFAULT '{}'::jsonb, updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), CHECK (min_age IS NULL OR max_age IS NULL OR max_age>=min_age)
);
CREATE TABLE public.integration_orientations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  organization_unit_id uuid NOT NULL REFERENCES public.organization_units(id) ON DELETE CASCADE,
  source text NOT NULL DEFAULT 'humain' CHECK (source IN ('systeme','integration','personne','responsable_unite','autre')),
  match_score integer CHECK (match_score IS NULL OR match_score BETWEEN 0 AND 100),
  status text NOT NULL DEFAULT 'suggere' CHECK (status IN ('suggere','propose','interesse','a_contacter','accepte','refuse','rejoint','archive')),
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb, person_comment text, team_comment text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL, decided_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  decided_at timestamptz, joined_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_integration_orientations_integration ON public.integration_orientations(integration_id,match_score DESC NULLS LAST);
CREATE INDEX idx_integration_orientations_unit ON public.integration_orientations(organization_unit_id,status);
CREATE TABLE public.integration_unit_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  organization_unit_id uuid NOT NULL REFERENCES public.organization_units(id) ON DELETE CASCADE, score integer NOT NULL CHECK (score BETWEEN 0 AND 100),
  reasons jsonb NOT NULL DEFAULT '[]'::jsonb, generated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(integration_id,organization_unit_id)
);
CREATE INDEX idx_integration_recommendations_rank ON public.integration_unit_recommendations(integration_id,score DESC);

CREATE OR REPLACE FUNCTION public.refresh_integration_unit_recommendations(target_integration uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_age integer; v_gender text; v_interests text[]:='{}'; v_skills text[]:='{}'; v_avail text[]:='{}'; v_count integer:=0;
BEGIN
  IF NOT (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT extract(year from age(current_date,coalesce(m.birth_date,ev.birth_date)))::int,coalesce(m.gender,ev.gender),coalesce(ipp.interests,m.interests,'{}'),coalesce(ipp.skills,m.skills,'{}'),coalesce(ipp.availability_tags,m.availability_tags,'{}')
  INTO v_age,v_gender,v_interests,v_skills,v_avail FROM public.integrations i LEFT JOIN public.members m ON m.id=i.member_id LEFT JOIN public.external_visitors ev ON ev.id=i.external_visitor_id LEFT JOIN public.integration_person_profiles ipp ON ipp.integration_id=i.id WHERE i.id=target_integration;
  DELETE FROM public.integration_unit_recommendations WHERE integration_id=target_integration;
  INSERT INTO public.integration_unit_recommendations(integration_id,organization_unit_id,score,reasons)
  SELECT target_integration,p.organization_unit_id,
    least(100,greatest(0,round((35
      +CASE WHEN v_age IS NOT NULL AND (p.min_age IS NULL OR v_age>=p.min_age) AND (p.max_age IS NULL OR v_age<=p.max_age) THEN 15 ELSE 0 END
      +CASE WHEN cardinality(p.allowed_genders)=0 OR v_gender IS NULL OR v_gender=ANY(p.allowed_genders) THEN 5 ELSE 0 END
      +CASE WHEN EXISTS(SELECT 1 FROM unnest(v_interests) x WHERE x=ANY(p.preferred_interests)) THEN 15 ELSE 0 END
      +CASE WHEN EXISTS(SELECT 1 FROM unnest(v_skills) x WHERE x=ANY(p.preferred_skills)) THEN 10 ELSE 0 END
      +CASE WHEN EXISTS(SELECT 1 FROM unnest(v_avail) x WHERE x=ANY(p.preferred_availability)) THEN 10 ELSE 0 END
      +(p.current_need_score*0.10))*p.recommendation_weight)::int)),
    jsonb_strip_nulls(jsonb_build_object('age',CASE WHEN v_age IS NOT NULL THEN jsonb_build_object('value',v_age,'compatible',((p.min_age IS NULL OR v_age>=p.min_age) AND (p.max_age IS NULL OR v_age<=p.max_age))) END,'interets_communs',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM unnest(v_interests) x WHERE x=ANY(p.preferred_interests)),'competences_communes',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM unnest(v_skills) x WHERE x=ANY(p.preferred_skills)),'disponibilites_communes',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM unnest(v_avail) x WHERE x=ANY(p.preferred_availability)),'besoin_actuel',p.current_need_score,'besoins',p.current_needs))
  FROM public.organization_integration_profiles p JOIN public.organization_units ou ON ou.id=p.organization_unit_id AND ou.active
  WHERE p.active AND p.accepts_orientation AND (NOT p.age_required OR v_age IS NULL OR ((p.min_age IS NULL OR v_age>=p.min_age) AND (p.max_age IS NULL OR v_age<=p.max_age))) AND (NOT p.gender_required OR v_gender IS NULL OR cardinality(p.allowed_genders)=0 OR v_gender=ANY(p.allowed_genders));
  GET DIAGNOSTICS v_count=ROW_COUNT; RETURN v_count;
END $$;

CREATE TABLE public.communication_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), requesting_unit_id uuid NOT NULL REFERENCES public.organization_units(id) ON DELETE RESTRICT,
  communication_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL, program_id uuid REFERENCES public.programs(id) ON DELETE SET NULL,
  workstream_id uuid REFERENCES public.program_workstreams(id) ON DELETE SET NULL, title text NOT NULL, objective text, target_audience text, brief text,
  requested_deliverables text[] NOT NULL DEFAULT '{}', channels text[] NOT NULL DEFAULT '{}', formats text[] NOT NULL DEFAULT '{}', source_assets_notes text, constraints text,
  priority text NOT NULL DEFAULT 'normale' CHECK (priority IN ('basse','normale','haute','urgente')),
  status text NOT NULL DEFAULT 'brouillon' CHECK (status IN ('brouillon','envoyee','recue','a_preciser','prise_en_charge','en_cours','livree','terminee','annulee')),
  desired_delivery_at timestamptz, planned_publication_at timestamptz, requested_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  communication_owner_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL, external_app_reference text, external_app_url text,
  submitted_at timestamptz, completed_at timestamptz, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_communication_requests_unit ON public.communication_requests(requesting_unit_id,created_at DESC);
CREATE INDEX idx_communication_requests_program ON public.communication_requests(program_id);
CREATE INDEX idx_communication_requests_status ON public.communication_requests(status,priority,created_at DESC);
CREATE INDEX idx_communication_requests_owner ON public.communication_requests(communication_owner_profile_id);
CREATE TABLE public.communication_request_files (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL REFERENCES public.communication_requests(id) ON DELETE CASCADE, file_name text NOT NULL,
 storage_path text, external_url text, file_type text, file_size_bytes bigint, description text, uploaded_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(), CHECK (storage_path IS NOT NULL OR external_url IS NOT NULL)
);
CREATE INDEX idx_communication_request_files_request ON public.communication_request_files(request_id);

CREATE TABLE public.notification_devices (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 device_name text, device_brand text, platform text, user_agent text, push_endpoint text NOT NULL, p256dh_key text, auth_key text,
 push_enabled boolean NOT NULL DEFAULT true, active boolean NOT NULL DEFAULT true, last_seen_at timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(profile_id,push_endpoint)
);
CREATE INDEX idx_notification_devices_profile ON public.notification_devices(profile_id,active,push_enabled);
CREATE TABLE public.notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recipient_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 type text NOT NULL, title text NOT NULL, body text, link text, source_unit_id uuid REFERENCES public.organization_units(id) ON DELETE SET NULL,
 read_at timestamptz, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_recipient ON public.notifications(recipient_profile_id,read_at,created_at DESC);
CREATE TABLE public.notification_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
 device_id uuid REFERENCES public.notification_devices(id) ON DELETE CASCADE, channel text NOT NULL DEFAULT 'push' CHECK (channel IN ('push','email','in_app')),
 status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed','skipped')), attempts integer NOT NULL DEFAULT 0, last_error text, sent_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_deliveries_pending ON public.notification_deliveries(status,created_at);
CREATE INDEX idx_notification_deliveries_notification ON public.notification_deliveries(notification_id);

CREATE OR REPLACE FUNCTION public.enqueue_unit_notification(p_unit_id uuid,p_type text,p_title text,p_body text DEFAULT NULL,p_link text DEFAULT NULL,p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_count integer; BEGIN
 INSERT INTO public.notifications(recipient_profile_id,type,title,body,link,source_unit_id,metadata)
 SELECT DISTINCT a.profile_id,p_type,p_title,p_body,p_link,p_unit_id,coalesce(p_metadata,'{}'::jsonb) FROM public.profile_unit_assignments a WHERE a.organization_unit_id=p_unit_id AND a.active AND (a.ends_at IS NULL OR a.ends_at>=current_date);
 GET DIAGNOSTICS v_count=ROW_COUNT; RETURN v_count;
END $$;
CREATE OR REPLACE FUNCTION public.create_push_delivery_outbox() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN INSERT INTO public.notification_deliveries(notification_id,device_id,channel,status) SELECT NEW.id,d.id,'push','pending' FROM public.notification_devices d WHERE d.profile_id=NEW.recipient_profile_id AND d.active AND d.push_enabled; RETURN NEW; END $$;
CREATE TRIGGER trg_notification_push_outbox AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.create_push_delivery_outbox();
CREATE OR REPLACE FUNCTION public.notify_integration_referral() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_unit uuid; BEGIN v_unit:=coalesce(NEW.referred_to_unit_id,(SELECT id FROM public.organization_units WHERE code='INTEGRATION')); IF v_unit IS NOT NULL THEN PERFORM public.enqueue_unit_notification(v_unit,'nouveau_transmis_integration','Nouveau transmis à l’Intégration',coalesce(NEW.reason,'Une personne a été orientée depuis l’Accueil.'),'/integration',jsonb_build_object('referral_id',NEW.id,'program_id',NEW.program_id)); END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_notify_integration_referral AFTER INSERT ON public.integration_referrals FOR EACH ROW EXECUTE FUNCTION public.notify_integration_referral();
CREATE OR REPLACE FUNCTION public.notify_communication_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_unit uuid; BEGIN IF NEW.status='envoyee' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN v_unit:=coalesce(NEW.communication_unit_id,(SELECT id FROM public.organization_units WHERE code='COMMUNICATION')); IF v_unit IS NOT NULL THEN PERFORM public.enqueue_unit_notification(v_unit,'nouvelle_demande_communication','Nouvelle demande Communication',NEW.title,'/communication/demandes/'||NEW.id::text,jsonb_build_object('request_id',NEW.id,'requesting_unit_id',NEW.requesting_unit_id,'program_id',NEW.program_id)); END IF; END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_notify_communication_request AFTER INSERT OR UPDATE OF status ON public.communication_requests FOR EACH ROW EXECUTE FUNCTION public.notify_communication_request();

CREATE OR REPLACE VIEW public.member_attendance_stats AS
SELECT m.id AS member_id,count(a.id) FILTER(WHERE a.status='present') AS total_presences,min(coalesce(p.starts_at,a.recorded_at)) FILTER(WHERE a.status='present') AS first_presence_at,max(coalesce(p.starts_at,a.recorded_at)) FILTER(WHERE a.status='present') AS last_presence_at,count(a.id) FILTER(WHERE a.status='present' AND coalesce(p.starts_at,a.recorded_at)>=now()-interval '30 days') AS presences_30j,count(a.id) FILTER(WHERE a.status='present' AND coalesce(p.starts_at,a.recorded_at)>=now()-interval '60 days') AS presences_60j,count(a.id) FILTER(WHERE a.status='present' AND coalesce(p.starts_at,a.recorded_at)>=now()-interval '90 days') AS presences_90j,count(DISTINCT a.program_id) FILTER(WHERE a.status='present' AND a.program_id IS NOT NULL) AS programmes_distincts
FROM public.members m LEFT JOIN public.attendance a ON a.member_id=m.id LEFT JOIN public.programs p ON p.id=a.program_id GROUP BY m.id;
CREATE OR REPLACE VIEW public.integration_pilotage AS
SELECT i.id AS integration_id,i.status AS integration_status,i.member_id,i.external_visitor_id,coalesce(m.first_name,ev.first_name) AS first_name,coalesce(m.last_name,ev.last_name) AS last_name,m.journey_status,i.created_at,i.first_contact_at,i.next_followup_at,count(DISTINCT iv.id) AS interview_records,count(DISTINCT iv.id) FILTER(WHERE iv.happened) AS interviews_realises,count(DISTINCT f.id) AS followups_total,count(DISTINCT f.id) FILTER(WHERE f.status IN ('a_faire','a_rappeler')) AS followups_a_faire,count(DISTINCT o.id) FILTER(WHERE o.status IN ('interesse','accepte','rejoint')) AS orientations_positives,s.total_presences,s.presences_30j,s.presences_60j,s.presences_90j,CASE WHEN m.id IS NOT NULL AND coalesce(s.presences_90j,0)>=6 AND coalesce((SELECT count(*) FROM public.integration_interviews x WHERE x.integration_id=i.id AND x.happened),0)>0 THEN true ELSE false END AS suggestion_examiner_integration_membre
FROM public.integrations i LEFT JOIN public.members m ON m.id=i.member_id LEFT JOIN public.external_visitors ev ON ev.id=i.external_visitor_id LEFT JOIN public.integration_interviews iv ON iv.integration_id=i.id LEFT JOIN public.integration_followups f ON f.integration_id=i.id LEFT JOIN public.integration_orientations o ON o.integration_id=i.id LEFT JOIN public.member_attendance_stats s ON s.member_id=m.id GROUP BY i.id,m.id,ev.id,s.member_id,s.total_presences,s.presences_30j,s.presences_60j,s.presences_90j;

ALTER TABLE public.member_journey_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_person_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_followups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_integration_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_orientations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_unit_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_request_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY journey_history_select ON public.member_journey_history FOR SELECT TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='ACCUEIL')) OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY journey_history_manage ON public.member_journey_history FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_referrals_select ON public.integration_referrals FOR SELECT TO authenticated USING (public.is_pasteur_or_admin() OR (referred_from_unit_id IS NOT NULL AND public.can_manage_organization_unit(referred_from_unit_id)) OR (referred_to_unit_id IS NOT NULL AND public.can_manage_organization_unit(referred_to_unit_id)) OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='ACCUEIL')) OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_referrals_manage ON public.integration_referrals FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='ACCUEIL')) OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='ACCUEIL')) OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_person_profiles_manage ON public.integration_person_profiles FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_interviews_manage ON public.integration_interviews FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_followups_manage ON public.integration_followups FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY integration_profiles_manage ON public.organization_integration_profiles FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(organization_unit_id)) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(organization_unit_id));
CREATE POLICY integration_orientations_manage ON public.integration_orientations FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')) OR public.can_manage_organization_unit(organization_unit_id)) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')) OR public.can_manage_organization_unit(organization_unit_id));
CREATE POLICY integration_recommendations_manage ON public.integration_unit_recommendations FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION'))) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit((SELECT id FROM public.organization_units WHERE code='INTEGRATION')));
CREATE POLICY communication_requests_select ON public.communication_requests FOR SELECT TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(requesting_unit_id) OR (communication_unit_id IS NOT NULL AND public.can_manage_organization_unit(communication_unit_id)) OR requested_by=(select auth.uid()));
CREATE POLICY communication_requests_manage ON public.communication_requests FOR ALL TO authenticated USING (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(requesting_unit_id) OR (communication_unit_id IS NOT NULL AND public.can_manage_organization_unit(communication_unit_id)) OR requested_by=(select auth.uid())) WITH CHECK (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(requesting_unit_id) OR (communication_unit_id IS NOT NULL AND public.can_manage_organization_unit(communication_unit_id)) OR requested_by=(select auth.uid()));
CREATE POLICY communication_files_select ON public.communication_request_files FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.communication_requests r WHERE r.id=request_id));
CREATE POLICY communication_files_manage ON public.communication_request_files FOR ALL TO authenticated USING (EXISTS(SELECT 1 FROM public.communication_requests r WHERE r.id=request_id AND (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(r.requesting_unit_id) OR (r.communication_unit_id IS NOT NULL AND public.can_manage_organization_unit(r.communication_unit_id)) OR r.requested_by=(select auth.uid())))) WITH CHECK (EXISTS(SELECT 1 FROM public.communication_requests r WHERE r.id=request_id AND (public.is_pasteur_or_admin() OR public.can_manage_organization_unit(r.requesting_unit_id) OR (r.communication_unit_id IS NOT NULL AND public.can_manage_organization_unit(r.communication_unit_id)) OR r.requested_by=(select auth.uid()))));
CREATE POLICY devices_owner ON public.notification_devices FOR ALL TO authenticated USING (profile_id=(select auth.uid()) OR public.is_pasteur_or_admin()) WITH CHECK (profile_id=(select auth.uid()) OR public.is_pasteur_or_admin());
CREATE POLICY notifications_owner_select ON public.notifications FOR SELECT TO authenticated USING (recipient_profile_id=(select auth.uid()) OR public.is_pasteur_or_admin());
CREATE POLICY notifications_owner_update ON public.notifications FOR UPDATE TO authenticated USING (recipient_profile_id=(select auth.uid()) OR public.is_pasteur_or_admin()) WITH CHECK (recipient_profile_id=(select auth.uid()) OR public.is_pasteur_or_admin());
CREATE POLICY notification_deliveries_owner_select ON public.notification_deliveries FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.notifications n WHERE n.id=notification_id AND (n.recipient_profile_id=(select auth.uid()) OR public.is_pasteur_or_admin())));

CREATE TRIGGER set_integration_person_profile_updated_at BEFORE UPDATE ON public.integration_person_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_integration_interview_updated_at BEFORE UPDATE ON public.integration_interviews FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_integration_followup_updated_at BEFORE UPDATE ON public.integration_followups FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_org_integration_profile_updated_at BEFORE UPDATE ON public.organization_integration_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_integration_orientation_updated_at BEFORE UPDATE ON public.integration_orientations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_communication_request_updated_at BEFORE UPDATE ON public.communication_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER set_notification_device_updated_at BEFORE UPDATE ON public.notification_devices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.organization_integration_profiles(organization_unit_id,accepts_orientation,min_age,max_age,orientation_description,rules)
SELECT id,true,CASE WHEN code='FAMILLES_IMPACT_JEUNES' THEN 18 ELSE NULL END,CASE WHEN code='FAMILLES_IMPACT_JEUNES' THEN 25 ELSE NULL END,
CASE code WHEN 'FAMILLES_IMPACT' THEN 'Dynamique FI — critères à affiner dans les paramètres.' WHEN 'FAMILLES_IMPACT_JEUNES' THEN 'Dynamique FIJ — tranche d’âge initiale configurable.' WHEN 'FAMILLES_DISCIPLES' THEN 'Familles de disciples — critères à configurer selon le fonctionnement de l’église.' ELSE 'Critères d’orientation configurables.' END,jsonb_build_object('seeded',true)
FROM public.organization_units WHERE code IN ('FAMILLES_IMPACT','FAMILLES_IMPACT_JEUNES','FAMILLES_DISCIPLES','MHI','MFI','EJP','JKIDS_MINISTERE','ACCUEIL','NAVETTE','FORMATION','MODERATION') ON CONFLICT (organization_unit_id) DO NOTHING;

DO $$ DECLARE r record; BEGIN FOR r IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prosecdef LOOP EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC',r.signature); EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon',r.signature); END LOOP; END $$;
GRANT EXECUTE ON FUNCTION public.refresh_integration_unit_recommendations(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_organization_unit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_unit_people(uuid) TO authenticated;
