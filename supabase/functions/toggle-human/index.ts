// =============================================================================
// Edge Function: toggle-human
// Proxy para start-human / stop-human na API GPTMaker (evita ETIMEDOUT Vercel).
//
// CRM (API Route) chama:
//   POST https://[projeto].supabase.co/functions/v1/toggle-human
//   Headers: x-internal-secret
//   Body: { chatId, apiKey, action: "start-human" | "stop-human" }
// =============================================================================

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const secret = req.headers.get('x-internal-secret');
  const expectedSecret = Deno.env.get('INTERNAL_SECRET');

  if (!secret || secret !== expectedSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  let body: { chatId: string; apiKey: string; action: string };
  try {
    body = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const { chatId, apiKey, action } = body;

  if (!chatId || !apiKey || !action) {
    return new Response(
      JSON.stringify({ error: 'chatId, apiKey e action são obrigatórios' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const pathSuffix =
    action === 'start-human' ? 'start-human' : action === 'stop-human' ? 'stop-human' : null;

  if (!pathSuffix) {
    return new Response(
      JSON.stringify({ error: 'action deve ser "start-human" ou "stop-human"' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const response = await fetch(
      `https://api.gptmaker.ai/v2/chat/${encodeURIComponent(chatId)}/${pathSuffix}`,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
      },
    );

    const responseText = await response.text();
    console.log(`GPTMaker toggle-human (${action}): ${response.status} ${responseText}`);

    if (!response.ok) {
      return new Response(
        JSON.stringify({ success: false, error: responseText, status: response.status }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }

    let data: unknown;
    try {
      data = responseText ? JSON.parse(responseText) : {};
    } catch {
      data = { raw: responseText };
    }

    return new Response(JSON.stringify({ success: true, data }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Erro ao chamar GPTMaker toggle-human:', error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Erro desconhecido',
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
