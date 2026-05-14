/**
 * Toggle GPTMaker human mode (pause / resume IA) via API Route + Edge Function.
 */
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { queryKeys } from '../queryKeys';

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
    }): Promise<{ success: boolean; data?: unknown }> => {
      const response = await fetch('/api/messaging/human-toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ conversationId, action }),
      });

      const raw = await response.text();
      let payload: { message?: string; success?: boolean; data?: unknown };
      try {
        payload = raw ? (JSON.parse(raw) as typeof payload) : {};
      } catch {
        throw new Error(raw || `Erro HTTP ${response.status}`);
      }

      if (!response.ok) {
        throw new Error(payload.message || 'Falha ao alternar modo humano');
      }

      return { success: payload.success ?? true, data: payload.data };
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
