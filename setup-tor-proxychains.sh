#!/usr/bin/env bash
# setup-tor-proxychains.sh
# Script idempotente para atualizar sistema, instalar Tor e proxychains e configurá-los.
# Suporta apt, pacman, dnf, zypper.
# Executar como root ou o script relançará com sudo.

set -euo pipefail
IFS=$'\n\t'

# Relaunch com sudo se necessário
if [ "$EUID" -ne 0 ]; then
  echo "Relançando com sudo... (será pedido sua senha se necessário)"
  exec sudo bash "$0" "$@"
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/setup-backups-$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "Backup será salvo em: $BACKUP_DIR"

# Detecta gerenciador de pacotes
PKG_TOOL=""
PKG_INSTALL=""
PKG_UPDATE=""
PKG_UPGRADE=""
PKG_CHECK_CMD=""

if command -v apt >/dev/null 2>&1; then
  PKG_TOOL="apt"
  PKG_UPDATE="apt update -y"
  PKG_UPGRADE="apt upgrade -y"
  PKG_INSTALL="apt install -y"
  PKG_CHECK_CMD="dpkg -l"
elif command -v pacman >/dev/null 2>&1; then
  PKG_TOOL="pacman"
  PKG_UPDATE="pacman -Sy --noconfirm"
  PKG_UPGRADE="pacman -Syu --noconfirm"
  PKG_INSTALL="pacman -S --noconfirm"
  PKG_CHECK_CMD="pacman -Qs"
elif command -v dnf >/dev/null 2>&1; then
  PKG_TOOL="dnf"
  PKG_UPDATE="dnf check-update -y || true"
  PKG_UPGRADE="dnf upgrade -y"
  PKG_INSTALL="dnf install -y"
  PKG_CHECK_CMD="dnf list installed"
elif command -v zypper >/dev/null 2>&1; then
  PKG_TOOL="zypper"
  PKG_UPDATE="zypper refresh"
  PKG_UPGRADE="zypper update -y"
  PKG_INSTALL="zypper install -y"
  PKG_CHECK_CMD="zypper se -i"
else
  echo "Nenhum gerenciador de pacotes suportado (apt, pacman, dnf ou zypper) foi encontrado."
  exit 1
fi

echo "Gerenciador detectado: $PKG_TOOL"
echo "Atualizando índices e atualizando pacotes..."
eval "$PKG_UPDATE"
eval "$PKG_UPGRADE"

# Instalar pacotes: tor e proxychains (nome varia por distro)
PKGS_TO_TRY=( "tor" "torbrowser-launcher" )
PROXYCANDIDATES=( "proxychains-ng" "proxychains4" "proxychains" )

echo "Tentando instalar Tor..."
# Instala tor (nome padrão 'tor')
if ! command -v tor >/dev/null 2>&1; then
  # tenta instalar tor
  eval "$PKG_INSTALL tor" || true
fi

# Verifica se tor agora existe
if ! command -v tor >/dev/null 2>&1; then
  echo "A instalação direta de 'tor' falhou ou pacote não disponível. Tentando alternativas de nome..."
  for p in "${PKGS_TO_TRY[@]}"; do
    echo "Tentando instalar $p ..."
    if eval "$PKG_INSTALL $p"; then
      break
    fi
  done
fi

if ! command -v tor >/dev/null 2>&1; then
  echo "Falha ao instalar Tor automaticamente. Instale o Tor manualmente e reexecute o script."
  exit 1
fi

echo "Tor instalado: $(command -v tor)"

# Instalar proxychains
echo "Tentando instalar proxychains (vários nomes)..."
PROXY_PKGS_INSTALLED=()
for pc in "${PROXYCANDIDATES[@]}"; do
  if eval "$PKG_INSTALL $pc" >/dev/null 2>&1; then
    PROXY_PKGS_INSTALLED+=("$pc")
    echo "Instalado: $pc"
    break
  fi
done

if [ "${#PROXY_PKGS_INSTALLED[@]}" -eq 0 ]; then
  echo "Não foi possível instalar proxychains automaticamente. Tente instalar 'proxychains-ng' ou 'proxychains4' manualmente."
  # não sai, pois Tor já pode ser útil sozinho
fi

# Habilitar e iniciar o serviço tor (systemd)
echo "Habilitando e iniciando o serviço tor (systemd)..."
if command -v systemctl >/dev/null 2>&1; then
  # nomes possíveis: tor.service, tor@default.service (raros)
  if systemctl list-unit-files | grep -q '^tor.service'; then
    systemctl enable --now tor.service
    systemctl restart tor.service || true
    echo "tor.service habilitado e iniciado."
  elif systemctl list-unit-files | grep -q '^tor@'; then
    # fallback
    systemctl enable --now 'tor@default.service' || true
    systemctl restart 'tor@default.service' || true
    echo "tor@default.service habilitado e iniciado (fallback)."
  else
    echo "systemd presente mas unidade tor.service não encontrada — pode ser nome diferente na sua distro."
  fi
else
  echo "systemctl não encontrado: não posso habilitar o serviço automaticamente."
fi

# Configurar /etc/tor/torrc — backup e inserção de linhas essenciais
TORRC_PATH="/etc/tor/torrc"
if [ -f "$TORRC_PATH" ]; then
  cp "$TORRC_PATH" "$BACKUP_DIR/torrc.$TIMESTAMP.bak"
  echo "Backup de $TORRC_PATH salvo."
else
  # cria um arquivo default
  echo "# torrc criado pelo setup-tor-proxychains.sh - $TIMESTAMP" > "$TORRC_PATH"
  echo "Arquivo $TORRC_PATH criado."
fi

