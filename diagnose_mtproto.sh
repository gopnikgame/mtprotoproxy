#!/bin/bash

# Диагностика MTProto Proxy для Remnawave
# Использование: sudo bash diagnose_mtproto.sh

set +e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Проверка root
if [ "$EUID" -ne 0 ]; then
    print_error "Запустите скрипт с правами root (sudo)"
    exit 1
fi

print_header "ДИАГНОСТИКА MTPROTO PROXY"
echo

# 1. Проверка контейнеров
print_header "1. СТАТУС КОНТЕЙНЕРОВ"
echo

MTPROTO_STATUS=$(docker ps --filter "name=mtprotoproxy" --format "{{.Status}}")
NGINX_STATUS=$(docker ps --filter "name=remnawave-nginx" --format "{{.Status}}")

if [ -n "$MTPROTO_STATUS" ]; then
    if echo "$MTPROTO_STATUS" | grep -q "Up"; then
        print_success "MTProto контейнер: $MTPROTO_STATUS"
    else
        print_error "MTProto контейнер: $MTPROTO_STATUS"
    fi
else
    print_error "MTProto контейнер: НЕ ЗАПУЩЕН"
fi

if [ -n "$NGINX_STATUS" ]; then
    if echo "$NGINX_STATUS" | grep -q "Up"; then
        print_success "Nginx контейнер: $NGINX_STATUS"
    else
        print_error "Nginx контейнер: $NGINX_STATUS"
    fi
else
    print_error "Nginx контейнер: НЕ ЗАПУЩЕН"
fi

echo

# 2. Проверка портов
print_header "2. ПРОВЕРКА ПОРТОВ"
echo

# MTProto порт (8888)
if ss -tulpn | grep -q ":8888"; then
    PORT_8888=$(ss -tulpn | grep ":8888" | head -1)
    print_success "Порт 8888 (MTProto): слушает"
    echo "   $PORT_8888"
else
    print_error "Порт 8888 (MTProto): НЕ СЛУШАЕТ"
    print_warning "MTProto контейнер не слушает порт 8888"
fi

echo

# Nginx backend порт (10443)
if ss -tulpn | grep -q ":10443"; then
    PORT_10443=$(ss -tulpn | grep ":10443" | head -1)
    print_success "Порт 10443 (Nginx backend): слушает"
    echo "   $PORT_10443"
else
    print_error "Порт 10443 (Nginx backend): НЕ СЛУШАЕТ"
    print_warning "Nginx не слушает backend порт 10443"
fi

echo

# Внешний порт (443)
if ss -tulpn | grep -q ":443"; then
    PORT_443=$(ss -tulpn | grep ":443" | head -1)
    print_success "Порт 443 (внешний): слушает"
    echo "   $PORT_443"
else
    print_error "Порт 443 (внешний): НЕ СЛУШАЕТ"
    print_warning "Nginx не слушает внешний порт 443"
fi

echo

# 3. Проверка конфигураций
print_header "3. ПРОВЕРКА КОНФИГУРАЦИЙ"
echo

# config.py
CONFIG_PY="/opt/MTProto_Proxy/config.py"
if [ -f "$CONFIG_PY" ]; then
    print_success "config.py найден"
    
    PORT=$(grep "^PORT = " "$CONFIG_PY" | sed 's/PORT = //')
    SECRET=$(grep '"tg":' "$CONFIG_PY" | sed 's/.*"\([^"]*\)".*/\1/')
    TLS_DOMAIN=$(grep "^TLS_DOMAIN = " "$CONFIG_PY" | sed 's/TLS_DOMAIN = "\(.*\)"/\1/')
    
    echo "   Порт: $PORT"
    echo "   Секрет: $SECRET"
    echo "   TLS домен: $TLS_DOMAIN"
    
    if [ "$PORT" != "8888" ]; then
        print_warning "Порт в config.py ($PORT) не равен 8888"
    fi
else
    print_error "config.py не найден: $CONFIG_PY"
fi

echo

# stream.conf
STREAM_CONF="/opt/remnanode/stream.conf"
if [ -f "$STREAM_CONF" ]; then
    print_success "stream.conf найден"
    
    # Проверяем upstream mtproto_backend
    if grep -q "upstream mtproto_backend" "$STREAM_CONF"; then
        print_success "upstream mtproto_backend настроен"
        
        BACKEND_PORT=$(grep -A2 "upstream mtproto_backend" "$STREAM_CONF" | grep "server" | sed 's/.*127\.0\.0\.1:\([0-9]*\).*/\1/')
        echo "   Backend порт: $BACKEND_PORT"
        
        if [ "$BACKEND_PORT" != "10443" ]; then
            print_warning "Backend порт ($BACKEND_PORT) не равен 10443"
        fi
    else
        print_error "upstream mtproto_backend НЕ НАЙДЕН в stream.conf"
    fi
    
    # Проверяем map для MTProto домена
    if grep -q "russia3-t.vline.online.*mtproto_backend" "$STREAM_CONF"; then
        print_success "Домен russia3-t.vline.online маршрутизируется на mtproto_backend"
    else
        print_error "Домен russia3-t.vline.online НЕ НАЙДЕН в map"
    fi
