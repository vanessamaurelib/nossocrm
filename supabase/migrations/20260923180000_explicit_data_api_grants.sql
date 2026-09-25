-- Grants explícitos da Data API para projetos Supabase novos.
-- Em projetos criados a partir de 30/05/2026, tabelas novas em public
-- não recebem GRANT automático para anon, authenticated e service_role.
-- GRANT é idempotente. Esta migration não altera RLS nem policies
-- e não revoga os GRANT ALL que o banco atual já tem.
-- Não há sequences em public (PKs usam gen_random_uuid()).
-- Sem grant: view vw_hitl_pending_by_age, knowledge_base e knowledge_base_text
-- (estas duas ficam em docs/provisionamento_n8n.sql).

-- anon: só a leitura do health check (app/api/health/route.ts).
-- A policy authenticated_access é TO authenticated, então anon não vê linhas.
GRANT SELECT ON TABLE public.organizations TO anon;

-- authenticated: operações que alguma policy permite
-- (TO authenticated, ou policy sem TO). Sem FOR, a policy vale para
-- select, insert, update e delete.
-- Onde o comentário diz "bloqueado pelo RLS", o código da sessão de usuário
-- executa a operação e nenhuma policy a permite. O grant existe para um
-- projeto novo se comportar como o atual (GRANT ALL + RLS): DELETE e UPDATE
-- afetam zero linhas sem erro; INSERT falha por RLS. Sem o grant, o
-- PostgREST responde 42501 e pode abortar o fluxo.

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.activities TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_audio_notes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_conversations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_decisions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_feature_flags TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_prompt_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_qualification_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_suggestion_interactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.api_keys TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.board_ai_config TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.board_stages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.boards TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.business_unit_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.business_units TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contacts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.crm_companies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.custom_field_definitions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_files TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_notes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integration_inbound_sources TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integration_outbound_endpoints TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.lead_routing_rules TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.leads TO authenticated;
-- INSERT, UPDATE, DELETE: grant concedido; bloqueado pelo RLS (policy lifecycle_stages_readonly é só SELECT).
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.lifecycle_stages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_channels TO authenticated;
-- DELETE: grant concedido; bloqueado pelo RLS (policies são SELECT, INSERT e UPDATE).
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_conversations TO authenticated;
-- DELETE: grant concedido; bloqueado pelo RLS (policies são SELECT, INSERT e UPDATE).
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organization_invites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organizations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.quick_scripts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stage_ai_config TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.system_notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.tags TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_consents TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.voice_calls TO authenticated;

GRANT SELECT, INSERT, UPDATE ON TABLE public.organization_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.whatsapp_calls TO authenticated;

GRANT SELECT, INSERT ON TABLE public.contact_merge_log TO authenticated;
GRANT SELECT, INSERT ON TABLE public.deal_activities TO authenticated;

-- DELETE: grant concedido; bloqueado pelo RLS (policies são SELECT e UPDATE).
GRANT SELECT, UPDATE, DELETE ON TABLE public.profiles TO authenticated;

GRANT SELECT, UPDATE ON TABLE public.ai_pending_stage_advances TO authenticated;

-- INSERT: grant concedido; bloqueado pelo RLS (a policy de INSERT é TO service_role).
GRANT SELECT, INSERT ON TABLE public.ai_conversation_log TO authenticated;
-- INSERT: grant concedido; bloqueado pelo RLS (policy audit_logs_org_select é só SELECT).
GRANT SELECT, INSERT ON TABLE public.audit_logs TO authenticated;

-- DELETE: grant concedido; bloqueado pelo RLS (policies são só SELECT).
GRANT SELECT, DELETE ON TABLE public.webhook_deliveries TO authenticated;
GRANT SELECT, DELETE ON TABLE public.webhook_events_in TO authenticated;
GRANT SELECT, DELETE ON TABLE public.webhook_events_out TO authenticated;

GRANT SELECT ON TABLE public.ai_pending_evaluations TO authenticated;
GRANT SELECT ON TABLE public.instance_feature_flags TO authenticated;
GRANT SELECT ON TABLE public.messaging_webhook_events TO authenticated;
GRANT SELECT ON TABLE public.rate_limits TO authenticated;
GRANT SELECT ON TABLE public.security_alerts TO authenticated;

-- service_role: select, insert, update, delete em toda tabela criada por migration.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.activities TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_audio_notes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_conversation_log TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_conversations TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_decisions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_feature_flags TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_pending_evaluations TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_pending_stage_advances TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_prompt_templates TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_qualification_templates TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_suggestion_interactions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.api_keys TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.audit_logs TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.board_ai_config TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.board_stages TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.boards TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.business_unit_members TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.business_units TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contact_merge_log TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.contacts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.crm_companies TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.custom_field_definitions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_activities TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_files TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_items TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deal_notes TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.deals TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.instance_feature_flags TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integration_inbound_sources TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.integration_outbound_endpoints TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.lead_routing_rules TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.leads TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.lifecycle_stages TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_channels TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_conversations TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_messages TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_templates TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.messaging_webhook_events TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organization_invites TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organization_settings TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.organizations TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.profiles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.quick_scripts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rate_limits TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.security_alerts TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stage_ai_config TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.system_notifications TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.tags TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_consents TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_settings TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.voice_calls TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.webhook_deliveries TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.webhook_events_in TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.webhook_events_out TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.whatsapp_calls TO service_role;
