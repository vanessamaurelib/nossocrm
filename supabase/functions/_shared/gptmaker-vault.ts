import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export async function getGptmakerApiKey(): Promise<string> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('Supabase credentials not configured');
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data, error } = await supabase.rpc('get_gptmaker_api_key');

  if (error) {
    console.error('Vault RPC get_gptmaker_api_key failed:', error.message);
    throw new Error('Failed to load GPTMaker API key');
  }

  if (!data || typeof data !== 'string' || !data.trim()) {
    throw new Error('GPTMaker API key not found in Vault');
  }

  return data;
}