else
    print_error "stream.conf не найден: $STREAM_CONF"
fi

echo

# Nginx конфиг MTProto домена
NGINX_CONF="/opt/remnanode/sites-available/russia3-t.vline.online"
if [ -f "$NGINX_CONF" ]; then
    print_success "Nginx конфиг MTProto домена найден"
    
    # Проверяем listen
    if grep -q "listen 10443 ssl proxy_protocol" "$NGINX_CONF"; then
        print_success "Nginx слушает порт 10443"
    else
        print_error "Nginx НЕ слушает порт 10443"
    fi
    
    # Проверяем proxy_pass
    if grep -q "proxy_pass http://127.0.0.1:8888" "$NGINX_CONF"; then
        print_success "Nginx проксирует на 127.0.0.1:8888"
    else
        PROXY_TARGET=$(grep "proxy_pass" "$NGINX_CONF" | sed 's/.*proxy_pass \(.*\);/\1/')
        print_error "Nginx проксирует на: $PROXY_TARGET (ожидалось http://127.0.0.1:8888)"
    fi
else
    print_error "Nginx конфиг не найден: $NGINX_CONF"
fi

echo

# 4. Проверка SSL сертификата
print_header "4. ПРОВЕРКА SSL СЕРТИФИКАТА"
echo

SSL_CERT="/etc/letsencrypt/live/russia3-t.vline.online/fullchain.pem"
if [ -f "$SSL_CERT" ]; then
    print_success "SSL сертификат найден"
    
    # Проверяем срок действия
    EXPIRES=$(openssl x509 -in "$SSL_CERT" -noout -enddate | sed 's/notAfter=//')
    echo "   Истекает: $EXPIRES"
else
    print_error "SSL сертификат не найден: $SSL_CERT"
fi

echo

# 5. Проверка Firewall
print_header "5. ПРОВЕРКА FIREWALL"
echo

# Проверяем UFW
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | grep "Status:" | awk '{print $2}')
    if [ "$UFW_STATUS" = "active" ]; then
        print_warning "UFW активен"

        if ufw status | grep -q "443.*ALLOW"; then
            print_success "Порт 443 разрешен в UFW"
        else
            print_error "Порт 443 НЕ разрешен в UFW"
            echo "   Разрешите: sudo ufw allow 443/tcp"
        fi
    else
        print_info "UFW неактивен"
    fi
else
    print_info "UFW не установлен"
fi

echo

# Проверяем iptables
if command -v iptables &> /dev/null; then
    IPTABLES_443=$(iptables -L INPUT -n | grep -E "tcp.*:443|tcp dpt:443" | grep ACCEPT)
    if [ -n "$IPTABLES_443" ]; then
        print_success "Порт 443 разрешен в iptables"
    else
        print_warning "Порт 443 может быть заблокирован в iptables"
        echo "   Проверьте: sudo iptables -L INPUT -n | grep 443"
    fi
fi

echo

# 6. Тест подключения
print_header "6. ТЕСТ ЛОКАЛЬНОГО ПОДКЛЮЧЕНИЯ"
echo

# Тест MTProto порта
print_info "Тестируем подключение к MTProto (127.0.0.1:8888)..."
if timeout 2 bash -c "</dev/tcp/127.0.0.1/8888" 2>/dev/null; then
    print_success "Порт 8888 доступен"
else
    print_error "Порт 8888 недоступен"
fi

echo

# Тест Nginx backend порта
print_info "Тестируем подключение к Nginx backend (127.0.0.1:10443)..."
if timeout 2 bash -c "</dev/tcp/127.0.0.1/10443" 2>/dev/null; then
    print_success "Порт 10443 доступен"
else
    print_error "Порт 10443 недоступен"
fi

echo

# Тест внешнего порта
print_info "Тестируем подключение к внешнему порту (127.0.0.1:443)..."
if timeout 2 bash -c "</dev/tcp/127.0.0.1/443" 2>/dev/null; then
    print_success "Порт 443 доступен локально"
else
    print_error "Порт 443 недоступен локально"
fi

echo

