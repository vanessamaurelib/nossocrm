-- Add sales_agent_paused column to contacts table
-- When true, the external sales agent (n8n/Giulia) must not auto-reply to this contact.

ALTER TABLE contacts
  ADD COLUMN IF NOT EXISTS sales_agent_paused BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN contacts.sales_agent_paused IS
  'When true, the external sales agent (n8n/Giulia) must not auto-reply to this contact.';
