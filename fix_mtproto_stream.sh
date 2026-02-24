#!/bin/bash

# Фикс MTProto: Отдельный stream upstream без HTTP backend
# Проблема: MTProto проходит через HTTP proxy, что ломает протокол

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
    print_error "Запустите: sudo bash fix_mtproto_stream.sh"
    exit 1
fi

echo "============================================"
echo "ИСПРАВЛЕНИЕ MTPROTO STREAM"
echo "============================================"
echo

STREAM_CONF="/opt/remnanode/stream.conf"
NGINX_CONF="/opt/remnanode/sites-available/russia3-t.vline.online"
MTPROTO_DOMAIN="russia3-t.vline.online"

print_info "ПРОБЛЕМА:"
echo "   MTProto домен идет через HTTP backend (10443)"
echo "   HTTP proxy обрабатывает MTProto как HTTP → ломает протокол"
echo
print_info "РЕШЕНИЕ:"
echo "   Создать отдельный stream upstream для MTProto"
echo "   Прямое TCP проксирование: 443 → stream → 8888"
echo "   БЕЗ промежуточного HTTP backend!"
echo

# Проверяем config.py
CONFIG_PY="/opt/MTProto_Proxy/config.py"

if [ ! -f "$CONFIG_PY" ]; then
    print_error "config.py не найден: $CONFIG_PY"
    exit 1
fi

# Проверяем порт и хост
CURRENT_PORT=$(grep "^PORT = " "$CONFIG_PY" | sed 's/PORT = //')
CURRENT_HOST=$(grep "^HOST = " "$CONFIG_PY" | sed 's/HOST = "\(.*\)"/\1/')

if [ "$CURRENT_PORT" != "8888" ] || [ "$CURRENT_HOST" == "0.0.0.0" ]; then
    print_error "ПРОБЛЕМА в config.py:"
    echo "   Текущий PORT: $CURRENT_PORT (должен быть 8888)"
    echo "   Текущий HOST: $CURRENT_HOST (должен быть 127.0.0.1)"
    echo
    print_warning "Исправляем config.py..."

    cp "$CONFIG_PY" "$CONFIG_PY.before_fix"

    # Исправляем PORT
    sed -i 's/^PORT = .*/PORT = 8888/' "$CONFIG_PY"

    # Исправляем или добавляем HOST
    if grep -q "^HOST = " "$CONFIG_PY"; then
        sed -i 's/^HOST = .*/HOST = "127.0.0.1"/' "$CONFIG_PY"
    else
        sed -i '/^PORT = /a HOST = "127.0.0.1"' "$CONFIG_PY"
    fi

    print_success "config.py исправлен:"
    echo "   PORT = 8888"
    echo "   HOST = '127.0.0.1'"
    echo
fi

# Бэкап stream.conf
cp "$STREAM_CONF" "$STREAM_CONF.before_mtproto_direct"
print_success "Backup: $STREAM_CONF.before_mtproto_direct"
echo

# Изменяем upstream mtproto_backend
print_warning "Изменяем mtproto_backend на прямое подключение..."

# Меняем порт с 10443 на 8888 в mtproto_backend
sed -i '/upstream mtproto_backend/,/^}/ s/127\.0\.0\.1:10443/127.0.0.1:8888/' "$STREAM_CONF"

print_success "mtproto_backend теперь: 127.0.0.1:8888 (прямое подключение)"
echo

# Отключаем HTTP backend конфиг
if [ -f "$NGINX_CONF" ]; then
    print_warning "Отключаем HTTP backend (больше не нужен)..."
    mv "$NGINX_CONF" "$NGINX_CONF.disabled"
    print_success "HTTP backend отключен: $NGINX_CONF.disabled"
    echo
fi

print_success "Конфигурация изменена!"
echo

print_info "НОВАЯ АРХИТЕКТУРА:"
echo "   Internet:443"
echo "     ↓"
echo "   Nginx stream (SNI: russia3-t.vline.online)"
echo "     ↓"
echo "   mtproto_backend → 127.0.0.1:8888 (ПРЯМО!)"
echo "     ↓"
echo "   MTProto контейнер (получает чистый TLS)"
echo
print_warning "HTTP backend на 10443 больше НЕ используется!"
echo

# Проверяем конфиг
print_info "Проверяем конфигурацию Nginx..."
if docker exec remnawave-nginx nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx конфиг валиден"
else
    print_error "Ошибка в конфиге!"
    
    print_warning "Откатываем изменения..."
    cp "$STREAM_CONF.before_mtproto_direct" "$STREAM_CONF"
    
    if [ -f "$NGINX_CONF.disabled" ]; then
        mv "$NGINX_CONF.disabled" "$NGINX_CONF"
    fi
    
    print_error "Изменения откачены"
    exit 1
fi

echo

# Перезапуск
print_warning "Перезапуск сервисов..."
cd /opt/remnanode && docker compose restart
sleep 2
cd /opt/MTProto_Proxy && docker compose restart

print_success "Сервисы перезапущены"
echo

sleep 5

# Проверка
print_info "Проверяем порты..."
echo

if ss -tulpn | grep -q ":443"; then
    print_success "Порт 443: слушается"
else
    print_error "Порт 443: НЕ слушается"
fi

if ss -tulpn | grep -q ":8888"; then
    print_success "Порт 8888: слушается (MTProto)"
else
    print_error "Порт 8888: НЕ слушается"
fi

if ss -tulpn | grep -q ":10443"; then
    print_warning "Порт 10443: всё ещё слушается"
    print_info "Это нормально, если есть другие домены на этом порту"
fi

echo

# Тест подключения
print_info "Тестируем подключение к MTProto через stream..."

if timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/443 && echo "test" >&3' 2>/dev/null; then
    print_success "TCP подключение к 443: работает"
else
    print_warning "TCP подключение к 443: timeout (это нормально для TLS)"
fi

echo
print_success "============================================"
print_success "ГОТОВО!"
print_success "============================================"
echo

print_info "Что изменилось:"
echo "   ✓ mtproto_backend теперь проксирует напрямую на 8888"
echo "   ✓ HTTP backend (10443) отключен для MTProto"
echo "   ✓ proxy_protocol on остается (нужен для других доменов)"
echo "   ✓ MTProto получает чистый TCP/TLS без HTTP обработки"
echo

print_info "🎯 Попробуйте подключиться в Telegram!"
echo

if [ -f "/opt/MTProto_Proxy/proxy_link.txt" ]; then
    cat /opt/MTProto_Proxy/proxy_link.txt
    echo
fi

print_info "Логи:"
echo "   docker logs --tail 30 mtprotoproxy"
echo "   docker logs --tail 30 remnawave-nginx"
echo

print_info "Если не работает:"
echo "   1. Проверьте логи MTProto контейнера"
echo "   2. Убедитесь что firewall разрешает 443"
echo "   3. Попробуйте с мобильного интернета"
echo

print_warning "⚠️  Важно: proxy_protocol on НЕ отключен!"
print_warning "   Он нужен для ru3-x.vline.online"
print_warning "   MTProto теперь обходит HTTP backend напрямую через stream"
echo
