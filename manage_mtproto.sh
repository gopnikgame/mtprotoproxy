#!/bin/bash

# Константы
REPO_URL="https://github.com/gopnikgame/mtprotoproxy"
INSTALL_DIR="/opt/MTProto_Proxy"
REMNANODE_DIR="/opt/remnanode"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода заголовка
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
}

# Функция для вывода успеха
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Функция для вывода ошибки
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Функция для вывода предупреждения
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Проверка запуска от root для certbot
check_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Клонирование репозитория
clone_repository() {
    print_header "Клонирование репозитория MTProto Proxy"

    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Директория $INSTALL_DIR уже существует"
        print_warning "Удалить и клонировать заново? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            sudo rm -rf "$INSTALL_DIR"
            print_success "Старая директория удалена"
        else
            print_warning "Используем существующую директорию"
            cd "$INSTALL_DIR" || exit 1
            return 0
        fi
    fi

    print_warning "Клонирование репозитория..."
    if ! command -v git &> /dev/null; then
        print_error "Git не установлен"
        print_warning "Установить git? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install -y git
        else
            exit 1
        fi
    fi

    sudo git clone "$REPO_URL" "$INSTALL_DIR"
    if [ $? -eq 0 ]; then
        print_success "Репозиторий успешно клонирован в $INSTALL_DIR"
        sudo chmod -R 755 "$INSTALL_DIR"
        cd "$INSTALL_DIR" || exit 1
    else
        print_error "Ошибка клонирования репозитория"
        exit 1
    fi

    echo
}

# Проверка установки
check_installation() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "MTProto Proxy не установлен в $INSTALL_DIR"
        print_warning "Запустите сначала: Клонировать репозиторий"
        return 1
    fi

    if [ ! -d "$REMNANODE_DIR" ]; then
        print_error "Remnanode не найден в $REMNANODE_DIR"
        print_warning "Убедитесь что Remnanode установлен и работает"
        return 1
    fi

    return 0
}

# Установка зависимостей
install_dependencies() {
    print_header "Установка зависимостей"

    if ! command -v python3 &> /dev/null; then
        print_error "Python3 не установлен"
        print_warning "Установить Python3? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install -y python3 python3-pip
        else
            exit 1
        fi
    fi
    print_success "Python3 установлен"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен"
        exit 1
    fi
    print_success "Docker установлен"
    
    if ! command -v docker-compose &> /dev/null; then
        print_warning "docker-compose не найден, проверка docker compose..."
        if ! docker compose version &> /dev/null; then
            print_error "Docker Compose не установлен"
            exit 1
        fi
        print_success "Docker Compose (plugin) установлен"
    else
        print_success "Docker Compose установлен"
    fi
    
    if ! command -v certbot &> /dev/null; then
        print_warning "Certbot не установлен. Установить? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install -y certbot
            print_success "Certbot установлен"
        else
            print_error "Certbot необходим для получения SSL сертификатов"
            exit 1
        fi
    else
        print_success "Certbot установлен"
    fi
    
    echo
}

# Запуск скрипта настройки
run_setup() {
    print_header "Запуск настройки MTProto Proxy"

    cd "$INSTALL_DIR" || exit 1

    if [ -f "config_example.json" ]; then
        print_warning "Найден config_example.json. Использовать его? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            python3 setup_mtproto_nginx.py --config config_example.json
        else
            python3 setup_mtproto_nginx.py --interactive
        fi
    else
        python3 setup_mtproto_nginx.py --interactive
    fi

    echo
}

