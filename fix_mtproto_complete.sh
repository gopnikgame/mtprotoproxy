#!/bin/bash

# Полное исправление MTProto + Nginx
# Исправляет ВСЕ проблемы в правильном порядке

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
print_header() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

if [ "$EUID" -ne 0 ]; then
    print_error "Запустите: sudo bash fix_mtproto_complete.sh"
    exit 1
fi

print_header "ПОЛНОЕ ИСПРАВЛЕНИЕ MTPROTO"

print_info "Этот скрипт исправит:"
echo "   1. config.py (PORT=8888, HOST=127.0.0.1)"
echo "   2. stream.conf (прямое подключение к 8888)"
echo "   3. Отключит HTTP backend"
echo "   4. Перезапустит контейнеры"
echo

read -p "Продолжить? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Отменено"
    exit 0
fi

# ===========================================
# ШАГ 1: Исправление config.py
# ===========================================

print_header "ШАГ 1: ИСПРАВЛЕНИЕ CONFIG.PY"

CONFIG_PY="/opt/MTProto_Proxy/config.py"

if [ ! -f "$CONFIG_PY" ]; then
    print_error "config.py не найден: $CONFIG_PY"
    exit 1
fi

CURRENT_PORT=$(grep "^PORT = " "$CONFIG_PY" | sed 's/PORT = //')
CURRENT_HOST=$(grep "^HOST = " "$CONFIG_PY" 2>/dev/null | sed 's/HOST = "\(.*\)"/\1/')

print_info "Текущие настройки:"
echo "   PORT: $CURRENT_PORT"
echo "   HOST: ${CURRENT_HOST:-не задан}"
echo

if [ "$CURRENT_PORT" != "8888" ] || [ "$CURRENT_HOST" != "127.0.0.1" ]; then
    print_warning "Исправляем config.py..."
    
    cp "$CONFIG_PY" "$CONFIG_PY.before_complete_fix"
    print_success "Backup: $CONFIG_PY.before_complete_fix"
    
    # Исправляем PORT
    sed -i 's/^PORT = .*/PORT = 8888/' "$CONFIG_PY"
    
    # Исправляем или добавляем HOST
    if grep -q "^HOST = " "$CONFIG_PY"; then
        sed -i 's/^HOST = .*/HOST = "127.0.0.1"/' "$CONFIG_PY"
    else
        sed -i '/^PORT = /a HOST = "127.0.0.1"' "$CONFIG_PY"
    fi
    
    print_success "config.py исправлен: PORT=8888, HOST=127.0.0.1"
else
    print_success "config.py в порядке"
fi

# ===========================================
# ШАГ 2: Исправление stream.conf
# ===========================================

print_header "ШАГ 2: ИСПРАВЛЕНИЕ STREAM.CONF"

STREAM_CONF="/opt/remnanode/stream.conf"
NGINX_CONF="/opt/remnanode/sites-available/russia3-t.vline.online"

if [ ! -f "$STREAM_CONF" ]; then
    print_error "stream.conf не найден: $STREAM_CONF"
    exit 1
fi

# Проверяем текущий upstream
CURRENT_BACKEND=$(grep -A1 "upstream mtproto_backend" "$STREAM_CONF" | grep "server" | awk '{print $2}' | sed 's/;//')

print_info "Текущий mtproto_backend: $CURRENT_BACKEND"
echo

if [ "$CURRENT_BACKEND" != "127.0.0.1:8888" ]; then
    print_warning "Изменяем stream.conf..."
    
    cp "$STREAM_CONF" "$STREAM_CONF.before_complete_fix"
    print_success "Backup: $STREAM_CONF.before_complete_fix"
    
    # Меняем порт в mtproto_backend с 10443 на 8888
    sed -i '/upstream mtproto_backend/,/^}/ s/127\.0\.0\.1:10443/127.0.0.1:8888/' "$STREAM_CONF"
    sed -i '/upstream mtproto_backend/,/^}/ s/127\.0\.0\.1:[0-9]*/127.0.0.1:8888/' "$STREAM_CONF"
    
    print_success "stream.conf исправлен: mtproto_backend → 127.0.0.1:8888"
else
    print_success "stream.conf в порядке"
fi

# ===========================================
# ШАГ 3: Отключение HTTP backend
# ===========================================

print_header "ШАГ 3: ОТКЛЮЧЕНИЕ HTTP BACKEND"

