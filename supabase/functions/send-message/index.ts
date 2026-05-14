// =============================================================================
// Edge Function: send-message
// Proxy para envio de mensagens via API do GPTMaker
//
// Motivo: Vercel tem restrições de rede (ETIMEDOUT) ao chamar api.gptmaker.ai
// Solução: CRM chama esta Edge Function no Supabase, que por sua vez chama
//          o GPTMaker sem restrições de rede.
//
// Endpoint chamado pelo CRM:
//   POST https://[projeto].supabase.co/functions/v1/send-message
//   Body: { chatId, message, apiKey }
//
// =============================================================================

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

// Validação via secret no header
  const secret = req.headers.get('x-internal-secret');
  const expectedSecret = Deno.env.get('INTERNAL_SECRET');
  
  if (!secret || secret !== expectedSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: { chatId: string; message: string; apiKey: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const { chatId, message, apiKey } = body;

  if (!chatId || !message || !apiKey) {
    return new Response(
      JSON.stringify({ error: 'chatId, message e apiKey são obrigatórios' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

  try {
    const response = await fetch(
      `https://api.gptmaker.ai/v2/chat/${chatId}/send-message`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ message }),
      }
    );

    const responseText = await response.text();

    console.log(`GPTMaker response: ${response.status} ${responseText}`);

    if (!response.ok) {
      return new Response(
        JSON.stringify({ success: false, error: responseText, status: response.status }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    }

    let data: unknown;
    try {
      data = JSON.parse(responseText);
    } catch {
      data = { raw: responseText };
    }

    return new Response(
      JSON.stringify({ success: true, data }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Erro ao chamar GPTMaker:', error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Erro desconhecido',
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});