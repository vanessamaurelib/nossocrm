import type { InfiniteData } from '@tanstack/react-query';
import type { MessagingMessage } from '@/lib/messaging/types';

export type MessagesInfiniteData = InfiniteData<{
  messages: MessagingMessage[];
  nextCursor: string | null;
}>;

export function isOptimisticMessageId(id: string): boolean {
  return id.startsWith('temp-');
}

/** Keeps the first occurrence of each message id. */
export function dedupeMessagesById(messages: MessagingMessage[]): MessagingMessage[] {
  const seen = new Set<string>();
  const result: MessagingMessage[] = [];
  for (const message of messages) {
    if (seen.has(message.id)) continue;
    seen.add(message.id);
    result.push(message);
  }
  return result;
}

export function hasOptimisticOutbound(messages: MessagingMessage[]): boolean {
  return messages.some((m) => isOptimisticMessageId(m.id));
}

export function messageExistsInInfinite(
  data: MessagesInfiniteData | undefined,
  messageId: string,
): boolean {
  return data?.pages.some((p) => p.messages.some((m) => m.id === messageId)) ?? false;
}

export function hasOptimisticOutboundInInfinite(
  data: MessagesInfiniteData | undefined,
): boolean {
  return data?.pages.some((p) => hasOptimisticOutbound(p.messages)) ?? false;
}

/**
 * Drops duplicate message ids across pages (first occurrence wins in flatMap order:
 * page 0 → page 1 → …).
 */
export function dedupeInfiniteMessagesGlobally(
  data: MessagesInfiniteData | undefined,
): MessagesInfiniteData | undefined {
  if (!data) return data;
  const seen = new Set<string>();
  const pages = data.pages.map((page) => ({
    ...page,
    messages: page.messages.filter((m) => {
      if (seen.has(m.id)) return false;
      seen.add(m.id);
      return true;
    }),
  }));
  return { ...data, pages };
}

/**
 * Appends a message to pages[0] (most recent page).
 * Skips append if the id already exists anywhere in the cache.
 */
export function appendToNewestPage(
  data: MessagesInfiniteData | undefined,
  message: MessagingMessage,
): MessagesInfiniteData | undefined {
  if (!data) return data;
  if (messageExistsInInfinite(data, message.id)) return data;

  const pages = data.pages.map((page, i) => {
    if (i !== 0) return page;
    return { ...page, messages: [...page.messages, message] };
  });

  return dedupeInfiniteMessagesGlobally({ ...data, pages });
}

/**
 * Replaces one temp row with the server row and removes duplicate ids globally.
 * Other temp-* rows stay (concurrent sends).
 */
export function replaceOptimisticInInfinite(
  data: MessagesInfiniteData | undefined,
  tempId: string,
  realMessage: MessagingMessage,
): MessagesInfiniteData | undefined {
  if (!data) return data;

  const pages = data.pages.map((page) => ({
    ...page,
    messages: page.messages.map((m) => (m.id === tempId ? realMessage : m)),
  }));

  return dedupeInfiniteMessagesGlobally({ ...data, pages });
}

/** Flat list: replace the temp id with the server row; dedupe by id. */
export function replaceOptimisticInFlat(
  messages: MessagingMessage[] | undefined,
  tempId: string,
  realMessage: MessagingMessage,
): MessagingMessage[] {
  const list = messages ?? [];
  return dedupeMessagesById(list.map((m) => (m.id === tempId ? realMessage : m)));
}

/** Flat list: append optimistic message (keep other pending temps for concurrent sends). */
export function appendOptimisticToFlat(
  messages: MessagingMessage[] | undefined,
  optimisticMessage: MessagingMessage,
): MessagingMessage[] {
  return dedupeMessagesById([...(messages ?? []), optimisticMessage]);
}
