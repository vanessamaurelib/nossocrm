/**
 * @fileoverview GPTMaker WhatsApp Provider
 *
 * Provider para envio de mensagens via API do GPTMaker.
 * Usa a API oficial do WhatsApp (Cloud API) via GPTMaker como intermediário.
 *
 * @see https://developer.gptmaker.ai/api-reference/chats/send-message
 *
 * @module lib/messaging/providers/whatsapp/gptmaker
 */

import { BaseChannelProvider } from '../base.provider';
import type {
  ChannelType,
  ProviderConfig,
  ValidationResult,
  ValidationError,
  ConnectionStatusResult,
  SendMessageParams,
  SendMessageResult,
  WebhookHandlerResult,
  TextContent,
} from '../../types';

// =============================================================================
// TYPES
// =============================================================================

/**
 * Credenciais do GPTMaker (por canal).
 * A API Key global fica no Supabase Vault (gptmaker_api_key).
 */
export interface GPTMakerCredentials {
  /** ID do agente no GPTMaker */
  agentId: string;
}

// =============================================================================
// PROVIDER
// =============================================================================

export class GPTMakerWhatsAppProvider extends BaseChannelProvider {
  readonly channelType: ChannelType = 'whatsapp';
  readonly providerName = 'gptmaker';

  private agentId: string = '';

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  async initialize(config: ProviderConfig): Promise<void> {
    this.config = config;
    this.isInitialized = true;

    const credentials = config.credentials as unknown as GPTMakerCredentials;
    this.agentId = credentials?.agentId ?? '';

    this.log('info', 'GPTMaker provider initialized', { agentId: this.agentId });
  }

  async disconnect(): Promise<void> {
    this.log('info', 'GPTMaker provider disconnected');
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  async getStatus(): Promise<ConnectionStatusResult> {
    if (!this.agentId) {
      return { status: 'error', message: 'Agent ID não configurado' };
    }
    return { status: 'connected', message: 'Conectado ao GPTMaker' };
  }

  // ---------------------------------------------------------------------------
  // Envio de mensagens
  // ---------------------------------------------------------------------------

  /**
   * Envia uma mensagem via GPTMaker.
   *
   * O `params.to` contém o `external_contact_id` da conversa, que no GPTMaker
   * é o `contextId` (formato: `{assistantId}-{telefone}`).
   *
   * O endpoint usado é:
   *   POST /v2/chat/{chatId}/send-message
   *
   * Onde `chatId` = contextId = external_contact_id da conversa.
   */
  async sendMessage(params: SendMessageParams): Promise<SendMessageResult> {
    const { to, content } = params;

    try {
      if (content.type !== 'text') {
        return this.errorResult(
          'UNSUPPORTED_CONTENT',
          `Tipo de conteúdo não suportado pelo GPTMaker: ${content.type}`
        );
      }

      const text = (content as TextContent).text;
      const chatId = to;

      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      const proxyUrl = `${supabaseUrl}/functions/v1/send-message`;

      const response = await fetch(proxyUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-internal-secret': process.env.INTERNAL_SECRET ?? '',
        },
        body: JSON.stringify({
          chatId,
          message: text,
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        return this.errorResult('PROXY_ERROR', `Proxy retornou erro ${response.status}: ${errorText}`);
      }

      const data = await response.json() as { success: boolean; data?: { messageId?: string }; error?: string };

      if (!data.success) {
        return this.errorResult('API_ERROR', data.error ?? 'Erro desconhecido do GPTMaker');
      }

      return this.successResult(data.data?.messageId ?? `gptmaker-${Date.now()}`);
    } catch (error) {
      this.log('error', 'Falha ao enviar mensagem', { error, to });
      return this.errorResult(
        'REQUEST_FAILED',
        error instanceof Error ? error.message : 'Erro desconhecido',
        true
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Webhook
  // ---------------------------------------------------------------------------

  /**
   * O GPTMaker envia webhooks via `onNewMessage` diretamente para a Edge Function
   * `webhook-messages` no Supabase. O handler dessa Edge Function já processa
   * e grava no banco — este método não é usado no fluxo atual.
   */
  async handleWebhook(_payload: unknown): Promise<WebhookHandlerResult> {
    return {
      type: 'error',
      data: {
        type: 'error',
        code: 'NOT_IMPLEMENTED',
        message: 'Webhooks do GPTMaker são processados pela Edge Function webhook-messages',
        timestamp: new Date(),
      },
      raw: _payload,
    };
  }

  // ---------------------------------------------------------------------------
  // Validação
  // ---------------------------------------------------------------------------

  validateConfig(config: ProviderConfig): ValidationResult {
    const errors: ValidationError[] = [];
    const credentials = config.credentials as unknown as GPTMakerCredentials;

    if (!credentials?.agentId) {
      errors.push({
        field: 'credentials.agentId',
        message: 'Agent ID do GPTMaker é obrigatório',
        code: 'REQUIRED',
      });
    }

    return {
      valid: errors.length === 0,
      errors: errors.length > 0 ? errors : undefined,
    };
  }
}

export default GPTMakerWhatsAppProvider;
