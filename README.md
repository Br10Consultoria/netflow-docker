# NetFlow ELK Stack with Docker

Um stack completo Elasticsearch, Kibana e Filebeat dockerizado para captura e análise de dados NetFlow de roteadores Cisco, Huawei, Mikrotik, Juniper e outros.

## 🏗️ Arquitetura

- **Elasticsearch**: Armazenamento e indexação dos dados NetFlow
- **Kibana**: Interface web para visualização e dashboards
- **Filebeat**: Coleta e processamento de dados NetFlow UDP

## 📋 Pré-requisitos

- Docker Engine 20.10+
- Docker Compose 2.0+
- Debian 12 (recomendado)
- Mínimo 4GB RAM (8GB+ recomendado)
- 50GB+ espaço em disco

## 🚀 Instalação Rápida

1. **Clone o repositório:**
```bash
git clone <seu-repo>

cd netflow-elk-docker


netflow-elk-docker/
├── docker-compose.yml
├── .env
├── configs/
│   ├── elasticsearch/
│   │   └── elasticsearch.yml
│   ├── kibana/
│   │   └── kibana.yml
│   └── filebeat/
│       ├── filebeat.yml
│       └── modules.d/
│           └── netflow.yml
├── scripts/
│   ├── cleanup-data.sh
│   ├── debian-optimization.sh
│   └── setup.sh
├── data/
│   ├── elasticsearch/
│   ├── kibana/
│   └── filebeat/
└── README.md
