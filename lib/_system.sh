#!/bin/bash
#
# system management - Versão Corrigida
# Uso: ./script.sh [opções]
# Requer variáveis de ambiente ou arquivo de configuração

set -e  # Para o script em caso de erro

# Verifica se as variáveis de cor já existem
if [[ -z "${RED}" ]]; then
  # Cores para output
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  WHITE='\033[1;37m'
  GRAY_LIGHT='\033[0;37m'
  NC='\033[0m' # No Color
fi

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

# Função para log de aviso
log_warning() {
  printf "${YELLOW} ⚠️  $1${NC}\n"
}

# Função para validar variáveis obrigatórias
validate_variables() {
  local missing_vars=()
  
  # Lista de variáveis obrigatórias para deploy
  if [[ "$1" == "deploy" ]]; then
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
  fi
  
  if [ ${#missing_vars[@]} -ne 0 ]; then
    log_error "Variáveis obrigatórias não definidas: ${missing_vars[*]}"
    log_info "Defina as variáveis antes de executar:"
    for var in "${missing_vars[@]}"; do
      echo "  export $var=\"valor\""
    done
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
    log_warning "Senha gerada para usuário ${DEPLOY_USER}: ${DEPLOY_PASSWORD}"
    log_warning "Salve esta senha em local seguro!"
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

  # Verifica se o diretório home do usuário existe
  if [ ! -d "/home/${DEPLOY_USER}" ]; then
    log_error "Diretório do usuário ${DEPLOY_USER} não encontrado"
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
  
  # Lista conteúdo
  echo "Conteúdo do diretório:"
  ls -la /home/${DEPLOY_USER}/${instancia_add}/
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
    lsb-release \
    build-essential \
    dirmngr
    
  # Limpa cache
  apt clean
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
  
  # Configura npm global sem sudo
  mkdir -p /home/${DEPLOY_USER}/.npm-global
  npm config set prefix '/home/${DEPLOY_USER}/.npm-global'
  echo 'export PATH=/home/${DEPLOY_USER}/.npm-global/bin:$PATH' >> /home/${DEPLOY_USER}/.bashrc
  chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.npm-global
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
  
  # Aguarda PostgreSQL iniciar
  sleep 5
  
  # Configura PostgreSQL
  sudo -u postgres psql <<PSQL
    ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';
    CREATE DATABASE ${instancia_add} WITH OWNER postgres;
    \du
    \l
PSQL

  # Configura PostgreSQL para aceitar conexões locais
  echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/*/main/pg_hba.conf
  systemctl restart postgresql
  
  # Verifica status
  systemctl status postgresql --no-pager
EOF

  if [ $? -eq 0 ]; then
    log_success "PostgreSQL instalado com sucesso"
    log_info "Banco de dados '${instancia_add}' criado"
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
  
  # Instala Docker usando script oficial
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  
  # Aguarda instalação
  sleep 3
  
  # Adiciona usuário ao grupo docker
  usermod -aG docker ${DEPLOY_USER}
  
  # Instala Docker Compose
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  
  # Verifica instalação
  docker --version
  docker-compose --version
  
  # Inicia docker
  systemctl start docker
  systemctl enable docker
EOF

  if [ $? -eq 0 ]; then
    log_success "Docker instalado com sucesso"
    log_warning "Faça logout e login novamente para usar docker sem sudo"
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
  su - ${DEPLOY_USER} -c "pm2 startup systemd -u ${DEPLOY_USER} --hp /home/${DEPLOY_USER}"
  
  # Configura permissões
  su - ${DEPLOY_USER} -c "pm2 save"
  
  # Verifica instalação
  pm2 --version
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
    libxkbcommon0 \
    --no-install-recommends
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
  
  # Verifica status
  systemctl status nginx --no-pager
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
  # Remove versões antigas
  apt remove -y certbot || true
  
  # Instala snap se necessário
  apt install -y snapd
  
  # Atualiza snap
  snap install core
  snap refresh core
  
  # Instala certbot
  snap install --classic certbot
  
  # Cria link simbólico
  ln -sf /snap/bin/certbot /usr/bin/certbot
  
  # Verifica instalação
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
          --domains ${backend_domain},${frontend_domain} \
          || echo "Certbot pode ter falhado - verifique se os domínios apontam para este servidor"
  
  systemctl reload nginx
EOF

  if [ $? -eq 0 ]; then
    log_success "Certificado SSL configurado com sucesso"
  else
    log_warning "Falha ao configurar certificado SSL - verifique se os domínios estão apontando para este servidor"
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
  local start_time=$(date +%s)
  
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
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log_success "Instalação completa finalizada com sucesso em ${duration} segundos!"
  
  if [ -f "/root/deploy_password.txt" ]; then
    log_warning "Senha do usuário deploy salva em: /root/deploy_password.txt"
  fi
}

#######################################
# Função de deploy
#######################################
deploy() {
  print_banner
  log_info "Iniciando processo de deploy..."
  
  validate_variables "deploy"
  install_all
  
  print_banner
  printf "${GREEN}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                DEPLOY FINALIZADO COM SUCESSO              ║"
  echo "╠════════════════════════════════════════════════════════════╣"
  echo "║ Frontend: ${frontend_url}           ║"
  echo "║ Backend: ${backend_url}           ║"
  echo "║ Usuário: ${DEPLOY_USER}                                    ║"
  echo "║ Banco: ${instancia_add}                                    ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  printf "${NC}\n"
  
  log_warning "IMPORTANTE: Faça logout e login novamente para usar docker sem sudo"
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
    echo "Use: export empresa_delete=\"nome_da_empresa\""
    exit 1
  fi

  sudo su - root <<EOF
  # Para containers Docker
  docker stop redis-${empresa_delete} 2>/dev/null || true
  docker rm redis-${empresa_delete} 2>/dev/null || true
  
  # Remove configurações do Nginx
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-enabled/${empresa_delete}-backend
  rm -f /etc/nginx/sites-available/${empresa_delete}-frontend
  rm -f /etc/nginx/sites-available/${empresa_delete}-backend
  
  # Remove banco de dados PostgreSQL
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${empresa_delete};"
  sudo -u postgres psql -c "DROP USER IF EXISTS ${empresa_delete};"
  
  # Reinicia Nginx
  systemctl reload nginx
EOF

  # Remove arquivos do deploy e processos PM2
  if id "${DEPLOY_USER}" &>/dev/null; then
    sudo su - ${DEPLOY_USER} <<EOF
    pm2 delete ${empresa_delete}-frontend ${empresa_delete}-backend 2>/dev/null || true
    pm2 save
EOF
    sudo rm -rf /home/${DEPLOY_USER}/${empresa_delete}
  fi

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
    echo "Use: export empresa_bloquear=\"nome_da_empresa\""
    exit 1
  fi

  if id "${DEPLOY_USER}" &>/dev/null; then
    sudo su - ${DEPLOY_USER} <<EOF
    pm2 stop ${empresa_bloquear}-backend || true
    pm2 save
EOF
    log_success "Bloqueio da instância ${empresa_bloquear} realizado com sucesso"
  else
    log_error "Usuário ${DEPLOY_USER} não encontrado"
    exit 1
  fi
  
  sleep 2
}

# Desbloquear instância
configurar_desbloqueio() {
  print_banner
  log_info "Desbloqueando instância ${empresa_desbloquear}..."
  sleep 2

  if [ -z "${empresa_desbloquear}" ]; then
    log_error "Nome da empresa não fornecido"
    echo "Use: export empresa_desbloquear=\"nome_da_empresa\""
    exit 1
  fi

  if id "${DEPLOY_USER}" &>/dev/null; then
    sudo su - ${DEPLOY_USER} <<EOF
    pm2 start ${empresa_desbloquear}-backend || true
    pm2 save
EOF
    log_success "Desbloqueio da instância ${empresa_desbloquear} realizado com sucesso"
  else
    log_error "Usuário ${DEPLOY_USER} não encontrado"
    exit 1
  fi
  
  sleep 2
}

# Alterar domínio
configurar_dominio() {
  print_banner
  log_info "Alterando domínios da instância ${empresa_dominio}..."
  sleep 2

    if [ -z "${empresa_dominio}" ] || [ -z "${alter_backend_url}" ] || [ -z "${alter_frontend_url}" ] || [ -z "${alter_backend_port}" ] || [ -z "${alter_frontend_port}" ]; then
    log_error "Parâmetros não fornecidos corretamente"
    echo "Necessário definir:"
    echo "  export empresa_dominio=\"nome\""
    echo "  export alter_backend_url=\"api.exemplo.com\""
    echo "  export alter_frontend_url=\"app.exemplo.com\""
    echo "  export alter_backend_port=\"3000\""
    echo "  export alter_frontend_port=\"3001\""
    exit 1
  fi

  # Remove configurações antigas do Nginx
  sudo su - root <<EOF
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-frontend
  rm -f /etc/nginx/sites-enabled/${empresa_dominio}-backend
  rm -f /etc/nginx/sites-available/${empresa_dominio}-frontend
  rm -f /etc/nginx/sites-available/${empresa_dominio}-backend
EOF

  # Atualiza arquivos .env se existirem
  if id "${DEPLOY_USER}" &>/dev/null; then
    sudo su - ${DEPLOY_USER} <<EOF
    # Atualiza frontend .env
    if [ -f "/home/${DEPLOY_USER}/${empresa_dominio}/frontend/.env" ]; then
      sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=https://${alter_backend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/frontend/.env
      echo "Frontend .env atualizado"
    fi
    
    # Atualiza backend .env
    if [ -f "/home/${DEPLOY_USER}/${empresa_dominio}/backend/.env" ]; then
      sed -i "s|^BACKEND_URL=.*|BACKEND_URL=https://${alter_backend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/backend/.env
      sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=https://${alter_frontend_url}|" /home/${DEPLOY_USER}/${empresa_dominio}/backend/.env
      echo "Backend .env atualizado"
    fi
EOF
  fi

  # Configura novo backend no Nginx
  backend_hostname=$(echo "${alter_backend_url}" | sed 's|https://||' | sed 's|http://||')
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
  frontend_hostname=$(echo "${alter_frontend_url}" | sed 's|https://||' | sed 's|http://||')
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

  # Renova certificado SSL se email foi fornecido
  if [ -n "${deploy_email}" ]; then
    log_info "Renovando certificado SSL..."
    sudo su - root <<EOF
    certbot --nginx \
            --non-interactive \
            --agree-tos \
            --email ${deploy_email} \
            --domains ${backend_hostname},${frontend_hostname} \
            || echo "Certbot pode ter falhado - verifique os domínios"
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
  echo "  alterar-dominio     - Altera domínios (requer múltiplas variáveis)"
  echo "  help                - Mostra esta ajuda"
  echo ""
  echo "Variáveis necessárias para deploy:"
  echo "  link_git            - URL do repositório git"
  echo "  instancia_add       - Nome da instância"
  echo "  backend_url         - URL do backend (ex: https://api.exemplo.com)"
  echo "  frontend_url        - URL do frontend (ex: https://app.exemplo.com)"
  echo "  backend_port        - Porta do backend"
  echo "  frontend_port       - Porta do frontend"
  echo "  deploy_email        - Email para certificado SSL"
  echo ""
  echo "Variáveis opcionais:"
  echo "  DEPLOY_PASSWORD     - Senha para usuário deploy (gerada automática se vazia)"
  echo "  POSTGRES_PASSWORD   - Senha do PostgreSQL (padrão: postgres)"
  echo ""
  echo "Exemplo completo:"
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
# Verifica dependências básicas
#######################################
check_dependencies() {
  local missing_deps=()
  
  for cmd in sudo openssl curl wget git; do
    if ! command -v $cmd &> /dev/null; then
      missing_deps+=($cmd)
    fi
  done
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Dependências básicas não encontradas: ${missing_deps[*]}"
    log_info "Instale as dependências com:"
    echo "  sudo apt update && sudo apt install -y ${missing_deps[*]}"
    exit 1
  fi
}

#######################################
# Main
#######################################
main() {
  # Verifica dependências básicas
  check_dependencies
  
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
  echo "Use um usuário comum com sudo"
  exit 1
fi

# Executa main com todos os argumentos
main "$@"
