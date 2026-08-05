/**
 * Toggle sales agent human mode (pause / resume n8n) via API Route writing contacts.sales_agent_paused.
 */
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { queryKeys } from '../queryKeys';
import type { ConversationView } from '@/lib/messaging/types';

export type MessagingHumanToggleAction = 'start-human' | 'stop-human';

export function useMessagingHumanToggle() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({
      conversationId,
      action,
    }: {
      conversationId: string;
      action: MessagingHumanToggleAction;
    }): Promise<{ success: boolean; salesAgentPaused?: boolean }> => {
      const response = await fetch('/api/messaging/human-toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ conversationId, action }),
      });

      const raw = await response.text();
      let payload: { message?: string; success?: boolean; salesAgentPaused?: boolean };
      try {
        payload = raw ? (JSON.parse(raw) as typeof payload) : {};
      } catch {
        throw new Error(raw || `Erro HTTP ${response.status}`);
      }

      if (!response.ok) {
        throw new Error(payload.message || 'Falha ao alternar modo humano');
      }

      return {
        success: payload.success ?? true,
        salesAgentPaused: payload.salesAgentPaused,
      };
    },
    onSuccess: (data, variables) => {
      const paused =
        data.salesAgentPaused ?? (variables.action === 'start-human');
      queryClient.setQueryData<ConversationView | null>(
        queryKeys.messagingConversations.detail(variables.conversationId),
        (current) =>
          current ? { ...current, contactSalesAgentPaused: paused } : current,
      );
    },
    onSettled: (_data, _err, variables) => {
      queryClient.invalidateQueries({
        queryKey: queryKeys.messagingConversations.detail(variables.conversationId),
      });
      queryClient.invalidateQueries({
        queryKey: queryKeys.messagingConversations.all,
      });
    },
  });
}