# Получение SSL сертификата
get_ssl_cert() {
    print_header "Получение SSL сертификата"

    if ! check_root; then
        print_error "Для получения сертификата нужны права root"
        print_warning "Запустите: sudo bash $0 cert"
        exit 1
    fi

    echo -n "Введите домен для MTProto прокси: "
    read -r domain

    print_warning "Получение сертификата для домена: $domain"
    print_warning "Убедитесь что домен указывает на этот сервер!"
    echo

    # Останавливаем контейнеры если запущены
    cd "$REMNANODE_DIR" 2>/dev/null
    if [ -f "docker-compose.yml" ]; then
        print_warning "Остановка Remnawave контейнеров..."
        docker compose down 2>/dev/null || true
    fi

    # Останавливаем MTProto если запущен
    cd "$INSTALL_DIR" 2>/dev/null
    if [ -f "docker-compose.yml" ]; then
        print_warning "Остановка MTProto контейнера..."
        docker-compose down 2>/dev/null || true
    fi

    # Получаем сертификат
    certbot certonly --standalone -d "$domain"

    if [ $? -eq 0 ]; then
        print_success "Сертификат успешно получен"

        # Запускаем контейнеры обратно
        print_warning "Запуск контейнеров..."
        cd "$REMNANODE_DIR"
        docker compose up -d 2>/dev/null || true

        cd "$INSTALL_DIR"
        docker-compose up -d 2>/dev/null || true

        print_success "Контейнеры запущены"
    else
        print_error "Ошибка получения сертификата"
        exit 1
    fi

    echo
}

# Запуск Docker контейнеров
start_containers() {
    print_header "Запуск Docker контейнеров"

    print_warning "Запуск контейнеров..."
    echo

    # Запускаем Remnawave (Nginx)
    print_warning "1. Запуск Remnawave Nginx..."
    cd "$REMNANODE_DIR" || exit 1

    if docker compose up -d 2>/dev/null; then
        print_success "Remnawave Nginx запущен (docker compose)"
    else
        print_error "Ошибка запуска Remnawave"
        exit 1
    fi

    # Запускаем MTProto Proxy
    print_warning "2. Запуск MTProto Proxy..."
    cd "$INSTALL_DIR" || exit 1

    if docker-compose up -d --build 2>/dev/null; then
        print_success "MTProto Proxy запущен (docker-compose)"
    else
        print_error "Ошибка запуска MTProto Proxy"
        print_error "Убедитесь что все файлы на месте (mtprotoproxy.py, pyaes/, config.py)"
        exit 1
    fi

    echo
    print_success "Все контейнеры запущены!"

    # Показываем статус
    echo
    print_warning "Статус контейнеров:"
    docker ps --filter "name=mtprotoproxy" --filter "name=remnawave-nginx" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

    echo
}

# Просмотр логов
view_logs() {
    print_header "Просмотр логов"
    
    echo "1) MTProto Proxy"
    echo "2) Nginx"
    echo "3) Remnanode"
    echo -n "Выберите сервис (1-3): "
    read -r choice
    
    case $choice in
        1)
            docker logs -f mtprotoproxy
            ;;
        2)
            docker logs -f remnawave-nginx
            ;;
        3)
            docker logs -f remnanode
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac
}

# Статус контейнеров
check_status() {
    print_header "Статус контейнеров"
    
    docker ps -a | grep -E "mtprotoproxy|remnawave-nginx|remnanode" || print_warning "Контейнеры не найдены"
    
    echo
}

# Перезапуск сервиса
restart_service() {
    print_header "Перезапуск сервиса"

    echo "1) MTProto Proxy"
    echo "2) Remnawave Nginx"
    echo "3) Оба контейнера"
    echo -n "Выберите опцию (1-3): "
    read -r choice

    case $choice in
        1)
            cd "$INSTALL_DIR" || exit 1
            docker-compose restart 2>/dev/null
            print_success "MTProto Proxy перезапущен"
            ;;
        2)
            cd "$REMNANODE_DIR" || exit 1
            docker compose restart remnawave-nginx 2>/dev/null
            print_success "Remnawave Nginx перезапущен"
            ;;
        3)
            print_warning "Перезапуск всех контейнеров..."

            cd "$INSTALL_DIR" || exit 1
            docker-compose restart 2>/dev/null
            print_success "MTProto Proxy перезапущен"

            cd "$REMNANODE_DIR" || exit 1
            docker compose restart 2>/dev/null
            print_success "Remnawave перезапущен"
            ;;
        *)
            print_error "Неверный выбор"
            ;;
    esac

    echo
}

