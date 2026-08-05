import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

type HumanToggleAction = 'start-human' | 'stop-human';

export async function POST(request: NextRequest) {
  try {
    const [supabase, body] = await Promise.all([
      createClient(),
      request.json() as Promise<{ conversationId?: string; action?: string }>,
    ]);

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return NextResponse.json({ message: 'Unauthorized' }, { status: 401 });
    }

    const { conversationId, action } = body;
    if (!conversationId || (action !== 'start-human' && action !== 'stop-human')) {
      return NextResponse.json(
        { message: 'conversationId e action ("start-human" | "stop-human") são obrigatórios' },
        { status: 400 },
      );
    }

    const orgId: string | undefined =
      (user.app_metadata?.organization_id as string | undefined) ??
      (await supabase
        .from('profiles')
        .select('organization_id')
        .eq('id', user.id)
        .single()
        .then(({ data }) => data?.organization_id as string | undefined));

    if (!orgId) {
      return NextResponse.json({ message: 'Profile not found' }, { status: 404 });
    }

    const { data: conversation, error: convError } = await supabase
      .from('messaging_conversations')
      .select(`
        id,
        organization_id,
        contact_id
      `)
      .eq('id', conversationId)
      .eq('organization_id', orgId)
      .single();

    if (convError || !conversation) {
      return NextResponse.json({ message: 'Conversation not found' }, { status: 404 });
    }

    const contactId = conversation.contact_id as string | null;
    if (!contactId) {
      return NextResponse.json(
        { message: 'Conversa sem contato vinculado' },
        { status: 400 },
      );
    }

    const paused = (action as HumanToggleAction) === 'start-human';

    const { error: updateError } = await supabase
      .from('contacts')
      .update({ sales_agent_paused: paused })
      .eq('id', contactId)
      .eq('organization_id', orgId);

    if (updateError) {
      console.error('[human-toggle] Failed to update sales_agent_paused:', updateError.message);
      return NextResponse.json({ message: 'Falha ao atualizar contato' }, { status: 500 });
    }

    return NextResponse.json({ success: true, salesAgentPaused: paused });
  } catch (error) {
    console.error('[human-toggle]', error instanceof Error ? error.message : error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
