// =============================================================================
// Edge Function: webhook-messages
// Recebe eventos onNewMessage do GPTMaker e espelha no Supabase
//
// Fluxo:
// 1. GPTMaker dispara POST com payload de mensagem
// 2. Valida autenticação via WEBHOOK_SECRET
// 3. Idempotência: ignora se messageId já foi processado
// 4. Cria ou atualiza conversa em messaging_conversations
// 5. Grava mensagem em messaging_messages
// 6. Realtime do Supabase notifica a tela /messaging automaticamente
//
// Configuração necessária (Supabase → Edge Functions → Secrets):
//   WEBHOOK_SECRET   → string secreta pra validar origem do GPTMaker
//   CHANNEL_ID       → 37ead11e-75e7-44f2-ac6b-db419e75db93
//   BUSINESS_UNIT_ID → 94cdbafa-2021-478a-aed0-5b1d239a9ea9
//   ORGANIZATION_ID  → 390b818d-6f2a-4f2a-9460-531a4cf60822
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ---------------------------------------------------------------------------
// Tipos
// ---------------------------------------------------------------------------

interface GPTMakerMessagePayload {
  date: string;           // ISO 8601 UTC
  assistantId: string;
  contextId: string;      // ID da conversa = chatId
  messageId: string;      // ID único da mensagem (usado pra idempotência)
  role: 'user' | 'assistant';
  message: string;
  channel: string;        // 'CLOUD_API' em produção, 'TRAINING' em testes
  contactName: string | null;
  contactPhone: string | null;
  images: string[];
  audios: string[];
  documents: string[];
}

// ---------------------------------------------------------------------------
// Handler principal
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  // Só aceita POST
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

// Validação via secret na URL
const url = new URL(req.url);
const secret = url.searchParams.get('secret');
const expectedSecret = Deno.env.get('WEBHOOK_SECRET');

console.log('secret recebido (primeiros 8):', secret?.substring(0, 8));
console.log('secret esperado (primeiros 8):', expectedSecret?.substring(0, 8));

