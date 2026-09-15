import { NextResponse } from 'next/server';
import { z } from 'zod';
import { authPublicApi } from '@/lib/public-api/auth';
import { pauseSalesAgent } from '@/lib/public-api/pauseSalesAgent';

export const runtime = 'nodejs';

const PauseSalesAgentSchema = z.object({
  phone: z.string(),
}).strict();

export async function POST(request: Request) {
  const auth = await authPublicApi(request);
  if (!auth.ok) return NextResponse.json(auth.body, { status: auth.status });

  try {
    const body = await request.json().catch(() => null);
    const parsed = PauseSalesAgentSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { success: false, code: 'VALIDATION_ERROR', message: 'phone é obrigatório' },
        { status: 200 },
      );
    }

    const result = await pauseSalesAgent({
      organizationId: auth.organizationId,
      phone: parsed.data.phone,
    });

    return NextResponse.json(result, { status: 200 });
  } catch (error) {
    console.error('[pause-sales-agent]', error instanceof Error ? error.message : error);
    return NextResponse.json(
      { success: false, code: 'INTERNAL_ERROR', message: 'Internal server error' },
      { status: 200 },
    );
  }
}
