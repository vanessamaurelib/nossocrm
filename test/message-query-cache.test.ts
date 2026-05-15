import { describe, expect, it } from 'vitest';
import type { MessagingMessage } from '@/lib/messaging/types';
import {
  appendOptimisticToFlat,
  appendToNewestPage,
  dedupeInfiniteMessagesGlobally,
  dedupeMessagesById,
  hasOptimisticOutboundInInfinite,
  replaceOptimisticInInfinite,
  type MessagesInfiniteData,
} from '@/lib/messaging/cache/message-query-cache';

function msg(id: string): MessagingMessage {
  return {
    id,
    conversationId: 'conv-1',
    direction: 'outbound',
    contentType: 'text',
    content: { type: 'text', text: 'hi' },
    status: 'pending',
    metadata: {},
    createdAt: '2026-01-01T00:00:00.000Z',
  };
}

function infiniteData(...pageMessageIds: string[][]): MessagesInfiniteData {
  return {
    pageParams: [null],
    pages: pageMessageIds.map((ids) => ({
      messages: ids.map(msg),
      nextCursor: null,
    })),
  };
}

describe('message-query-cache', () => {
  it('dedupes by id', () => {
    const a = msg('a');
    expect(dedupeMessagesById([a, a, msg('b')])).toHaveLength(2);
  });

  it('appendToNewestPage skips duplicate id', () => {
    const data = infiniteData(['a']);
    const result = appendToNewestPage(data, msg('a'));
    expect(result?.pages[0].messages).toHaveLength(1);
  });

  it('replaceOptimisticInInfinite removes duplicate real after realtime race', () => {
    const tempId = 'temp-1';
    const real = msg('real-uuid');
    const data: MessagesInfiniteData = {
      pageParams: [null],
      pages: [
        {
          messages: [msg(tempId), real],
          nextCursor: null,
        },
      ],
    };
    const result = replaceOptimisticInInfinite(data, tempId, real);
    const flat = result?.pages.flatMap((p) => p.messages) ?? [];
    expect(flat.filter((m) => m.id === 'real-uuid')).toHaveLength(1);
    expect(flat.some((m) => m.id.startsWith('temp-'))).toBe(false);
  });

  it('replaceOptimisticInInfinite keeps other pending temps', () => {
    const real = msg('real-uuid');
    const data = infiniteData(['temp-other', 'temp-mine']);
    const result = replaceOptimisticInInfinite(data, 'temp-mine', real);
    const flat = result?.pages.flatMap((p) => p.messages) ?? [];
    expect(flat.some((m) => m.id === 'temp-other')).toBe(true);
    expect(flat.some((m) => m.id === 'real-uuid')).toBe(true);
    expect(flat.some((m) => m.id === 'temp-mine')).toBe(false);
  });

  it('dedupeInfiniteMessagesGlobally keeps first occurrence across pages', () => {
    const data: MessagesInfiniteData = {
      pageParams: [null, 'c2'],
      pages: [
        { messages: [msg('dup'), msg('x')], nextCursor: 'c2' },
        { messages: [msg('y'), msg('dup')], nextCursor: null },
      ],
    };
    const result = dedupeInfiniteMessagesGlobally(data)!;
    const flat = result.pages.flatMap((p) => p.messages);
    expect(flat.filter((m) => m.id === 'dup')).toHaveLength(1);
    expect(flat.find((m) => m.id === 'dup')).toMatchObject({ id: 'dup' });
  });

  it('hasOptimisticOutboundInInfinite detects temp rows', () => {
    expect(hasOptimisticOutboundInInfinite(infiniteData(['temp-123']))).toBe(true);
    expect(hasOptimisticOutboundInInfinite(infiniteData(['uuid']))).toBe(false);
  });

  it('appendOptimisticToFlat keeps concurrent temps', () => {
    const result = appendOptimisticToFlat([msg('temp-1'), msg('a')], msg('temp-2'));
    expect(result.filter((m) => m.id.startsWith('temp-'))).toHaveLength(2);
    expect(result.find((m) => m.id === 'temp-2')).toBeDefined();
  });
});
