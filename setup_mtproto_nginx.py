#!/usr/bin/env python3
"""
Скрипт автоматической настройки MTProto Proxy через Nginx для работы на сервере с нодой Remnawave
"""

import os
import re
import sys
import json
import secrets
import argparse
from pathlib import Path


class MTProtoNginxSetup:
    def __init__(self, config_data):
        self.config = config_data
        self.base_path = Path(__file__).parent
        # Путь к рабочей директории remnanode
        self.remnawave_path = Path("/opt/remnanode")
        self.sites_available = self.remnawave_path / "sites-available"

        # Определяем какую версию docker-compose использовать
        self.docker_compose_cmd = self._detect_docker_compose()

    def _detect_docker_compose(self):
        """Определяет доступную версию docker-compose"""
        import subprocess

        # Проверяем docker compose (v2 plugin)
        try:
            result = subprocess.run(
                ['docker', 'compose', 'version'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print("✓ Обнаружен Docker Compose v2 (plugin)")
                return ['docker', 'compose']
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        # Проверяем docker-compose (v1 standalone)
        try:
            result = subprocess.run(
                ['docker-compose', 'version'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print("✓ Обнаружен Docker Compose v1 (standalone)")
                return ['docker-compose']
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        # По умолчанию пытаемся v2
        print("⚠ Не удалось определить версию Docker Compose, использую docker compose")
        return ['docker', 'compose']

    def validate_domain(self, domain):
        """Проверка корректности домена"""
        pattern = r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
        return re.match(pattern, domain) is not None

    def check_port_available(self, port):
        """Проверка доступности порта"""
        import socket
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('127.0.0.1', port))
                return True
        except OSError:
            return False

    def generate_secret(self):
        """Генерация секрета для MTProto"""
        return secrets.token_hex(16)
    
    def backup_file(self, filepath):
        """Создание резервной копии файла"""
        if os.path.exists(filepath):
            backup_path = str(filepath) + '.backup'
            with open(filepath, 'r') as src, open(backup_path, 'w') as dst:
                dst.write(src.read())
            print(f"✓ Создана резервная копия: {backup_path}")

    def parse_existing_stream_conf(self):
        """Парсинг существующего stream.conf для извлечения доменов"""
        stream_conf_path = self.remnawave_path / "stream.conf"
        existing_domains = []
        existing_upstreams = {}
        xray_reality_domain = None

        if not os.path.exists(stream_conf_path):
            return existing_domains, existing_upstreams, xray_reality_domain

        try:
            with open(stream_conf_path, 'r') as f:
                content = f.read()

            # Извлекаем домены из map блока
            map_pattern = r'map\s+\$ssl_preread_server_name\s+\$backend_name\s*\{([^}]+)\}'
            map_match = re.search(map_pattern, content, re.DOTALL)

            if map_match:
                map_content = map_match.group(1)
                # Ищем строки вида: domain    backend;
                domain_pattern = r'([a-zA-Z0-9\.\-]+)\s+([a-zA-Z0-9_]+);'
                for match in re.finditer(domain_pattern, map_content):
                    domain = match.group(1).strip()
                    backend = match.group(2).strip()
                    if domain != 'default':
                        existing_domains.append(domain)
                        existing_upstreams[domain] = backend
                        # Проверяем xray_reality
                        if backend == 'xray_reality':
                            xray_reality_domain = domain

            print(f"✓ Найдено существующих доменов: {len(existing_domains)}")
            if existing_domains:
                for domain in existing_domains:
                    backend = existing_upstreams.get(domain, 'unknown')
                    print(f"  - {domain} -> {backend}")

        except Exception as e:
            print(f"⚠ Ошибка при парсинге stream.conf: {e}")

        return existing_domains, existing_upstreams, xray_reality_domain

    def parse_existing_80_conf(self):
        """Парсинг существующего 80.conf для извлечения доменов"""
        conf_80_path = self.sites_available / "80.conf"
        existing_domains = []

        if not os.path.exists(conf_80_path):
            return existing_domains

        try:
            with open(conf_80_path, 'r') as f:
                content = f.read()

            # Ищем server_name
            server_name_pattern = r'server_name\s+([^;]+);'
            match = re.search(server_name_pattern, content)

            if match:
                domains_str = match.group(1).strip()
                existing_domains = domains_str.split()
                print(f"✓ Найдено доменов в 80.conf: {len(existing_domains)}")

        except Exception as e:
            print(f"⚠ Ошибка при парсинге 80.conf: {e}")

        return existing_domains

    def parse_existing_mtproto_config(self):
        """Парсинг существующего config.py для извлечения параметров MTProto"""
        config_path = self.base_path / "config.py"
        mtproto_config = {}

        if not config_path.exists():
            return mtproto_config

        try:
            with open(config_path, 'r') as f:
                content = f.read()

            # Извлекаем PORT
            port_match = re.search(r'PORT\s*=\s*(\d+)', content)
            if port_match:
                mtproto_config['port'] = int(port_match.group(1))

            # Извлекаем SECRET из USERS
            secret_match = re.search(r'"tg"\s*:\s*"([a-fA-F0-9]{32})"', content)
            if secret_match:
                mtproto_config['secret'] = secret_match.group(1)

            # Извлекаем TLS_DOMAIN
            tls_match = re.search(r'TLS_DOMAIN\s*=\s*"([^"]+)"', content)
            if tls_match:
                mtproto_config['tls_domain'] = tls_match.group(1)

            # Извлекаем AD_TAG
            ad_match = re.search(r'AD_TAG\s*=\s*"([^"]*)"', content)
            if ad_match:
                mtproto_config['ad_tag'] = ad_match.group(1)

            # Проверяем режимы
            tls_mode_match = re.search(r'"tls"\s*:\s*(True|False)', content)
            if tls_mode_match:
                mtproto_config['tls_mode'] = tls_mode_match.group(1) == 'True'

        except Exception as e:
            print(f"⚠ Ошибка при парсинге config.py: {e}")

        return mtproto_config

    def parse_backend_port_from_stream_conf(self):
        """Извлекает backend порт для mtproto_backend из stream.conf"""
        stream_conf_path = self.remnawave_path / "stream.conf"

        if not stream_conf_path.exists():
            return None

        try:
            with open(stream_conf_path, 'r') as f:
                content = f.read()

            # Ищем upstream mtproto_backend
            pattern = r'upstream\s+mtproto_backend\s*\{[^}]*server\s+127\.0\.0\.1:(\d+)'
            match = re.search(pattern, content, re.DOTALL)

            if match:
                return int(match.group(1))
        except Exception as e:
            print(f"⚠ Ошибка при парсинге backend порта: {e}")

        return None

    def detect_existing_mtproto_setup(self):
        """Определяет существующую настройку MTProto (домен из stream.conf + config.py)"""
        existing_domains, existing_upstreams, _ = self.parse_existing_stream_conf()

        # Ищем домен с mtproto_backend
        mtproto_domain = None
        for domain, backend in existing_upstreams.items():
            if backend == 'mtproto_backend':
                mtproto_domain = domain
                break

        if not mtproto_domain:
            return None, None

        # Парсим config.py
        mtproto_config = self.parse_existing_mtproto_config()

        # Парсим backend порт из stream.conf
        backend_port = self.parse_backend_port_from_stream_conf()
        if backend_port:
            mtproto_config['backend_port'] = backend_port

        return mtproto_domain, mtproto_config

    def show_current_mtproto_config(self, domain, config_data):
        """Вывод текущей конфигурации MTProto"""
        print("\n" + "="*60)
        print("📋 НАЙДЕНА СУЩЕСТВУЮЩАЯ НАСТРОЙКА MTPROTO")
        print("="*60 + "\n")

        print(f"🌐 Домен:           {domain}")

        if config_data:
            if 'port' in config_data:
                print(f"🔌 Порт (прокси):   {config_data['port']}")
            else:
                print(f"⚠  Порт (прокси):   НЕ НАСТРОЕН")

            if 'backend_port' in config_data:
                print(f"🔌 Порт (backend):  {config_data['backend_port']}")
            else:
                print(f"⚠  Порт (backend):  НЕ НАСТРОЕН")

            if 'secret' in config_data:
                print(f"🔑 Секрет:          {config_data['secret']}")
            else:
                print(f"⚠  Секрет:          НЕ НАСТРОЕН")

            if 'tls_domain' in config_data:
                print(f"🎭 TLS маскировка:  {config_data['tls_domain']}")
            else:
                print(f"⚠  TLS маскировка:  НЕ НАСТРОЕНА")

            if 'ad_tag' in config_data and config_data['ad_tag']:
                print(f"📢 AD Tag:          {config_data['ad_tag']}")
            else:
                print(f"ℹ️  AD Tag:          не установлен")

            if 'tls_mode' in config_data:
                mode_status = "✓ Включен" if config_data['tls_mode'] else "✗ Выключен"
                print(f"🔒 TLS режим:       {mode_status}")
        else:
            print("⚠  config.py не найден или пуст")

        # Проверка SSL сертификата
        cert_path = Path(f"/etc/letsencrypt/live/{domain}/fullchain.pem")
        if cert_path.exists():
            print(f"✓ SSL сертификат:  установлен")
        else:
            print(f"⚠  SSL сертификат:  НЕ УСТАНОВЛЕН")

        # Проверка docker-compose.yml
        docker_compose_path = self.base_path / "docker-compose.yml"
        if docker_compose_path.exists():
            print(f"✓ Docker Compose:  настроен")
        else:
            print(f"⚠  Docker Compose:  НЕ НАСТРОЕН")

        # Проверка Nginx конфига
        nginx_conf_path = self.sites_available / domain
        if nginx_conf_path.exists():
            print(f"✓ Nginx конфиг:    создан")
        else:
            print(f"⚠  Nginx конфиг:    НЕ СОЗДАН")

        print()

    def validate_mtproto_setup(self, domain, config_data):
        """Проверяет корректность существующей настройки"""
        issues = []

        # Проверяем обязательные параметры
        if not config_data or 'port' not in config_data:
            issues.append("Порт не настроен в config.py")

        if not config_data or 'secret' not in config_data:
            issues.append("Секрет не настроен в config.py")

        if not config_data or 'tls_domain' not in config_data:
            issues.append("TLS домен не настроен в config.py")

        # Проверяем SSL сертификат
        cert_path = Path(f"/etc/letsencrypt/live/{domain}/fullchain.pem")
        if not cert_path.exists():
            issues.append(f"SSL сертификат не найден для {domain}")

        # Проверяем docker-compose.yml
        docker_compose_path = self.base_path / "docker-compose.yml"
        if not docker_compose_path.exists():
            issues.append("docker-compose.yml не найден")

        # Проверяем Nginx конфиг
        nginx_conf_path = self.sites_available / domain
        if not nginx_conf_path.exists():
            issues.append(f"Nginx конфигурация не найдена для {domain}")

        return issues

    def update_stream_conf(self):
        """Обновление stream.conf для MTProto прокси"""
        stream_conf_path = self.remnawave_path / "stream.conf"
        self.backup_file(stream_conf_path)

        # Парсим существующие настройки
        existing_domains, existing_upstreams, xray_reality_domain = self.parse_existing_stream_conf()

        mtproto_domain = self.config['mtproto_domain']
        mtproto_port = self.config.get('mtproto_backend_port', 10443)

        # Собираем все домены
        all_upstreams = existing_upstreams.copy()

        # Добавляем MTProto домен
        all_upstreams[mtproto_domain] = 'mtproto_backend'

        # Если был найден xray_reality в существующей конфигурации
        if xray_reality_domain and xray_reality_domain not in self.config:
            self.config['xray_reality_domain'] = xray_reality_domain

        # Формирование map блока
        map_entries = []
        for domain, backend in sorted(all_upstreams.items()):
            map_entries.append(f"    {domain}    {backend};")

        map_entries.append("    default                 nginx_backend;")

        content = f"""map $ssl_preread_server_name $backend_name {{
{chr(10).join(map_entries)}
}}

upstream nginx_backend {{
    server 127.0.0.1:8443;
}}

upstream mtproto_backend {{
    server 127.0.0.1:{mtproto_port};
}}

"""

        # Если есть xray_reality
        if xray_reality_domain or self.config.get('xray_reality_domain'):
            content += """upstream xray_reality {
    server 127.0.0.1:9443;
}

"""

        content += """server {
    listen 443 reuseport;
    listen [::]:443 reuseport;

    proxy_pass  $backend_name;
    ssl_preread on;
    proxy_protocol on;
}
"""

        with open(stream_conf_path, 'w') as f:
            f.write(content)

        print(f"✓ Обновлен {stream_conf_path}")
        print(f"  Всего доменов в конфигурации: {len(all_upstreams)}")
    
    def create_mtproto_nginx_conf(self):
        """Создание конфигурации Nginx для MTProto домена"""
        mtproto_domain = self.config['mtproto_domain']
        mtproto_port = self.config.get('mtproto_backend_port', 10443)
        mtproto_proxy_port = self.config.get('mtproto_proxy_port', 8888)
        conf_path = self.sites_available / mtproto_domain
        
        self.backup_file(conf_path)
        
        content = f"""server {{
    server_tokens off;
    server_name {mtproto_domain};
    listen {mtproto_port} ssl proxy_protocol;
    listen [::]:{mtproto_port} ssl proxy_protocol;
    http2 on;
    
    index index.html index.htm index.nginx-debian.html;
    root /var/www/html/;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
    ssl_certificate /etc/letsencrypt/live/{mtproto_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{mtproto_domain}/privkey.pem;

    # MTProto Proxy location
    location / {{
        proxy_pass http://127.0.0.1:{mtproto_proxy_port};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $proxy_protocol_addr;
        proxy_set_header X-Forwarded-For $proxy_protocol_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Таймауты для долгих соединений
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Отключаем буферизацию для прокси
        proxy_buffering off;
        proxy_request_buffering off;
    }}

    # Security
    set $safe "";
    if ($host !~* ^(.+\\.)?{re.escape(mtproto_domain)}$ ){{return 444;}}
    if ($scheme ~* https) {{set $safe 1;}}
    if ($ssl_server_name !~* ^(.+\\.)?{re.escape(mtproto_domain)}$ ) {{set $safe "${{safe}}0"; }}
    if ($safe = 10){{return 444;}}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;

    # Timeouts
    http2_max_concurrent_streams 1024;
    http2_body_preread_size      128k;
    keepalive_time               2h;
    keepalive_timeout            60s;
    keepalive_requests           2048;
    client_body_buffer_size      1m;
    client_body_timeout          600s;
    client_header_timeout        300s;
    large_client_header_buffers  8 16k;

    sendfile              on;
    tcp_nodelay           on;
    tcp_nopush            on;
    client_max_body_size  0;
}}
"""
        
        with open(conf_path, 'w') as f:
            f.write(content)
        
        print(f"✓ Создана конфигурация Nginx: {conf_path}")
    
    def update_80_conf(self):
        """Обновление конфигурации для порта 80 (HTTP)"""
        conf_80_path = self.sites_available / "80.conf"
        self.backup_file(conf_80_path)

        # Парсим существующие домены
        existing_domains = self.parse_existing_80_conf()

        # Добавляем MTProto домен если его еще нет
        mtproto_domain = self.config['mtproto_domain']
        if mtproto_domain not in existing_domains:
            existing_domains.append(mtproto_domain)

        domains_str = ' '.join(sorted(set(existing_domains)))

        content = f"""server {{
    listen 80;
    server_name {domains_str};

    # ACME challenges для обновления сертификатов
    location /.well-known/acme-challenge/ {{
        root /var/www/certbot;
        try_files $uri =404;
    }}

    # Все остальные запросы редиректим на HTTPS
    location / {{
        return 301 https://$host$request_uri;
    }}
}}
"""

        with open(conf_80_path, 'w') as f:
            f.write(content)

        print(f"✓ Обновлен {conf_80_path}")
        print(f"  Всего доменов: {len(existing_domains)}")
    
    def create_mtproto_config(self):
        """Создание конфигурации для MTProto прокси"""
        config_path = self.base_path / "config.py"
        self.backup_file(config_path)
        
        port = self.config.get('mtproto_proxy_port', 8888)
        secret = self.config.get('mtproto_secret', self.generate_secret())
        tls_domain = self.config.get('tls_domain', 'www.google.com')
        ad_tag = self.config.get('ad_tag', '')
        
        content = f"""PORT = {port}

# name -> secret (32 hex chars)
USERS = {{
    "tg":  "{secret}",
}}

MODES = {{
    # Classic mode, easy to detect
    "classic": False,

    # Makes the proxy harder to detect
    # Can be incompatible with very old clients
    "secure": False,

    # Makes the proxy even more hard to detect
    # Can be incompatible with old clients
    "tls": True
}}

# The domain for TLS mode, bad clients are proxied there
TLS_DOMAIN = "{tls_domain}"

"""
        
        if ad_tag:
            content += f'# Tag for advertising, obtainable from @MTProxybot\nAD_TAG = "{ad_tag}"\n'
        else:
            content += '# Tag for advertising, obtainable from @MTProxybot\n# AD_TAG = ""\n'
        
        with open(config_path, 'w') as f:
            f.write(content)
        
        print(f"✓ Создана конфигурация MTProto: {config_path}")
        print(f"  Секрет: {secret}")
        print(f"  Порт: {port}")
    

    def create_docker_compose(self):
        """Создание docker-compose.yml для MTProto Proxy в /opt/MTProto_Proxy/"""
        docker_compose_path = self.base_path / "docker-compose.yml"
        self.backup_file(docker_compose_path)

        mtproto_port = self.config.get('mtproto_proxy_port', 8888)

        # Проверяем наличие необходимых файлов
        required_files = {
            'mtprotoproxy.py': self.base_path / 'mtprotoproxy.py',
            'pyaes': self.base_path / 'pyaes',
            'Dockerfile': self.base_path / 'Dockerfile'
        }

        missing_files = []
        for name, path in required_files.items():
            if not path.exists():
                missing_files.append(str(path))

        if missing_files:
            print(f"⚠ Предупреждение: Не найдены следующие файлы:")
            for f in missing_files:
                print(f"  - {f}")
            print(f"⚠ Docker контейнер может не запуститься!")
            print(f"⚠ Убедитесь что mtprotoproxy.py и pyaes/ находятся в {self.base_path}")

        # Создаем docker-compose.yml для MTProto Proxy
        content = f"""version: '3.8'

services:
  # MTProto Proxy - работает отдельно от Remnawave
  # Интеграция через network_mode: host
  # Архитектура: Internet:443 → remnawave-nginx (SNI) → 127.0.0.1:10443 → 127.0.0.1:{mtproto_port}
  mtprotoproxy:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mtprotoproxy
    hostname: mtprotoproxy
    restart: always
    network_mode: host  # Обязательно для связи с Nginx из /opt/remnanode
    volumes:
      - ./config.py:/app/config.py:ro
      - ./mtprotoproxy.py:/app/mtprotoproxy.py:ro
      - ./pyaes:/app/pyaes:ro
    command: python3 /app/mtprotoproxy.py
    logging:
      driver: 'json-file'
      options:
        max-size: '30m'
        max-file: '5'
"""

        with open(docker_compose_path, 'w', encoding='utf-8') as f:
            f.write(content)

        print(f"✓ Создан docker-compose.yml: {docker_compose_path}")
        print(f"  Контейнер: mtprotoproxy")
        print(f"  Режим сети: host (127.0.0.1:{mtproto_port})")
        print(f"  Интеграция: через локальный порт с Nginx из /opt/remnanode")
    
    def create_dockerfile_if_not_exists(self):
        """Создание Dockerfile для MTProto если не существует"""
        dockerfile_path = self.base_path / "Dockerfile"
        
        if not dockerfile_path.exists():
            content = """FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

COPY mtprotoproxy.py /app/
COPY config.py /app/
COPY pyaes /app/pyaes

EXPOSE 443
EXPOSE 8888

CMD ["python3", "mtprotoproxy.py"]
"""
            with open(dockerfile_path, 'w') as f:
                f.write(content)
            
            print(f"✓ Создан Dockerfile")
    
    def obtain_ssl_certificate(self):
        """Получение SSL сертификата через certbot"""
        import subprocess

        mtproto_domain = self.config['mtproto_domain']

        print(f"\n{'='*60}")
        print("ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА")
        print(f"{'='*60}\n")

        # Проверяем наличие сертификата
        cert_path = Path(f"/etc/letsencrypt/live/{mtproto_domain}/fullchain.pem")

        if cert_path.exists():
            print(f"✓ SSL сертификат уже существует для {mtproto_domain}")
            print(f"  Путь: {cert_path}")
            return True

        print(f"🔐 Получение SSL сертификата для {mtproto_domain}...")
        print(f"   Используется certbot в режиме standalone")
        print()

        try:
            # Останавливаем контейнеры чтобы освободить порт 80
            print("⏸ Временная остановка контейнеров для освобождения порта 80...")

            # Останавливаем Remnawave (Nginx)
            subprocess.run(
                ['docker', 'compose', 'down'],
                cwd=str(self.remnawave_path),
                check=False,
                capture_output=True
            )

            # Останавливаем MTProto если он уже запущен
            subprocess.run(
                self.docker_compose_cmd + ['down'],
                cwd=str(self.base_path),
                check=False,
                capture_output=True
            )

            # Запускаем certbot
            result = subprocess.run(
                ['certbot', 'certonly', '--standalone', '--non-interactive', 
                 '--agree-tos', '--register-unsafely-without-email',
                 '-d', mtproto_domain],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                print(f"✓ SSL сертификат успешно получен для {mtproto_domain}")
                return True
            else:
                print(f"✗ Ошибка при получении сертификата:")
                print(result.stderr)
                print(f"\n⚠ Получите сертификат вручную:")
                print(f"   sudo certbot certonly --standalone -d {mtproto_domain}")
                return False

        except Exception as e:
            print(f"✗ Ошибка при получении сертификата: {e}")
            print(f"\n⚠ Получите сертификат вручную:")
            print(f"   sudo certbot certonly --standalone -d {mtproto_domain}")
            return False

    def restart_containers(self):
        """Перезапуск Docker контейнеров"""
        import subprocess

        print(f"\n{'='*60}")
        print("ЗАПУСК DOCKER КОНТЕЙНЕРОВ")
        print(f"{'='*60}\n")

        print("🔄 Перезапуск контейнеров...")

        try:
            # Запускаем Remnawave контейнеры (Nginx)
            print("\n   📦 Remnawave (/opt/remnanode/):")
            print("      Остановка...")
            subprocess.run(
                ['docker', 'compose', 'down'],
                cwd=str(self.remnawave_path),
                check=False,
                capture_output=True
            )

            print("      Запуск...")
            subprocess.run(
                ['docker', 'compose', 'up', '-d'],
                cwd=str(self.remnawave_path),
                check=True,
                capture_output=True
            )
            print("      ✓ Запущен")

            # Запускаем MTProto Proxy контейнер
            print("\n   📦 MTProto Proxy (/opt/MTProto_Proxy/):")
            print("      Остановка...")
            subprocess.run(
                self.docker_compose_cmd + ['down'],
                cwd=str(self.base_path),
                check=False,
                capture_output=True
            )

            print("      Сборка и запуск...")
            result = subprocess.run(
                self.docker_compose_cmd + ['up', '-d', '--build'],
                cwd=str(self.base_path),
                check=True,
                capture_output=True,
                text=True
            )
            print("      ✓ Запущен")

            print("\n✓ Все контейнеры успешно запущены")
            print()

            # Даем время на запуск
            import time
            print("⏳ Ожидание запуска сервисов (5 секунд)...")
            time.sleep(5)

            # Проверяем статус контейнеров
            print("\n📊 Статус контейнеров:")
            subprocess.run(
                ['docker', 'ps', '--filter', 'name=mtprotoproxy', 
                 '--filter', 'name=remnawave-nginx', '--format', 
                 'table {{.Names}}\t{{.Status}}\t{{.Ports}}']
            )

            return True

        except subprocess.CalledProcessError as e:
            print(f"\n✗ Ошибка при перезапуске контейнеров: {e}")

            # Определяем какая команда использовалась
            compose_cmd = ' '.join(self.docker_compose_cmd)

            print(f"\n⚠ Перезапустите контейнеры вручную:")
            print(f"\n   Remnawave:")
            print(f"   cd {self.remnawave_path}")
            print(f"   docker compose down && docker compose up -d")
            print(f"\n   MTProto Proxy:")
            print(f"   cd {self.base_path}")
            print(f"   {compose_cmd} down && {compose_cmd} up -d --build")
            return False
        except FileNotFoundError as e:
            print(f"\n✗ Docker Compose не найден: {e}")
            print(f"\n⚠ Установите Docker Compose:")
            print(f"   sudo apt update && sudo apt install -y docker-compose-plugin")
            print(f"\n   Или перезапустите контейнеры вручную:")
            print(f"   cd {self.base_path}")
            print(f"   docker compose up -d --build  # или docker-compose")
            return False

    def print_connection_info(self):
        """Вывод информации для подключения"""
        mtproto_domain = self.config['mtproto_domain']
        secret = self.config.get('mtproto_secret', '')
        mtproto_port = self.config.get('mtproto_proxy_port', 8888)
        tls_domain = self.config.get('tls_domain', 'www.google.com')

        # Генерация TLS секрета
        domain_hex = mtproto_domain.encode().hex()
        tls_secret = 'ee' + domain_hex + secret

        proxy_link = f"https://t.me/proxy?server={mtproto_domain}&port=443&secret={tls_secret}"

        print(f"\n{'='*60}")
        print("✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!")
        print(f"{'='*60}\n")

        print("📋 КОНФИГУРАЦИЯ:")
        print(f"   Домен:           {mtproto_domain}")
        print(f"   Порт (внешний):  443")
        print(f"   Порт (прокси):   {mtproto_port}")
        print(f"   Секрет:          {secret}")
        print(f"   TLS маскировка:  {tls_domain}")
        print()

        print("🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:")
        print(f"{'='*60}")
        print(proxy_link)
        print(f"{'='*60}\n")

        print("💡 ИНСТРУКЦИЯ ПО ПОДКЛЮЧЕНИЮ:")
        print("   1. Откройте ссылку на устройстве с Telegram")
        print("   2. Нажмите 'Connect Proxy' или 'Подключить прокси'")
        print("   3. Прокси автоматически добавится в настройки\n")

        print("📊 МОНИТОРИНГ:")
        print("   Логи MTProto:  docker logs -f mtprotoproxy")
        print("   Логи Nginx:    docker logs -f remnawave-nginx")
        print("   Статус:        docker ps | grep -E 'mtprotoproxy|remnawave'")
        print()

        print("🔧 УПРАВЛЕНИЕ:")
        print(f"   Конфигурация MTProto:  {self.base_path}/config.py")
        print(f"   Docker MTProto:        {self.base_path}/docker-compose.yml")
        print(f"   Docker Remnawave:      {self.remnawave_path}/docker-compose.yml")
        print(f"   Nginx конфиг:          {self.sites_available}/{mtproto_domain}")
        print(f"   Nginx stream:          {self.remnawave_path}/stream.conf")
        print()

        # Сохраняем ссылку в файл
        link_file = self.base_path / "proxy_link.txt"
        try:
            with open(link_file, 'w') as f:
                f.write(f"MTProto Proxy Connection Link\n")
                f.write(f"{'='*60}\n\n")
                f.write(f"Domain: {mtproto_domain}\n")
                f.write(f"Port: 443\n")
                f.write(f"Secret: {secret}\n\n")
                f.write(f"Connection Link:\n")
                f.write(f"{proxy_link}\n")
            print(f"💾 Ссылка сохранена в: {link_file}")
        except Exception as e:
            print(f"⚠ Не удалось сохранить ссылку в файл: {e}")

        print(f"\n{'='*60}\n")
    
    def run(self):
        """Запуск процесса настройки"""
        print(f"\n{'='*60}")
        print("НАСТРОЙКА MTPROTO PROXY ДЛЯ REMNAWAVE")
        print(f"{'='*60}\n")

        try:
            # Проверяем флаг skip_setup (только показать ссылку)
            if self.config.get('skip_setup'):
                print("💡 Используется существующая настройка\n")
                self.print_connection_info()
                return

            # Проверяем наличие Remnawave
            print("🔍 Проверка установки Remnawave...\n")

            if not self.remnawave_path.exists():
                print(f"✗ ОШИБКА: Не найдена директория Remnawave: {self.remnawave_path}")
                print(f"   Убедитесь что Remnawave установлена в /opt/remnanode/")
                sys.exit(1)

            docker_compose_path = self.remnawave_path / "docker-compose.yml"
            if not docker_compose_path.exists():
                print(f"✗ ОШИБКА: Не найден docker-compose.yml: {docker_compose_path}")
                print(f"   Убедитесь что Remnawave правильно установлена")
                sys.exit(1)

            stream_conf_path = self.remnawave_path / "stream.conf"
            if not stream_conf_path.exists():
                print(f"⚠ ВНИМАНИЕ: Не найден stream.conf: {stream_conf_path}")
                print(f"   Будет создан новый файл")
                print()

            print(f"✓ Remnawave найдена: {self.remnawave_path}")
            print()

            # Создаем директории если не существуют
            self.sites_available.mkdir(parents=True, exist_ok=True)

            # Проверяем порты
            print("🔍 Проверка доступности портов...\n")

            mtproto_proxy_port = self.config.get('mtproto_proxy_port', 8888)
            mtproto_backend_port = self.config.get('mtproto_backend_port', 10443)

            if not self.check_port_available(mtproto_proxy_port):
                print(f"⚠ ВНИМАНИЕ: Порт {mtproto_proxy_port} уже используется!")
                print(f"   MTProto прокси может не запуститься. Рекомендуется выбрать другой порт.")
                print()
            else:
                print(f"✓ Порт {mtproto_proxy_port} свободен")

            if not self.check_port_available(mtproto_backend_port):
                print(f"⚠ ВНИМАНИЕ: Порт {mtproto_backend_port} уже используется!")
                print(f"   Nginx backend может не запуститься. Рекомендуется выбрать другой порт.")
                print()
            else:
                print(f"✓ Порт {mtproto_backend_port} свободен")

            print()

            # Проверяем наличие необходимых файлов MTProto
            print("🔍 Проверка необходимых файлов MTProto...\n")

            mtprotoproxy_py = self.base_path / 'mtprotoproxy.py'
            pyaes_dir = self.base_path / 'pyaes'

            if not mtprotoproxy_py.exists():
                print(f"⚠ ПРЕДУПРЕЖДЕНИЕ: Не найден mtprotoproxy.py")
                print(f"   Ожидается: {mtprotoproxy_py}")
                print(f"   Скачайте файл из репозитория: https://github.com/alexbers/mtprotoproxy")
                print()
            else:
                print(f"✓ Найден mtprotoproxy.py")

            if not pyaes_dir.exists():
                print(f"⚠ ПРЕДУПРЕЖДЕНИЕ: Не найдена директория pyaes/")
                print(f"   Ожидается: {pyaes_dir}")
                print(f"   Скачайте из репозитория: https://github.com/alexbers/mtprotoproxy")
                print()
            else:
                print(f"✓ Найдена директория pyaes/")

            print()

            # Выполняем настройку
            print("\n" + "="*60)
            print("ШАГ 1/7: СОЗДАНИЕ DOCKERFILE")
            print("="*60)
            self.create_dockerfile_if_not_exists()

            print("\n" + "="*60)
            print("ШАГ 2/7: ОБНОВЛЕНИЕ STREAM.CONF")
            print("="*60)
            self.update_stream_conf()

            print("\n" + "="*60)
            print("ШАГ 3/7: СОЗДАНИЕ NGINX КОНФИГУРАЦИИ")
            print("="*60)
            self.create_mtproto_nginx_conf()

            print("\n" + "="*60)
            print("ШАГ 4/7: ОБНОВЛЕНИЕ 80.CONF")
            print("="*60)
            self.update_80_conf()

            print("\n" + "="*60)
            print("ШАГ 5/7: СОЗДАНИЕ MTPROTO КОНФИГУРАЦИИ")
            print("="*60)
            self.create_mtproto_config()

            print("\n" + "="*60)
            print("ШАГ 5.5/7: СОЗДАНИЕ DOCKER-COMPOSE")
            print("="*60)
            self.create_docker_compose()

            # Получаем SSL сертификат
            print("\n" + "="*60)
            print("ШАГ 6/7: ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА")
            print("="*60)
            cert_obtained = self.obtain_ssl_certificate()

            if not cert_obtained:
                print("\n⚠ Не удалось получить SSL сертификат автоматически.")
                print("   Получите сертификат вручную и перезапустите контейнеры.")
                return

            # Перезапускаем контейнеры
            print("\n" + "="*60)
            print("ШАГ 7/7: ЗАПУСК СЕРВИСОВ")
            print("="*60)
            containers_started = self.restart_containers()

            if not containers_started:
                print("\n⚠ Не удалось запустить контейнеры автоматически.")
                print("   Запустите их вручную.")
                return

            # Выводим информацию для подключения
            self.print_connection_info()

        except Exception as e:
            print(f"\n✗ Ошибка при настройке: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


def interactive_setup():
    """Интерактивная настройка"""
    print("=== Интерактивная настройка MTProto Proxy ===\n")

    config = {}

    # Создаем временный объект для парсинга существующих настроек
    temp_setup = MTProtoNginxSetup({})

    # Парсим существующие настройки
    print("🔍 Анализ существующей конфигурации...\n")
    existing_domains, existing_upstreams, xray_reality_domain = temp_setup.parse_existing_stream_conf()
    existing_80_domains = temp_setup.parse_existing_80_conf()

    print()

    # Автоматически определяем xray_reality если найден
    if xray_reality_domain:
        config['xray_reality_domain'] = xray_reality_domain
        print(f"✓ Автоматически определен Xray Reality домен: {xray_reality_domain}\n")

    # Проверяем существующую настройку MTProto
    existing_mtproto_domain, existing_mtproto_config = temp_setup.detect_existing_mtproto_setup()

    if existing_mtproto_domain:
        # MTProto уже настроен - показываем текущую конфигурацию
        temp_setup.show_current_mtproto_config(existing_mtproto_domain, existing_mtproto_config)

        # Проверяем корректность
        issues = temp_setup.validate_mtproto_setup(existing_mtproto_domain, existing_mtproto_config)

        if issues:
            print("⚠️  ОБНАРУЖЕНЫ ПРОБЛЕМЫ:")
            for i, issue in enumerate(issues, 1):
                print(f"   {i}. {issue}")
            print()
        else:
            print("✅ Настройка выглядит корректной!\n")

        # Предлагаем варианты действий
        print("="*60)
        print("Что вы хотите сделать?")
        print("="*60)
        print()
        print("1) Показать ссылку для подключения (оставить как есть)")
        print("2) Изменить существующую настройку (реконфигурация)")
        if issues:
            print("3) Исправить проблемы (автоматическое исправление)")
        print("0) Выход")
        print()

        while True:
            choice = input("Ваш выбор: ").strip()

            if choice == '1':
                # Только показать ссылку
                if not existing_mtproto_config or 'secret' not in existing_mtproto_config:
                    print("\n✗ Невозможно показать ссылку: секрет не настроен")
                    print("   Выберите опцию 2 или 3 для настройки\n")
                    continue

                # Используем существующие данные
                config['mtproto_domain'] = existing_mtproto_domain
                config['mtproto_secret'] = existing_mtproto_config.get('secret')
                config['mtproto_proxy_port'] = existing_mtproto_config.get('port', 8888)
                config['mtproto_backend_port'] = existing_mtproto_config.get('backend_port', 10443)
                config['tls_domain'] = existing_mtproto_config.get('tls_domain', 'www.google.com')
                if existing_mtproto_config.get('ad_tag'):
                    config['ad_tag'] = existing_mtproto_config['ad_tag']
                config['skip_setup'] = True  # Флаг что ничего не делаем, только показываем ссылку
                return config

            elif choice == '2':
                # Полная реконфигурация
                print("\n" + "="*60)
                print("РЕКОНФИГУРАЦИЯ MTPROTO")
                print("="*60 + "\n")

                # Предлагаем текущий домен по умолчанию
                print(f"💡 Текущий домен: {existing_mtproto_domain}")
                new_domain = input(f"Новый домен [{existing_mtproto_domain}]: ").strip()

                if new_domain:
                    # Проверяем новый домен
                    while not temp_setup.validate_domain(new_domain):
                        print("✗ Некорректный домен. Попробуйте снова.")
                        new_domain = input(f"Новый домен [{existing_mtproto_domain}]: ").strip()
                        if not new_domain:
                            new_domain = existing_mtproto_domain
                            break
                    config['mtproto_domain'] = new_domain
                else:
                    config['mtproto_domain'] = existing_mtproto_domain

                # Остальные параметры спрашиваем с текущими значениями
                print()
                print("=" * 60)
                print("НАСТРОЙКА ПОРТОВ")
                print("=" * 60)
                print()
                print("💡 Архитектура портов:")
                print("   Internet:443 → Nginx (SNI) → 127.0.0.1:BACKEND → 127.0.0.1:PROXY")
                print()
                print("   • Внешний порт: 443 (для клиентов Telegram)")
                print("   • Backend порт: порт Nginx конфига для MTProto домена")
                print("   • Proxy порт: порт MTProto контейнера (должен быть СВОБОДНЫМ!)")
                print()

                current_port = existing_mtproto_config.get('port', 8888) if existing_mtproto_config else 8888
                port_input = input(f"Proxy порт (MTProto контейнер, свободный) [{current_port}]: ").strip()
                config['mtproto_proxy_port'] = int(port_input) if port_input else current_port

                current_backend = existing_mtproto_config.get('backend_port', 10443) if existing_mtproto_config else 10443
                backend_input = input(f"Backend порт (Nginx конфиг) [{current_backend}]: ").strip()
                config['mtproto_backend_port'] = int(backend_input) if backend_input else current_backend

                print()
                print("=" * 60)
                print("НАСТРОЙКА TLS И СЕКРЕТА")
                print("=" * 60)
                print()

                current_tls = existing_mtproto_config.get('tls_domain', 'www.google.com') if existing_mtproto_config else 'www.google.com'
                tls_input = input(f"Домен для TLS маскировки [{current_tls}]: ").strip()
                config['tls_domain'] = tls_input if tls_input else current_tls

                # Секрет
                if existing_mtproto_config and 'secret' in existing_mtproto_config:
                    print(f"💡 Текущий секрет: {existing_mtproto_config['secret']}")
                    change_secret = input("Изменить секрет? (y/n) [n]: ").strip().lower()
                    if change_secret == 'y':
                        generate = input("Сгенерировать новый секрет? (y/n) [y]: ").strip().lower()
                        if generate != 'n':
                            config['mtproto_secret'] = temp_setup.generate_secret()
                        else:
                            secret = input("Введите секрет (32 hex символа): ").strip()
                            config['mtproto_secret'] = secret
                    else:
                        config['mtproto_secret'] = existing_mtproto_config['secret']
                else:
                    generate = input("Сгенерировать новый секрет? (y/n) [y]: ").strip().lower()
                    if generate != 'n':
                        config['mtproto_secret'] = temp_setup.generate_secret()
                    else:
                        secret = input("Введите секрет (32 hex символа): ").strip()
                        config['mtproto_secret'] = secret

                # AD Tag
                current_ad = existing_mtproto_config.get('ad_tag', '') if existing_mtproto_config else ''
                if current_ad:
                    print(f"💡 Текущий AD Tag: {current_ad}")
                ad_input = input(f"AD Tag от @MTProxybot [{current_ad or 'оставьте пустым'}]: ").strip()
                if ad_input or current_ad:
                    config['ad_tag'] = ad_input if ad_input else current_ad

                return config

            elif choice == '3' and issues:
                # Исправление проблем
                print("\n" + "="*60)
                print("ИСПРАВЛЕНИЕ ПРОБЛЕМ")
                print("="*60 + "\n")

                # Используем существующий домен
                config['mtproto_domain'] = existing_mtproto_domain
                print(f"✓ Домен: {existing_mtproto_domain}")
                print()

                # Недостающие данные спрашиваем
                if not existing_mtproto_config or 'port' not in existing_mtproto_config:
                    print("💡 Proxy порт - локальный порт MTProto контейнера (НЕ 443!)")
                    port_input = input("Proxy порт (свободный, например 8888) [8888]: ").strip()
                    config['mtproto_proxy_port'] = int(port_input) if port_input else 8888
                else:
                    config['mtproto_proxy_port'] = existing_mtproto_config['port']
                    print(f"✓ Порт (прокси): {config['mtproto_proxy_port']}")

                # Backend порт
                if not existing_mtproto_config or 'backend_port' not in existing_mtproto_config:
                    backend_input = input("Backend порт для Nginx [10443]: ").strip()
                    config['mtproto_backend_port'] = int(backend_input) if backend_input else 10443
                else:
                    config['mtproto_backend_port'] = existing_mtproto_config['backend_port']
                    print(f"✓ Порт (backend): {config['mtproto_backend_port']}")

                if not existing_mtproto_config or 'secret' not in existing_mtproto_config:
                    generate = input("Сгенерировать новый секрет? (y/n) [y]: ").strip().lower()
                    if generate != 'n':
                        config['mtproto_secret'] = temp_setup.generate_secret()
                    else:
                        secret = input("Введите секрет (32 hex символа): ").strip()
                        config['mtproto_secret'] = secret
                else:
                    config['mtproto_secret'] = existing_mtproto_config['secret']
                    print(f"✓ Секрет: {config['mtproto_secret']}")

                if not existing_mtproto_config or 'tls_domain' not in existing_mtproto_config:
                    tls = input("Домен для TLS маскировки [www.google.com]: ").strip()
                    config['tls_domain'] = tls if tls else "www.google.com"
                else:
                    config['tls_domain'] = existing_mtproto_config['tls_domain']
                    print(f"✓ TLS домен: {config['tls_domain']}")

                # AD Tag (опционально)
                if existing_mtproto_config and 'ad_tag' in existing_mtproto_config and existing_mtproto_config['ad_tag']:
                    config['ad_tag'] = existing_mtproto_config['ad_tag']
                    print(f"✓ AD Tag: {config['ad_tag']}")

                return config

            elif choice == '0':
                print("Выход...")
                sys.exit(0)

            else:
                print("✗ Неверный выбор. Попробуйте снова.\n")
                continue

    # Новая установка - существующего MTProto нет
    print("💡 MTProto Proxy еще не настроен. Начинаем новую установку.\n")

    # MTProto домен
    while True:
        mtproto_domain = input("Введите домен для MTProto прокси (например, proxy.example.com): ").strip()
        setup = MTProtoNginxSetup({})
        if setup.validate_domain(mtproto_domain):
            config['mtproto_domain'] = mtproto_domain
            break
        print("✗ Некорректный домен. Попробуйте снова.")

    print("\n💡 Существующие домены будут автоматически сохранены из текущей конфигурации")
    print("   Нет необходимости вводить их повторно\n")

    # Порты с пояснениями
    print("=" * 60)
    print("НАСТРОЙКА ПОРТОВ")
    print("=" * 60)
    print()
    print("💡 Архитектура портов:")
    print("   Internet:443 → Nginx (SNI) → 127.0.0.1:BACKEND → 127.0.0.1:PROXY")
    print()
    print("   • Внешний порт: 443 (для клиентов Telegram)")
    print("   • Backend порт: порт Nginx конфига для MTProto домена")
    print("   • Proxy порт: порт MTProto контейнера (должен быть СВОБОДНЫМ!)")
    print()
    print("⚠️  ВАЖНО: Proxy порт НЕ должен быть 443 (он уже занят Nginx)!")
    print()

    mtproto_proxy_port = input("Proxy порт (MTProto контейнер, свободный) [8888]: ").strip()
    config['mtproto_proxy_port'] = int(mtproto_proxy_port) if mtproto_proxy_port else 8888

    mtproto_backend_port = input("Backend порт (Nginx конфиг) [10443]: ").strip()
    config['mtproto_backend_port'] = int(mtproto_backend_port) if mtproto_backend_port else 10443

    print()
    print("=" * 60)
    print("НАСТРОЙКА TLS И СЕКРЕТА")
    print("=" * 60)
    print()

    # TLS домен для маскировки
    tls_domain = input("Домен для TLS маскировки [www.google.com]: ").strip()
    config['tls_domain'] = tls_domain if tls_domain else "www.google.com"

    # Секрет
    generate_secret = input("Сгенерировать новый секрет? (y/n) [y]: ").strip().lower()
    if generate_secret != 'n':
        setup = MTProtoNginxSetup({})
        config['mtproto_secret'] = setup.generate_secret()
    else:
        secret = input("Введите секрет (32 hex символа): ").strip()
        config['mtproto_secret'] = secret

    # AD TAG
    ad_tag = input("AD Tag от @MTProxybot (оставьте пустым если нет): ").strip()
    if ad_tag:
        config['ad_tag'] = ad_tag

    return config


def main():
    parser = argparse.ArgumentParser(
        description='Настройка MTProto Proxy через Nginx для Remnawave'
    )
    parser.add_argument(
        '--config',
        type=str,
        help='Путь к JSON файлу с конфигурацией'
    )
    parser.add_argument(
        '--interactive',
        action='store_true',
        help='Интерактивный режим настройки'
    )
    
    args = parser.parse_args()
    
    if args.config:
        # Загрузка из файла
        with open(args.config, 'r', encoding='utf-8') as f:
            config = json.load(f)
    elif args.interactive or len(sys.argv) == 1:
        # Интерактивный режим
        config = interactive_setup()
    else:
        parser.print_help()
        sys.exit(1)
    
    # Запуск настройки
    setup = MTProtoNginxSetup(config)
    setup.run()


if __name__ == '__main__':
    main()
