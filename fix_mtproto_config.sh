#!/bin/bash

# Быстрое исправление config.py MTProto
# Исправляет: PORT = 8888, HOST = 127.0.0.1

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    print_error "Запустите: sudo bash fix_mtproto_config.sh"
    exit 1
fi

echo "============================================"
echo "ИСПРАВЛЕНИЕ CONFIG.PY"
echo "============================================"
echo

CONFIG_PY="/opt/MTProto_Proxy/config.py"

if [ ! -f "$CONFIG_PY" ]; then
    print_error "config.py не найден: $CONFIG_PY"
    exit 1
fi

# Проверяем текущие настройки
CURRENT_PORT=$(grep "^PORT = " "$CONFIG_PY" | sed 's/PORT = //')
CURRENT_HOST=$(grep "^HOST = " "$CONFIG_PY" 2>/dev/null | sed 's/HOST = "\(.*\)"/\1/')

print_info "Текущие настройки:"
echo "   PORT: $CURRENT_PORT"
echo "   HOST: ${CURRENT_HOST:-не задан}"
echo

NEED_FIX=0

if [ "$CURRENT_PORT" == "443" ]; then
    print_error "PORT = 443 - НЕПРАВИЛЬНО!"
    echo "   Порт 443 занят Nginx!"
    NEED_FIX=1
fi

if [ "$CURRENT_HOST" == "0.0.0.0" ]; then
    print_error "HOST = 0.0.0.0 - НЕПРАВИЛЬНО!"
    echo "   MTProto должен слушать только локально!"
    NEED_FIX=1
fi

if [ "$CURRENT_PORT" != "8888" ]; then
    print_warning "PORT != 8888"
    NEED_FIX=1
fi

if [ -z "$CURRENT_HOST" ] || [ "$CURRENT_HOST" != "127.0.0.1" ]; then
    print_warning "HOST не задан или != 127.0.0.1"
    NEED_FIX=1
fi

if [ $NEED_FIX -eq 0 ]; then
    print_success "config.py в порядке!"
    exit 0
fi

echo
print_warning "Исправляем config.py..."

# Бэкап
cp "$CONFIG_PY" "$CONFIG_PY.before_fix"
print_success "Backup: $CONFIG_PY.before_fix"

# Исправляем PORT
sed -i 's/^PORT = .*/PORT = 8888/' "$CONFIG_PY"

# Исправляем или добавляем HOST
if grep -q "^HOST = " "$CONFIG_PY"; then
    sed -i 's/^HOST = .*/HOST = "127.0.0.1"/' "$CONFIG_PY"
else
    # Добавляем HOST после PORT
    sed -i '/^PORT = /a HOST = "127.0.0.1"' "$CONFIG_PY"
fi

print_success "config.py исправлен!"
echo

# Проверяем
NEW_PORT=$(grep "^PORT = " "$CONFIG_PY" | sed 's/PORT = //')
NEW_HOST=$(grep "^HOST = " "$CONFIG_PY" | sed 's/HOST = "\(.*\)"/\1/')

print_info "Новые настройки:"
echo "   PORT: $NEW_PORT"
echo "   HOST: $NEW_HOST"
echo

# Перезапускаем
print_warning "Перезапуск MTProto контейнера..."
cd /opt/MTProto_Proxy
docker compose restart

sleep 5

# Проверяем порт
if ss -tulpn | grep -q "127.0.0.1:8888"; then
    print_success "MTProto слушает 127.0.0.1:8888"
elif ss -tulpn | grep -q ":8888"; then
    print_success "MTProto слушает порт 8888"
else
    print_error "MTProto НЕ слушает порт 8888"
    echo
    print_warning "Проверьте логи:"
    echo "   docker logs --tail 30 mtprotoproxy"
    exit 1
fi

echo
print_success "============================================"
print_success "ГОТОВО!"
print_success "============================================"
echo

print_info "MTProto теперь правильно настроен:"
echo "   ✓ Слушает 127.0.0.1:8888 (локально)"
echo "   ✓ Nginx проксирует 443 → 8888"
echo
print_info "Следующий шаг: исправьте stream.conf"
echo "   sudo bash fix_mtproto_stream.sh"
echo