# Função para garantir linha no torrc (se não existir)
ensure_torrc_line() {
  local line="$1"
  local file="$TORRC_PATH"
  if ! grep -Fxq "$line" "$file"; then
    echo "$line" >> "$file"
    echo "Adicionada ao torrc: $line"
  else
    echo "Já existe no torrc: $line"
  fi
}

# Linhas recomendadas para uso com proxychains / dns via Tor
ensure_torrc_line "SocksPort 9050"
ensure_torrc_line "Log notice file /var/log/tor/notices.log"
ensure_torrc_line "VirtualAddrNetworkIPv4 10.192.0.0/10"
ensure_torrc_line "AutomapHostsOnResolve 1"
ensure_torrc_line "DNSPort 5353"

# Ajustar permissões do log/dir se necessário
mkdir -p /var/log/tor
chown -R debian-tor:debian-tor /var/log/tor 2>/dev/null || true
chmod 750 /var/log/tor 2>/dev/null || true

# Reiniciar tor para aplicar mudanças
if command -v systemctl >/dev/null 2>&1; then
  echo "Reiniciando tor para aplicar as mudanças..."
  systemctl restart tor.service || true
fi

# Configurar proxychains: /etc/proxychains.conf ou /etc/proxychains4.conf dependendo do que existe
PROXY_CONF_CANDIDATES=( "/etc/proxychains.conf" "/etc/proxychains4.conf" "/etc/proxychains/proxychains.conf" )
PROXY_CONF=""
for pc in "${PROXY_CONF_CANDIDATES[@]}"; do
  if [ -f "$pc" ]; then
    PROXY_CONF="$pc"
    break
  fi
done

# Se nenhum desses arquivos existir, cria /etc/proxychains.conf padrão
if [ -z "$PROXY_CONF" ]; then
  PROXY_CONF="/etc/proxychains.conf"
  echo "# Proxychains config criado por setup-tor-proxychains.sh - $TIMESTAMP" > "$PROXY_CONF"
  echo "strict_chain" >> "$PROXY_CONF"
  echo "proxy_dns" >> "$PROXY_CONF"
  echo "tcp_read_time_out 15000" >> "$PROXY_CONF"
  echo "tcp_connect_time_out 8000" >> "$PROXY_CONF"
fi

cp "$PROXY_CONF" "$BACKUP_DIR/$(basename "$PROXY_CONF").$TIMESTAMP.bak"
echo "Backup de $PROXY_CONF salvo."

# Função para comentar/ajustar opções comuns
# Ativa proxy_dns e define chain default para "dynamic_chain" ou "strict_chain" conforme preferir.
# Aqui colocamos proxy_dns e dynamic_chain por padrão.
sed -i 's/^# *proxy_dns/proxy_dns/' "$PROXY_CONF" 2>/dev/null || true

# Define dynamic_chain (se existir linha) — substitui strict_chain por dynamic_chain para menor quebra
if grep -q '^strict_chain' "$PROXY_CONF"; then
  sed -i 's/^strict_chain/dynamic_chain/' "$PROXY_CONF"
else
  if ! grep -q '^dynamic_chain' "$PROXY_CONF"; then
    echo "dynamic_chain" >> "$PROXY_CONF"
  fi
fi

# Remove linhas antigas de proxy no final e adiciona a nossa configuração de tor
# Apagar linhas que combinam com localhost:9050 para evitar duplicatas
sed -i '/127\.0\.0\.1[: ]*9050/d' "$PROXY_CONF" 2>/dev/null || true
sed -i '/socks4 127\.0\.0\.1 9050/d' "$PROXY_CONF" 2>/dev/null || true
sed -i '/socks5 127\.0\.0\.1 9050/d' "$PROXY_CONF" 2>/dev/null || true

# Garantir que no final exista a linha 'socks5 127.0.0.1 9050'
if ! tail -n 20 "$PROXY_CONF" | grep -q 'socks5 127.0.0.1 9050'; then
  echo "" >> "$PROXY_CONF"
  echo "# Tor SOCKS proxy (adicionado por setup-tor-proxychains.sh)" >> "$PROXY_CONF"
  echo "socks5 127.0.0.1 9050" >> "$PROXY_CONF"
  echo "Adicionada linha de proxychains: socks5 127.0.0.1 9050"
fi

echo ""
echo "Resumo das ações:"
echo "- Atualização/upgrade do sistema via $PKG_TOOL"
echo "- Tor instalado em: $(command -v tor || echo 'não encontrado')"
echo "- Serviço tor habilitado/iniciado (se systemd disponível)"
echo "- torrc atualizado em $TORRC_PATH e backup salvo em $BACKUP_DIR"
echo "- proxychains configurado em $PROXY_CONF e backup salvo em $BACKUP_DIR"

# Testes rápidos (não obrigatórios)
echo ""
echo "Testes rápidos (opcionais):"
if command -v tor >/dev/null 2>&1; then
  echo "- PID do tor: $(pgrep -a tor || echo 'tor não em execução')"
else
  echo "- Tor não instalado"
fi

echo ""
echo "Para testar uso do proxychains:"
echo "  proxychains4 curl https://check.torproject.org || proxychains curl https://check.torproject.org"
echo "ou"
echo "  proxychains4 ssh user@host"
echo ""
echo "Observações / segurança:"
echo "- Este script modifica /etc/tor/torrc e arquivos em /etc — backups foram salvos em $BACKUP_DIR."
echo "- A configuração padrão usa SocksPort 9050 e DNS via Tor (DNSPort 5353). Ajuste se necessário."
echo "- Se sua distro usa outra configuração (nome do serviço diferente, usuário tor distinto), verifique os backups antes de reverter."
echo ""
echo "Concluído! 🚀"
