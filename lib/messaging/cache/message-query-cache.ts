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

/** Removes all optimistic temp messages (e.g. before adding a new one). */
export function stripOptimisticMessages(messages: MessagingMessage[]): MessagingMessage[] {
  return messages.filter((m) => !isOptimisticMessageId(m.id));
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
    return { ...page, messages: dedupeMessagesById([...page.messages, message]) };
  });

  return { ...data, pages };
}

/**
 * Replaces a temp message with the server row and dedupes by id across all pages.
 * Removes any other temp-* rows (e.g. Strict Mode double onMutate).
 */
export function replaceOptimisticInInfinite(
  data: MessagesInfiniteData | undefined,
  tempId: string,
  realMessage: MessagingMessage,
): MessagesInfiniteData | undefined {
  if (!data) return data;

  const pages = data.pages.map((page) => ({
    ...page,
    messages: dedupeMessagesById(
      page.messages
        .filter((m) => !isOptimisticMessageId(m.id) || m.id === tempId)
        .map((m) => (m.id === tempId ? realMessage : m)),
    ),
  }));

  return { ...data, pages };
}

/** Flat list: replace temp, strip other temps, dedupe by id. */
export function replaceOptimisticInFlat(
  messages: MessagingMessage[] | undefined,
  tempId: string,
  realMessage: MessagingMessage,
): MessagingMessage[] {
  const base = stripOptimisticMessages(messages ?? []).filter((m) => m.id !== realMessage.id);
  const hadTemp = messages?.some((m) => m.id === tempId) ?? false;
  if (hadTemp || !base.some((m) => m.id === realMessage.id)) {
    return dedupeMessagesById([...base, realMessage]);
  }
  return dedupeMessagesById(base);
}

/** Flat list: strip temps, append optimistic, dedupe. */
export function appendOptimisticToFlat(
  messages: MessagingMessage[] | undefined,
  optimisticMessage: MessagingMessage,
): MessagingMessage[] {
  return dedupeMessagesById([
    ...stripOptimisticMessages(messages ?? []),
    optimisticMessage,
  ]);
}
