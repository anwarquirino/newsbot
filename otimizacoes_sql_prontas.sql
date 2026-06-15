-- ============================================================
--  NEWSBOT — Otimizações SQL Prontas para Executar
--  Executar: mysql -u root -p newsbot < otimizacoes_sql_prontas.sql
-- ============================================================

USE newsbot;

-- ══════════════════════════════════════════════════════════
--  0. ADICIONAR COLUNAS NOVAS (deve vir ANTES dos índices/views)
-- ══════════════════════════════════════════════════════════
--  Estas colunas não existem no schema v1 (newsbot_schema.sql), mas
--  são referenciadas pelos índices, views e queries abaixo. Precisam
--  ser criadas primeiro, senão os ALTER/CREATE seguintes falham.

ALTER TABLE noticias_publicadas
  ADD COLUMN source_topic   VARCHAR(255)   DEFAULT NULL COMMENT 'Para Google Trends',
  ADD COLUMN processed_at   DATETIME       DEFAULT NULL,
  ADD COLUMN custo_total_usd DECIMAL(8,4)  DEFAULT 0    COMMENT 'Custo OpenAI+DALL-E do artigo',
  ADD COLUMN qualidade_score TINYINT       DEFAULT NULL COMMENT 'Score 0-100 de qualidade';


-- ══════════════════════════════════════════════════════════
--  1. CRIAR ÍNDICES PARA PERFORMANCE
-- ══════════════════════════════════════════════════════════

-- Índice composto para buscar próximo item da fila
ALTER TABLE noticias_publicadas 
ADD INDEX idx_fila_order (status, data_coleta, id);

-- Índice para verificar duplicados rapidamente
ALTER TABLE noticias_publicadas 
ADD INDEX idx_hash_status (hash, status);

-- Índice para queries de publicação
ALTER TABLE noticias_publicadas 
ADD INDEX idx_publicacoes (data_publicacao, status);

-- Índice para post_id WordPress
ALTER TABLE noticias_publicadas 
ADD INDEX idx_post_wp (post_id_wp);

-- Índice para fonte (RSS feed)
ALTER TABLE noticias_publicadas 
ADD INDEX idx_fonte (fonte);

-- Índice para analytics (source_topic para Trends)
ALTER TABLE noticias_publicadas 
ADD INDEX idx_source_topic (source_topic);

-- Atualizar estatísticas para otimizador
ANALYZE TABLE noticias_publicadas;

-- Verificar índices criados
SHOW INDEX FROM noticias_publicadas;


-- ══════════════════════════════════════════════════════════
--  2. ÍNDICE COMPOSTO PARA TENDÊNCIAS (colunas criadas na Seção 0)
-- ══════════════════════════════════════════════════════════

-- Criar índice para deduplicação de trending topics por janela de tempo
ALTER TABLE noticias_publicadas
ADD INDEX idx_source_topic_time (source_topic, data_coleta);


