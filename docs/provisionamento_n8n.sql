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
--   Atualizado em 03/10/2026 (tarefa 3.15.1): prazo do PIX na business_config
--   (validade_pix_horas), cobrancas.expira_em, a função fmt_data_hora e a view
--   business_config_runtime com a coluna nova (seção 4c).
--   Atualizado em 06/10/2026 (tarefa 3.15.2): situações permitidas da
--   cobrança, order_id único, cobrancas.confirmado_por (seção 4d) e as funções
--   registrar_pagamento e marcar_expirada (seção 8), que são o único caminho
--   para mudar a situação de uma cobrança.
--   Atualizado em 06/10/2026 (tarefa 3.15.3): funções faixas_de_inicio e
--   agenda_horarios (seção 8), as regras de horário num lugar só. O caminho
--   principal (sugestões) e a entrada interna (conferir horário pedido) usam
--   as duas; os nós Calcular Horarios e Conferir Regras não calculam mais.
--   Atualizado em 09/10/2026 (tarefa 3.18): registro de fatos da conversa
--   (sales_agent.fatos_conversa), business_config.validade_fatos_dias, a view
--   business_config_runtime com a coluna nova, agenda_horarios com 3 sugestões
--   (uma por dia) e as funções dia_iso, registrar_fatos_mensagem,
--   situacao_da_conversa, fatos_e_etapa e registrar_fatos_resposta.
--   Atualizado em 11/10/2026 (tarefa 3.18): agenda_horarios com sugestões em
--   períodos diferentes (no máximo 2 no mesmo dia) e o parâmetro p_filtro
--   (período, dia da semana ou data pedidos pela cliente) — a versão antiga,
--   de 4 parâmetros, é removida; as funções periodos_do_dia, proxima_data,
--   fmt_motivo e fmt_sugestoes; registrar_fatos_mensagem usa a proxima_data;
--   fatos_e_etapa devolve horarios_pedidos (horários livres do período ou
--   dia pedido).
--   Atualizado em 20/10/2026 (tarefa 3.18): agenda_horarios com o pedido por
--   dia — dia da semana: a próxima ocorrência primeiro, completada pelas
--   seguintes, sem pular nenhuma com vaga; data: só ela (sem vaga, a Giulia
--   recebe a lista geral).
--   Atualizado em 20/10/2026 (tarefa 3.18, bug #28): registrar_fatos_resposta
--   reconhece a hora até 100 caracteres depois da data, sem outra data no meio.
--   Atualizado em 23/10/2026 (tarefa 3.18, fase B): situacao_da_conversa
--   (linhas que só informam fatos, hesitação tira do Fechamento, devolve
--   valores_informados, perfil_a_confirmar e perfil_caso, linha da etapa
--   fora_do_perfil); fatos_e_etapa (linha do dia da semana que não bate com a
--   data, devolve perfil_whatsapp_fora); registrar_fatos_mensagem grava
--   nome_informado e a regra chk_fato_tipo_valor o aceita (seção 4f, recriada
--   a cada execução); business_config.genero_atendido (padrão "todos") e a view
--   business_config_runtime com a coluna nova; função caso_do_nome.
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

CREATE SEQUENCE IF NOT EXISTS sales_agent.fatos_conversa_id_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1;

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

CREATE TABLE IF NOT EXISTS sales_agent.fatos_conversa (
  id bigint DEFAULT nextval('sales_agent.fatos_conversa_id_seq'::regclass) NOT NULL,
  telefone text NOT NULL,
  tipo text NOT NULL,
  valor text,
  horario timestamp with time zone,
  valor_consulta numeric(10,2),
  detalhes jsonb,
  origem text NOT NULL,
  wamid text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT fatos_conversa_pkey PRIMARY KEY (id),
  CONSTRAINT chk_fato_origem CHECK ((origem = ANY (ARRAY['classificador'::text, 'sistema'::text, 'meta'::text])))
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


-- 4c. Colunas da tarefa 3.15.1 (03/10/2026) -------------------------------------
-- Prazo do PIX definido por nós: informado ao banco na criação e guardado na
-- cobrança. Ao banco só se pergunta se o PIX foi pago.

ALTER TABLE sales_agent.business_config
  ADD COLUMN IF NOT EXISTS validade_pix_horas integer DEFAULT 24 NOT NULL;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_validade_pix' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_validade_pix CHECK (((validade_pix_horas >= 1) AND (validade_pix_horas <= 720)));
  END IF;
END $do$;

ALTER TABLE sales_agent.cobrancas
  ADD COLUMN IF NOT EXISTS expira_em timestamp with time zone;


-- 4d. Situação da cobrança protegida — tarefa 3.15.2 (06/10/2026) ---------------
-- Lista fechada de situações, um registro por pedido do banco e quem confirmou
-- o pagamento. As mudanças de situação são feitas pelas funções da seção 8.

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_status_cobranca' AND conrelid = 'sales_agent.cobrancas'::regclass) THEN
    ALTER TABLE sales_agent.cobrancas ADD CONSTRAINT chk_status_cobranca CHECK ((status = ANY (ARRAY['pendente'::text, 'paga'::text, 'expirada'::text, 'estornada'::text])));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_cobrancas_order_id' AND conrelid = 'sales_agent.cobrancas'::regclass) THEN
    ALTER TABLE sales_agent.cobrancas ADD CONSTRAINT uq_cobrancas_order_id UNIQUE (order_id);
  END IF;
END $do$;

ALTER TABLE sales_agent.cobrancas
  ADD COLUMN IF NOT EXISTS confirmado_por text;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_confirmado_por' AND conrelid = 'sales_agent.cobrancas'::regclass) THEN
    ALTER TABLE sales_agent.cobrancas ADD CONSTRAINT chk_confirmado_por CHECK (((confirmado_por IS NULL) OR (confirmado_por = ANY (ARRAY['cliente'::text, 'aviso'::text, 'varredura'::text]))));
  END IF;
END $do$;


-- 4e. Validade dos fatos da conversa — tarefa 3.18 (09/10/2026) --------------------
-- Por quantos dias um fato da conversa ainda conduz a conversa (padrão 30).

ALTER TABLE sales_agent.business_config
  ADD COLUMN IF NOT EXISTS validade_fatos_dias integer DEFAULT 30 NOT NULL;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_validade_fatos' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_validade_fatos CHECK (((validade_fatos_dias >= 1) AND (validade_fatos_dias <= 365)));
  END IF;
END $do$;


-- 4f. Perfil atendido — tarefa 3.18 (21 e 22/10/2026) -----------------------------
-- Regra de tipos e valores dos fatos da conversa, com o fato nome_informado.
-- A lista de tipos e de valores permitidos fica só aqui: as funções tentam
-- gravar e descartam o que esta regra recusar. Recriada a cada execução, para
-- que o arquivo também atualize um banco montado com a versão anterior dele.

ALTER TABLE sales_agent.fatos_conversa DROP CONSTRAINT IF EXISTS chk_fato_tipo_valor;
ALTER TABLE sales_agent.fatos_conversa ADD CONSTRAINT chk_fato_tipo_valor CHECK ((
       ((tipo = ANY (ARRAY['problema_contado'::text, 'vai_pensar'::text])) AND (valor = 'sim'::text))
    OR ((tipo = ANY (ARRAY['decidiu'::text, 'fora_do_perfil'::text, 'conhece_trabalho'::text, 'ja_fez_terapia'::text])) AND (valor = ANY (ARRAY['sim'::text, 'nao'::text])))
    OR ((tipo = 'objecao'::text) AND (valor = ANY (ARRAY['preco'::text, 'tempo'::text, 'outra_pessoa'::text, 'duvida_terapia'::text, 'outra'::text])))
    OR ((tipo = 'horario_escolhido'::text) AND (horario IS NOT NULL))
    OR ((tipo = 'valores_informados'::text) AND (valor_consulta IS NOT NULL))
    OR (tipo = 'horarios_oferecidos'::text)
    OR ((tipo = 'origem_anuncio'::text) AND (detalhes IS NOT NULL))
    OR ((tipo = 'nome_informado'::text) AND (valor = ANY (ARRAY['feminino'::text, 'masculino'::text, 'ambos'::text])))
  ));

-- Gênero que a terapeuta atende. Padrão "todos": terapeuta nova começa sem
-- conferência pelo nome. O valor de cada terapeuta entra no onboarding.

ALTER TABLE sales_agent.business_config
  ADD COLUMN IF NOT EXISTS genero_atendido text DEFAULT 'todos'::text NOT NULL;

DO $do$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_genero_atendido' AND conrelid = 'sales_agent.business_config'::regclass) THEN
    ALTER TABLE sales_agent.business_config ADD CONSTRAINT chk_genero_atendido CHECK ((genero_atendido = ANY (ARRAY['mulheres'::text, 'homens'::text, 'todos'::text])));
  END IF;
END $do$;


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

ALTER SEQUENCE sales_agent.fatos_conversa_id_seq OWNED BY sales_agent.fatos_conversa.id;

ALTER SEQUENCE sales_agent.n8n_chat_histories_id_seq OWNED BY sales_agent.n8n_chat_histories.id;


-- 7. Índices ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_chat_histories_session ON sales_agent.n8n_chat_histories USING btree (session_id, id);

CREATE INDEX IF NOT EXISTS idx_cobrancas_telefone ON sales_agent.cobrancas USING btree (telefone, criada_em DESC);

CREATE INDEX IF NOT EXISTS idx_fatos_conversa ON sales_agent.fatos_conversa USING btree (telefone, tipo, criado_em DESC);

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

CREATE OR REPLACE FUNCTION sales_agent.fmt_data_hora(ts timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT sales_agent.fmt_dias(ARRAY[EXTRACT(ISODOW FROM ts AT TIME ZONE 'America/Sao_Paulo')::integer])
      || ', ' || to_char(ts AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
      || ' às ' || sales_agent.fmt_hora((ts AT TIME ZONE 'America/Sao_Paulo')::time);
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

CREATE OR REPLACE FUNCTION sales_agent.registrar_pagamento(p_order_id text, p_paga_em timestamp with time zone, p_charge_id text, p_confirmado_por text)
 RETURNS TABLE(order_id text, telefone text, mudou boolean)
 LANGUAGE sql
AS $function$
  WITH alvo AS (
    SELECT c.order_id, c.telefone
    FROM sales_agent.cobrancas c
    WHERE c.order_id = p_order_id
  ),
  mudanca AS (
    UPDATE sales_agent.cobrancas c
    SET status         = 'paga',
        paga_em        = COALESCE(p_paga_em, now()),
        charge_id      = COALESCE(NULLIF(p_charge_id, ''), c.charge_id),
        confirmado_por = p_confirmado_por
    WHERE c.order_id = p_order_id
      AND c.status IN ('pendente', 'expirada')
    RETURNING c.order_id
  )
  SELECT a.order_id, a.telefone, EXISTS (SELECT 1 FROM mudanca)
  FROM alvo a;
$function$
;

CREATE OR REPLACE FUNCTION sales_agent.marcar_expirada(p_order_id text)
 RETURNS TABLE(order_id text, telefone text, mudou boolean)
 LANGUAGE sql
AS $function$
  WITH alvo AS (
    SELECT c.order_id, c.telefone
    FROM sales_agent.cobrancas c
    WHERE c.order_id = p_order_id
  ),
  mudanca AS (
    UPDATE sales_agent.cobrancas c
    SET status = 'expirada'
    WHERE c.order_id = p_order_id
      AND c.status = 'pendente'
      AND (c.expira_em IS NULL OR c.expira_em <= now())
    RETURNING c.order_id
  )
  SELECT a.order_id, a.telefone, EXISTS (SELECT 1 FROM mudanca)
  FROM alvo a;
$function$
;

-- Faixas de início possíveis de uma consulta num dia: dentro do expediente
-- (blocos de atendimento) e fora dos intervalos proibidos.
-- Um bloco [bi, bf] permite começar de bi até bf menos a duração.
-- Cada intervalo proibido é ABERTO nas duas pontas: começar exatamente na
-- borda é permitido (encostar não é conflito). Por isso a borda fica, mesmo
-- quando sobra um único minuto de início: um vão do tamanho exato da
-- consulta é horário livre.
CREATE OR REPLACE FUNCTION sales_agent.faixas_de_inicio(p_dia date, p_blocos jsonb, p_duracao integer, p_proibido_ini timestamp with time zone[], p_proibido_fim timestamp with time zone[])
 RETURNS TABLE(inicio timestamp with time zone, fim timestamp with time zone)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  ji timestamptz[] := '{}';
  jf timestamptz[] := '{}';
  ni timestamptz[];
  nf timestamptz[];
  b  jsonb;
  bi timestamptz;
  bf timestamptz;
  k  integer;
  m  integer;
BEGIN
  -- Janelas do expediente neste dia (1 = segunda ... 7 = domingo)
  FOR b IN
    SELECT x FROM jsonb_array_elements(COALESCE(p_blocos, '[]'::jsonb)) AS x
    WHERE (x->>'dia')::integer = EXTRACT(ISODOW FROM p_dia)::integer
    ORDER BY x->>'inicio'
  LOOP
    bi := (p_dia + (b->>'inicio')::time) AT TIME ZONE tz;
    bf := ((p_dia + (b->>'fim')::time) AT TIME ZONE tz) - make_interval(mins => p_duracao);
    IF bf >= bi THEN
      ji := ji || bi;
      jf := jf || bf;
    END IF;
  END LOOP;

  -- Tira de cada janela os intervalos proibidos
  FOR k IN 1 .. COALESCE(array_length(p_proibido_ini, 1), 0) LOOP
    ni := '{}';
    nf := '{}';
    FOR m IN 1 .. COALESCE(array_length(ji, 1), 0) LOOP
      IF p_proibido_fim[k] <= ji[m] OR p_proibido_ini[k] >= jf[m] THEN
        ni := ni || ji[m];
        nf := nf || jf[m];
      ELSE
        IF p_proibido_ini[k] >= ji[m] THEN
          ni := ni || ji[m];
          nf := nf || p_proibido_ini[k];
        END IF;
        IF p_proibido_fim[k] <= jf[m] THEN
          ni := ni || p_proibido_fim[k];
          nf := nf || jf[m];
        END IF;
      END IF;
    END LOOP;
    ji := ni;
    jf := nf;
  END LOOP;

  RETURN QUERY
    SELECT t.i, t.f
    FROM unnest(ji, jf) AS t(i, f)
    WHERE t.i <= t.f
    ORDER BY t.i;
END;
$function$
;

-- Períodos do dia, num lugar só. Usada pela agenda_horarios (sugestões) e
-- pela fatos_e_etapa (texto do período pedido).
CREATE OR REPLACE FUNCTION sales_agent.periodos_do_dia()
 RETURNS TABLE(codigo integer, nome text, de time without time zone, ate time without time zone)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  VALUES (1, 'manha', NULL::time, '12:00'::time),
         (2, 'tarde', '12:00'::time, '18:00'::time),
         (3, 'noite', '18:00'::time, NULL::time);
$function$
;

-- Até 11/10/2026 a agenda_horarios tinha 4 parâmetros. Em projeto que já tem
-- a versão antiga, ela é removida: as duas juntas deixariam ambígua a chamada
-- com 4 argumentos.
DROP FUNCTION IF EXISTS sales_agent.agenda_horarios(jsonb, text, timestamp with time zone, timestamp with time zone);

-- Regras de horário da agenda, num lugar só. Usada pelo caminho principal
-- (sugestões e consultas da cliente) e pela entrada interna (conferir o
-- horário pedido). Recebe os eventos como o Google devolve e o telefone da
-- cliente; as consultas dela (marca giulia_telefone) não ocupam horário.
-- Com p_filtro (período e/ou dia pedidos pela cliente), as sugestões saem só
-- desse recorte; sem nenhuma, motivo diz por quê. Data pedida: só ela. Dia da
-- semana pedido: a próxima ocorrência primeiro, completada pelas seguintes,
-- sem pular nenhuma que tenha vaga.
-- Devolve só dados; os textos para a Giulia ficam no workflow.
CREATE OR REPLACE FUNCTION sales_agent.agenda_horarios(p_eventos jsonb, p_telefone text, p_inicio timestamp with time zone DEFAULT NULL::timestamp with time zone, p_agora timestamp with time zone DEFAULT now(), p_filtro jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  -- Apresentação das sugestões (não é regra de negócio da terapeuta)
  passo_sugestao constant integer := 30;  -- de quanto em quanto gerar candidatos
  max_dias       constant integer := 3;   -- dias COM vaga que entram nas sugestões
  max_sugestoes  constant integer := 3;   -- total sugerido (3.18: no máximo 3 opções por vez)
  max_por_dia    constant integer := 2;   -- duas no mesmo dia, só em períodos diferentes

  cfg        record;
  blocos     jsonb;
  duracao    integer;
  intervalo  integer;
  min_horas  integer;
  janela     integer;
  minimo     timestamptz;
  limite     timestamptz;
  hoje       date;
  inicio_sug timestamptz;
  lm         timestamp;

  ev         jsonb;
  ini        timestamptz;
  fim        timestamptz;
  pi         timestamptz[] := '{}';
  pf         timestamptz[] := '{}';
  consultas  jsonb := '[]';
  erro       text;

  dia        date;
  dias_vaga  integer := 0;
  sugestoes  jsonb := '[]';
  qtd        integer := 0;
  t          timestamptz;
  f          record;
  achou      boolean;
  per        integer;
  -- Recorte pedido pela cliente (p_filtro)
  f_per      integer;
  f_dow      integer;
  f_data     date;
  semana     boolean;  -- pediu um dia da semana (sem data)
  -- Candidatos (todo início possível nos primeiros dias com vaga) e escolhidos
  c_t        timestamptz[] := '{}';
  c_dia      date[] := '{}';
  c_per      integer[] := '{}';
  s_t        timestamptz[] := '{}';
  s_dia      date[] := '{}';
  s_per      integer[] := '{}';
  n          integer;
  dist       numeric;
  melhor     integer;
  melhor_d   numeric;

  livre      boolean;
  motivo     text;
BEGIN
  -- Sem valor padrão aqui: os padrões ficam nas colunas da business_config
  -- (ex.: antecedência de 24 h quando a terapeuta não preenche).
  SELECT * INTO cfg FROM sales_agent.business_config_runtime LIMIT 1;
  blocos    := COALESCE(cfg.blocos_atendimento::jsonb, '[]'::jsonb);
  duracao   := cfg.duracao_consulta_minutos;
  intervalo := cfg.intervalo_entre_consultas_minutos;
  min_horas := cfg.antecedencia_minima_horas;
  janela    := cfg.janela_maxima_dias;
  hoje      := (p_agora AT TIME ZONE tz)::date;
  minimo    := p_agora + make_interval(hours => min_horas);
  limite    := ((hoje + janela + 1)::timestamp AT TIME ZONE tz) - interval '1 millisecond';

  -- Recorte pedido: período (manha, tarde, noite), dia da semana (1 = segunda) e/ou data
  IF jsonb_typeof(p_filtro) = 'object' THEN
    SELECT p.codigo INTO f_per FROM sales_agent.periodos_do_dia() AS p
     WHERE p.nome = translate(lower(btrim(COALESCE(p_filtro->>'periodo', ''))), 'ã', 'a');
    f_dow := CASE WHEN (p_filtro->>'dia_semana') ~ '^[1-7]$' THEN (p_filtro->>'dia_semana')::integer END;
    BEGIN
      f_data := (p_filtro->>'data')::date;
    EXCEPTION WHEN OTHERS THEN
      f_data := NULL;
    END;
  END IF;
  semana := f_dow IS NOT NULL AND f_data IS NULL;

  -- Sugestões começam na hora cheia ou meia hora seguinte à antecedência:
  -- agora + 48 h às 13h22 vira 13h30. Evita oferecer um horário quebrado
  -- que um minuto depois já fica dentro da antecedência.
  lm         := minimo AT TIME ZONE tz;
  inicio_sug := (date_trunc('hour', lm)
                 + make_interval(mins => passo_sugestao
                     * ceil(EXTRACT(EPOCH FROM lm - date_trunc('hour', lm)) / (passo_sugestao * 60))::integer)
                ) AT TIME ZONE tz;

  -- Eventos: as consultas da cliente são listadas e não ocupam horário;
  -- os demais ocupam, expandidos pela folga entre consultas nos dois lados.
  FOR ev IN SELECT x FROM jsonb_array_elements(COALESCE(p_eventos, '[]'::jsonb)) AS x LOOP
    CONTINUE WHEN jsonb_typeof(ev) IS DISTINCT FROM 'object';
    -- Evento-mestre recorrente: a agenda não veio expandida. Falha fechada.
    IF jsonb_typeof(ev->'recurrence') = 'array' THEN
      erro := 'recorrencia';
    END IF;
    CONTINUE WHEN ev->'start' IS NULL OR ev->>'status' = 'cancelled';

    -- Dia inteiro: date começa à meia-noite; o fim (end.date) já é exclusivo.
    ini := COALESCE((ev->'start'->>'dateTime')::timestamptz,
                    (ev->'start'->>'date')::date::timestamp AT TIME ZONE tz);
    fim := COALESCE((ev->'end'->>'dateTime')::timestamptz,
                    (ev->'end'->>'date')::date::timestamp AT TIME ZONE tz,
                    ini);

    IF ev->'extendedProperties'->'private'->>'giulia_telefone' = p_telefone THEN
      IF ev->'start'->>'dateTime' IS NOT NULL THEN
        consultas := consultas || jsonb_build_object(
          'id',     ev->>'id',
          'inicio', ini,
          'fmt',    sales_agent.fmt_data_hora(ini),
          'futura', ini > p_agora,
          'resumo', ev->>'summary',
          'marcas', COALESCE(ev->'extendedProperties'->'private', '{}'::jsonb));
      END IF;
      CONTINUE;
    END IF;

    -- Um compromisso proíbe começar entre (início - folga - duração) e (fim + folga)
    pi := pi || (ini - make_interval(mins => intervalo + duracao));
    pf := pf || (fim + make_interval(mins => intervalo));
  END LOOP;

  -- Em ordem de data, sem repetir (o mesmo evento pode vir de duas buscas)
  SELECT COALESCE(jsonb_agg(u.c ORDER BY (u.c->>'inicio')::timestamptz), '[]'::jsonb)
    INTO consultas
    FROM (SELECT DISTINCT ON (COALESCE(c->>'id', c::text)) c
            FROM jsonb_array_elements(consultas) AS c
           ORDER BY COALESCE(c->>'id', c::text)) AS u;

  IF jsonb_array_length(blocos) = 0 THEN
    erro := COALESCE(erro, 'sem_expediente');
  END IF;

  -- Antecedência mínima: nada antes de agora + N horas
  pi := pi || ((hoje - 1)::timestamp AT TIME ZONE tz);
  pf := pf || minimo;

  -- Sugestões (só quando não há horário pedido), nos primeiros dias com vaga.
  -- Até 3, no máximo 2 no mesmo dia e, no mesmo dia, de períodos diferentes
  -- (manhã, tarde, noite) e espaçadas pela duração + folga. Ordem de escolha:
  --   1. um horário de cada período, o mais cedo possível;
  --   2. o que faltar, no primeiro dia que ainda aceita, na hora mais distante
  --      das já escolhidas (evita três ofertas na mesma hora);
  --   3. se nada disso couber, o primeiro horário que as regras aceitarem.
  IF erro IS NULL AND p_inicio IS NULL THEN
    dia := hoje;
    WHILE ((dia::timestamp AT TIME ZONE tz) <= limite) AND dias_vaga < max_dias LOOP
      EXIT WHEN f_data IS NOT NULL AND dia > f_data;
      IF (f_data IS NULL OR dia = f_data) AND (f_dow IS NULL OR EXTRACT(ISODOW FROM dia)::integer = f_dow) THEN
        achou := false;
        FOR f IN SELECT * FROM sales_agent.faixas_de_inicio(dia, blocos, duracao, pi, pf) LOOP
          t := GREATEST(f.inicio, inicio_sug);
          WHILE t <= f.fim LOOP
            SELECT p.codigo INTO per FROM sales_agent.periodos_do_dia() AS p
             WHERE (p.de IS NULL OR (t AT TIME ZONE tz)::time >= p.de)
               AND (p.ate IS NULL OR (t AT TIME ZONE tz)::time < p.ate);
            IF f_per IS NULL OR per = f_per THEN
              c_t   := c_t || t;
              c_dia := c_dia || dia;
              c_per := c_per || per;
              achou := true;
            END IF;
            t := t + make_interval(mins => passo_sugestao);
          END LOOP;
        END LOOP;
        IF achou THEN
          dias_vaga := dias_vaga + 1;
        END IF;
      END IF;
      dia := dia + 1;
    END LOOP;
    n := COALESCE(array_length(c_t, 1), 0);

    -- Cada rodada escolhe um candidato e o acrescenta; o passo muda quando
    -- não sobra candidato para ele
    FOR passo IN 1 .. 3 LOOP
      WHILE qtd < max_sugestoes LOOP
        melhor := NULL;
        FOR i IN 1 .. n LOOP
          -- passos 1 e 3: o primeiro que servir; passo 2: o melhor do primeiro dia que aceita
          EXIT WHEN melhor IS NOT NULL AND (passo <> 2 OR c_dia[i] <> c_dia[melhor]);
          CONTINUE WHEN c_t[i] = ANY (s_t)
                     OR (passo = 1 AND c_per[i] = ANY (s_per))
                     -- Dia da semana pedido: um de cada período só na primeira
                     -- ocorrência com vaga; as seguintes entram em ordem, no passo 2
                     OR (passo = 1 AND semana AND c_dia[i] <> c_dia[1]);
          -- No mesmo dia: no máximo max_por_dia, de períodos diferentes e espaçadas
          CONTINUE WHEN (SELECT count(*) FROM unnest(s_dia) AS d WHERE d = c_dia[i]) >= max_por_dia
                     OR EXISTS (SELECT 1 FROM unnest(s_t, s_dia, s_per) AS s(t, d, p)
                                 WHERE s.d = c_dia[i]
                                   AND (s.p = c_per[i]
                                        OR abs(EXTRACT(EPOCH FROM c_t[i] - s.t)) < (duracao + intervalo) * 60));
          IF passo = 2 THEN
            -- distância, em hora do dia, até a escolhida mais próxima
            SELECT min(abs(EXTRACT(EPOCH FROM (c_t[i] AT TIME ZONE tz)::time - (x AT TIME ZONE tz)::time)))
              INTO dist FROM unnest(s_t) AS x;
            -- Dia da semana pedido: a mesma hora em outra semana vale (fica por
            -- último), para não pular uma semana com vaga
            CONTINUE WHEN dist IS NULL OR (dist = 0 AND NOT semana) OR (melhor IS NOT NULL AND dist <= melhor_d);
            melhor_d := dist;
          END IF;
          melhor := i;
        END LOOP;
        EXIT WHEN melhor IS NULL;
        s_t   := s_t || c_t[melhor];
        s_dia := s_dia || c_dia[melhor];
        s_per := s_per || c_per[melhor];
        qtd   := qtd + 1;
      END LOOP;
    END LOOP;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('inicio', x, 'fmt', sales_agent.fmt_data_hora(x)) ORDER BY x), '[]'::jsonb)
      INTO sugestoes FROM unnest(s_t) AS x;

    -- Recorte pedido sem nenhum horário: o expediente não tem esse dia ou
    -- período, a data fica fora da antecedência ou do prazo, ou está ocupado
    IF qtd = 0 AND (f_per IS NOT NULL OR f_dow IS NOT NULL OR f_data IS NOT NULL) THEN
      motivo := CASE
        WHEN NOT EXISTS (
          SELECT 1
            FROM jsonb_array_elements(blocos) AS b
            LEFT JOIN sales_agent.periodos_do_dia() AS p ON p.codigo = f_per
           WHERE (COALESCE(f_dow, EXTRACT(ISODOW FROM f_data)::integer) IS NULL
                  OR (b->>'dia')::integer = COALESCE(f_dow, EXTRACT(ISODOW FROM f_data)::integer))
             -- o bloco permite começar entre o início dele e o fim menos a duração
             AND (b->>'fim')::time - make_interval(mins => duracao) >= (b->>'inicio')::time
             AND (f_per IS NULL OR ((p.ate IS NULL OR (b->>'inicio')::time < p.ate)
                                AND (p.de IS NULL OR (b->>'fim')::time - make_interval(mins => duracao) >= p.de))))
          THEN 'fora_do_expediente'
        WHEN f_data IS NOT NULL AND ((f_data + 1)::timestamp AT TIME ZONE tz) <= minimo THEN 'antecedencia'
        WHEN f_data IS NOT NULL AND (f_data::timestamp AT TIME ZONE tz) > limite THEN 'fora_do_prazo'
        ELSE 'sem_vaga' END;
    END IF;
  END IF;

  -- Conferência do horário pedido, na ordem em que a Giulia explica a recusa
  IF p_inicio IS NOT NULL AND erro IS NULL THEN
    dia := (p_inicio AT TIME ZONE tz)::date;
    IF p_inicio < minimo THEN
      motivo := 'antecedencia';
    ELSIF p_inicio > limite THEN
      motivo := 'fora_do_prazo';
    ELSIF NOT EXISTS (SELECT 1 FROM sales_agent.faixas_de_inicio(dia, blocos, duracao, '{}', '{}') x
                      WHERE p_inicio BETWEEN x.inicio AND x.fim) THEN
      motivo := 'fora_do_expediente';
    ELSIF NOT EXISTS (SELECT 1 FROM sales_agent.faixas_de_inicio(dia, blocos, duracao, pi, pf) x
                      WHERE p_inicio BETWEEN x.inicio AND x.fim) THEN
      motivo := 'ocupado';
    END IF;
    livre := motivo IS NULL;
  END IF;

  RETURN jsonb_build_object(
    'erro',       erro,
    'sugestoes',  sugestoes,
    'consultas',  consultas,
    'livre',      livre,
    'motivo',     motivo,
    'inicio_fmt', CASE WHEN p_inicio IS NOT NULL THEN sales_agent.fmt_data_hora(p_inicio) END,
    'duracao_minutos', duracao);
END;
$function$
;

-- Nome do dia da semana, como a cliente ou a Giulia escreve, para o número
-- ISO (1 = segunda ... 7 = domingo). Aceita "quinta", "Quinta-feira",
-- "sábado", "sabado". Devolve NULL se não reconhecer.
CREATE OR REPLACE FUNCTION sales_agent.dia_iso(p_texto text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE split_part(split_part(translate(lower(btrim(COALESCE(p_texto, ''))), 'áàâãéêíóôõúç', 'aaaaeeiooouc'), '-', 1), ' ', 1)
    WHEN 'segunda' THEN 1 WHEN 'terca' THEN 2 WHEN 'quarta' THEN 3 WHEN 'quinta' THEN 4
    WHEN 'sexta' THEN 5 WHEN 'sabado' THEN 6 WHEN 'domingo' THEN 7
  END;
$function$
;

-- Data escrita como DD/MM (com ou sem ano): a próxima data com esse dia e mês,
-- a partir de hoje. NULL se não for uma data válida.
CREATE OR REPLACE FUNCTION sales_agent.proxima_data(p_texto text, p_hoje date)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  md text[];
  dt date;
BEGIN
  md := regexp_match(btrim(COALESCE(p_texto, '')), '^(\d{1,2})/(\d{1,2})(?:/\d{2,4})?$');
  IF md IS NULL THEN
    RETURN NULL;
  END IF;
  BEGIN
    dt := make_date(EXTRACT(YEAR FROM p_hoje)::integer, md[2]::integer, md[1]::integer);
    IF dt < p_hoje THEN
      dt := make_date(EXTRACT(YEAR FROM p_hoje)::integer + 1, md[2]::integer, md[1]::integer);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
  RETURN dt;
END;
$function$
;

-- Grava o que o classificador achou na mensagem da cliente.
-- "nada" e vazio não são gravados: só sim, não e os tipos de objeção.
-- O horário pedido é conferido pela agenda_horarios com os eventos que o
-- workflow já buscou; só vira fato se estiver livre.
CREATE OR REPLACE FUNCTION sales_agent.registrar_fatos_mensagem(p_telefone text, p_wamid text, p_classificacao jsonb, p_eventos jsonb, p_referral jsonb DEFAULT NULL::jsonb, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  c           jsonb := CASE WHEN jsonb_typeof(p_classificacao) = 'object' THEN p_classificacao ELSE '{}'::jsonb END;
  gravados    text[] := '{}';
  descartados text[] := '{}';
  campo       text;
  v           text;
  d_txt       text;
  h_txt       text;
  dia_txt     text;
  mh          text[];
  hoje        date;
  dt          date;
  hr          time;
  ini         timestamptz;
  dow         integer;
  r           jsonb;
  horario     jsonb;
BEGIN
  hoje := (p_agora AT TIME ZONE tz)::date;

  -- Campos de sim/não, objeção e nome informado. Quem decide o que é válido
  -- é a regra da tabela (chk_fato_tipo_valor): o que ela recusar é descartado.
  FOREACH campo IN ARRAY ARRAY['problema_contado', 'decidiu', 'fora_do_perfil', 'conhece_trabalho', 'ja_fez_terapia', 'objecao', 'vai_pensar', 'nome_informado'] LOOP
    v := lower(btrim(c->>campo));
    CONTINUE WHEN v IS NULL OR v = '' OR v = 'nada';
    BEGIN
      INSERT INTO sales_agent.fatos_conversa (telefone, tipo, valor, origem, wamid, criado_em)
      VALUES (p_telefone, campo, v, 'classificador', p_wamid, p_agora);
      gravados := gravados || campo;
    EXCEPTION WHEN check_violation THEN
      descartados := descartados || (campo || '=' || v);
    END;
  END LOOP;

  -- Horário escolhido ou pedido
  d_txt   := btrim(COALESCE(c->>'horario_data', ''));
  h_txt   := lower(btrim(COALESCE(c->>'horario_hora', '')));
  dia_txt := btrim(COALESCE(c->>'horario_dia_semana', ''));
  IF d_txt <> '' AND h_txt <> '' THEN
    mh := regexp_match(h_txt, '^(\d{1,2})(?:\s*[:h]\s*(\d{2})?)?\s*h?$');
    dt := sales_agent.proxima_data(d_txt, hoje);
    BEGIN
      IF mh IS NULL THEN
        RAISE EXCEPTION 'formato';
      END IF;
      hr := make_time(mh[1]::integer, COALESCE(mh[2], '0')::integer, 0);
    EXCEPTION WHEN OTHERS THEN
      dt := NULL;
    END;

    IF dt IS NULL THEN
      horario := jsonb_build_object('resultado', 'invalido', 'data', d_txt, 'hora', h_txt);
    ELSE
      dow := sales_agent.dia_iso(dia_txt);
      ini := (dt + hr) AT TIME ZONE tz;
      IF dow IS NOT NULL AND dow <> EXTRACT(ISODOW FROM dt)::integer THEN
        -- O dia da semana citado não bate com a data: não grava (bug #25)
        horario := jsonb_build_object('resultado', 'dia_nao_bate', 'inicio', ini, 'fmt', sales_agent.fmt_data_hora(ini), 'dia_citado', dia_txt);
      ELSE
        r := sales_agent.agenda_horarios(p_eventos, p_telefone, ini, p_agora);
        IF r->>'erro' IS NOT NULL THEN
          horario := jsonb_build_object('resultado', 'erro_agenda', 'inicio', ini, 'fmt', r->>'inicio_fmt', 'erro', r->>'erro');
        ELSIF (r->>'livre')::boolean THEN
          INSERT INTO sales_agent.fatos_conversa (telefone, tipo, horario, origem, wamid, criado_em)
          VALUES (p_telefone, 'horario_escolhido', ini, 'classificador', p_wamid, p_agora);
          gravados := gravados || 'horario_escolhido'::text;
          horario := jsonb_build_object('resultado', 'livre', 'inicio', ini, 'fmt', r->>'inicio_fmt');
        ELSE
          horario := jsonb_build_object('resultado', 'indisponivel', 'inicio', ini, 'fmt', r->>'inicio_fmt', 'motivo', r->>'motivo');
        END IF;
      END IF;
    END IF;
  END IF;

  -- Origem do anúncio: o objeto referral da Meta, só na primeira mensagem
  -- depois do clique. Guarda só os identificadores.
  IF jsonb_typeof(p_referral) = 'object'
     AND (COALESCE(p_referral->>'ctwa_clid', '') <> '' OR COALESCE(p_referral->>'source_id', '') <> '')
     AND NOT EXISTS (SELECT 1 FROM sales_agent.fatos_conversa
                      WHERE telefone = p_telefone AND tipo = 'origem_anuncio' AND wamid IS NOT DISTINCT FROM p_wamid) THEN
    INSERT INTO sales_agent.fatos_conversa (telefone, tipo, detalhes, origem, wamid, criado_em)
    VALUES (p_telefone, 'origem_anuncio',
            jsonb_strip_nulls(jsonb_build_object(
              'ctwa_clid',   NULLIF(p_referral->>'ctwa_clid', ''),
              'source_id',   NULLIF(p_referral->>'source_id', ''),
              'source_type', NULLIF(p_referral->>'source_type', ''),
              'source_url',  NULLIF(p_referral->>'source_url', ''))),
            'meta', p_wamid, p_agora);
    gravados := gravados || 'origem_anuncio'::text;
  END IF;

  RETURN jsonb_build_object('gravados', to_jsonb(gravados), 'descartados', to_jsonb(descartados), 'horario', horario);
END;
$function$
;

-- Caso de um nome contra o gênero atendido pela terapeuta. Regra única, usada
-- pela situacao_da_conversa e pela fatos_e_etapa.
CREATE OR REPLACE FUNCTION sales_agent.caso_do_nome(p_genero_atendido text, p_genero_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Regra única, para o nome informado e para o nome do perfil do WhatsApp:
  -- "fora" quando o nome é do gênero que a terapeuta não atende, "dois" quando
  -- serve para os dois e a terapeuta atende um gênero só; senão, NULL.
  SELECT CASE p_genero_atendido
           WHEN 'mulheres' THEN CASE p_genero_nome WHEN 'masculino' THEN 'fora' WHEN 'ambos' THEN 'dois' END
           WHEN 'homens'   THEN CASE p_genero_nome WHEN 'feminino'  THEN 'fora' WHEN 'ambos' THEN 'dois' END
         END
$function$
;

-- Calcula a etapa a partir dos fatos, do banco e da agenda, e monta as linhas
-- de fatos da SITUACAO_DA_CLIENTE. Não grava nada.
-- Ordem fixa: a primeira condição que valer decide a etapa.
CREATE OR REPLACE FUNCTION sales_agent.situacao_da_conversa(p_telefone text, p_eventos jsonb, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  cfg          record;
  valor_atual  numeric;
  corte        timestamptz;
  ag           jsonb;
  tem_consulta boolean;
  sinal_livre  boolean;
  pix_prazo    timestamptz;
  fora         text;
  oferta_em    timestamptz;
  problema_em  timestamptz;
  valores_ok   boolean;
  dec_valor    text;
  dec_em       timestamptz;
  nao_em       timestamptz;
  oferta_antes boolean := false;
  h_ini        timestamptz;
  h_em         timestamptz;
  h_ok         boolean := false;
  h_livre      boolean;
  obj          text;
  pensar_em    timestamptz;
  hesita_em    timestamptz;
  hesitou      boolean := false;
  nome_v       text;
  perfil_conf  boolean := false;
  perfil_caso  text;
  etapa        text;
  primeira     boolean;
  linhas       text[] := '{}';
BEGIN
  SELECT * INTO cfg FROM sales_agent.business_config_runtime LIMIT 1;
  valor_atual := cfg.consulta_total_centavos / 100.0;

  -- Fatos anteriores ao corte não contam (continuam no registro):
  -- o último sinal usado encerra a venda anterior; e uma decisão com mais
  -- de validade_fatos_dias já não é atual.
  corte := GREATEST(p_agora - make_interval(days => cfg.validade_fatos_dias),
                    (SELECT max(usada_em) FROM sales_agent.cobrancas WHERE telefone = p_telefone),
                    '-infinity'::timestamptz);

  -- Agenda: consultas futuras da cliente
  ag := sales_agent.agenda_horarios(p_eventos, p_telefone, NULL, p_agora);
  tem_consulta := EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(ag->'consultas', '[]'::jsonb)) x
                           WHERE (x->>'futura')::boolean);

  -- Banco: sinal pago e não usado (mesma condição do nó Ler Situação) e PIX
  -- pendente ainda no prazo (o contrário exato da condição da marcar_expirada)
  sinal_livre := EXISTS (SELECT 1 FROM sales_agent.cobrancas
                          WHERE telefone = p_telefone AND status = 'paga' AND usada_em IS NULL);
  pix_prazo := (SELECT max(expira_em) FROM sales_agent.cobrancas
                 WHERE telefone = p_telefone AND status = 'pendente' AND expira_em > p_agora);

  -- Fatos vigentes (depois do corte); de cada tipo, vale o mais recente
  SELECT valor INTO fora FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'fora_do_perfil' AND criado_em > corte
   ORDER BY criado_em DESC, id DESC LIMIT 1;

  -- "Valores informados" só vale se o valor for o atual (preço sempre o atual).
  -- Devolvido também em valores_informados: a trava da cobrança lê daqui.
  valores_ok := EXISTS (SELECT 1 FROM sales_agent.fatos_conversa
                         WHERE telefone = p_telefone AND tipo = 'valores_informados' AND criado_em > corte
                           AND valor_consulta = valor_atual);
  SELECT max(criado_em) INTO oferta_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND criado_em > corte
     AND ((tipo = 'valores_informados' AND valor_consulta = valor_atual) OR tipo = 'horarios_oferecidos');
  SELECT max(criado_em) INTO problema_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'problema_contado' AND criado_em > corte;

  SELECT valor, criado_em INTO dec_valor, dec_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'decidiu' AND criado_em > corte
   ORDER BY criado_em DESC, id DESC LIMIT 1;
  SELECT max(criado_em) INTO nao_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'decidiu' AND valor = 'nao' AND criado_em > corte;
  IF dec_valor = 'sim' THEN
    oferta_antes := EXISTS (SELECT 1 FROM sales_agent.fatos_conversa
                             WHERE telefone = p_telefone AND criado_em > corte AND criado_em < dec_em
                               AND ((tipo = 'valores_informados' AND valor_consulta = valor_atual) OR tipo = 'horarios_oferecidos'));
  END IF;

  -- Horário escolhido: o mais recente, ainda no futuro e sem desistência depois
  SELECT horario, criado_em INTO h_ini, h_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'horario_escolhido' AND criado_em > corte
   ORDER BY criado_em DESC, id DESC LIMIT 1;
  h_ok := h_ini IS NOT NULL AND h_ini > p_agora AND (nao_em IS NULL OR h_em > nao_em);
  IF h_ok THEN
    h_livre := COALESCE((sales_agent.agenda_horarios(p_eventos, p_telefone, h_ini, p_agora)->>'livre')::boolean, false);
  END IF;

  -- Hesitação depois do compromisso: "vou pensar" ou objeção mais recente que
  -- a última decisão ou que o horário escolhido. Ela volta a decidir, então
  -- sai do Fechamento até decidir de novo. Na mesma mensagem, não conta.
  SELECT max(criado_em) INTO hesita_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo IN ('vai_pensar', 'objecao') AND criado_em > corte;
  hesitou := hesita_em > GREATEST(CASE WHEN dec_valor = 'sim' THEN dec_em END,
                                  CASE WHEN h_ok THEN h_em END);

  -- Perfil a confirmar: a terapeuta atende um gênero só (genero_atendido), o
  -- último nome de quem vai à consulta é do outro gênero ou serve para os dois
  -- (classificador), e a conversa não tem confirmação de que a consulta é para
  -- alguém no perfil (fora_do_perfil = nao, antes ou depois do nome). Fora do
  -- perfil confirmado já é outra etapa. Atende todos: não há o que confirmar
  -- pelo nome. Lido pela trava da cobrança.
  SELECT valor INTO nome_v FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'nome_informado' AND criado_em > corte
   ORDER BY criado_em DESC, id DESC LIMIT 1;
  -- O caso do nome vem da caso_do_nome, a mesma regra usada para o nome do
  -- perfil do WhatsApp: "dois" (o nome serve para os dois) ou "fora" (o nome
  -- é do gênero não atendido); a montagem do prompt escolhe o texto pelo caso
  perfil_caso := sales_agent.caso_do_nome(cfg.genero_atendido, nome_v);
  perfil_conf := perfil_caso IS NOT NULL AND fora IS DISTINCT FROM 'nao' AND fora IS DISTINCT FROM 'sim';
  IF NOT perfil_conf THEN
    perfil_caso := NULL;
  END IF;

  -- A etapa: banco e agenda antes da conversa
  IF fora = 'sim' THEN
    etapa := 'fora_do_perfil';
  ELSIF tem_consulta THEN
    etapa := 'agendada';
  ELSIF sinal_livre THEN
    etapa := 'pago_sem_consulta';
  ELSIF pix_prazo IS NOT NULL THEN
    etapa := 'aguardando_pagamento';
  ELSIF (h_ok OR (dec_valor = 'sim' AND oferta_antes)) AND hesitou IS NOT TRUE THEN
    etapa := 'fechamento';
  ELSIF problema_em IS NOT NULL AND (oferta_em IS NULL OR problema_em > oferta_em) THEN
    etapa := 'qualificacao';
  ELSIF oferta_em IS NOT NULL THEN
    etapa := 'oferta';
  ELSE
    etapa := 'chegada';
  END IF;

  -- Primeira resposta: a Giulia ainda não respondeu nesta conversa
  -- (falas da terapeuta não contam)
  primeira := NOT EXISTS (
    SELECT 1 FROM sales_agent.n8n_chat_histories
     WHERE session_id = p_telefone
       AND message->>'type' = 'ai'
       AND COALESCE(message->>'content', '') <> ''
       AND COALESCE(message->'additional_kwargs'->>'sender', '') <> 'therapist');

  -- Linhas da SITUACAO_DA_CLIENTE (só as que se aplicam). Só informam fatos:
  -- o que a Giulia faz com eles está no prompt.
  IF sinal_livre THEN
    linhas := linhas || 'Sinal: pago, ainda não usado.'::text;
  ELSIF pix_prazo IS NOT NULL THEN
    linhas := linhas || ('Sinal: PIX enviado, vale até ' || sales_agent.fmt_data_hora(pix_prazo) || '.');
  END IF;

  IF etapa IN ('chegada', 'qualificacao', 'oferta', 'fechamento') THEN
    linhas := linhas || ('Valores da consulta: '
                         || CASE WHEN valores_ok THEN 'já informados nesta conversa.' ELSE 'ainda não informados nesta conversa.' END);
  END IF;

  IF h_ok THEN
    linhas := linhas || ('Horário escolhido: ' || sales_agent.fmt_data_hora(h_ini)
                         || CASE WHEN h_livre THEN ' — livre (conferido agora).' ELSE ' — não está mais livre (conferido agora).' END);
  END IF;

  IF perfil_conf AND etapa IN ('chegada', 'qualificacao', 'oferta', 'fechamento') THEN
    linhas := linhas || ('Perfil atendido: ainda não confirmado nesta conversa (o nome de quem vai à consulta '
                         || CASE nome_v WHEN 'masculino' THEN 'é de homem' WHEN 'feminino' THEN 'é de mulher'
                                        ELSE 'pode ser de homem ou de mulher' END || ').');
  END IF;

  IF etapa = 'fora_do_perfil' THEN
    linhas := linhas || 'Perfil atendido: a conversa confirmou que a consulta é para alguém fora do perfil atendido.'::text;
  END IF;

  SELECT valor INTO obj FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'objecao' AND criado_em > corte
   ORDER BY criado_em DESC, id DESC LIMIT 1;
  IF obj IS NOT NULL THEN
    linhas := linhas || ('Objeção já levantada: '
                         || CASE obj WHEN 'preco' THEN 'preço' WHEN 'tempo' THEN 'tempo'
                                     WHEN 'outra_pessoa' THEN 'a consulta é para outra pessoa'
                                     WHEN 'duvida_terapia' THEN 'dúvida sobre a terapia'
                                     ELSE 'outro motivo' END || '.');
  END IF;

  SELECT max(criado_em) INTO pensar_em FROM sales_agent.fatos_conversa
   WHERE telefone = p_telefone AND tipo = 'vai_pensar' AND criado_em > corte;
  IF pensar_em IS NOT NULL AND (dec_em IS NULL OR pensar_em > dec_em) THEN
    linhas := linhas || ('Disse que ia pensar, em ' || to_char(pensar_em AT TIME ZONE tz, 'DD/MM') || '.');
  END IF;

  RETURN jsonb_build_object('etapa', etapa, 'primeira_resposta', primeira, 'linhas', to_jsonb(linhas),
                            'valores_informados', valores_ok, 'perfil_a_confirmar', perfil_conf,
                            'perfil_caso', perfil_caso);
END;
$function$
;

-- Motivo de um horário não estar disponível, por extenso, para o prompt.
CREATE OR REPLACE FUNCTION sales_agent.fmt_motivo(p_motivo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_motivo
    WHEN 'antecedencia'       THEN 'fica antes da antecedência mínima para marcar'
    WHEN 'fora_do_prazo'      THEN 'fica além do prazo máximo para marcar'
    WHEN 'fora_do_expediente' THEN 'fora do horário de atendimento'
    WHEN 'sem_vaga'           THEN 'tudo ocupado'
    ELSE 'ocupado' END;
$function$
;

-- Sugestões de horário uma por linha, para HORARIOS_DISPONIVEIS.
CREATE OR REPLACE FUNCTION sales_agent.fmt_sugestoes(p_sugestoes jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT string_agg(s->>'fmt', E'\n' ORDER BY n)
    FROM jsonb_array_elements(COALESCE(p_sugestoes, '[]'::jsonb)) WITH ORDINALITY AS x(s, n)
$function$
;

-- Chamada única do n8n antes da Giulia responder: grava os fatos da mensagem
-- e devolve a etapa e as linhas de fatos para o prompt. Com período ou dia
-- pedido, devolve também os horários livres desse recorte (horarios_pedidos).
CREATE OR REPLACE FUNCTION sales_agent.fatos_e_etapa(p_telefone text, p_wamid text, p_classificacao jsonb, p_eventos jsonb, p_referral jsonb DEFAULT NULL::jsonb, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  reg     jsonb;
  sit     jsonb;
  h       jsonb;
  h_local timestamp;
  d_cit   integer;
  d_alt   date;
  hoje    date;
  linhas  jsonb;
  c       jsonb;
  per     record;
  dia_txt text;
  f_data  date;
  f_dow   integer;
  ag      jsonb;
  recorte text;
  pedidos jsonb;
  genero  text;
  wpp_fora boolean := false;
BEGIN
  reg := sales_agent.registrar_fatos_mensagem(p_telefone, p_wamid, p_classificacao, p_eventos, p_referral, p_agora);
  sit := sales_agent.situacao_da_conversa(p_telefone, p_eventos, p_agora);
  linhas := sit->'linhas';

  -- Horário pedido nesta mensagem que não virou fato: a linha só informa o
  -- motivo. O que a Giulia faz com isso está no prompt.
  h := reg->'horario';
  IF h->>'resultado' = 'indisponivel' THEN
    linhas := linhas || to_jsonb('Horário pedido nesta mensagem: ' || (h->>'fmt') || ' — não disponível (conferido agora): '
      || sales_agent.fmt_motivo(h->>'motivo') || '.');
  ELSIF h->>'resultado' = 'dia_nao_bate' THEN
    -- O dia da semana que ela disse não combina com a data (bug #25): o dia
    -- citado sai pelo nome padrão (dia_iso + fmt_dias), nunca pelo texto livre.
    -- A linha traz também a data desse dia da semana mais próxima da data dita
    -- (até 3 dias antes ou depois), para a Giulia não fazer conta de data. Se
    -- essa data for hoje ou já tiver passado, vai a próxima a partir de amanhã.
    h_local := (h->>'inicio')::timestamptz AT TIME ZONE tz;
    hoje    := (p_agora AT TIME ZONE tz)::date;
    d_cit   := sales_agent.dia_iso(h->>'dia_citado');
    d_alt   := h_local::date + ((((d_cit - EXTRACT(ISODOW FROM h_local)::integer + 3) % 7) + 7) % 7 - 3);
    linhas := linhas || to_jsonb('Horário pedido nesta mensagem: '
      || sales_agent.fmt_dias(ARRAY[d_cit])
      || ', ' || to_char(h_local, 'DD/MM') || ' às ' || sales_agent.fmt_hora(h_local::time)
      || ' — o dia da semana não bate com a data: ' || to_char(h_local, 'DD/MM') || ' é '
      || sales_agent.fmt_dias(ARRAY[EXTRACT(ISODOW FROM h_local)::integer]) || '; '
      || CASE WHEN d_alt > hoje
           THEN CASE WHEN d_cit >= 6 THEN 'o ' ELSE 'a ' END || sales_agent.fmt_dias(ARRAY[d_cit])
                || CASE WHEN d_cit >= 6 THEN ' mais próximo' ELSE ' mais próxima' END
                || ' dessa data é ' || to_char(d_alt, 'DD/MM')
           ELSE CASE WHEN d_cit >= 6 THEN 'o próximo ' ELSE 'a próxima ' END || sales_agent.fmt_dias(ARRAY[d_cit])
                || ' é ' || to_char(d_alt + 7, 'DD/MM')
         END || '.');
  END IF;

  -- Pedido de horários de um período e/ou de um dia, sem hora exata: as opções
  -- livres saem só desse recorte, pela mesma agenda_horarios. Havendo, elas vão
  -- para HORARIOS_DISPONIVEIS no lugar das sugestões gerais (horarios_pedidos);
  -- a linha diz só o que ela pediu, sem instrução que contradiga outra seção.
  c := CASE WHEN jsonb_typeof(p_classificacao) = 'object' THEN p_classificacao ELSE '{}'::jsonb END;
  SELECT * INTO per FROM sales_agent.periodos_do_dia() AS p
   WHERE p.nome = translate(lower(btrim(COALESCE(c->>'periodo_pedido', ''))), 'ã', 'a');
  dia_txt := btrim(COALESCE(c->>'dia_pedido', ''));
  f_data  := sales_agent.proxima_data(dia_txt, (p_agora AT TIME ZONE tz)::date);
  f_dow   := CASE WHEN f_data IS NULL THEN sales_agent.dia_iso(dia_txt) END;
  IF (per.codigo IS NOT NULL OR f_data IS NOT NULL OR f_dow IS NOT NULL)
     AND COALESCE(h->>'resultado', '') <> 'livre' THEN
    ag := sales_agent.agenda_horarios(p_eventos, p_telefone, NULL, p_agora,
            jsonb_strip_nulls(jsonb_build_object('periodo', per.nome, 'dia_semana', f_dow, 'data', f_data)));
    recorte := btrim(
      CASE WHEN f_data IS NOT NULL THEN 'no dia ' || to_char(f_data, 'DD/MM')
                                        || ' (' || sales_agent.fmt_dias(ARRAY[EXTRACT(ISODOW FROM f_data)::integer]) || ')'
           WHEN f_dow IS NOT NULL THEN CASE WHEN f_dow >= 6 THEN 'no ' ELSE 'na ' END || sales_agent.fmt_dias(ARRAY[f_dow])
           ELSE '' END
      || CASE per.nome
           WHEN 'manha' THEN ' de manhã (até as ' || sales_agent.fmt_hora(per.ate) || ')'
           WHEN 'tarde' THEN ' à tarde (das ' || sales_agent.fmt_hora(per.de) || ' às ' || sales_agent.fmt_hora(per.ate) || ')'
           WHEN 'noite' THEN ' à noite (a partir das ' || sales_agent.fmt_hora(per.de) || ')'
           ELSE '' END);
    -- Agenda com erro: o texto de HORARIOS_DISPONIVEIS já orienta a Giulia
    IF ag->>'erro' IS NULL THEN
      IF jsonb_array_length(ag->'sugestoes') > 0 THEN
        pedidos := jsonb_build_object('texto', sales_agent.fmt_sugestoes(ag->'sugestoes'),
                                      'sugestoes', ag->'sugestoes');
        linhas := linhas || to_jsonb('Ela pediu horários ' || recorte || '.');
      ELSE
        linhas := linhas || to_jsonb('Ela pediu horários ' || recorte || ': nenhum disponível ('
          || sales_agent.fmt_motivo(ag->>'motivo') || ').');
      END IF;
    END IF;
  END IF;

  -- Nome do perfil do WhatsApp do gênero que a terapeuta não atende, na
  -- primeira resposta da Giulia: a montagem do prompt acrescenta a pergunta do
  -- perfil. Mesma regra do nome informado (caso_do_nome), só no caso "fora".
  -- Só nas etapas da venda (quem já pagou ou tem consulta não recebe a
  -- pergunta). Não vale quando o perfil já está a confirmar pelo nome
  -- informado, nem quando esta mensagem já diz se a consulta é para alguém no
  -- perfil.
  -- Nada é gravado.
  IF (sit->>'primeira_resposta')::boolean IS TRUE
     AND (sit->>'perfil_a_confirmar')::boolean IS NOT TRUE
     AND sit->>'etapa' IN ('chegada', 'qualificacao', 'oferta', 'fechamento')
     AND COALESCE(c->>'fora_do_perfil', 'nada') NOT IN ('sim', 'nao') THEN
    SELECT genero_atendido INTO genero FROM sales_agent.business_config_runtime LIMIT 1;
    wpp_fora := sales_agent.caso_do_nome(genero, c->>'nome_perfil') = 'fora';
  END IF;

  RETURN sit || jsonb_build_object(
    'perfil_whatsapp_fora', COALESCE(wpp_fora, false),
    'linhas', linhas,
    'linhas_texto', (SELECT COALESCE(string_agg(l, E'\n' ORDER BY n), '') FROM jsonb_array_elements_text(linhas) WITH ORDINALITY AS t(l, n)),
    'registro', reg,
    -- Horários livres do período ou dia pedido, ou NULL: no n8n, substituem as
    -- sugestões gerais no prompt e no registro dos horários oferecidos
    'horarios_pedidos', pedidos);
END;
$function$
;

-- Grava o que a resposta enviada da Giulia mostrou à cliente. Chamada depois
-- de o envio dar certo, só nas etapas antes do pagamento.
-- Valores: o texto traz o valor da consulta (R$490,00, R$ 490,00 ou R$490).
-- Horários: o texto traz a data e a hora de uma das sugestões (15/10 às 14h).
-- A hora vale até 100 caracteres depois da data, sem outra data no meio:
-- "29/10 (quinta-feira) às 18h" e "22/10, estão disponíveis: 13h30, 18h".
CREATE OR REPLACE FUNCTION sales_agent.registrar_fatos_resposta(p_telefone text, p_wamid text, p_texto text, p_sugestoes jsonb, p_etapa text, p_agora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  tz constant text := 'America/Sao_Paulo';
  cfg      record;
  v        numeric;
  norm     text;
  inteiro  text;
  cent     text;
  padrao   text;
  s        jsonb;
  t        timestamptz;
  achou    jsonb := '[]'::jsonb;
  gravados text[] := '{}';
BEGIN
  IF COALESCE(p_texto, '') = '' OR p_etapa IS NULL
     OR p_etapa NOT IN ('chegada', 'qualificacao', 'oferta', 'fechamento') THEN
    RETURN jsonb_build_object('gravados', '[]'::jsonb);
  END IF;

  -- Espaço comum ou espaço "duro" entre R$ e o número não conta
  norm := regexp_replace(replace(p_texto, chr(160), ' '), 'R\$\s+', 'R$', 'g');

  SELECT * INTO cfg FROM sales_agent.business_config_runtime LIMIT 1;
  v := cfg.consulta_total_centavos / 100.0;
  IF v IS NOT NULL THEN
    inteiro := translate(to_char(trunc(v), 'FM999,999,990'), ',', '.');
    cent    := lpad(round((v - trunc(v)) * 100)::integer::text, 2, '0');
    -- Com ou sem o separador de milhar; centavos ",00" opcionais
    padrao := 'R\$(' || replace(inteiro, '.', '\.')
              || CASE WHEN strpos(inteiro, '.') > 0 THEN '|' || replace(inteiro, '.', '') ELSE '' END || ')'
              || CASE WHEN cent = '00' THEN '(,00)?' ELSE ',' || cent END
              || '(?!,?[0-9])';
    IF norm ~ padrao THEN
      INSERT INTO sales_agent.fatos_conversa (telefone, tipo, valor_consulta, origem, wamid, criado_em)
      VALUES (p_telefone, 'valores_informados', v, 'sistema', p_wamid, p_agora);
      gravados := gravados || 'valores_informados'::text;
    END IF;
  END IF;

  FOR s IN SELECT x FROM jsonb_array_elements(COALESCE(p_sugestoes, '[]'::jsonb)) AS x LOOP
    t := (s->>'inicio')::timestamptz;
    CONTINUE WHEN t IS NULL;
    padrao := '(^|[^0-9])0?' || to_char(t AT TIME ZONE tz, 'FMDD') || '/' || to_char(t AT TIME ZONE tz, 'MM')
              || '(/[0-9]{2,4})?((?![0-9]{1,2}/[0-9]{1,2}).){0,100}[^0-9]0?' || to_char(t AT TIME ZONE tz, 'FMHH24')
              || CASE WHEN to_char(t AT TIME ZONE tz, 'MI') = '00'
                      THEN '(h(?![0-9])|:00|\s*horas?)'
                      ELSE '(h' || to_char(t AT TIME ZONE tz, 'MI') || '|:' || to_char(t AT TIME ZONE tz, 'MI') || ')' END;
    IF norm ~* padrao THEN
      achou := achou || jsonb_build_array(s->'inicio');
    END IF;
  END LOOP;
  IF jsonb_array_length(achou) > 0 THEN
    INSERT INTO sales_agent.fatos_conversa (telefone, tipo, detalhes, origem, wamid, criado_em)
    VALUES (p_telefone, 'horarios_oferecidos', jsonb_build_object('horarios', achou), 'sistema', p_wamid, p_agora);
    gravados := gravados || 'horarios_oferecidos'::text;
  END IF;

  RETURN jsonb_build_object('gravados', to_jsonb(gravados));
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
    intervalo_nova_consulta_dias,
    validade_pix_horas,
    validade_fatos_dias,
    genero_atendido
   FROM sales_agent.business_config c;

CREATE OR REPLACE TRIGGER trg_touch_business_config BEFORE UPDATE ON sales_agent.business_config FOR EACH ROW EXECUTE FUNCTION sales_agent.touch_business_config();


-- 10. RLS ligado em todas as tabelas -------------------------------------------

ALTER TABLE public.knowledge_base_text ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.business_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.cobranca_tipos ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.cobrancas ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_agent.fatos_conversa ENABLE ROW LEVEL SECURITY;
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

COMMENT ON COLUMN sales_agent.business_config.intervalo_entre_consultas_minutos IS 'Folga mínima entre o fim de um compromisso e o início do próximo atendimento. Usada em dois lugares pela função agenda_horarios: todo compromisso da agenda é expandido por este valor nos dois lados, e as sugestões de horário ficam espaçadas de (duracao_consulta_minutos + este valor). Zero = atendimentos colados.';

COMMENT ON COLUMN sales_agent.business_config.janela_maxima_dias IS 'Não oferecer horário depois de hoje + N dias. Evita agendar para daqui a seis meses.';

COMMENT ON TABLE sales_agent.horarios_atendimento IS 'Blocos de atendimento por dia da semana. Duas linhas no mesmo dia = intervalo entre elas (almoço). Fonte única dos horários — a business_config não guarda mais hora_inicio/hora_fim.';

COMMENT ON COLUMN sales_agent.business_config.antecedencia_reagendamento_horas IS 'A Giulia só reagenda se a consulta atual começar daqui a pelo menos N horas. Dentro do prazo, ela informa a regra e transfere para a terapeuta.';

COMMENT ON COLUMN sales_agent.business_config.limite_reagendamentos IS 'Quantas vezes a mesma consulta pode ser reagendada pela Giulia. Vazio = sem limite.';

COMMENT ON COLUMN sales_agent.business_config.intervalo_nova_consulta_dias IS 'A Giulia só vende nova consulta inicial se a cliente não tiver consulta marcada pela Giulia no futuro nem nos últimos N dias. Consulta recente: transfere para a terapeuta.';

COMMENT ON COLUMN sales_agent.cobrancas.usada_em IS 'Quando o sinal foi usado para marcar a primeira consulta. Preenchido uma vez e nunca liberado pelo sistema: devolução, retenção ou crédito é decisão da terapeuta.';

COMMENT ON COLUMN sales_agent.business_config.validade_pix_horas IS 'Por quantas horas o PIX do sinal vale depois de gerado. O sistema informa esse prazo ao banco ao criar a cobrança, e o banco recusa pagamento depois dele.';

COMMENT ON COLUMN sales_agent.cobrancas.expira_em IS 'Quando o PIX vence: o mesmo prazo informado ao banco na criação. O sistema decide por ele se reaproveita a cobrança ou gera outra; ao banco só pergunta se foi paga.';

COMMENT ON FUNCTION sales_agent.fmt_data_hora(timestamp with time zone) IS 'Data e hora por extenso no horário de Brasília (ex.: domingo, 04/10 às 10h22). Reaproveita fmt_dias e fmt_hora.';

COMMENT ON COLUMN sales_agent.cobrancas.status IS 'pendente → paga (registrar_pagamento) → estornada · pendente → expirada (marcar_expirada) · expirada → paga, se o banco confirmar o pagamento. Mudar a situação só pelas funções, que conferem a mudança permitida.';

COMMENT ON COLUMN sales_agent.cobrancas.confirmado_por IS 'Quem confirmou o pagamento: cliente (conferido numa conversa — "paguei" ou novo pedido de PIX), aviso (aviso do banco) ou varredura. Mede no piloto quantas vezes o aviso do banco falhou.';

COMMENT ON FUNCTION sales_agent.registrar_pagamento(text, timestamp with time zone, text, text) IS 'Marca a cobrança como paga, a partir de pendente ou expirada (se o banco diz que foi pago, o dinheiro entrou). Devolve o telefone e se algo mudou; já paga devolve mudou = false. Pedido inexistente não devolve linha.';

COMMENT ON FUNCTION sales_agent.marcar_expirada(text) IS 'Marca a cobrança como expirada, só a partir de pendente e só depois do prazo (expira_em). Devolve o telefone e se algo mudou; ainda no prazo devolve mudou = false.';

COMMENT ON COLUMN sales_agent.horarios_atendimento.dia_semana IS '1=segunda ... 7=domingo. Padrão ISO 8601 — mesmo do EXTRACT(ISODOW) do Postgres, usado pela função agenda_horarios.';

COMMENT ON FUNCTION sales_agent.faixas_de_inicio(date, jsonb, integer, timestamp with time zone[], timestamp with time zone[]) IS 'Horários em que uma consulta pode começar num dia: dentro dos blocos de atendimento e fora dos intervalos proibidos. Os intervalos proibidos são abertos (encostar não é conflito), então um vão do tamanho exato da consulta conta como livre. Usada pela agenda_horarios.';

COMMENT ON FUNCTION sales_agent.agenda_horarios(jsonb, text, timestamp with time zone, timestamp with time zone, jsonb) IS 'Regras de horário da agenda num lugar só: expediente, antecedência mínima, prazo máximo e folga entre consultas. Recebe os eventos como o Google devolve e o telefone da cliente; as consultas dela não ocupam horário. Sem horário pedido, devolve até 3 sugestões nos 3 primeiros dias com vaga: no máximo 2 no mesmo dia, de períodos diferentes (periodos_do_dia); primeiro uma de cada período, depois horas diferentes das já escolhidas. Com p_filtro (periodo, dia_semana, data), só desse recorte; sem nenhuma, motivo diz por quê. Data pedida: só ela. Dia da semana pedido: a próxima ocorrência primeiro, completada pelas seguintes, sem pular nenhuma com vaga. Também devolve as consultas da cliente. Com horário pedido, diz se está livre ou o motivo da recusa. Não tem valores padrão próprios: usa os da business_config. Devolve só dados.';

COMMENT ON COLUMN sales_agent.business_config.validade_fatos_dias IS 'Por quantos dias um fato da conversa (decidiu, horário escolhido, valores informados...) ainda conduz a conversa. Mais velho que isso, a regra da etapa o ignora (o fato continua no registro). Padrão 30.';

COMMENT ON TABLE sales_agent.fatos_conversa IS 'Registro dos fatos da conversa, por cliente (3.18). Cada fato é uma linha nova, com quem anotou e o código da mensagem; nada é alterado nem apagado pela Giulia. De cada tipo vale o mais recente. A etapa não é guardada: é calculada pela situacao_da_conversa.';
COMMENT ON COLUMN sales_agent.fatos_conversa.tipo IS 'problema_contado, decidiu, horario_escolhido, fora_do_perfil, valores_informados, horarios_oferecidos (mudam a etapa) · conhece_trabalho, ja_fez_terapia, objecao, vai_pensar, origem_anuncio (métrica) · nome_informado (não muda a etapa; decide o perfil a confirmar). Fato de métrica nunca muda a etapa.';
COMMENT ON COLUMN sales_agent.fatos_conversa.valor IS 'sim/nao, o tipo de objeção (preco, tempo, outra_pessoa, duvida_terapia, outra) ou, no nome informado, feminino/masculino/ambos.';
COMMENT ON COLUMN sales_agent.fatos_conversa.horario IS 'Horário escolhido pela cliente. Só gravado depois de a agenda_horarios confirmar que estava livre.';
COMMENT ON COLUMN sales_agent.fatos_conversa.valor_consulta IS 'Valor da consulta que a Giulia informou. O fato só vale enquanto for igual ao valor atual (preço sempre o atual).';
COMMENT ON COLUMN sales_agent.fatos_conversa.detalhes IS 'origem_anuncio: identificadores do anúncio (ctwa_clid, source_id...). horarios_oferecidos: os horários encontrados na resposta.';
COMMENT ON COLUMN sales_agent.fatos_conversa.origem IS 'Quem anotou: classificador (antes da Giulia responder), sistema (depois do envio da resposta) ou meta (webhook).';
COMMENT ON COLUMN sales_agent.fatos_conversa.wamid IS 'Código da mensagem do WhatsApp que gerou o fato. O texto não é copiado: o CRM o guarda pelo mesmo código.';

COMMENT ON FUNCTION sales_agent.dia_iso(text) IS 'Nome do dia da semana para o número ISO (1 = segunda ... 7 = domingo). Usada para conferir o dia citado pela cliente com a data.';
COMMENT ON FUNCTION sales_agent.registrar_fatos_mensagem(text, text, jsonb, jsonb, jsonb, timestamp with time zone) IS 'Grava o que o classificador achou na mensagem da cliente ("nada" não é gravado), inclusive o nome informado (feminino, masculino ou ambos). Horário pedido: confere o dia da semana com a data e a agenda_horarios; só vira fato se estiver livre. Origem do anúncio: guarda os identificadores do referral da Meta.';
COMMENT ON FUNCTION sales_agent.situacao_da_conversa(text, jsonb, timestamp with time zone) IS 'Calcula a etapa (fora_do_perfil, agendada, pago_sem_consulta, aguardando_pagamento, fechamento, qualificacao, oferta, chegada — nesta ordem, a primeira que valer) e as linhas de fatos da SITUACAO_DA_CLIENTE, que só informam fatos. Um "vou pensar" ou uma objeção mais recente que a última decisão ou que o horário escolhido tira a cliente do Fechamento até ela decidir de novo. Devolve também valores_informados (o valor atual da consulta já foi informado nesta conversa), lido pela trava da cobrança. Devolve ainda perfil_a_confirmar: a terapeuta atende um gênero só (business_config.genero_atendido), o último nome de quem vai à consulta é do outro gênero ou serve para os dois e a conversa não confirmou que a consulta é para alguém no perfil (também lido pela trava da cobrança), e perfil_caso: "dois" quando o nome serve para os dois, "fora" quando é do gênero não atendido, pela caso_do_nome (lido pela montagem do prompt). Na etapa fora_do_perfil, uma linha informa que a conversa confirmou o perfil não atendido. Ignora fatos anteriores ao último sinal usado ou mais velhos que validade_fatos_dias. Não grava nada.';
COMMENT ON FUNCTION sales_agent.fatos_e_etapa(text, text, jsonb, jsonb, jsonb, timestamp with time zone) IS 'Chamada única do n8n antes da Giulia responder: registrar_fatos_mensagem + situacao_da_conversa, mais a linha do horário pedido que não está livre ou cujo dia da semana não bate com a data (com a data desse dia da semana mais próxima da data dita), e a linha do período ou dia pedido. As linhas só informam fatos. Devolve horarios_pedidos (texto e sugestoes) quando há horários livres nesse recorte: no n8n, eles substituem as sugestões gerais. Devolve também perfil_whatsapp_fora: na primeira resposta, numa etapa da venda (chegada, qualificação, oferta ou fechamento), o nome do perfil do WhatsApp (classificador) é do gênero que a terapeuta não atende, pela caso_do_nome, o perfil não está a confirmar pelo nome informado e a mensagem não diz se a consulta é para alguém no perfil (lido pela montagem do prompt). Não grava o nome do perfil.';
COMMENT ON FUNCTION sales_agent.registrar_fatos_resposta(text, text, text, jsonb, text, timestamp with time zone) IS 'Grava valores_informados e horarios_oferecidos a partir da resposta enviada da Giulia. Só nas etapas antes do pagamento. Chamada depois de o envio dar certo.';
COMMENT ON FUNCTION sales_agent.periodos_do_dia() IS 'Períodos do dia (manha, tarde, noite) com início e fim, num lugar só. Usada pela agenda_horarios e pela fatos_e_etapa.';
COMMENT ON FUNCTION sales_agent.proxima_data(text, date) IS 'Data escrita como DD/MM (com ou sem ano): a próxima com esse dia e mês, a partir de hoje. NULL se inválida. Usada pela registrar_fatos_mensagem e pela fatos_e_etapa.';
COMMENT ON FUNCTION sales_agent.fmt_motivo(text) IS 'Motivo de um horário não estar disponível (antecedencia, fora_do_prazo, fora_do_expediente, sem_vaga, ocupado), por extenso, para o prompt.';
COMMENT ON FUNCTION sales_agent.fmt_sugestoes(jsonb) IS 'Sugestões de horário (fmt) uma por linha, na ordem em que vieram, para HORARIOS_DISPONIVEIS. NULL se a lista estiver vazia. Usada pelo nó Calcular Horarios e pela fatos_e_etapa.';
COMMENT ON COLUMN sales_agent.business_config.genero_atendido IS 'Gênero que a terapeuta atende: mulheres, homens ou todos. Com mulheres ou homens, o sistema confere o nome de quem vai à consulta: nome do outro gênero ou que serve para os dois deixa o perfil a confirmar, e a cobrança só sai depois da confirmação. Com todos (padrão), não há conferência pelo nome. O texto do perfil que a Giulia diz fica na base de conhecimento (perfil_atendido): ao mudar um, conferir o outro.';
COMMENT ON FUNCTION sales_agent.caso_do_nome(text, text) IS 'Caso de um nome contra o gênero atendido pela terapeuta (business_config.genero_atendido): "fora" quando o nome é do gênero não atendido, "dois" quando serve para os dois, NULL nos outros casos. Usada pela situacao_da_conversa (nome informado) e pela fatos_e_etapa (nome do perfil do WhatsApp).';


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

-- Formatação do prazo do PIX (3.15.1): só a Giulia executa
REVOKE ALL ON FUNCTION sales_agent.fmt_data_hora(timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.fmt_data_hora(timestamp with time zone) TO sales_agent_api;

-- Mudanças de situação da cobrança (3.15.2): só a Giulia executa
REVOKE ALL ON FUNCTION sales_agent.registrar_pagamento(text, timestamp with time zone, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.registrar_pagamento(text, timestamp with time zone, text, text) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.marcar_expirada(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.marcar_expirada(text) TO sales_agent_api;

-- Regras de horário da agenda (3.15.3): só a Giulia executa
REVOKE ALL ON FUNCTION sales_agent.faixas_de_inicio(date, jsonb, integer, timestamp with time zone[], timestamp with time zone[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.faixas_de_inicio(date, jsonb, integer, timestamp with time zone[], timestamp with time zone[]) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.agenda_horarios(jsonb, text, timestamp with time zone, timestamp with time zone, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.agenda_horarios(jsonb, text, timestamp with time zone, timestamp with time zone, jsonb) TO sales_agent_api;

-- Fatos da conversa (3.18): a Giulia lê e acrescenta; só ela executa as funções
-- A Giulia só lê e acrescenta: o registro não é alterado nem apagado por ela.
REVOKE ALL ON sales_agent.fatos_conversa FROM anon, authenticated;
REVOKE ALL ON SEQUENCE sales_agent.fatos_conversa_id_seq FROM anon, authenticated;
GRANT SELECT, INSERT ON sales_agent.fatos_conversa TO sales_agent_api;
GRANT USAGE, SELECT ON SEQUENCE sales_agent.fatos_conversa_id_seq TO sales_agent_api;

REVOKE ALL ON FUNCTION sales_agent.dia_iso(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.dia_iso(text) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.registrar_fatos_mensagem(text, text, jsonb, jsonb, jsonb, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.registrar_fatos_mensagem(text, text, jsonb, jsonb, jsonb, timestamp with time zone) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.situacao_da_conversa(text, jsonb, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.situacao_da_conversa(text, jsonb, timestamp with time zone) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.fatos_e_etapa(text, text, jsonb, jsonb, jsonb, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.fatos_e_etapa(text, text, jsonb, jsonb, jsonb, timestamp with time zone) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.registrar_fatos_resposta(text, text, text, jsonb, text, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.registrar_fatos_resposta(text, text, text, jsonb, text, timestamp with time zone) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.periodos_do_dia() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.periodos_do_dia() TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.proxima_data(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.proxima_data(text, date) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.fmt_motivo(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.fmt_motivo(text) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.fmt_sugestoes(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.fmt_sugestoes(jsonb) TO sales_agent_api;
REVOKE ALL ON FUNCTION sales_agent.caso_do_nome(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION sales_agent.caso_do_nome(text, text) TO sales_agent_api;

-- Base de conhecimento: o n8n lê pela API REST com a chave service_role.
-- anon e authenticated não recebem grant nesta tabela, de propósito.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.knowledge_base_text TO service_role;

-- A função devolve os dados de negócio de qualquer organização e roda com
-- privilégio de dono (SECURITY DEFINER): nunca pode ficar aberta para as
-- chaves públicas (anon/authenticated).
REVOKE ALL ON FUNCTION public.get_knowledge_base(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_knowledge_base(uuid, text) TO service_role;
