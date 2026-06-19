# NewsBot — Portal de Notícias de Tecnologia Automatizado

Sistema que **captura notícias e tendências, reescreve com IA e prepara artigos prontos para publicação** — totalmente automatizado via [n8n](https://n8n.io), com **custo de operação R$ 0** usando a IA gratuita da [Groq](https://groq.com).

> Status atual: capturando notícias (RSS), monitorando tendências (Google Trends) e reescrevendo artigos com IA. Publicação no WordPress e geração de imagens estão no roadmap.

---

## Arquitetura

```
                ┌─────────────────────────────────────────────┐
                │                  n8n                         │
                │                                              │
  RSS Feeds ───►│  Fluxo 1: Captura RSS ──────┐                │
                │                              ▼                │
  Google ──────►│  Fluxo 3: Tendências ───► [ MySQL: fila ]    │
  Trends        │                              │                │
                │                              ▼                │
                │  Fluxo 2: Reescrita IA (Groq) ─► [ pronto ]   │
                └─────────────────────────────────────────────┘
```

| Componente | Papel |
|---|---|
| **n8n** | Orquestração dos fluxos (cron, HTTP, banco) |
| **MySQL** | Fila de notícias, deduplicação, artigos prontos, analytics |
| **Groq** (llama-3.3-70b) | Reescrita de artigos e geração de pautas — **gratuito** |

---

## Os fluxos

### Fluxo 1 — Captura RSS (`fluxo1_captura_rss.json`)
A cada 15 min, lê 4 feeds RSS (Google News, TechCrunch, G1 Tecnologia, Canaltech), gera um hash SHA-256 de cada notícia e insere na fila. Duplicatas são ignoradas automaticamente via `INSERT IGNORE` + índice `UNIQUE(hash)`.

### Fluxo 2 — Reescrita com IA (`fluxo2_publicacao.json`)
A cada 5 min, pega o próximo item `fila`, marca como `processando`, envia para a Groq reescrever (título SEO + corpo HTML 500-800 palavras + resumo + tags + categoria) e salva o artigo com status `pronto`.

### Fluxo 3 — Monitor de Tendências (`fluxo3_tendencias.json`)
A cada hora, lê o Google Trends BR, pega os 5 principais, e usa a Groq para gerar pautas jornalísticas relevantes, inserindo-as na fila com `fonte = 'Google Trends'`.

---

## Banco de dados

Tabela principal `noticias_publicadas` (fila + artigos). Schema base em [`newsbot_schema.sql`](newsbot_schema.sql); índices, tabelas de apoio (`rss_feeds`, `fluxo_execucoes`, `analytics_daily`), a view `vw_dashboard_realtime` e a procedure `ResetarItensTravados()` em [`otimizacoes_sql_prontas.sql`](otimizacoes_sql_prontas.sql).

Status de uma notícia: `fila` → `processando` → `pronto` (→ `publicado` quando houver WordPress) ou `erro`.

Todas as queries do n8n usam **prepared statements** (`$1, $2...` + `queryReplacement`) — sem risco de SQL injection.

---

## Setup (Windows)

### Pré-requisitos
- [MySQL](https://dev.mysql.com/downloads/) 8+ (testado no 9.7)
- [Node.js](https://nodejs.org) 20+ (para o n8n)
- Uma API key gratuita da [Groq](https://console.groq.com/keys)

### 1. Banco de dados
```powershell
# Criar o banco e o schema
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS newsbot CHARACTER SET utf8mb4;"
mysql -u root -p newsbot < newsbot_schema.sql

# Aplicar índices, tabelas de apoio, views e procedures
mysql -u root -p newsbot < otimizacoes_sql_prontas.sql
```
> No Windows, se o `mysql` não estiver no PATH, use o caminho completo, ex.:
> `& "C:\Program Files\MySQL\MySQL Server 9.7\bin\mysql.exe" ...`

### 2. n8n
```powershell
npx n8n
# abre em http://localhost:5678 — crie a conta de dono no primeiro acesso
```

### 3. Importar os fluxos
No n8n: **Create Workflow → menu ⋯ → Import from File**, e importe os três `fluxo*.json`.

### 4. Credenciais (em cada fluxo)
| Credencial | Tipo n8n | Configuração |
|---|---|---|
| **MySQL** | MySQL | Host `localhost`, Port `3306`, DB `newsbot`, User/Senha do seu MySQL |
| **Groq** | OpenAI | **API Key** = sua chave Groq · **Base URL** = `https://api.groq.com/openai/v1` |

> A Groq é compatível com a API da OpenAI, por isso usamos a credencial "OpenAI" apontando a Base URL para o Groq.

### 5. Executar
Rode cada fluxo manualmente (**Execute Workflow**) para testar, ou ative o toggle **Active** para rodar no agendamento. O n8n precisa permanecer em execução.

---

## Estrutura do projeto

```
.
├── README.md                    ← este arquivo
├── newsbot_schema.sql           ← schema base do banco
├── otimizacoes_sql_prontas.sql  ← índices, tabelas de apoio, view, procedure
├── fluxo1_captura_rss.json      ← n8n: captura RSS (15 min)
├── fluxo2_publicacao.json       ← n8n: reescrita com IA (5 min)
└── fluxo3_tendencias.json       ← n8n: tendências Google Trends (1 h)
```

---

## Custo

| Item | Custo |
|---|---|
| n8n (self-hosted) | Grátis |
| MySQL | Grátis |
| IA (Groq free tier) | **Grátis** |
| **Total** | **R$ 0** |

---

## Roadmap

- [ ] Publicação automática no WordPress (status `pronto` → `publicado`)
- [ ] Geração/seleção de imagem destacada (ex.: Pexels/Unsplash grátis)
- [ ] Deduplicação de tendências (janela de 6h via `source_topic`)
- [ ] Alertas no Telegram em caso de erro
- [ ] Dashboard de analytics (Grafana / `vw_dashboard_realtime`)

---

## Segurança

- **Nunca** faça commit de chaves de API. A chave da Groq fica fora do versionamento (veja `.gitignore`).
- As credenciais ficam armazenadas no banco interno do n8n (`~/.n8n`), não no repositório.
