import { beforeEach, describe, expect, it, vi } from 'vitest';

const ORG_ID = 'a1b2c3d4-e5f6-4a7b-8c9d-e0f1a2b3c4d5';
const CONTACT_A = 'd4e5f6a7-b8c9-4d0e-8f1a-b2c3d4e5f6a7';
const CONTACT_B = 'e5f6a7b8-c9d0-4e1f-8a2b-c3d4e5f6a7b8';

type SelectResult = {
  data: Array<{ id: string; sales_agent_paused: boolean }> | null;
  error: { message: string } | null;
};

let selectResult: SelectResult;
let updateError: { message: string } | null;
const builders: ReturnType<typeof createBuilder>[] = [];

function createBuilder() {
  const builder = {
    select: vi.fn(),
    update: vi.fn(),
    eq: vi.fn(),
    is: vi.fn(),
    in: vi.fn(),
    then: undefined as unknown as (
      onFulfilled: (value: unknown) => unknown,
      onRejected?: (reason: unknown) => unknown,
    ) => Promise<unknown>,
  };
  builder.select.mockReturnValue(builder);
  builder.update.mockReturnValue(builder);
  builder.eq.mockReturnValue(builder);
  builder.is.mockReturnValue(builder);
  builder.in.mockReturnValue(builder);
  builder.then = (onFulfilled, onRejected) => {
    const payload = builder.update.mock.calls.length > 0
      ? { error: updateError }
      : selectResult;
    return Promise.resolve(payload).then(onFulfilled, onRejected);
  };
  builders.push(builder);
  return builder;
}

vi.mock('@/lib/supabase/server', () => ({
  createStaticAdminClient: vi.fn(() => ({
    from: vi.fn((table: string) => {
      if (table !== 'contacts') throw new Error(`Unexpected table: ${table}`);
      return createBuilder();
    }),
  })),
}));

import {
  isSalesAgentPausedIfAny,
  pauseSalesAgent,
  phoneLookupValues,
} from './pauseSalesAgent';

describe('isSalesAgentPausedIfAny', () => {
  it('é false quando não há linhas', () => {
    expect(isSalesAgentPausedIfAny([])).toBe(false);
    expect(isSalesAgentPausedIfAny(null)).toBe(false);
    expect(isSalesAgentPausedIfAny(undefined)).toBe(false);
  });

  it('é false quando todos estão false', () => {
    expect(isSalesAgentPausedIfAny([
      { sales_agent_paused: false },
      { sales_agent_paused: false },
    ])).toBe(false);
  });

  it('é true se qualquer contato ativo estiver true', () => {
    expect(isSalesAgentPausedIfAny([
      { sales_agent_paused: false },
      { sales_agent_paused: true },
    ])).toBe(true);
  });

  it('é true quando o único match já está pausado', () => {
    expect(isSalesAgentPausedIfAny([{ sales_agent_paused: true }])).toBe(true);
  });
});

describe('phoneLookupValues', () => {
  it('só faz trim, sem E.164', () => {
    expect(phoneLookupValues('  5511930452744  ')).toEqual(['5511930452744']);
  });

  it('se vier com +, tenta também sem +', () => {
    expect(phoneLookupValues('+5511930452744')).toEqual(['+5511930452744', '5511930452744']);
  });
});

describe('pauseSalesAgent', () => {
  beforeEach(() => {
    builders.length = 0;
    updateError = null;
    selectResult = { data: null, error: null };
  });

  it('pausa o contato encontrado (match)', async () => {
    selectResult = {
      data: [{ id: CONTACT_A, sales_agent_paused: false }],
      error: null,
    };

    const result = await pauseSalesAgent({ organizationId: ORG_ID, phone: '5511930452744' });

    expect(result).toEqual({
      success: true,
      sales_agent_paused: true,
      already_paused: false,
      updated_count: 1,
      contact_ids: [CONTACT_A],
    });
    expect(builders[0].eq).toHaveBeenCalledWith('organization_id', ORG_ID);
    expect(builders[0].eq).toHaveBeenCalledWith('phone', '5511930452744');
    expect(builders[0].is).toHaveBeenCalledWith('deleted_at', null);
    expect(builders[0].is).toHaveBeenCalledWith('merged_into_id', null);
    expect(builders[1].update).toHaveBeenCalledWith({ sales_agent_paused: true });
    expect(builders[1].in).toHaveBeenCalledWith('id', [CONTACT_A]);
  });

  it('é idempotente se já estiver pausado', async () => {
    selectResult = {
      data: [{ id: CONTACT_A, sales_agent_paused: true }],
      error: null,
    };

    const result = await pauseSalesAgent({ organizationId: ORG_ID, phone: '5511930452744' });

    expect(result).toEqual({
      success: true,
      sales_agent_paused: true,
      already_paused: true,
      updated_count: 0,
      contact_ids: [CONTACT_A],
    });
    expect(builders).toHaveLength(1);
  });

  it('retorna 404 de negócio quando o telefone não existe', async () => {
    selectResult = { data: [], error: null };

    const result = await pauseSalesAgent({ organizationId: ORG_ID, phone: '5511930452744' });

    expect(result).toEqual({
      success: false,
      code: 'NOT_FOUND',
      message: 'Contato não encontrado para este telefone',
    });
    expect(builders).toHaveLength(1);
  });

  it('pausa todos os duplicatas do mesmo phone', async () => {
    selectResult = {
      data: [
        { id: CONTACT_A, sales_agent_paused: false },
        { id: CONTACT_B, sales_agent_paused: true },
      ],
      error: null,
    };

    const result = await pauseSalesAgent({ organizationId: ORG_ID, phone: '5511930452744' });

    expect(result).toEqual({
      success: true,
      sales_agent_paused: true,
      already_paused: false,
      updated_count: 1,
      contact_ids: [CONTACT_A, CONTACT_B],
    });
    expect(builders[1].in).toHaveBeenCalledWith('id', [CONTACT_A]);
  });

  it('não cria contato quando o telefone está vazio', async () => {
    const result = await pauseSalesAgent({ organizationId: ORG_ID, phone: '   ' });
    expect(result).toEqual({
      success: false,
      code: 'VALIDATION_ERROR',
      message: 'phone é obrigatório',
    });
    expect(builders).toHaveLength(0);
  });
});
