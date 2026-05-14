import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import type { GPTMakerCredentials } from '@/lib/messaging/providers/whatsapp/gptmaker.provider';

type HumanToggleAction = 'start-human' | 'stop-human';

type ChannelRow = {
  id: string;
  provider: string;
  credentials: Record<string, unknown>;
};

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
        external_contact_id,
        channel:messaging_channels!channel_id (
          id,
          provider,
          credentials
        )
      `)
      .eq('id', conversationId)
      .eq('organization_id', orgId)
      .single();

    if (convError || !conversation) {
      return NextResponse.json({ message: 'Conversation not found' }, { status: 404 });
    }

    const channel = conversation.channel as unknown as ChannelRow | null;
    if (!channel || channel.provider !== 'gptmaker') {
      return NextResponse.json(
        { message: 'Ação disponível apenas para canais GPTMaker' },
        { status: 400 },
      );
    }

    const credentials = channel.credentials as unknown as GPTMakerCredentials;
    const apiKey = credentials?.apiKey;
    if (!apiKey) {
      return NextResponse.json({ message: 'API Key do canal não configurada' }, { status: 400 });
    }

    const chatId = conversation.external_contact_id as string;
    if (!chatId) {
      return NextResponse.json({ message: 'Conversa sem external_contact_id' }, { status: 400 });
    }

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const internalSecret = process.env.INTERNAL_SECRET;
    if (!supabaseUrl || !internalSecret) {
      console.error('[human-toggle] Missing NEXT_PUBLIC_SUPABASE_URL or INTERNAL_SECRET');
      return NextResponse.json({ message: 'Server configuration error' }, { status: 500 });
    }

    const proxyUrl = `${supabaseUrl}/functions/v1/toggle-human`;
    const edgeResponse = await fetch(proxyUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-internal-secret': internalSecret,
      },
      body: JSON.stringify({
        chatId,
        apiKey,
        action: action as HumanToggleAction,
      }),
    });

    if (!edgeResponse.ok) {
      const text = await edgeResponse.text();
      return NextResponse.json(
        { message: `Proxy error: ${edgeResponse.status}`, detail: text },
        { status: 502 },
      );
    }

    const data = (await edgeResponse.json()) as { success?: boolean; error?: string; data?: unknown };
    if (!data.success) {
      return NextResponse.json(
        { message: data.error ?? 'GPTMaker retornou erro' },
        { status: 502 },
      );
    }

    return NextResponse.json({ success: true, data: data.data });
  } catch (error) {
    console.error('[human-toggle]', error instanceof Error ? error.message : error);
    return NextResponse.json({ message: 'Internal server error' }, { status: 500 });
  }
}