# 7. Тест DNS и внешнего доступа
print_header "7. ТЕСТ DNS И ВНЕШНЕГО ДОСТУПА"
echo

MTPROTO_DOMAIN="russia3-t.vline.online"

# Проверяем DNS
print_info "Проверяем DNS резолв для $MTPROTO_DOMAIN..."
if command -v dig &> /dev/null; then
    DNS_RESULT=$(dig +short $MTPROTO_DOMAIN | head -1)
    if [ -n "$DNS_RESULT" ]; then
        print_success "DNS резолвится: $DNS_RESULT"
    else
        print_error "DNS не резолвится"
        echo "   Проверьте настройки DNS для домена"
    fi
else
    print_info "dig не установлен, пропускаем DNS проверку"
fi

echo

# Тест TLS подключения к домену
print_info "Тестируем TLS подключение к $MTPROTO_DOMAIN:443..."
if command -v openssl &> /dev/null; then
    TLS_TEST=$(timeout 5 openssl s_client -connect $MTPROTO_DOMAIN:443 -servername $MTPROTO_DOMAIN 2>&1 </dev/null)

    if echo "$TLS_TEST" | grep -q "Verify return code: 0"; then
        print_success "TLS подключение успешно (сертификат валиден)"
    elif echo "$TLS_TEST" | grep -q "CONNECTED"; then
        print_warning "TLS подключение установлено, но сертификат может быть невалидным"
    else
        print_error "Не удалось установить TLS подключение"
        echo "   Проверьте firewall и DNS"
    fi
else
    print_info "openssl не установлен, пропускаем TLS тест"
fi

echo

# 6. Логи контейнеров
print_header "8. ПОСЛЕДНИЕ ЛОГИ КОНТЕЙНЕРОВ"
echo

print_info "MTProto логи (последние 10 строк):"
docker logs --tail 10 mtprotoproxy 2>&1 | sed 's/^/   /'

echo
echo

print_info "Nginx логи (последние 10 строк):"
docker logs --tail 10 remnawave-nginx 2>&1 | sed 's/^/   /'

echo

# 7. Итоги и рекомендации
print_header "9. ИТОГИ И РЕКОМЕНДАЦИИ"
echo

# Проверяем критичные проблемы
CRITICAL_ISSUES=0

if ! docker ps --filter "name=mtprotoproxy" --format "{{.Status}}" | grep -q "Up"; then
    print_error "MTProto контейнер не запущен"
    echo "   Запустите: cd /opt/MTProto_Proxy && sudo docker compose up -d --build"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if ! docker ps --filter "name=remnawave-nginx" --format "{{.Status}}" | grep -q "Up"; then
    print_error "Nginx контейнер не запущен"
    echo "   Запустите: cd /opt/remnanode && sudo docker compose up -d"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if ! ss -tulpn | grep -q ":8888"; then
    print_error "MTProto не слушает порт 8888"
    echo "   Проверьте config.py и перезапустите контейнер"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if ! ss -tulpn | grep -q ":10443"; then
    print_error "Nginx не слушает порт 10443"
    echo "   Проверьте Nginx конфиг и перезапустите контейнер"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if ! ss -tulpn | grep -q ":443"; then
    print_error "Nginx не слушает порт 443"
    echo "   Проверьте stream.conf и перезапустите контейнер"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

echo

if [ $CRITICAL_ISSUES -eq 0 ]; then
    print_success "Все критичные проверки пройдены!"
    echo
    print_info "Если прокси всё ещё не работает, проверьте:"
    echo "   1. Firewall (разрешен ли порт 443 извне)"
    echo "      sudo ufw allow 443/tcp && sudo ufw reload"
    echo "      или: sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT"
    echo
    echo "   2. DNS (резолвится ли домен russia3-t.vline.online на ваш IP)"
    echo "      nslookup russia3-t.vline.online"
    echo
    echo "   3. Внешний доступ (попробуйте с другой машины)"
    echo "      telnet russia3-t.vline.online 443"
    echo "      или: curl -v https://russia3-t.vline.online"
    echo
    echo "   4. Проверьте ссылку для подключения:"
    echo "      cat /opt/MTProto_Proxy/proxy_link.txt"
    echo
    print_info "📊 Статистика MTProto (должна увеличиваться при подключениях):"
    echo "   docker logs --tail 5 mtprotoproxy | grep 'Stats'"
else
    print_error "Найдено критичных проблем: $CRITICAL_ISSUES"
    echo
    print_info "Исправьте проблемы выше и запустите диагностику снова:"
    echo "   sudo bash diagnose_mtproto.sh"
fi

echo
print_header "ДИАГНОСТИКА ЗАВЕРШЕНА"
echo