# Показать ссылку для подключения
show_proxy_link() {
    print_header "Ссылка для подключения к прокси"

    cd "$INSTALL_DIR" || exit 1

    if [ ! -f "config.py" ]; then
        print_error "Файл config.py не найден. Сначала выполните настройку."
        exit 1
    fi

    # Проверяем наличие сохраненной ссылки
    if [ -f "proxy_link.txt" ]; then
        print_success "Найдена сохраненная ссылка:"
        echo
        cat proxy_link.txt
        echo
        return
    fi

    # Извлекаем секрет из config.py
    secret=$(grep -oP '(?<=")[0-9a-f]{32}(?=")' config.py | head -1)

    if [ -z "$secret" ]; then
        print_error "Не удалось извлечь секрет из config.py"
        exit 1
    fi

    echo -n "Введите домен MTProto прокси: "
    read -r domain

    # Формируем TLS секрет
    domain_hex=$(echo -n "$domain" | xxd -p | tr -d '\n')
    tls_secret="ee${domain_hex}${secret}"

    proxy_link="https://t.me/proxy?server=${domain}&port=443&secret=${tls_secret}"

    echo
    print_success "Ссылка для подключения:"
    echo -e "${GREEN}${proxy_link}${NC}"
    echo

    # QR код если установлен qrencode
    if command -v qrencode &> /dev/null; then
        print_warning "Хотите создать QR-код? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            qrencode -t UTF8 "$proxy_link"
        fi
    fi

    echo
}

# Обновление сертификатов
renew_certs() {
    print_header "Обновление SSL сертификатов"

    if ! check_root; then
        print_error "Для обновления сертификатов нужны права root"
        print_warning "Запустите: sudo bash $0 renew-certs"
        exit 1
    fi

    cd "$REMNANODE_DIR" || exit 1
    
    if [ -f "renew-certs.sh" ]; then
        bash renew-certs.sh
    else
        print_warning "Скрипт renew-certs.sh не найден, используем certbot напрямую"
        certbot renew
        docker restart remnawave-nginx
    fi
    
    cd ..
    echo
}

# Восстановление из резервных копий
restore_backup() {
    print_header "Восстановление из резервных копий"
    
    print_warning "Найденные резервные копии:"
    find . -name "*.backup" -type f
    
    echo
    print_warning "Восстановить ВСЕ файлы из резервных копий? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        find . -name "*.backup" -type f | while read -r backup_file; do
            original_file="${backup_file%.backup}"
            cp "$backup_file" "$original_file"
            print_success "Восстановлен: $original_file"
        done
    else
        print_warning "Восстановление отменено"
    fi
    
    echo
}

# Главное меню
show_menu() {
    print_header "MTProto Proxy - Управление"

    echo "Установка и настройка:"
    echo "  1) Проверить зависимости"
    echo "  2) Настроить MTProto Proxy (автоматически: SSL + запуск)"
    echo "  3) Получить SSL сертификат (вручную)"
    echo ""
    echo "Управление контейнерами:"
    echo "  4) Запустить Docker контейнеры"
    echo "  5) Просмотреть логи"
    echo "  6) Проверить статус"
    echo "  7) Перезапустить сервис"
    echo ""
    echo "Дополнительно:"
    echo "  8) Показать ссылку для подключения"
    echo "  9) Обновить SSL сертификаты"
    echo "  10) Восстановить из резервных копий"
    echo ""
    echo "  0) Выход"
    echo
    echo -n "Выберите опцию: "
}

# Главный цикл
main() {
    if [ "$1" == "cert" ]; then
        get_ssl_cert
        exit 0
    elif [ "$1" == "renew-certs" ]; then
        renew_certs
        exit 0
    elif [ "$1" == "setup" ]; then
        install_dependencies
        run_setup
        exit 0
    elif [ "$1" == "start" ]; then
        start_containers
        exit 0
    fi
    
    while true; do
        show_menu
        read -r choice
        echo
        
        case $choice in
            1) install_dependencies ;;
            2) run_setup ;;
            3) get_ssl_cert ;;
            4) start_containers ;;
            5) view_logs ;;
            6) check_status ;;
            7) restart_service ;;
            8) show_proxy_link ;;
            9) renew_certs ;;
            10) restore_backup ;;
            0) print_success "До свидания!"; exit 0 ;;
            *) print_error "Неверный выбор" ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
        clear
    done
}

# Запуск
main "$@"
