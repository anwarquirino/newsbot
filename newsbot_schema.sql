-- ============================================================
--  NEWSBOT — Schema do banco de dados
--  Execute: mysql -u root -p newsbot < newsbot_schema.sql
-- ============================================================

CREATE DATABASE IF NOT EXISTS newsbot
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE newsbot;

-- Tabela principal de controle de notícias
CREATE TABLE IF NOT EXISTS noticias_publicadas (
  id               INT           AUTO_INCREMENT PRIMARY KEY,
  titulo           VARCHAR(500)  NOT NULL,
  url_original     TEXT          NOT NULL,
  hash             CHAR(64)      NOT NULL UNIQUE COMMENT 'SHA-256 de titulo+url',
  status           ENUM('fila','processando','publicado','erro') NOT NULL DEFAULT 'fila',
  post_id_wp       INT           DEFAULT NULL  COMMENT 'ID do post no WordPress',
  fonte            VARCHAR(100)  DEFAULT NULL  COMMENT 'Nome do feed RSS de origem',
  data_coleta      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  data_publicacao  DATETIME      DEFAULT NULL,
  tentativas       TINYINT       NOT NULL DEFAULT 0,
  erro_msg         TEXT          DEFAULT NULL,

  INDEX idx_hash      (hash),
  INDEX idx_status    (status),
  INDEX idx_coleta    (data_coleta),
  INDEX idx_publicacao(data_publicacao)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Tabela de log de execuções (opcional, para monitoramento)
CREATE TABLE IF NOT EXISTS execucoes_log (
  id           INT       AUTO_INCREMENT PRIMARY KEY,
  fluxo        VARCHAR(100),
  status       ENUM('ok','erro'),
  mensagem     TEXT,
  criado_em    DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_fluxo (fluxo),
  INDEX idx_criado(criado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── Queries úteis ────────────────────────────────────────────

-- Próximo item da fila
-- SELECT * FROM noticias_publicadas WHERE status = 'fila' ORDER BY data_coleta ASC LIMIT 1;

-- Resumo de status
-- SELECT status, COUNT(*) AS total FROM noticias_publicadas GROUP BY status;

-- Últimos publicados
-- SELECT titulo, data_publicacao FROM noticias_publicadas WHERE status = 'publicado' ORDER BY data_publicacao DESC LIMIT 20;

-- Resetar itens travados em 'processando' por mais de 10 minutos
-- UPDATE noticias_publicadas SET status = 'fila' WHERE status = 'processando' AND data_coleta < NOW() - INTERVAL 10 MINUTE;