if [ -f "$NGINX_CONF" ]; then
    print_warning "Отключаем HTTP backend (больше не нужен)..."
    mv "$NGINX_CONF" "$NGINX_CONF.disabled"
    print_success "HTTP backend отключен: $NGINX_CONF.disabled"
else
    print_success "HTTP backend уже отключен"
fi

# ===========================================
# ШАГ 4: Проверка конфигурации
# ===========================================

print_header "ШАГ 4: ПРОВЕРКА КОНФИГУРАЦИИ"

print_info "Проверяем Nginx конфиг..."
if docker exec remnawave-nginx nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx конфиг валиден"
else
    print_error "Ошибка в Nginx конфиге!"
    
    print_warning "Откатываем изменения..."
    cp "$STREAM_CONF.before_complete_fix" "$STREAM_CONF"
    
    if [ -f "$NGINX_CONF.disabled" ]; then
        mv "$NGINX_CONF.disabled" "$NGINX_CONF"
    fi
    
    print_error "Изменения откатаны"
    exit 1
fi

# ===========================================
# ШАГ 5: Перезапуск сервисов
# ===========================================

print_header "ШАГ 5: ПЕРЕЗАПУСК СЕРВИСОВ"

print_warning "Перезапуск Nginx..."
cd /opt/remnanode
docker compose restart
print_success "Nginx перезапущен"

sleep 2

print_warning "Перезапуск MTProto..."
cd /opt/MTProto_Proxy
docker compose restart
print_success "MTProto перезапущен"

# ===========================================
# ШАГ 6: Проверка результата
# ===========================================

print_header "ШАГ 6: ПРОВЕРКА РЕЗУЛЬТАТА"

sleep 5

print_info "Проверяем порты..."
echo

NGINX_443=$(ss -tulpn | grep ":443" | head -1)
MTPROTO_8888=$(ss -tulpn | grep "127.0.0.1:8888" | head -1)

if [ -n "$NGINX_443" ]; then
    print_success "Порт 443: слушается (Nginx)"
else
    print_error "Порт 443: НЕ слушается"
fi

if [ -n "$MTPROTO_8888" ]; then
    print_success "Порт 8888: слушается (MTProto, локально)"
else
    print_error "Порт 8888: НЕ слушается"
    print_warning "Проверьте логи: docker logs --tail 30 mtprotoproxy"
fi

if ss -tulpn | grep -q "0.0.0.0:8888"; then
    print_warning "⚠️  MTProto слушает 0.0.0.0:8888 (не только локально)"
    print_warning "   Это работает, но лучше использовать 127.0.0.1"
fi

# ===========================================
# ГОТОВО!
# ===========================================

print_header "ГОТОВО!"

print_success "Все исправления применены!"
echo

print_info "Что было сделано:"
echo "   ✓ config.py: PORT=8888, HOST=127.0.0.1"
echo "   ✓ stream.conf: mtproto_backend → 127.0.0.1:8888"
echo "   ✓ HTTP backend отключен (10443 не используется)"
echo "   ✓ proxy_protocol on оставлен (нужен для других доменов)"
echo "   ✓ Контейнеры перезапущены"
echo

print_info "Архитектура теперь:"
echo "   Internet:443"
echo "     ↓"
echo "   Nginx stream (SNI routing, proxy_protocol on)"
echo "     ↓"
echo "   russia3-t.vline.online → mtproto_backend"
echo "     ↓"
echo "   127.0.0.1:8888 (MTProto контейнер)"
echo "     ↓"
echo "   Чистый TCP/TLS без HTTP обработки!"
echo

print_info "🎯 Попробуйте подключиться в Telegram!"
echo

if [ -f "/opt/MTProto_Proxy/proxy_link.txt" ]; then
    cat /opt/MTProto_Proxy/proxy_link.txt
    echo
fi

print_info "Проверка:"
echo "   sudo bash diagnose_mtproto.sh"
echo

print_info "Логи:"
echo "   docker logs --tail 30 mtprotoproxy"
echo "   docker logs --tail 30 remnawave-nginx"
echo

print_warning "⚠️  Если не работает:"
echo "   1. Проверьте firewall: sudo ufw status"
echo "   2. Попробуйте с мобильного интернета"
echo "   3. Убедитесь что DNS указывает на ваш IP"
echo