-- ══════════════════════════════════════════════════════════
--  3. CRIAR NOVA TABELA: RSS Feeds Customizáveis
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS rss_feeds (
  id INT AUTO_INCREMENT PRIMARY KEY,
  
  nome VARCHAR(100) NOT NULL UNIQUE,
  url TEXT NOT NULL,
  categoria VARCHAR(50) DEFAULT 'Geral',
  descricao TEXT,
  
  frequencia_minutos INT DEFAULT 15,
  ativo BOOLEAN DEFAULT true,
  peso_prioridade INT DEFAULT 5,
  
  criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,
  atualizado_em DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ultima_coleta DATETIME DEFAULT NULL,
  
  total_coletadas INT DEFAULT 0,
  total_publicadas INT DEFAULT 0,
  taxa_sucesso_pct DECIMAL(5,2) DEFAULT 0,
  
  INDEX idx_ativo (ativo),
  INDEX idx_categoria (categoria),
  INDEX idx_prioridade (peso_prioridade)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
COMMENT='Fontes RSS configuráveis para captura de notícias';

-- Inserir feeds padrão
INSERT INTO rss_feeds (nome, url, categoria, peso_prioridade) VALUES
  ('Google News BR', 'https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGRqTVhZU0FtcHZHZ0pRVWlnQVAB?hl=pt-BR&gl=BR', 'Geral', 4),
  ('TechCrunch', 'https://techcrunch.com/feed/', 'Tecnologia', 3),
  ('G1 Tecnologia', 'https://g1.globo.com/rss/g1/tecnologia/', 'Tecnologia', 4),
  ('Canaltech', 'https://canaltech.com.br/rss/', 'Tecnologia', 5),
  ('Google Trends', 'https://trends.google.com/trends/trendingsearches/daily/rss?geo=BR', 'Trending', 2);


-- ══════════════════════════════════════════════════════════
--  4. CRIAR NOVA TABELA: Log de Execuções
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS fluxo_execucoes (
  id INT AUTO_INCREMENT PRIMARY KEY,
  
  fluxo_id VARCHAR(100) NOT NULL,
  fluxo_nome VARCHAR(100) NOT NULL,
  
  inicio DATETIME DEFAULT CURRENT_TIMESTAMP,
  fim DATETIME DEFAULT NULL,
  tempo_ms INT DEFAULT 0,
  
  status ENUM('iniciado','completado','erro','timeout') DEFAULT 'iniciado',
  items_processados INT DEFAULT 0,
  items_sucesso INT DEFAULT 0,
  items_erro INT DEFAULT 0,
  
  custo_usd DECIMAL(8,4) DEFAULT 0,
  custo_openai DECIMAL(8,4) DEFAULT 0,
  custo_dallee DECIMAL(8,4) DEFAULT 0,
  
  mensagem_erro TEXT,
  stack_trace TEXT,
  
  INDEX idx_fluxo_tempo (fluxo_id, inicio),
  INDEX idx_status (status),
  INDEX idx_data (inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
COMMENT='Log detalhado de execuções de fluxos n8n';


-- ══════════════════════════════════════════════════════════
--  5. CRIAR NOVA TABELA: Analytics Diária
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS analytics_daily (
  data DATE PRIMARY KEY,
  
  total_capturadas INT DEFAULT 0,
  total_publicadas INT DEFAULT 0,
  total_erros INT DEFAULT 0,
  total_rejeitadas INT DEFAULT 0,
  
  tempo_medio_processamento_ms INT DEFAULT 0,
  
  score_qualidade_media INT DEFAULT 0,
  taxa_sucesso_pct DECIMAL(5,2) DEFAULT 0,
  
  custo_openai_total DECIMAL(8,4) DEFAULT 0,
  custo_dallee_total DECIMAL(8,4) DEFAULT 0,
  custo_total_dia DECIMAL(8,4) DEFAULT 0,
  
  total_views INT DEFAULT 0,
  total_shares INT DEFAULT 0,
  total_comments INT DEFAULT 0,
  
  INDEX idx_data (data)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
COMMENT='Resumo de analytics diária para relatórios';


-- ══════════════════════════════════════════════════════════
--  6. CRIAR VIEWS ÚTEIS
-- ══════════════════════════════════════════════════════════

-- Dashboard em tempo real
CREATE OR REPLACE VIEW vw_dashboard_realtime AS
SELECT 
  'Fila Pendente' as metrica,
  COUNT(*) as valor
FROM noticias_publicadas
WHERE status = 'fila'

UNION ALL

SELECT 'Processando', COUNT(*)
FROM noticias_publicadas
WHERE status = 'processando'

UNION ALL

SELECT 'Hoje Publicadas', COUNT(*)
FROM noticias_publicadas
WHERE DATE(data_publicacao) = CURDATE()

UNION ALL

SELECT 'Custo Hoje (USD)', ROUND(SUM(CAST(custo_total_usd AS DECIMAL(8,4))), 2)
FROM noticias_publicadas
WHERE DATE(data_publicacao) = CURDATE();


-- ══════════════════════════════════════════════════════════
--  7. QUERIES ÚTEIS — COPIAR E USAR
-- ══════════════════════════════════════════════════════════

-- Query: Próximo item da fila (otimizada)
-- SELECT * FROM noticias_publicadas 
-- WHERE status = 'fila' AND tentativas < 3
-- ORDER BY data_coleta ASC LIMIT 1;

-- Query: Dashboard 7 dias
-- SELECT 
--   DATE(n.data_coleta) as data,
--   COUNT(*) as total_capturadas,
--   SUM(CASE WHEN n.status = 'publicado' THEN 1 ELSE 0 END) as publicadas,
--   ROUND(AVG(CAST(n.custo_total_usd AS DECIMAL(8,4))), 2) as custo_medio_usd,
--   ROUND(AVG(n.qualidade_score)) as qualidade_media
-- FROM noticias_publicadas n
-- WHERE n.data_coleta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
-- GROUP BY DATE(n.data_coleta)
-- ORDER BY data DESC;

-- Query: Verificar trending duplicado (últimas 6h)
-- SELECT COUNT(*) as existe
-- FROM noticias_publicadas
-- WHERE source_topic = 'IA' AND data_coleta > NOW() - INTERVAL 6 HOUR;

-- Query: Performance por fonte
-- SELECT 
--   fonte,
--   COUNT(*) as total,
--   ROUND(100 * SUM(CASE WHEN status = 'publicado' THEN 1 ELSE 0 END) / COUNT(*)) as taxa_sucesso_pct,
--   ROUND(AVG(CAST(custo_total_usd AS DECIMAL(8,4))), 4) as custo_medio_usd
-- FROM noticias_publicadas
-- WHERE data_publicacao >= DATE_SUB(NOW(), INTERVAL 30 DAY)
-- GROUP BY fonte
-- ORDER BY taxa_sucesso_pct DESC;


-- ══════════════════════════════════════════════════════════
--  8. RESETAR ITENS TRAVADOS (Procedure)
-- ══════════════════════════════════════════════════════════

DELIMITER //

CREATE PROCEDURE IF NOT EXISTS ResetarItensTravados()
BEGIN
  DECLARE item_count INT;
  
  -- Encontrar itens em "processando" por mais de 15 minutos
  SELECT COUNT(*) INTO item_count
  FROM noticias_publicadas
  WHERE status = 'processando'
    AND data_coleta < DATE_SUB(NOW(), INTERVAL 15 MINUTE);
  
  IF item_count > 0 THEN
    -- Retornar à fila, incrementar tentativas
    UPDATE noticias_publicadas
    SET 
      status = 'fila',
      tentativas = tentativas + 1
    WHERE status = 'processando'
      AND data_coleta < DATE_SUB(NOW(), INTERVAL 15 MINUTE);
  END IF;
END//

DELIMITER ;

-- Usar cron para chamar a cada 30 min:
-- 0 */0.5 * * * * mysql -u newsbot -p newsbot -e "CALL ResetarItensTravados();"


-- ══════════════════════════════════════════════════════════
--  9. VERIFICAÇÃO FINAL
-- ══════════════════════════════════════════════════════════

SELECT 'Índices criados:' as status;
SHOW INDEX FROM noticias_publicadas WHERE Key_name LIKE 'idx_%';

SELECT '✅ Optimization Complete!' as resultado;
