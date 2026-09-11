/**
 * @fileoverview n8n WhatsApp Provider
 *
 * Envia mensagens via webhook HTTP do n8n. URL e secret vêm de env vars
 * (N8N_SEND_WEBHOOK_URL / N8N_SEND_SECRET), não de credenciais por canal.
 *
 * @module lib/messaging/providers/whatsapp/n8n
 */

import { BaseChannelProvider } from '../base.provider';
import type {
  ChannelType,
  ConnectionStatusResult,
  SendMessageParams,
  SendMessageResult,
  WebhookHandlerResult,
  TextContent,
} from '../../types';

const SEND_TIMEOUT_MS = 15_000;

interface N8nSendSuccess {
  success: true;
  wamid?: string;
}

interface N8nSendFailure {
  success: false;
  error?: string;
}

type N8nSendResponse = N8nSendSuccess | N8nSendFailure | Record<string, unknown>;

export class N8nWhatsAppProvider extends BaseChannelProvider {
  readonly channelType: ChannelType = 'whatsapp';
  readonly providerName = 'n8n';

  async getStatus(): Promise<ConnectionStatusResult> {
    const webhookUrl = process.env.N8N_SEND_WEBHOOK_URL;
    const secret = process.env.N8N_SEND_SECRET;

    if (!webhookUrl || !secret) {
      return {
        status: 'error',
        message: 'N8N_SEND_WEBHOOK_URL ou N8N_SEND_SECRET não configurados',
      };
    }

    return { status: 'connected', message: 'Pronto para enviar via n8n' };
  }

  /**
   * POST { phone, text } no webhook do n8n.
   * Sucesso só com wamid real — nunca gera id sintético (idempotência da ingestão).
   */
  async sendMessage(params: SendMessageParams): Promise<SendMessageResult> {
    const { to, content } = params;

    if (content.type !== 'text') {
      return this.errorResult(
        'UNSUPPORTED_CONTENT',
        `Tipo de conteúdo não suportado pelo n8n: ${content.type}`
      );
    }

    const webhookUrl = process.env.N8N_SEND_WEBHOOK_URL;
    const secret = process.env.N8N_SEND_SECRET;

    if (!webhookUrl || !secret) {
      return this.errorResult(
        'N8N_SEND_FAILED',
        'N8N_SEND_WEBHOOK_URL ou N8N_SEND_SECRET não configurados'
      );
    }

    const text = (content as TextContent).text;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), SEND_TIMEOUT_MS);

    try {
      const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CRM-Secret': secret,
        },
        body: JSON.stringify({ phone: to, text }),
        signal: controller.signal,
      });

      const responseText = await response.text();

      if (!response.ok) {
        return this.errorResult(
          'N8N_HTTP_ERROR',
          `n8n retornou HTTP ${response.status}: ${responseText || response.statusText}`
        );
      }

      let data: N8nSendResponse;
      try {
        data = JSON.parse(responseText) as N8nSendResponse;
      } catch {
        return this.errorResult('N8N_SEND_FAILED', 'Resposta do n8n não é JSON válido');
      }

      if (data.success === false) {
        const message =
          typeof data.error === 'string' && data.error
            ? data.error
            : 'Falha no envio via n8n';
        return this.errorResult('N8N_SEND_FAILED', message, false);
      }

      const wamidRaw = 'wamid' in data ? data.wamid : undefined;
      const wamid = typeof wamidRaw === 'string' ? wamidRaw.trim() : '';
      if (data.success !== true || !wamid) {
        return this.errorResult('N8N_SEND_FAILED', 'Resposta do n8n sem wamid');
      }

      return this.successResult(wamid);
    } catch (error) {
      this.log('error', 'Falha ao enviar mensagem via n8n', { error, to });

      const isTimeout =
        error instanceof Error &&
        (error.name === 'AbortError' || error.message.toLowerCase().includes('timeout'));

      return this.errorResult(
        'REQUEST_FAILED',
        isTimeout
          ? 'Timeout ao chamar o webhook do n8n'
          : error instanceof Error
            ? error.message
            : 'Erro de rede ao chamar o n8n',
        true
      );
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Inbound é processado pela Edge Function webhook-messages — este método não é usado.
   */
  async handleWebhook(_payload: unknown): Promise<WebhookHandlerResult> {
    return {
      type: 'error',
      data: {
        type: 'error',
        code: 'NOT_IMPLEMENTED',
        message: 'Webhooks inbound não passam por este provider',
        timestamp: new Date(),
      },
      raw: _payload,
    };
  }
}

export default N8nWhatsAppProvider;
