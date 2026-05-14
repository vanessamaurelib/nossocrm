-- organization_id indexes
CREATE INDEX IF NOT EXISTS idx_activities_organization_id
  ON public.activities(organization_id);

CREATE INDEX IF NOT EXISTS idx_contacts_organization_id
  ON public.contacts(organization_id);

CREATE INDEX IF NOT EXISTS idx_deals_organization_id
  ON public.deals(organization_id);

CREATE INDEX IF NOT EXISTS idx_leads_organization_id
  ON public.leads(organization_id);

-- Composite indexes
CREATE INDEX IF NOT EXISTS idx_contacts_org_stage
  ON public.contacts(organization_id, stage);

CREATE INDEX IF NOT EXISTS idx_contacts_org_status
  ON public.contacts(organization_id, status);

CREATE INDEX IF NOT EXISTS idx_deals_org_board
  ON public.deals(organization_id, board_id);

CREATE INDEX IF NOT EXISTS idx_activities_org_date
  ON public.activities(organization_id, date DESC);

-- Cached RLS org lookup helper
CREATE OR REPLACE FUNCTION public.get_user_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization_id
  FROM public.profiles
  WHERE id = (SELECT auth.uid())
$$;

REVOKE ALL ON FUNCTION public.get_user_org_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_org_id() TO authenticated;