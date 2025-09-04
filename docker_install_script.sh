#!/bin/bash

# Script de instalação do Docker Engine 20.10+ e Docker Compose 2.0+
# Para Debian 12 (Bookworm)
# Execute com: bash install-docker.sh

echo "🐳 Iniciando instalação do Docker Engine e Docker Compose..."

# 1. Atualizar o sistema
echo "📦 Atualizando sistema..."
sudo apt update
sudo apt upgrade -y

# 2. Instalar dependências necessárias
echo "📋 Instalando dependências..."
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 3. Adicionar a chave GPG oficial do Docker
echo "🔑 Adicionando chave GPG do Docker..."
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 4. Adicionar o repositório do Docker
echo "📂 Adicionando repositório do Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Instalar o Docker Engine
echo "⬇️ Instalando Docker Engine..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. Iniciar e habilitar o Docker
echo "🚀 Iniciando serviços do Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# 7. Adicionar usuário ao grupo docker
echo "👤 Adicionando usuário ao grupo docker..."
sudo usermod -aG docker $USER

# 8. Verificar instalação
echo "✅ Verificando instalação..."
echo "Docker version:"
docker --version

echo "Docker Compose version:"
docker compose version

echo "Status do serviço Docker:"
sudo systemctl is-active docker

# 9. Teste do Docker
echo "🧪 Testando Docker..."
sudo docker run hello-world

echo ""
echo "🎉 Instalação concluída com sucesso!"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   - Faça logout e login novamente para usar docker sem sudo"
echo "   - Ou reinicie o sistema para aplicar as permissões"
echo ""
echo "🔧 Comandos úteis:"
echo "   docker ps                    # Ver containers rodando"
echo "   docker images                # Ver imagens baixadas"
echo "   docker compose up -d         # Subir serviços em background"
echo "   sudo systemctl status docker # Status do serviço"
echo ""