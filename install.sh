#!/bin/bash

# Скрипт быстрой установки MTProto Proxy для Remnawave
# Использование: wget -O - https://raw.githubusercontent.com/gopnikgame/mtprotoproxy/master/install.sh | sudo bash

set -e

# Константы
REPO_URL="https://github.com/gopnikgame/mtprotoproxy"
INSTALL_DIR="/opt/MTProto_Proxy"
REMNANODE_DIR="/opt/remnanode"

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
    echo
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

# Проверка root
if [ "$EUID" -ne 0 ]; then
    print_error "Запустите скрипт с правами root (sudo)"
    exit 1
fi

print_header "MTProto Proxy - Автоматическая установка"

# Проверка Remnanode
if [ ! -d "$REMNANODE_DIR" ]; then
    print_error "Remnanode не найден в $REMNANODE_DIR"
    print_warning "Сначала установите и настройте Remnawave"
    exit 1
fi
print_success "Remnanode найден"

# Установка Git
if ! command -v git &> /dev/null; then
    print_warning "Установка Git..."
    apt update
    apt install -y git
fi
print_success "Git установлен"

# Установка Python3
if ! command -v python3 &> /dev/null; then
    print_warning "Установка Python3..."
    apt update
    apt install -y python3 python3-pip
fi
print_success "Python3 установлен"

# Установка Docker
if ! command -v docker &> /dev/null; then
    print_warning "Установка Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
fi
print_success "Docker установлен"

# Установка Docker Compose
if ! docker compose version &> /dev/null; then
    if ! command -v docker-compose &> /dev/null; then
        print_warning "Установка Docker Compose..."
        apt update
        apt install -y docker-compose-plugin
    fi
fi
print_success "Docker Compose установлен"

# Установка Certbot
if ! command -v certbot &> /dev/null; then
    print_warning "Установка Certbot..."
    apt update
    apt install -y certbot
fi
print_success "Certbot установлен"

# Клонирование репозитория
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Директория $INSTALL_DIR уже существует"
    print_warning "Обновление из репозитория..."
    cd "$INSTALL_DIR"

    # Проверяем наличие локальных изменений
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_warning "Обнаружены локальные изменения в файлах"

        # Создаем backup локальных изменений
        BACKUP_DIR="/opt/MTProto_Proxy_backup_$(date +%Y%m%d_%H%M%S)"
        print_warning "Создание резервной копии в: $BACKUP_DIR"

        # Копируем измененные файлы
        mkdir -p "$BACKUP_DIR"
        git diff --name-only HEAD | while read file; do
            if [ -f "$file" ]; then
                mkdir -p "$BACKUP_DIR/$(dirname "$file")"
                cp "$file" "$BACKUP_DIR/$file"
            fi
        done

        # Показываем какие файлы были изменены
        echo "Измененные файлы (сохранены в backup):"
        git diff --name-only HEAD | sed 's/^/  - /'

        print_success "Резервная копия создана: $BACKUP_DIR"

        # Сбрасываем локальные изменения
        print_warning "Сброс локальных изменений..."
        git reset --hard HEAD
    fi

    # Обновляем из репозитория
    print_warning "Загрузка обновлений..."
    git fetch origin master
    git reset --hard origin/master

    print_success "Репозиторий обновлен до последней версии"
else
    print_warning "Клонирование репозитория..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    print_success "Репозиторий клонирован"
fi
print_success "Репозиторий готов"

cd "$INSTALL_DIR"

# Скачивание необходимых файлов MTProto если отсутствуют
if [ ! -f "mtprotoproxy.py" ]; then
    print_warning "Скачивание mtprotoproxy.py..."
    wget -q https://raw.githubusercontent.com/alexbers/mtprotoproxy/master/mtprotoproxy.py
    chmod +x mtprotoproxy.py
    print_success "mtprotoproxy.py скачан"
fi

if [ ! -d "pyaes" ]; then
    print_warning "Скачивание библиотеки pyaes..."
    git clone --depth 1 https://github.com/alexbers/mtprotoproxy temp_mtproto
    mv temp_mtproto/pyaes .
    rm -rf temp_mtproto
    print_success "pyaes скачан"
fi

# Сделать скрипты исполняемыми
chmod +x manage_mtproto.sh 2>/dev/null || true
chmod +x setup_mtproto_nginx.py 2>/dev/null || true

# Создание симлинка для быстрого запуска
if [ -L "/usr/local/bin/MTProto" ]; then
    print_warning "Симлинк /usr/local/bin/MTProto уже существует, обновление..."
    rm -f /usr/local/bin/MTProto
fi

ln -s "$INSTALL_DIR/manage_mtproto.sh" /usr/local/bin/MTProto
if [ $? -eq 0 ]; then
    print_success "Создан симлинк: MTProto -> $INSTALL_DIR/manage_mtproto.sh"
    print_success "Теперь можно запускать командой: MTProto"
else
    print_warning "Не удалось создать симлинк (требуются права root)"
    print_warning "Создайте вручную: sudo ln -s $INSTALL_DIR/manage_mtproto.sh /usr/local/bin/MTProto"
fi

print_success "Установка завершена!"
echo
print_header "Следующие шаги"
echo "1. Запустите интерактивную настройку ОДНОЙ КОМАНДОЙ:"
echo "   MTProto"
echo
echo "   Или полный путь:"
echo "   cd $INSTALL_DIR"
echo "   sudo python3 setup_mtproto_nginx.py --interactive"
echo
echo "   Скрипт автоматически:"
echo "   ✓ Обнаружит существующую настройку (если есть)"
echo "   ✓ Предложит варианты действий"
echo "   ✓ Получит SSL сертификат (если нужно)"
echo "   ✓ Настроит конфигурации"
echo "   ✓ Запустит все контейнеры"
echo "   ✓ Выдаст готовую ссылку для подключения"
echo
echo "Документация:"
echo "  - SMART_DETECTION.md - Умная проверка существующей настройки"
echo "  - EXAMPLE_USAGE.md - Примеры использования"
echo "  - ARCHITECTURE.md - Архитектура проектов"
echo "  - README.md - Общая информация"
echo

# Показываем информацию о backup если была создана
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo
    print_header "Резервная копия локальных изменений"
    echo "Ваши локальные изменения сохранены в:"
    echo "  $BACKUP_DIR"
    echo
    echo "Если нужно восстановить измененные файлы:"
    echo "  cp -r $BACKUP_DIR/* $INSTALL_DIR/"
    echo
fi

print_success "Готово! Удачной настройки!"
