#!/bin/bash

# Script para criar a estrutura completa do projeto netflow-elk-docker
# Execute com: bash create-netflow-structure.sh

echo "📁 Criando estrutura do projeto netflow-elk-docker..."

# Criar diretório principal
mkdir -p netflow-elk-docker
cd netflow-elk-docker

echo "🏗️  Criando estrutura de diretórios..."

# Criar todos os diretórios
mkdir -p configs/elasticsearch
mkdir -p configs/kibana
mkdir -p configs/filebeat/modules.d
mkdir -p scripts
mkdir -p data/elasticsearch
mkdir -p data/kibana
mkdir -p data/filebeat

echo "📄 Criando arquivos de configuração..."

# Criar arquivo docker-compose.yml (vazio)
touch docker-compose.yml

# Criar arquivo .env (vazio)
touch .env

# Criar arquivos de configuração do Elasticsearch
touch configs/elasticsearch/elasticsearch.yml

# Criar arquivos de configuração do Kibana
touch configs/kibana/kibana.yml

# Criar arquivos de configuração do Filebeat
touch configs/filebeat/filebeat.yml
touch configs/filebeat/modules.d/netflow.yml

# Criar scripts
touch scripts/cleanup-data.sh
touch scripts/debian-optimization.sh
touch scripts/setup.sh

# Criar README
touch README.md

echo "🔧 Configurando permissões..."

# Dar permissão de execução aos scripts
chmod +x scripts/cleanup-data.sh
chmod +x scripts/debian-optimization.sh
chmod +x scripts/setup.sh

# Configurar permissões para os diretórios de dados (necessário para Elasticsearch)
sudo chown -R 1000:1000 data/elasticsearch
sudo chown -R 1000:1000 data/kibana
sudo chown -R 1000:1000 data/filebeat

echo "✅ Estrutura criada com sucesso!"
echo ""
echo "📂 Estrutura do projeto:"
echo ""
echo "netflow-elk-docker/"
echo "├── docker-compose.yml"
echo "├── .env"
echo "├── configs/"
echo "│   ├── elasticsearch/"
echo "│   │   └── elasticsearch.yml"
echo "│   ├── kibana/"
echo "│   │   └── kibana.yml"
echo "│   └── filebeat/"
echo "│       ├── filebeat.yml"
echo "│       └── modules.d/"
echo "│           └── netflow.yml"
echo "├── scripts/"
echo "│   ├── cleanup-data.sh"
echo "│   ├── debian-optimization.sh"
echo "│   └── setup.sh"
echo "├── data/"
echo "│   ├── elasticsearch/"
echo "│   ├── kibana/"
echo "│   └── filebeat/"
echo "└── README.md"
echo ""
echo "🎯 Próximos passos:"
echo "   1. cd netflow-elk-docker"
echo "   2. Configurar os arquivos .env e docker-compose.yml"
echo "   3. Configurar os arquivos em configs/"
echo "   4. Executar ./scripts/setup.sh"
echo ""