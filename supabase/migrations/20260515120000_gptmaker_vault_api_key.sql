-- GPTMaker API key: read from Supabase Vault (service_role only via RPC).
-- Secret name in Vault: gptmaker_api_key

CREATE OR REPLACE FUNCTION public.get_gptmaker_api_key()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT decrypted_secret
  FROM vault.decrypted_secrets
  WHERE name = 'gptmaker_api_key'
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_gptmaker_api_key() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_gptmaker_api_key() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_gptmaker_api_key() TO service_role;

-- Remove plaintext apiKey from channel credentials (now in Vault).
UPDATE messaging_channels
SET credentials = credentials - 'apiKey'
WHERE provider = 'gptmaker'
  AND credentials ? 'apiKey';
