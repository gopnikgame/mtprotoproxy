# MTProto Proxy для Remnawave !Только для моего скрипта настройки ноды!

🚀 **Полностью автоматическая настройка MTProto прокси-сервера для Remnawave через Nginx**

[![GitHub](https://img.shields.io/badge/GitHub-gopnikgame/mtprotoproxy-blue)](https://github.com/gopnikgame/mtprotoproxy)
[![Upstream](https://img.shields.io/badge/Upstream-alexbers/mtprotoproxy-green)](https://github.com/alexbers/mtprotoproxy)

## ⚡ Установка в одну команду

```bash
wget -O - https://raw.githubusercontent.com/gopnikgame/mtprotoproxy/master/install.sh | sudo bash
```

**После установки запускайте просто командой:**

```bash
MTProto
```

**После завершения настройки вы получите полностью рабочий прокси-сервер и ссылку для подключения!**

## 🎯 Что делает скрипт

- ✅ **Полная автоматизация** - от начала до конца без ручных действий
- ✅ **Автоматический SSL** - получает сертификат Let's Encrypt для вашего домена
- ✅ **Умная настройка** - сохраняет все существующие домены и конфигурации
- ✅ **Запуск сервисов** - автоматически запускает все Docker контейнеры
- ✅ **Готовая ссылка** - выдает рабочую ссылку для подключения к прокси
- ✅ **Безопасность** - все изменения сохраняются в .backup файлы

## 🚀 Варианты установки

### Вариант 1: Автоустановка через команду (рекомендуется)

```bash
# 1. Установка
wget -O - https://raw.githubusercontent.com/gopnikgame/mtprotoproxy/master/install.sh | sudo bash

# 2. Настройка (просто одна команда!)
MTProto

# Выберите опцию 2 (Настроить MTProto Proxy)
```

### Вариант 2: Быстрая настройка одной командой

```bash
wget https://raw.githubusercontent.com/gopnikgame/mtprotoproxy/master/manage_mtproto.sh
chmod +x manage_mtproto.sh
sudo ./manage_mtproto.sh setup
```

### Вариант 3: Ручная установка

```bash
sudo git clone https://github.com/gopnikgame/mtprotoproxy /opt/MTProto_Proxy
cd /opt/MTProto_Proxy
sudo python3 setup_mtproto_nginx.py --interactive
```

### Вариант 4: Из конфигурационного файла

```bash
cd /opt/MTProto_Proxy
sudo python3 setup_mtproto_nginx.py --config config_example.json
```

## 📋 Требования

- Ubuntu/Debian сервер с root доступом
- Установленная нода Remnawave в `/opt/remnanode/`
- Docker и Docker Compose
- Python 3.6+
- Домен с A-записью, указывающей на ваш сервер

## 📊 Что происходит при установке

1. **Анализ системы** - проверка Remnawave, портов и конфигураций
2. **Настройка конфигураций** - создание и обновление всех необходимых файлов
3. **Получение SSL** - автоматическое получение Let's Encrypt сертификата
4. **Запуск сервисов** - перезапуск Docker контейнеров с новой конфигурацией
5. **Готово!** - вывод ссылки для подключения и инструкций

### Пример вывода после установки:

```
============================================================
✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!
============================================================

📋 КОНФИГУРАЦИЯ:
   Домен:           proxy.example.com
   Порт (внешний):  443
   Порт (прокси):   8888
   Секрет:          abcdef0123456789abcdef0123456789
   TLS маскировка:  www.google.com

🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:
============================================================
https://t.me/proxy?server=proxy.example.com&port=443&secret=ee...
============================================================

💡 ИНСТРУКЦИЯ ПО ПОДКЛЮЧЕНИЮ:
   1. Откройте ссылку на устройстве с Telegram
   2. Нажмите 'Connect Proxy' или 'Подключить прокси'
   3. Прокси автоматически добавится в настройки

📊 МОНИТОРИНГ:
   Логи MTProto:  docker logs -f mtprotoproxy
   Логи Nginx:    docker logs -f remnawave-nginx
   Статус:        docker ps | grep -E 'mtprotoproxy|remnawave'
```

## 🏗️ Архитектура

```
Интернет (443) → Remnawave Nginx (SNI Router) → MTProto Backend (10443) 
                                                → MTProto Container (8888) 
                                                → Telegram
```

**Два отдельных Docker проекта:**
- **Remnawave** (`/opt/remnanode/`) - Nginx с SNI роутингом
  - Команда: `docker compose` (новая версия)
  - Контейнер: `remnawave-nginx`

- **MTProto Proxy** (`/opt/MTProto_Proxy/`) - прокси-сервер
  - Команда: `docker-compose` (старая версия)
  - Контейнер: `mtprotoproxy`
  - Режим: `network_mode: host` для связи с Nginx

**Связь:** Оба используют `network_mode: host`, общаются через `127.0.0.1`

## 🛠️ Управление

### Через команду MTProto (самый простой способ)

```bash
# Запуск меню управления
MTProto

# Или напрямую с командами
MTProto setup       # Автоматическая настройка
MTProto start       # Запустить контейнеры
MTProto cert        # Получить SSL сертификат
MTProto diagnose    # Запустить диагностику
MTProto renew-certs # Обновить сертификаты
```

### Диагностика

```bash
# Полная диагностика на сервере
cd /opt/MTProto_Proxy
sudo bash diagnose_mtproto.sh

# Проверка с внешнего сервера
bash check_mtproto_external.sh russia3-t.vline.online

# Быстрая проверка портов
sudo ss -tulpn | grep -E ':443|:8888|:10443'

# Проверка статистики
docker logs --tail 10 mtprotoproxy | grep "Stats"
```

### Через Docker напрямую

```bash
# MTProto Proxy контейнер
cd /opt/MTProto_Proxy
docker-compose ps
docker-compose logs -f mtprotoproxy
docker-compose restart

# Remnawave контейнеры (Nginx)
cd /opt/remnanode
docker compose ps
docker compose logs -f remnawave-nginx
docker compose restart

# Статус всех контейнеров
docker ps | grep -E "mtprotoproxy|remnawave"
```

## 📊 Мониторинг

Логи контейнеров:
- **MTProto:** `docker-compose -f /opt/MTProto_Proxy/docker-compose.yml logs -f`
- **Nginx:** `docker compose -f /opt/remnanode/docker-compose.yml logs -f remnawave-nginx`

Файлы конфигурации:
- MTProto: `/opt/MTProto_Proxy/config.py`
- Nginx: `/opt/remnanode/stream.conf`, `/opt/remnanode/sites-available/`

## 📝 Файлы и директории

```
/opt/MTProto_Proxy/          # MTProto Proxy проект
├── docker-compose.yml       # Docker конфигурация MTProto
├── setup_mtproto_nginx.py   # Скрипт установки
├── manage_mtproto.sh        # Менеджер управления
├── config.py                # Конфигурация MTProto
├── Dockerfile               # Docker образ
├── mtprotoproxy.py          # Основной скрипт прокси
├── pyaes/                   # Библиотека шифрования
└── proxy_link.txt           # Сохраненная ссылка

/opt/remnanode/              # Remnawave нода
├── docker-compose.yml       # Docker конфигурация Nginx (НЕ ТРОГАЕМ!)
├── stream.conf              # SNI роутинг (обновляется)
└── sites-available/         # Nginx конфиги доменов (обновляются)
```

## 🆘 Решение проблем

### Быстрая диагностика

```bash
# Полная диагностика на сервере
cd /opt/MTProto_Proxy
sudo bash diagnose_mtproto.sh

# Показать правильную ссылку
sudo bash diagnose_mtproto.sh | grep -A3 "ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ"
```

### ✅ HTTP 400 - это УСПЕХ!

Если `curl -v https://your-domain.com` возвращает **HTTP 400 Bad Request** - всё работает правильно!

```
< HTTP/2 400 
< server: nginx
<html>
<head><title>400 Bad Request</title></head>
```

**Почему это хорошо:**
- ✅ Порт 443 доступен
- ✅ TLS работает
- ✅ Nginx работает
- ✅ MTProto отвечает (хоть и ошибкой на HTTP)

**MTProto ожидает специальный протокол, не HTTP!**  
Подробнее: [SUCCESS_HTTP_400_IS_OK.md](SUCCESS_HTTP_400_IS_OK.md)

### Типичные проблемы

#### ❌ Ошибка: `address already in use`

```
OSError: [Errno 98] error while attempting to bind on address ('0.0.0.0', 443): address already in use
```

**Быстрое решение:**
```bash
cd /opt/MTProto_Proxy
sudo bash fix_mtproto_complete.sh
```

Подробности: [FIX_ADDRESS_IN_USE.md](FIX_ADDRESS_IN_USE.md)

---

#### 🔧 MTProto не работает через Nginx (но работает на 8888)

**Проблема:** Прямое подключение к порту 8888 работает, но через Nginx на 443 - нет.

**Причина:** HTTP backend ломает MTProto протокол.

**Решение:**
```bash
cd /opt/MTProto_Proxy
sudo bash fix_mtproto_stream.sh
```

Это изменит stream.conf для прямого TCP проксирования (без HTTP обработки).

---

#### 📋 Другие проблемы

**Прокси не подключается:**
```bash
# 1. Проверить firewall
sudo ufw allow 443/tcp && sudo ufw reload

# 2. Проверить DNS (с вашего устройства)
nslookup your-domain.com

# 3. Проверить логи
docker logs --tail 30 mtprotoproxy

# 4. Попробовать с мобильного интернета
```

**Порты заняты:**
```bash
# Проверить что использует порт
sudo ss -tulpn | grep -E ':443|:8888|:10443'

# Остановить и перезапустить
cd /opt/MTProto_Proxy && sudo docker compose down
cd /opt/remnanode && sudo docker compose down
cd /opt/remnanode && sudo docker compose up -d
cd /opt/MTProto_Proxy && sudo docker compose up -d --build
```

**SSL сертификат не получается:**
```bash
# Остановить контейнеры (освободить порт 80)
cd /opt/remnanode && sudo docker compose down
cd /opt/MTProto_Proxy && sudo docker compose down

# Получить сертификат
sudo certbot certonly --standalone -d your-domain.com

# Запустить контейнеры
cd /opt/remnanode && sudo docker compose up -d
cd /opt/MTProto_Proxy && sudo docker compose up -d
```

### Проверка с внешнего сервера

```bash
# Скачать скрипт проверки
wget https://raw.githubusercontent.com/gopnikgame/mtprotoproxy/master/check_mtproto_external.sh

# Запустить
bash check_mtproto_external.sh your-domain.com

# Или вручную
curl -v https://your-domain.com  # Должен вернуть HTTP 400 (это нормально!)
telnet your-domain.com 443        # Должен подключиться
```

### Документация по диагностике

- **[FAQ.md](FAQ.md)** - Часто задаваемые вопросы ⭐
- **[QUICK_START.md](QUICK_START.md)** - Быстрый старт
- **[DIAGNOSIS_SUCCESS.md](DIAGNOSIS_SUCCESS.md)** - Успешная настройка
- **[SUCCESS_HTTP_400_IS_OK.md](SUCCESS_HTTP_400_IS_OK.md)** - Почему HTTP 400 = успех
- **[SECRET_EXPLANATION.md](SECRET_EXPLANATION.md)** - Почему секреты разные
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Полная диагностика
- **[NEXT_STEPS.md](NEXT_STEPS.md)** - Следующие шаги
- **[PORT_CONFLICT_FIX.md](PORT_CONFLICT_FIX.md)** - Решение конфликта портов

## 🆘 Поддержка

- **GitHub Issues**: https://github.com/gopnikgame/mtprotoproxy/issues
- **FAQ**: См. [FAQ.md](FAQ.md) для ответов на частые вопросы
- **Upstream**: https://github.com/alexbers/mtprotoproxy

## 📚 Дополнительная документация

- [Визуализация архитектуры](VISUALIZATION.md) - подробные диаграммы

## 📝 Лицензия

Распространяется под той же лицензией что и оригинальный mtprotoproxy.

## 🙏 Благодарности

- [alexbers/mtprotoproxy](https://github.com/alexbers/mtprotoproxy) - оригинальный MTProto прокси
- [remnawave](https://github.com/remnawave) - нода для VPN сервисов

---

**Made with ❤️ by gopnikgame**

https://github.com/gopnikgame/mtprotoproxy