if (!secret || secret !== expectedSecret) {
  return new Response('Unauthorized', { status: 401 });
}

  // Parse do payload
  let payload: GPTMakerMessagePayload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  if ((payload.role as string) === 'tool') {
    return new Response(
      JSON.stringify({ skipped: true, reason: 'tool_response' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  if (!payload.message && payload.images.length === 0 && payload.audios.length === 0 && payload.documents.length === 0) {
    return new Response(
      JSON.stringify({ skipped: true, reason: 'empty_message' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Ignorar mensagens de treino (canal TRAINING = testes pelo painel)
  if (payload.channel === 'TRAINING') {
    console.log('Ignorando mensagem de canal TRAINING');
    return new Response(JSON.stringify({ skipped: true, reason: 'TRAINING channel' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Variáveis de ambiente
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const channelId = Deno.env.get('CHANNEL_ID')!;
  const businessUnitId = Deno.env.get('BUSINESS_UNIT_ID')!;
  const organizationId = Deno.env.get('ORGANIZATION_ID')!;

  const supabase = createClient(supabaseUrl, supabaseKey);

  try {
    // -------------------------------------------------------------------------
    // 1. Idempotência: verificar se messageId já foi processado
    // -------------------------------------------------------------------------
    const { data: existingMessage } = await supabase
      .from('messaging_messages')
      .select('id')
      .eq('external_id', payload.messageId)
      .maybeSingle();

    if (existingMessage) {
      console.log(`Mensagem ${payload.messageId} já processada, ignorando`);
      return new Response(JSON.stringify({ skipped: true, reason: 'already processed' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // -------------------------------------------------------------------------
    // 2. Criar ou atualizar conversa
    // O contextId do GPTMaker é o identificador único da conversa.
    // Usamos external_contact_id = contextId pra garantir que a mesma
    // conversa do WhatsApp sempre mapeia pro mesmo registro no Supabase.
    // -------------------------------------------------------------------------
    const externalContactId = payload.contextId;
    const contactPhone = payload.contactPhone ?? externalContactId.split('-').pop() ?? '';
    const contactName = payload.contactName ?? 'Desconhecido';

    const { data: conversation, error: convError } = await supabase
      .from('messaging_conversations')
      .upsert(
        {
          organization_id: organizationId,
          channel_id: channelId,
          business_unit_id: businessUnitId,
          external_contact_id: externalContactId,
          external_contact_name: contactName,
          status: 'open',
          priority: 'normal',
        },
        {
          onConflict: 'channel_id,external_contact_id',
          ignoreDuplicates: false,
        }
      )
      .select('id, metadata')
      .single();

    if (convError) {
      console.error('Erro ao upsert conversa:', convError);
      throw convError;
    }

    const conversationId = conversation.id;

    // -------------------------------------------------------------------------
    // 3. Garantir contato no CRM (auto-cadastro de lead inbound)
    // -------------------------------------------------------------------------
    if (payload.role === 'user' && contactPhone) {
      let contactId: string | null = null;

      const { data: existingContact, error: contactLookupError } = await supabase
        .from('contacts')
        .select('id')
        .eq('organization_id', organizationId)
        .eq('phone', contactPhone)
        .is('deleted_at', null)
        .maybeSingle();

      if (contactLookupError) {
        console.error('Erro ao buscar contato:', contactLookupError);
        throw contactLookupError;
      }

      if (existingContact) {
        contactId = existingContact.id;
      } else {
        const { data: createdContact, error: createContactError } = await supabase
          .from('contacts')
          .insert({
            name: payload.contactName ?? 'Novo Lead',
            phone: contactPhone,
            organization_id: organizationId,
            source: 'gptmaker',
          })
          .select('id')
          .single();

        if (createContactError) {
          console.error('Erro ao criar contato:', createContactError);
          throw createContactError;
        }

        contactId = createdContact.id;
        console.log(`Contato auto-cadastrado (${contactPhone}): ${contactId}`);
      }

      const { error: linkError } = await supabase
        .from('messaging_conversations')
        .update({ contact_id: contactId })
        .eq('id', conversationId)
        .is('contact_id', null);

      if (linkError) {
        console.error('Erro ao vincular conversa ao contato:', linkError);
      }

      // -----------------------------------------------------------------------
      // 4. Garantir deal no primeiro board da organização (só cria se contato ainda não tem deal)
      // -----------------------------------------------------------------------
      try {
        const { data: existingDeal, error: dealLookupError } = await supabase
          .from('deals')
          .select('id')
          .eq('contact_id', contactId)
          .eq('organization_id', organizationId)
          .is('deleted_at', null)
          .limit(1)
          .maybeSingle();

        if (dealLookupError) {
          console.error('Erro ao buscar deal existente:', dealLookupError);
        } else if (!existingDeal) {
          const { data: board, error: boardError } = await supabase
            .from('boards')
            .select('id')
            .eq('organization_id', organizationId)
            .is('deleted_at', null)
            .order('created_at', { ascending: true })
            .limit(1)
            .maybeSingle();

          if (boardError || !board) {
            console.error('Nenhum board encontrado para a organização:', boardError);
          } else {
            const { data: firstStage, error: stageError } = await supabase
              .from('board_stages')
              .select('id')
              .eq('board_id', board.id)
              .eq('organization_id', organizationId)
              .order('order', { ascending: true })
              .limit(1)
              .maybeSingle();

            if (stageError || !firstStage) {
              console.error('Primeiro estágio do board não encontrado:', stageError);
            } else {
              const dealTitle =
                payload.contactName && payload.contactName.trim().length > 0
                  ? payload.contactName
                  : contactPhone;

              const { error: createDealError } = await supabase
                .from('deals')
                .insert({
                  title: dealTitle,
                  contact_id: contactId,
                  organization_id: organizationId,
                  board_id: board.id,
                  stage_id: firstStage.id,
                });

              if (createDealError) {
                console.error('Erro ao criar deal:', createDealError);
              } else {
                console.log(`Deal auto-criado no board ${board.id} para contato ${contactId}`);
              }
            }
          }
        }
      } catch (dealAutoCreateError) {
        console.error('Falha inesperada no auto-cadastro de deal:', dealAutoCreateError);
      }
    }

    // -------------------------------------------------------------------------
    // 5. Gravar mensagem
    // role 'user' = inbound (cliente → agente)
    // role 'assistant' = outbound (agente IA → cliente)
    //
    // Outbound pelo CRM: POST /api/messaging/messages já faz INSERT; o webhook
    // pode chegar antes do UPDATE de external_id. Merge na linha CRM evita duplicata.
    // Critério: outbound + external_id null ou gptmaker-* + sender_type = user + últimos 30s;
    // vários candidatos → mais recente. Sem igualdade de texto.
    // -------------------------------------------------------------------------
    const direction = payload.role === 'user' ? 'inbound' : 'outbound';

    // Determinar tipo de conteúdo (texto ou mídia)
    let contentType = 'text';
    let content: Record<string, unknown> = { type: 'text', text: payload.message };

    if (payload.images.length > 0) {
      contentType = 'image';
      content = { type: 'image', mediaUrl: payload.images[0], mimeType: 'image/jpeg', caption: payload.message || undefined };
    } else if (payload.audios.length > 0) {
      contentType = 'audio';
      content = { type: 'audio', mediaUrl: payload.audios[0], mimeType: 'audio/ogg' };
    } else if (payload.documents.length > 0) {
      contentType = 'document';
      content = { type: 'document', mediaUrl: payload.documents[0], mimeType: 'application/octet-stream', fileName: 'documento' };
    }

    if (payload.message?.includes('contentType":"application/json')) {
      return new Response(
        JSON.stringify({ skipped: true, reason: 'json_content_payload', conversationId }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    const newMetadata = {
      gptmaker_context_id: payload.contextId,
      gptmaker_assistant_id: payload.assistantId,
      channel: payload.channel,
    };

    if (direction === 'outbound') {
      const thirtySecondsAgo = new Date(Date.now() - 30_000).toISOString();
      const { data: crmCandidates, error: crmLookupError } = await supabase
        .from('messaging_messages')
        .select('id, metadata')
        .eq('conversation_id', conversationId)
        .eq('direction', 'outbound')
        .or('external_id.is.null,external_id.like.gptmaker-%')
        .eq('sender_type', 'user')
        .gte('created_at', thirtySecondsAgo)
        .order('created_at', { ascending: false })
        .limit(1);

      if (crmLookupError) {
        console.error('Erro ao buscar linha CRM para merge outbound:', crmLookupError);
        throw crmLookupError;
      }

      const crmRow = crmCandidates?.[0];
      if (crmRow) {
        const prevMeta = (crmRow.metadata as Record<string, unknown> | null) ?? {};
        const { error: mergeError } = await supabase
          .from('messaging_messages')
          .update({
            external_id: payload.messageId,
            sent_at: payload.date,
            status: 'sent',
            sender_name: 'GPTMaker IA',
            metadata: { ...prevMeta, ...newMetadata },
          })
          .eq('id', crmRow.id);

        if (mergeError) {
          console.error('Erro ao mergear mensagem outbound na linha CRM:', mergeError);
          throw mergeError;
        }

        console.log(
          `✅ Webhook ${payload.messageId} mergeado na linha CRM ${crmRow.id} (evita INSERT duplicado)`,
        );

        return new Response(
          JSON.stringify({
            success: true,
            conversationId,
            messageId: crmRow.id,
            mergedFromCrmRow: true,
          }),
          {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          },
        );
      }
    }

    const { data: message, error: msgError } = await supabase
      .from('messaging_messages')
      .insert({
        conversation_id: conversationId,
        external_id: payload.messageId,
        direction,
        content_type: contentType,
        content,
        status: direction === 'inbound' ? 'delivered' : 'sent',
        sender_type: payload.role === 'user' ? 'user' : 'ai',
        sender_name: payload.role === 'user' ? (payload.contactName ?? 'Cliente') : 'GPTMaker IA',
        sent_at: payload.date,
        metadata: newMetadata,
      })
      .select('id')
      .single();

    if (msgError) {
      console.error('Erro ao inserir mensagem:', msgError);
      throw msgError;
    }

    if (direction === 'inbound') {
      try {
        const conversationMetadata = conversation.metadata as Record<string, unknown> | null;
        const dealId = conversationMetadata?.deal_id;

        if (typeof dealId === 'string' && dealId) {
          const { error: queueError } = await supabase
            .from('ai_pending_evaluations')
            .insert({
              organization_id: organizationId,
              conversation_id: conversationId,
              deal_id: dealId,
              message_id: message.id,
              message_text: payload.message,
            });

          if (queueError) throw queueError;
        }
      } catch (error) {
        console.warn('Erro ao enfileirar avaliação de estágio:', error);
      }
    }

    if (direction === 'inbound') {
      try {
        const appUrl = Deno.env.get('CRM_APP_URL');
        const internalSecret = Deno.env.get('INTERNAL_API_SECRET');

        if (!appUrl || !internalSecret) {
          console.warn('CRM_APP_URL ou INTERNAL_API_SECRET ausente; pulando processamento AI');
        } else {
          const response = await fetch(`${appUrl}/api/messaging/ai/process`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-Internal-Secret': internalSecret,
            },
            body: JSON.stringify({
              conversationId,
              organizationId,
              messageId: message.id,
              messageText: payload.message,
            }),
          });

          if (!response.ok) {
            console.warn('Falha ao acionar processamento AI:', response.status, await response.text());
          }
        }
      } catch (error) {
        console.warn('Erro ao acionar processamento AI:', error);
      }
    }

    console.log(`✅ Mensagem ${payload.messageId} processada → conversa ${conversationId}`);

    return new Response(
      JSON.stringify({
        success: true,
        conversationId,
        messageId: message.id,
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('Erro ao processar webhook:', error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
});