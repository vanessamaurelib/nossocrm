-- =============================================================================
-- provisionamento_n8n.sql — estrutura de banco da Giulia (n8n)
-- =============================================================================
--
-- O QUE É
--   Cria no projeto Supabase de uma terapeuta tudo o que a Giulia usa no banco:
--   o schema sales_agent (fila de mensagens, memória, cobranças, configuração
--   do negócio e horários), a tabela public.knowledge_base_text, a função
--   public.get_knowledge_base, o papel sales_agent_api e as permissões.
--   Só estrutura: nenhum dado. Os valores de cada terapeuta (preços, horários,
--   textos da base) entram no onboarding.
--
-- QUANDO RODAR
--   Num projeto novo, DEPOIS das migrations do CRM (supabase db push).
--   Depende de public.organizations, public.profiles e auth.uid().
--
-- COMO RODAR
--   SQL Editor do Supabase -> New query -> colar o arquivo inteiro -> Run.
--   Se o Supabase avisar que "a query cria uma tabela sem RLS", escolha
--   "Run without RLS": o próprio arquivo liga o RLS de todas as tabelas
--   (seção 10).
--   Pode rodar mais de uma vez: tudo usa IF NOT EXISTS / OR REPLACE.
--
-- DE ONDE VEIO
--   Gerado em 01/10/2026 a partir do banco do projeto da Vanessa
--   (TerapIA-CRM, sa-east-1), pela leitura do catálogo do Postgres.
--   Substitui a versão de setembro, que cobria só a knowledge_base_text e
--   trazia uma get_knowledge_base antiga (sem business_config e sem os
--   blocos de preços e horários).
--   Fora de propósito: busca vetorial (knowledge_base, search_knowledge_base,
--   extensão vector) — tarefa 3.1d.
--   Atualizado em 02/10/2026 (tarefa 3.10): regras de reagendamento e de nova
--   consulta inicial na business_config, sinal usado em cobrancas.usada_em e
--   a view business_config_runtime com as colunas novas (seção 4b). A tabela
--   sales_agent.agendamentos, criada e removida no mesmo dia, não faz parte:
--   as consultas ficam registradas na própria agenda Google (Decisão #25).
--
-- AO MUDAR A ESTRUTURA DA GIULIA
--   Toda tabela, coluna, índice ou função nova no banco da Vanessa precisa
--   entrar aqui também, senão o projeto da próxima terapeuta nasce diferente.
-- =============================================================================



-- 1. Preparação ----------------------------------------------------------------

SET check_function_bodies = off;
CREATE SCHEMA IF NOT EXISTS sales_agent;


-- 2. Papel de acesso mínimo da Giulia (Decisão #11) -----------------------------
-- PENDENTE: hoje o n8n entra no banco com o usuário postgres (administrador),
-- e não com este papel. Ver a tarefa 3.9 do ROADMAP.md e o bug #15.

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sales_agent_api') THEN
    CREATE ROLE sales_agent_api NOLOGIN;
  END IF;
END $do$;


-- 3. Sequências (antes das tabelas, porque os DEFAULT usam nextval) ------------

CREATE SEQUENCE IF NOT EXISTS sales_agent.cobrancas_id_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1;

CREATE SEQUENCE IF NOT EXISTS sales_agent.n8n_chat_histories_id_seq AS integer START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1;


-- 4. Tabelas -------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.knowledge_base_text (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  organization_id uuid,
  content text NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  category text,
  CONSTRAINT knowledge_base_text_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS sales_agent.app_config (
  chave text NOT NULL,
  valor text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT app_config_pkey PRIMARY KEY (chave)
);

CREATE TABLE IF NOT EXISTS sales_agent.business_config (
  organization_id uuid NOT NULL,
  consulta_total numeric(10,2) NOT NULL,
  sinal numeric(10,2) NOT NULL,
  tratamento_medio numeric(10,2),
  moeda text DEFAULT 'BRL'::text NOT NULL,
  duracao_consulta_minutos integer DEFAULT 120 NOT NULL,
  descricao_consulta_inicial text,
  observacao_tratamento text,
  atende_online boolean DEFAULT true NOT NULL,
  plataforma_online text,
  atende_presencial boolean DEFAULT false NOT NULL,
  cidade text,
  endereco text,
  observacao_endereco text,
  forma_pagamento_sinal text DEFAULT 'PIX'::text NOT NULL,
  quando_pagar_restante text,
  formas_pagamento_restante text,
  aceita_parcelamento boolean DEFAULT false NOT NULL,
  parcelamento_max_vezes integer,
  aceita_convenio boolean DEFAULT false NOT NULL,
  observacoes_precos text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by uuid,
  antecedencia_minima_horas integer DEFAULT 24 NOT NULL,
  janela_maxima_dias integer DEFAULT 30 NOT NULL,
  observacoes_horarios text,
  intervalo_entre_consultas_minutos integer DEFAULT 0 NOT NULL,
  CONSTRAINT chk_alguma_modalidade CHECK ((atende_online OR atende_presencial)),
  CONSTRAINT chk_antecedencia CHECK (((antecedencia_minima_horas >= 0) AND (antecedencia_minima_horas <= 720))),
  CONSTRAINT chk_duracao CHECK (((duracao_consulta_minutos >= 15) AND (duracao_consulta_minutos <= 480))),
  CONSTRAINT chk_forma_sinal CHECK ((forma_pagamento_sinal = 'PIX'::text)),
  CONSTRAINT chk_intervalo CHECK (((intervalo_entre_consultas_minutos >= 0) AND (intervalo_entre_consultas_minutos <= 480))),
  CONSTRAINT chk_janela CHECK (((janela_maxima_dias >= 1) AND (janela_maxima_dias <= 365))),
  CONSTRAINT chk_online_plataforma CHECK (((NOT atende_online) OR (plataforma_online IS NOT NULL))),
  CONSTRAINT chk_parcelamento CHECK (((NOT aceita_parcelamento) OR (parcelamento_max_vezes IS NOT NULL))),
  CONSTRAINT chk_parcelas_faixa CHECK (((parcelamento_max_vezes IS NULL) OR ((parcelamento_max_vezes >= 2) AND (parcelamento_max_vezes <= 24)))),
  CONSTRAINT chk_presencial_end CHECK (((NOT atende_presencial) OR (endereco IS NOT NULL))),
  CONSTRAINT chk_sinal_menor CHECK ((sinal <= consulta_total)),
  CONSTRAINT chk_sinal_positivo CHECK ((sinal > (0)::numeric)),
  CONSTRAINT chk_total_positivo CHECK ((consulta_total > (0)::numeric)),
  CONSTRAINT chk_tratamento CHECK (((tratamento_medio IS NULL) OR (tratamento_medio > (0)::numeric))),
  CONSTRAINT business_config_pkey PRIMARY KEY (organization_id)
);

CREATE TABLE IF NOT EXISTS sales_agent.cobranca_tipos (
  tipo text NOT NULL,
  descricao text NOT NULL,
  valor_centavos integer NOT NULL,
  expira_horas integer DEFAULT 36 NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by text,
  CONSTRAINT cobranca_tipos_expira_horas_check CHECK ((expira_horas > 0)),
  CONSTRAINT cobranca_tipos_valor_centavos_check CHECK ((valor_centavos > 0)),
  CONSTRAINT cobranca_tipos_pkey PRIMARY KEY (tipo)
);

CREATE TABLE IF NOT EXISTS sales_agent.cobrancas (
  id bigint DEFAULT nextval('sales_agent.cobrancas_id_seq'::regclass) NOT NULL,
  telefone text NOT NULL,
  order_id text NOT NULL,
  charge_id text,
  valor integer NOT NULL,
  status text DEFAULT 'pendente'::text NOT NULL,
  criada_em timestamp with time zone DEFAULT now() NOT NULL,
  paga_em timestamp with time zone,
  CONSTRAINT cobrancas_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS sales_agent.horarios_atendimento (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  organization_id uuid NOT NULL,
  dia_semana smallint NOT NULL,
  hora_inicio time without time zone NOT NULL,
  hora_fim time without time zone NOT NULL,
  CONSTRAINT chk_dia CHECK (((dia_semana >= 1) AND (dia_semana <= 7))),
  CONSTRAINT chk_ordem CHECK ((hora_inicio < hora_fim)),
  CONSTRAINT horarios_atendimento_pkey PRIMARY KEY (id),
  CONSTRAINT uq_bloco UNIQUE (organization_id, dia_semana, hora_inicio)
);

CREATE TABLE IF NOT EXISTS sales_agent.n8n_chat_histories (
  id integer DEFAULT nextval('sales_agent.n8n_chat_histories_id_seq'::regclass) NOT NULL,
  session_id character varying NOT NULL,
  message jsonb NOT NULL,
  CONSTRAINT n8n_chat_histories_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS sales_agent.processed_messages (
  message_id text NOT NULL,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  status text DEFAULT 'received'::text NOT NULL,
  processed_at timestamp with time zone,
  telefone text,
  enviada_em timestamp with time zone,
  texto text,
  agrupada_em text,
  CONSTRAINT processed_messages_status_chk CHECK ((status = ANY (ARRAY['received'::text, 'processed'::text]))),
  CONSTRAINT processed_messages_pkey PRIMARY KEY (message_id)
);


-- 4b. Colunas da tarefa 3.10 (02/10/2026) ---------------------------------------
-- Acrescentadas com ALTER, e não dentro do CREATE TABLE acima, para que o
-- arquivo também atualize um banco montado com a versão anterior dele.

ALTER TABLE sales_agent.business_config
  ADD COLUMN IF NOT EXISTS antecedencia_reagendamento_horas integer DEFAULT 24 NOT NULL,
  ADD COLUMN IF NOT EXISTS limite_reagendamentos integer,
  ADD COLUMN IF NOT EXISTS intervalo_nova_consulta_dias integer DEFAULT 90 NOT NULL;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_antecedencia_reagendamento' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_antecedencia_reagendamento CHECK (((antecedencia_reagendamento_horas >= 0) AND (antecedencia_reagendamento_horas <= 720)));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_limite_reagendamentos' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_limite_reagendamentos CHECK (((limite_reagendamentos IS NULL) OR (limite_reagendamentos >= 0)));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_intervalo_nova_consulta' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_intervalo_nova_consulta CHECK (((intervalo_nova_consulta_dias >= 0) AND (intervalo_nova_consulta_dias <= 3650)));
  END IF;
END $do$;

ALTER TABLE sales_agent.cobrancas
  ADD COLUMN IF NOT EXISTS usada_em timestamp with time zone;


-- 5. Chaves estrangeiras ---------------------------------------------------------

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'knowledge_base_text_organization_id_fkey' AND conrelid = 'public.knowledge_base_text'::regclass) THEN
    ALTER TABLE public.knowledge_base_text ADD CONSTRAINT knowledge_base_text_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
  END IF;
END $do$;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'horarios_atendimento_organization_id_fkey' AND conrelid = 'sales_agent.horarios_atendimento'::regclass) THEN
    ALTER TABLE sales_agent.horarios_atendimento ADD CONSTRAINT horarios_atendimento_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES sales_agent.business_config(organization_id) ON DELETE CASCADE;
  END IF;
END $do$;


-- 6. Sequências ligadas às colunas -----------------------------------------------

ALTER SEQUENCE sales_agent.cobrancas_id_seq OWNED BY sales_agent.cobrancas.id;

ALTER SEQUENCE sales_agent.n8n_chat_histories_id_seq OWNED BY sales_agent.n8n_chat_histories.id;


-- 7. Índices ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_chat_histories_session ON sales_agent.n8n_chat_histories USING btree (session_id, id);

CREATE INDEX IF NOT EXISTS idx_cobrancas_telefone ON sales_agent.cobrancas USING btree (telefone, criada_em DESC);

CREATE INDEX IF NOT EXISTS idx_horarios_org ON sales_agent.horarios_atendimento USING btree (organization_id, dia_semana, hora_inicio);

CREATE INDEX IF NOT EXISTS idx_processed_messages_at ON sales_agent.processed_messages USING btree (received_at);

CREATE INDEX IF NOT EXISTS idx_processed_messages_fila ON sales_agent.processed_messages USING btree (telefone, enviada_em, received_at) WHERE (status = 'received'::text);

CREATE INDEX IF NOT EXISTS idx_processed_messages_status ON sales_agent.processed_messages USING btree (status, received_at);


-- 8. Funções -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sales_agent.fmt_brl(valor numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT 'R$' || translate(to_char(valor, 'FM999,999,990.00'), ',.', '.,');
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.fmt_dias(dias integer[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT string_agg(
           (ARRAY['segunda','terça','quarta','quinta','sexta','sábado','domingo'])[d],
           ', ' ORDER BY d)
  FROM unnest(dias) AS d;
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.fmt_duracao(minutos integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN minutos < 60     THEN minutos::text || ' minutos'
    WHEN minutos = 60     THEN '1 hora'
    WHEN minutos % 60 = 0 THEN (minutos / 60)::text || ' horas'
    ELSE (minutos / 60)::text || 'h' || lpad((minutos % 60)::text, 2, '0')
  END;
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.fmt_hora(t time without time zone)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN EXTRACT(MINUTE FROM t) = 0
      THEN to_char(t, 'FMHH24') || 'h'
    ELSE to_char(t, 'FMHH24') || 'h' || to_char(t, 'MI')
  END;
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.fmt_horarios(org uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH por_dia AS (
    SELECT dia_semana,
           string_agg('das ' || sales_agent.fmt_hora(hora_inicio) ||
                      ' às '  || sales_agent.fmt_hora(hora_fim),
                      ' e ' ORDER BY hora_inicio) AS faixa
    FROM sales_agent.horarios_atendimento
    WHERE organization_id = org
    GROUP BY dia_semana
  ),
  agrupado AS (
    SELECT faixa,
           min(dia_semana) AS ord,
           sales_agent.fmt_dias(array_agg(dia_semana ORDER BY dia_semana)) AS dias
    FROM por_dia
    GROUP BY faixa
  )
  SELECT string_agg(dias || ': ' || faixa, '; ' ORDER BY ord) FROM agrupado;
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.touch_business_config()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_knowledge_base(org_id uuid, category_filter text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'sales_agent'
AS $function$
DECLARE
  result text := '';
  row_record record;
  cfg sales_agent.business_config%ROWTYPE;
  bloco text;
  quer_tudo boolean := (category_filter IS NULL OR category_filter = '');
BEGIN
  SELECT * INTO cfg FROM sales_agent.business_config WHERE organization_id = org_id;

  -- PRECOS
  IF cfg.organization_id IS NOT NULL AND (quer_tudo OR category_filter = 'precos') THEN
    bloco := ''
      -- Primeiro o que ela entrega, depois quanto custa. A ordem do bloco
      -- é a ordem em que o prompt manda falar.
      || COALESCE('o_que_acontece_na_consulta_inicial: ' || cfg.descricao_consulta_inicial || E'\n', '')
      || 'duracao_consulta: '       || sales_agent.fmt_duracao(cfg.duracao_consulta_minutos) || E'\n'
      || 'consulta_inicial: '       || sales_agent.fmt_brl(cfg.consulta_total) || E'\n'
      || 'sinal_para_agendar: '     || sales_agent.fmt_brl(cfg.sinal) || E'\n'
      || 'forma_pagamento_sinal: '  || cfg.forma_pagamento_sinal || E'\n'
      || 'valor_restante: '         || sales_agent.fmt_brl(cfg.consulta_total - cfg.sinal) || E'\n'
      || COALESCE('quando_pagar_restante: '     || cfg.quando_pagar_restante     || E'\n', '')
      || COALESCE('formas_pagamento_restante: ' || cfg.formas_pagamento_restante || E'\n', '')
      || COALESCE('tratamento_completo_medio: ' || sales_agent.fmt_brl(cfg.tratamento_medio) || E'\n', '')
      || COALESCE('observacao_tratamento: '     || cfg.observacao_tratamento || E'\n', '')
      || 'aceita_parcelamento_do_restante: '
         || CASE WHEN cfg.aceita_parcelamento THEN 'sim' ELSE 'não' END || E'\n'
      || COALESCE('parcelamento_max_vezes: ' || cfg.parcelamento_max_vezes::text || E'\n', '')
      || 'sinal_pode_ser_parcelado: não' || E'\n'
      || 'aceita_convenio: ' || CASE WHEN cfg.aceita_convenio THEN 'sim' ELSE 'não' END
      || COALESCE(E'\n' || 'observacoes: ' || cfg.observacoes_precos, '');
    result := result || '## PRECOS' || E'\n' || bloco || E'\n\n';
  END IF;

  -- LOCAL_E_HORARIOS
  IF cfg.organization_id IS NOT NULL AND (quer_tudo OR category_filter = 'local_e_horarios') THEN
    bloco := ''
      || 'atende_online: ' || CASE WHEN cfg.atende_online THEN 'sim' ELSE 'não' END || E'\n'
      || COALESCE('plataforma_online: '   || cfg.plataforma_online   || E'\n', '')
      || 'atende_presencial: ' || CASE WHEN cfg.atende_presencial THEN 'sim' ELSE 'não' END || E'\n'
      || COALESCE('cidade: '              || cfg.cidade              || E'\n', '')
      || COALESCE('endereco: '            || cfg.endereco            || E'\n', '')
      || COALESCE('observacao_endereco: ' || cfg.observacao_endereco || E'\n', '')
      || COALESCE('horarios_de_atendimento: '
                  || sales_agent.fmt_horarios(cfg.organization_id) || E'\n', '')
      || COALESCE('observacoes_horarios: ' || cfg.observacoes_horarios || E'\n', '')
      || 'antecedencia_minima_agendamento: '
         || cfg.antecedencia_minima_horas::text || ' horas' || E'\n'
      || 'duracao_consulta: ' || sales_agent.fmt_duracao(cfg.duracao_consulta_minutos)
      || COALESCE(E'\n' || 'o_que_acontece_na_consulta_inicial: ' || cfg.descricao_consulta_inicial, '');
    result := result || '## LOCAL_E_HORARIOS' || E'\n' || bloco || E'\n\n';
  END IF;

  -- Demais categorias: texto livre
  FOR row_record IN
    SELECT category, content
    FROM public.knowledge_base_text
    WHERE organization_id = org_id
      AND category NOT IN ('precos', 'local_e_horarios')
      AND (quer_tudo OR category = category_filter)
    ORDER BY category
  LOOP
    result := result || '## ' || upper(row_record.category) || E'\n' ||
              row_record.content || E'\n\n';
  END LOOP;

  RETURN json_build_object('knowledge', result);
END;
$function$
;


-- 9. View e gatilho ------------------------------------------------------------

CREATE OR REPLACE VIEW sales_agent.business_config_runtime AS
 SELECT organization_id,
    (sinal * 100::numeric)::integer AS sinal_centavos,
    (consulta_total * 100::numeric)::integer AS consulta_total_centavos,
    duracao_consulta_minutos,
    intervalo_entre_consultas_minutos,
    antecedencia_minima_horas,
    janela_maxima_dias,
    moeda,
    COALESCE(( SELECT json_agg(json_build_object('dia', h.dia_semana, 'inicio', to_char(h.hora_inicio::interval, 'HH24:MI'::text), 'fim', to_char(h.hora_fim::interval, 'HH24:MI'::text)) ORDER BY h.dia_semana, h.hora_inicio) AS json_agg
           FROM sales_agent.horarios_atendimento h
          WHERE h.organization_id = c.organization_id), '[]'::json) AS blocos_atendimento,
    antecedencia_reagendamento_horas,
    limite_reagendamentos,
    intervalo_nova_consulta_dias
   FROM sales_agent.business_config c;

CREATE OR REPLACE TRIGGER trg_touch_business_config BEFORE UPDATE ON sales_agent.business_config FOR EACH ROW EXECUTE FUNCTION sales_agent.touch_business_config();


-- 10. RLS ligado em todas as tabelas -------------------------------------------

ALTER TABLE public.knowledge_base_text ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.business_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.cobranca_tipos ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.cobrancas ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.horarios_atendimento ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.n8n_chat_histories ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.processed_messages ENABLE ROW LEVEL SECURITY;


-- 11. Políticas de RLS ----------------------------------------------------------

-- O CRM não chama get_knowledge_base. O n8n usa a chave service_role, que ignora
-- o RLS. A policy abaixo continua exigindo auth.uid() para anon e authenticated,
-- que não recebem grant nesta tabela (seção 13).
DROP POLICY IF EXISTS knowledge_base_text_org_isolate ON public.knowledge_base_text;
CREATE POLICY knowledge_base_text_org_isolate ON public.knowledge_base_text AS PERMISSIVE FOR ALL TO public USING ((organization_id = ( SELECT profiles.organization_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))));


-- 12. Comentários (documentação dentro do banco) -------------------------------

COMMENT ON TABLE sales_agent.business_config IS 'Fonte única dos dados de negócio por terapeuta. Valores em reais. A Giulia lê via get_knowledge_base (formatado para falar); a cobrança lê via business_config_runtime (centavos para a API). Nunca escrever esses valores em knowledge_base_text.';

COMMENT ON COLUMN sales_agent.business_config.antecedencia_minima_horas IS 'Não oferecer horário antes de agora + N horas. Evita agendar para daqui a 20 minutos.';

COMMENT ON COLUMN sales_agent.business_config.intervalo_entre_consultas_minutos IS 'Folga mínima entre o fim de um compromisso e o início do próximo atendimento. Usada em dois lugares pelo nó Calcular Horarios: a grade de horários anda de (duracao_consulta_minutos + este valor), e todo evento ocupado da agenda é expandido por este valor nos dois lados. Zero = atendimentos colados.';

COMMENT ON COLUMN sales_agent.business_config.janela_maxima_dias IS 'Não oferecer horário depois de hoje + N dias. Evita agendar para daqui a seis meses.';

COMMENT ON TABLE sales_agent.horarios_atendimento IS 'Blocos de atendimento por dia da semana. Duas linhas no mesmo dia = intervalo entre elas (almoço). Fonte única dos horários — a business_config não guarda mais hora_inicio/hora_fim.';

COMMENT ON COLUMN sales_agent.business_config.antecedencia_reagendamento_horas IS 'A Giulia só reagenda se a consulta atual começar daqui a pelo menos N horas. Dentro do prazo, ela informa a regra e transfere para a terapeuta.';

COMMENT ON COLUMN sales_agent.business_config.limite_reagendamentos IS 'Quantas vezes a mesma consulta pode ser reagendada pela Giulia. Vazio = sem limite.';

COMMENT ON COLUMN sales_agent.business_config.intervalo_nova_consulta_dias IS 'A Giulia só vende nova consulta inicial se a cliente não tiver consulta marcada pela Giulia no futuro nem nos últimos N dias. Consulta recente: transfere para a terapeuta.';

COMMENT ON COLUMN sales_agent.cobrancas.usada_em IS 'Quando o sinal foi usado para marcar a primeira consulta. Preenchido uma vez e nunca liberado pelo sistema: devolução, retenção ou crédito é decisão da terapeuta.';

COMMENT ON COLUMN sales_agent.horarios_atendimento.dia_semana IS '1=segunda ... 7=domingo. Padrão ISO 8601 — mesmo do EXTRACT(ISODOW) do Postgres e do weekday do Luxon no nó Calcular Horarios.';


-- 13. Permissões -----------------------------------------------------------------

-- sales_agent_api: o que a Giulia precisa no schema sales_agent
GRANT USAGE ON SCHEMA sales_agent TO sales_agent_api;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  sales_agent.app_config,
  sales_agent.business_config,
  sales_agent.cobranca_tipos,
  sales_agent.cobrancas,
  sales_agent.horarios_atendimento,
  sales_agent.n8n_chat_histories
TO sales_agent_api;

-- A fila de mensagens não apaga linhas
GRANT SELECT, INSERT, UPDATE ON sales_agent.processed_messages TO sales_agent_api;

-- View: só leitura
GRANT SELECT ON sales_agent.business_config_runtime TO sales_agent_api;

GRANT USAGE, SELECT ON SEQUENCE
  sales_agent.cobrancas_id_seq,
  sales_agent.n8n_chat_histories_id_seq
TO sales_agent_api;

-- Base de conhecimento: o n8n lê pela API REST com a chave service_role.
-- anon e authenticated não recebem grant nesta tabela, de propósito.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.knowledge_base_text TO service_role;

-- A função devolve os dados de negócio de qualquer organização e roda com
-- privilégio de dono (SECURITY DEFINER): nunca pode ficar aberta para as
-- chaves públicas (anon/authenticated).
REVOKE ALL ON FUNCTION public.get_knowledge_base(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_knowledge_base(uuid, text) TO service_role;
