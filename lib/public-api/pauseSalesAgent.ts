import { createStaticAdminClient } from '@/lib/supabase/server';

export type PauseSalesAgentSuccess = {
  success: true;
  sales_agent_paused: true;
  already_paused: boolean;
  updated_count: number;
  contact_ids: string[];
};

export type PauseSalesAgentFailure = {
  success: false;
  code: 'VALIDATION_ERROR' | 'NOT_FOUND' | 'DB_ERROR';
  message: string;
};

export type PauseSalesAgentResult = PauseSalesAgentSuccess | PauseSalesAgentFailure;

/**
 * Paused if any active contact row has sales_agent_paused = true.
 * Shared with webhook-messages (same rule; Deno cannot import this module).
 */
export function isSalesAgentPausedIfAny(
  rows: Array<{ sales_agent_paused?: boolean | null } | null | undefined> | null | undefined,
): boolean {
  return (rows ?? []).some((row) => row?.sales_agent_paused === true);
}

/** Trim only. Does not E.164-normalize. If the value starts with +, also try without +. */
export function phoneLookupValues(raw: string): string[] {
  const phone = raw.trim();
  if (!phone) return [];
  if (phone.startsWith('+') && phone.length > 1) {
    const withoutPlus = phone.slice(1);
    return withoutPlus ? [phone, withoutPlus] : [phone];
  }
  return [phone];
}

export async function pauseSalesAgent(opts: {
  organizationId: string;
  phone: string;
}): Promise<PauseSalesAgentResult> {
  const phones = phoneLookupValues(opts.phone);
  if (phones.length === 0) {
    return { success: false, code: 'VALIDATION_ERROR', message: 'phone é obrigatório' };
  }

  const sb = createStaticAdminClient();

  let query = sb
    .from('contacts')
    .select('id, sales_agent_paused')
    .eq('organization_id', opts.organizationId)
    .is('deleted_at', null)
    .is('merged_into_id', null);

  query = phones.length === 1 ? query.eq('phone', phones[0]) : query.in('phone', phones);

  const { data, error } = await query;
  if (error) {
    return { success: false, code: 'DB_ERROR', message: error.message };
  }

  const rows = (data ?? []) as Array<{ id: string; sales_agent_paused: boolean }>;
  if (rows.length === 0) {
    return {
      success: false,
      code: 'NOT_FOUND',
      message: 'Contato não encontrado para este telefone',
    };
  }

  const contactIds = rows.map((row) => row.id);
  const idsToPause = rows.filter((row) => row.sales_agent_paused !== true).map((row) => row.id);
  const alreadyPaused = idsToPause.length === 0;

  if (!alreadyPaused) {
    const { error: updateError } = await sb
      .from('contacts')
      .update({ sales_agent_paused: true })
      .eq('organization_id', opts.organizationId)
      .in('id', idsToPause);

    if (updateError) {
      return { success: false, code: 'DB_ERROR', message: updateError.message };
    }
  }

  return {
    success: true,
    sales_agent_paused: true,
    already_paused: alreadyPaused,
    updated_count: idsToPause.length,
    contact_ids: contactIds,
  };
}
