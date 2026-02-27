#!/bin/bash
#
# system management - Versão Corrigida
# Uso: ./script.sh [opções]
# Requer variáveis de ambiente ou arquivo de configuração

set -e  # Para o script em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
GRAY_LIGHT='\033[0;37m'
NC='\033[0m' # No Color

# Configurações padrão
DEPLOY_USER="deploy"
DEPLOY_HOME="/home/${DEPLOY_USER}"
POSTGRES_PASSWORD="postgres"
DEPLOY_PASSWORD=""
INSTALACAO_COMPLETA=false

# Função para imprimir banner
print_banner() {
  clear
  printf "${GREEN}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           SCRIPT DE INSTALAÇÃO - EQUIPECHAT               ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  printf "${NC}\n"
}

# Função para log de erros
log_error() {
  printf "${RED} ❌ Erro: $1${NC}\n" >&2
}

# Função para log de sucesso
log_success() {
  printf "${GREEN} ✅ $1${NC}\n"
}

# Função para log de informação
log_info() {
  printf "${YELLOW} ℹ️  $1${NC}\n"
}

# Função para validar variáveis obrigatórias
validate_variables() {
  local missing_vars=()
  
  # Lista de variáveis obrigatórias
  local required_vars=(
    "link_git"
    "instancia_add"
    "backend_port"
    "frontend_port"
    "backend_url"
    "frontend_url"
    "deploy_email"
  )
  
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      missing_vars+=("$var")
    fi
  done
  
  if [ ${#missing_vars[@]} -ne 0 ]; then
    log_error "Variáveis obrigatórias não definidas: ${missing_vars[*]}"
    exit 1
  fi
}

#######################################
# Cria usuário do sistema
#######################################
system_create_user() {
  print_banner
  log_info "Criando usuário ${DEPLOY_USER}..."
  sleep 2

  # Gera senha aleatória se não for fornecida
  if [ -z "${DEPLOY_PASSWORD}" ]; then
    DEPLOY_PASSWORD=$(openssl rand -base64 12)
    log_info "Senha gerada para usuário ${DEPLOY_USER}: ${DEPLOY_PASSWORD}"
  fi
  
  # Executa comandos como root
  sudo su - root <<EOF
  # Verifica se o usuário já existe
  if id "${DEPLOY_USER}" &>/dev/null; then
    echo "Usuário ${DEPLOY_USER} já existe, atualizando senha..."
    echo "${DEPLOY_USER}:${DEPLOY_PASSWORD}" | chpasswd
  else
    echo "Criando usuário ${DEPLOY_USER}..."
    useradd -m -p \$(openssl passwd -6 "${DEPLOY_PASSWORD}") -s /bin/bash ${DEPLOY_USER}
    usermod -aG sudo ${DEPLOY_USER}
    
    # Configura sudo sem senha para deploy (opcional)
    echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEPLOY_USER}
    chmod 440 /etc/sudoers.d/${DEPLOY_USER}
    
    echo "Usuário ${DEPLOY_USER} criado com sucesso"
    echo "Senha do usuário ${DEPLOY_USER}: ${DEPLOY_PASSWORD}" > /root/deploy_password.txt
    chmod 600 /root/deploy_password.txt
  fi
  
  # Verifica criação
  id ${DEPLOY_USER}
EOF

  if [ $? -eq 0 ]; then
    log_success "Usuário ${DEPLOY_USER} configurado com sucesso"
  else
    log_error "Falha ao configurar usuário ${DEPLOY_USER}"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Clona repositórios usando git
#######################################
system_git_clone() {
  print_banner
  log_info "Fazendo download do código Equipechat..."
  sleep 2

  # Verifica se o link do git foi fornecido
  if [ -z "${link_git}" ]; then
    log_error "Link do git não fornecido"
    exit 1
  fi

  # Executa como usuário deploy
  sudo su - ${DEPLOY_USER} <<EOF
  # Cria diretório se não existir
  mkdir -p /home/${DEPLOY_USER}/${instancia_add}
  
  # Clona ou atualiza repositório
  if [ -d "/home/${DEPLOY_USER}/${instancia_add}/.git" ]; then
    echo "Repositório já existe, atualizando..."
    cd /home/${DEPLOY_USER}/${instancia_add}
    git pull
  else
    echo "Clonando repositório..."
    git clone ${link_git} /home/${DEPLOY_USER}/${instancia_add}/
  fi
  
  # Ajusta permissões
  chmod -R 755 /home/${DEPLOY_USER}/${instancia_add}
EOF

  if [ $? -eq 0 ]; then
    log_success "Código clonado com sucesso"
  else
    log_error "Falha ao clonar repositório"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Atualiza sistema
#######################################
system_update() {
  print_banner
  log_info "Atualizando sistema..."
  sleep 2

  sudo su - root <<EOF
  apt update
  apt upgrade -y
  apt autoremove -y
  
  # Instala dependências básicas
  apt install -y \
    curl \
    wget \
    git \
    unzip \
    zip \
    htop \
    net-tools \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release
EOF

  log_success "Sistema atualizado"
  sleep 2
}

#######################################
# Instala Node.js
#######################################
system_node_install() {
  print_banner
  log_info "Instalando Node.js..."
  sleep 2

  sudo su - root <<EOF
  # Remove instalações antigas
  apt remove -y nodejs npm || true
  apt autoremove -y
  
  # Instala Node.js 20.x
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
  
  # Instala npm e atualiza
  npm install -g npm@latest
  
  # Verifica instalação
  node --version
  npm --version
EOF

  if [ $? -eq 0 ]; then
    log_success "Node.js instalado com sucesso"
  else
    log_error "Falha ao instalar Node.js"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Instala PostgreSQL
#######################################
system_postgres_install() {
  print_banner
  log_info "Instalando PostgreSQL..."
  sleep 2

  sudo su - root <<EOF
  # Instala PostgreSQL
  apt install -y postgresql postgresql-contrib
  
  # Inicia e habilita serviço
  systemctl start postgresql
  systemctl enable postgresql
  
  # Configura PostgreSQL
  sudo -u postgres psql <<PSQL
    ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';
    CREATE DATABASE ${instancia_add} WITH OWNER postgres;
    \du
    \l
PSQL

  # Configura PostgreSQL para aceitar conexões
  echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/*/main/pg_hba.conf
  systemctl restart postgresql
EOF

  if [ $? -eq 0 ]; then
    log_success "PostgreSQL instalado com sucesso"
  else
    log_error "Falha ao instalar PostgreSQL"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Instala Docker
#######################################
system_docker_install() {
  print_banner
  log_info "Instalando Docker..."
  sleep 2

  sudo su - root <<EOF
  # Remove versões antigas
  apt remove -y docker docker-engine docker.io containerd runc || true
  
  # Instala Docker
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  
  # Adiciona usuário ao grupo docker
  usermod -aG docker ${DEPLOY_USER}
  
  # Instala Docker Compose
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  
  # Verifica instalação
  docker --version
  docker-compose --version
EOF

  if [ $? -eq 0 ]; then
    log_success "Docker instalado com sucesso"
  else
    log_error "Falha ao instalar Docker"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Instala PM2
#######################################
system_pm2_install() {
  print_banner
  log_info "Instalando PM2..."
  sleep 2

  sudo su - root <<EOF
  npm install -g pm2
  
  # Configura PM2 para iniciar com boot
  pm2 startup systemd -u ${DEPLOY_USER} --hp /home/${DEPLOY_USER}
  
  # Configura permissões
  su - ${DEPLOY_USER} -c "pm2 save"
EOF

  if [ $? -eq 0 ]; then
    log_success "PM2 instalado com sucesso"
  else
    log_error "Falha ao instalar PM2"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Instala dependências do Puppeteer
#######################################
system_puppeteer_dependencies() {
  print_banner
  log_info "Instalando dependências do Puppeteer..."
  sleep 2

  sudo su - root <<EOF
  apt install -y \
    libxshmfence-dev \
    libgbm-dev \
    wget \
    unzip \
    fontconfig \
    locales \
    gconf-service \
    libasound2 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgcc1 \
    libgconf-2-4 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    ca-certificates \
    fonts-liberation \
    libappindicator1 \
    libnss3 \
    lsb-release \
    xdg-utils \
    libgbm1 \
    libxkbcommon0
EOF

  log_success "Dependências do Puppeteer instaladas"
  sleep 2
}

#######################################
# Instala Nginx
#######################################
system_nginx_install() {
  print_banner
  log_info "Instalando Nginx..."
  sleep 2

  sudo su - root <<EOF
  apt install -y nginx
  
  # Remove configuração padrão
  rm -f /etc/nginx/sites-enabled/default
  
  # Configura limites
  echo "client_max_body_size 100M;" > /etc/nginx/conf.d/equipechat.conf
  
  # Testa configuração
  nginx -t
  
  # Reinicia serviço
  systemctl restart nginx
  systemctl enable nginx
EOF

  if [ $? -eq 0 ]; then
    log_success "Nginx instalado com sucesso"
  else
    log_error "Falha ao instalar Nginx"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Instala Certbot
#######################################
system_certbot_install() {
  print_banner
  log_info "Instalando Certbot..."
  sleep 2

  sudo su - root <<EOF
  apt remove -y certbot || true
  
  snap install core
  snap refresh core
  snap install --classic certbot
  ln -sf /snap/bin/certbot /usr/bin/certbot
  
  certbot --version
EOF

  if [ $? -eq 0 ]; then
    log_success "Certbot instalado com sucesso"
  else
    log_error "Falha ao instalar Certbot"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Configura certificado SSL
#######################################
system_certbot_setup() {
  print_banner
  log_info "Configurando certificado SSL..."
  sleep 2

  backend_domain=$(echo "${backend_url}" | sed 's|https://||')
  frontend_domain=$(echo "${frontend_url}" | sed 's|https://||')

  sudo su - root <<EOF
  certbot --nginx \
          --non-interactive \
          --agree-tos \
          --email ${deploy_email} \
          --domains ${backend_domain},${frontend_domain}
  
  systemctl reload nginx
EOF

  if [ $? -eq 0 ]; then
    log_success "Certificado SSL configurado com sucesso"
  else
    log_error "Falha ao configurar certificado SSL"
    exit 1
  fi
  
  sleep 2
}

#######################################
# Configura timezone
#######################################
system_timezone_config() {
  print_banner
  log_info "Configurando timezone..."
  sleep 2

  sudo su - root <<EOF
  timedatectl set-timezone America/Sao_Paulo
  timedatectl
EOF

  log_success "Timezone configurado para America/Sao_Paulo"
  sleep 2
}

#######################################
# Instala tudo
#######################################
install_all() {
  log_info "Iniciando instalação completa..."
  
  system_update
  system_create_user
  system_timezone_config
  system_node_install
  system_postgres_install
  system_docker_install
  system_pm2_install
  system_puppeteer_dependencies
  system_nginx_install
  system_certbot_install
  system_git_clone
  system_certbot_setup
  
  log_success "Instalação completa finalizada com sucesso!"
  log_info "Senha do usuário deploy: ${DEPLOY_PASSWORD}"
  log_info "Arquivo com senha salvo em: /root/deploy_password.txt"
}

#######################################
# Função de deploy
#######################################
deploy() {
  print_banner
  log_info "Iniciando processo de deploy..."
  
  validate_variables
  install_all
  
  print_banner
  printf "${GREEN}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                DEPLOY FINALIZADO COM SUCESSO              ║"
  echo "╠════════════════════════════════════════════════════════════╣"
  echo "║ Frontend: ${frontend_url}           ║"
  echo "║ Backend: ${backend_url}           ║"
  echo "║ Usuário: ${DEPLOY_USER}           ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  printf "${NC}\n"
}

#######################################
# Funções de gerenciamento
#######################################

# Deletar instância
deletar_tudo() {
  print_banner
  log_info "Removendo instância ${empresa_delete}..."
  sleep 2

  if [ -z "${empresa_delete}" ]; then
    log_error "Nome da empresa não fornecido"
    exit 1
  fi

  sudo su - root <<EOF
  # Remove containers Docker
  docker rm -f redis-${empresa_delete} 2>/dev/null || true
  
  # Remove configurações do Nginx
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-backend
  rm -f /etc/nginx/sites-available/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-available/${empresa_delete}-backend
  
  # Remove banco de dados
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${empresa_delete};"
  sudo -u postgres psql -c "DROP USER IF EXISTS ${empresa_delete};"
  
  # Reinicia Nginx
  systemctl reload nginx
EOF

  # Remove arquivos do deploy
  sudo su - ${DEPLOY_USER} <<EOF
  rm -rf /home/${DEPLOY_USER}/${empresa_delete}
  pm2 delete ${empresa_delete}-frontend ${empresa_delete}-backend 2>/dev/null || true
  pm2 save
EOF

  log_success "Remoção da instância ${empresa_delete} realizada com sucesso"
  sleep 2
}

# Bloquear instância
configurar_bloqueio() {
  print_banner
  log_info "Bloqueando instância ${empresa_bloquear}..."
  sleep 2

  if [ -z "${empresa_bloquear}" ]; then
    log_error "Nome da empresa não fornecido"
    exit 1
  fi

  sudo su - ${DEPLOY_USER} <<EOF
  pm2 stop ${empresa_bloquear}-backend || true
  pm2 save
EOF

  log_success "Bloqueio da instância ${empresa_bloquear} realizado com sucesso"
  sleep 2
}

# Desbloquear instância
configurar_desbloqueio() {
  print_banner
  log_info "Desbloqueando instância ${empresa_desbloquear}..."
  sleep 2

  if [ -z "${empresa_desbloquear}" ]; then
    log_error "Nome da empresa não fornecido"
    exit 1
  fi

  sudo su - ${DEPLOY_USER} <<EOF
  pm2 start ${empresa_desbloquear}-backend || true
  pm2 save
EOF

  log_success "Desbloqueio da instância ${empresa_desbloquear} realizado com sucesso"
  sleep 2
}

# Alterar domínio
configurar_dominio() {
  print_banner
  log_info "Alterando domínios da instância ${empresa_dominio}..."
  sleep 2

  if [ -z "${empresa_dominio}" ] || [ -z "${alter_backend_url}" ] || [ -z "${alter_frontend_url}" ]; then
    log_error "Parâmetros não fornecidos corretamente"
    exit 1
  fi

  # Remove configurações antigas do Nginx
  sudo su - root <<EOF
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-frontend
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-backend
  rm -f /etc/nginx/sites-available/${empresa_dominio}-frontend
  rm -f /etc/nginx/sites-available/${empresa_dominio}-backend
EOF

  # Atualiza arquivos .env
  sudo su - ${DEPLOY_USER} <<EOF
  # Atualiza frontend .env
  if [ -f "/home/${DEPLOY_USER}/${empresa_dominio}/frontend/.env" ]; then
    sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=https://${alter_backend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/frontend/.env
  fi
  
  # Atualiza backend .env
  if [ -f "/home/${DEPLOY_USER}/${empresa_dominio}/backend/.env" ]; then
    sed -i "s|^BACKEND_URL=.*|BACKEND_URL=https://${alter_backend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/backend/.env
    sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://${alter_frontend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/backend/.env
  fi
EOF

  # Configura novo backend no Nginx
  backend_hostname=$(echo "${alter_backend_url}" | sed 's|https://||')
  sudo su - root <<EOF
  cat > /etc/nginx/sites-available/${empresa_dominio}-backend << 'END'
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${alter_backend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END
  ln -sf /etc/nginx/sites-available/${empresa_dominio}-backend /etc/nginx/sites-enabled/
EOF

  # Configura novo frontend no Nginx
  frontend_hostname=$(echo "${alter_frontend_url}" | sed 's|https://||')
  sudo su - root <<EOF
  cat > /etc/nginx/sites-available/${empresa_dominio}-frontend << 'END'
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${alter_frontend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END
  ln -sf /etc/nginx/sites-available/${empresa_dominio}-frontend /etc/nginx/sites-enabled/
  
  # Testa e reinicia Nginx
  nginx -t && systemctl reload nginx
EOF

  # Renova certificado SSL
  if [ -n "${deploy_email}" ]; then
    sudo su - root <<EOF
    certbot --nginx \
            --non-interactive \
            --agree-tos \
            --email ${deploy_email} \
            --domains ${backend_hostname},${frontend_hostname}
EOF
  fi

  log_success "Alteração de domínio da instância ${empresa_dominio} realizada com sucesso"
  sleep 2
}

#######################################
# Menu de ajuda
#######################################
show_help() {
  echo "Uso: $0 [comando]"
  echo ""
  echo "Comandos disponíveis:"
  echo "  deploy              - Executa instalação completa"
  echo "  deletar             - Remove uma instância (requer empresa_delete)"
  echo "  bloquear            - Bloqueia uma instância (requer empresa_bloquear)"
  echo "  desbloquear         - Desbloqueia uma instância (requer empresa_desbloquear)"
  echo "  alterar-dominio     - Altera domínios (requer empresa_dominio, alter_backend_url, alter_frontend_url)"
  echo ""
  echo "Variáveis necessárias:"
  echo "  link_git            - URL do repositório git"
  echo "  instancia_add       - Nome da instância"
  echo "  backend_url         - URL do backend"
  echo "  frontend_url        - URL do frontend"
  echo "  backend_port        - Porta do backend"
  echo "  frontend_port       - Porta do frontend"
  echo "  deploy_email        - Email para certificado SSL"
  echo ""
  echo "Exemplo:"
  echo "  export link_git=\"https://github.com/usuario/repo.git\""
  echo "  export instancia_add=\"meuapp\""
  echo "  export backend_url=\"https://api.meuapp.com\""
  echo "  export frontend_url=\"https://app.meuapp.com\""
  echo "  export backend_port=\"3000\""
  echo "  export frontend_port=\"3001\""
  echo "  export deploy_email=\"email@example.com\""
  echo "  $0 deploy"
}

#######################################
# Main
#######################################
main() {
  case "$1" in
    deploy)
      deploy
      ;;
    deletar)
      deletar_tudo
      ;;
    bloquear)
      configurar_bloqueio
      ;;
    desbloquear)
      configurar_desbloqueio
      ;;
    alterar-dominio)
      configurar_dominio
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      if [ -z "$1" ]; then
        log_error "Nenhum comando especificado"
        show_help
        exit 1
      else
        log_error "Comando desconhecido: $1"
        show_help
        exit 1
      fi
      ;;
  esac
}

# Verifica se está rodando como root
if [ "$EUID" -eq 0 ]; then 
  log_error "Não execute este script como root diretamente"
  exit 1
fi

# Executa main com todos os argumentos
main "$@"
