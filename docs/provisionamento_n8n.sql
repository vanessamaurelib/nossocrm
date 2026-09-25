-- Provisionamento das tabelas criadas no SQL Editor para o agente n8n.
-- Não faz parte das migrations do CRM. Rodar no SQL Editor de um projeto novo,
-- depois das migrations. Idempotente.
--
-- Fora deste arquivo, de propósito: public.knowledge_base, search_knowledge_base
-- e a extensão vector (busca vetorial não usada).
--
-- O CRM não chama get_knowledge_base. O n8n usa a chave service_role.
-- service_role ignora o RLS. A policy abaixo continua exigindo auth.uid()
-- para anon e authenticated, que não recebem grant nesta tabela.

CREATE TABLE IF NOT EXISTS public.knowledge_base_text (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid,
    content text NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    category text,
    CONSTRAINT knowledge_base_text_pkey PRIMARY KEY (id),
    CONSTRAINT knowledge_base_text_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE
);

ALTER TABLE public.knowledge_base_text ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'knowledge_base_text'
      AND policyname = 'knowledge_base_text_org_isolate'
  ) THEN
    CREATE POLICY knowledge_base_text_org_isolate ON public.knowledge_base_text
      USING ((organization_id = ( SELECT profiles.organization_id
         FROM public.profiles
        WHERE (profiles.id = auth.uid()))));
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.knowledge_base_text TO service_role;

-- Corpo igual ao dump. CREATE OR REPLACE torna o arquivo idempotente.
CREATE OR REPLACE FUNCTION public.get_knowledge_base(org_id uuid, category_filter text DEFAULT NULL::text) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
  result text := '';
  row_record record;
BEGIN
  FOR row_record IN
    SELECT category, content
    FROM knowledge_base_text
    WHERE organization_id = org_id
      AND (category_filter IS NULL OR category_filter = '' OR category = category_filter)
    ORDER BY category
  LOOP
    result := result || '## ' || upper(row_record.category) || E'\n' || row_record.content || E'\n\n';
  END LOOP;
  RETURN json_build_object('knowledge', result);
END;
$$;

-- Diferença em relação ao dump: o pg_dump não define search_path nesta função.
ALTER FUNCTION public.get_knowledge_base(org_id uuid, category_filter text) SET search_path = public;

REVOKE ALL ON FUNCTION public.get_knowledge_base(org_id uuid, category_filter text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_knowledge_base(org_id uuid, category_filter text) FROM anon;
REVOKE ALL ON FUNCTION public.get_knowledge_base(org_id uuid, category_filter text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_knowledge_base(org_id uuid, category_filter text) TO service_role;
