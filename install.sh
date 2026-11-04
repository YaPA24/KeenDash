#!/bin/sh
# ============================================================================
# Файл: install.sh
# Назначение: Автоматическая установка системного монитора в стиле KeenKit
# ============================================================================

# ЗАМЕНИ ЭТУ СТРОКУ на ссылку на твой репозиторий (raw-ссылки)
# Пример: https://raw.githubusercontent.com/твой_ник/твой_репо/main
REPO_URL="https://raw.githubusercontent.com/ТВОЙ_НИК/ТВОЙ_РЕПОЗИТОРИЙ/main"

echo "🚀 Начинаем установку системного монитора..."

# 1. Создаем нужные директории (на всякий случай, если их нет)
mkdir -p /opt/bin
mkdir -p /opt/etc/ndm/netfilter.d
mkdir -p /opt/share/nginx/html

# 2. Скачиваем основные файлы с GitHub
echo "⬇️ Загрузка файлов..."
curl -fLsS "$REPO_URL/sysinfo.sh" > /opt/bin/sysinfo.sh
curl -fLsS "$REPO_URL/200-sysinfo-loop.sh" > /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
curl -fLsS "$REPO_URL/index.html" > /opt/share/nginx/html/index.html
curl -fLsS "$REPO_URL/dash.html" > /opt/share/nginx/html/dash.html
curl -fLsS "$REPO_URL/favicon.svg" > /opt/share/nginx/html/favicon.svg

# 3. Даем права на исполнение скриптам
chmod +x /opt/bin/sysinfo.sh
chmod +x /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh

# 4. Очищаем старые версии (если обновляемся или что-то пошло не так)
echo "🧹 Очистка старых процессов..."
kill $(cat /var/run/sysinfo-loop.pid 2>/dev/null) 2>/dev/null
pkill -f "sysinfo-loop" 2>/dev/null
rm -f /var/run/sysinfo-loop.pid /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json

# 5. Создаем СИМЛИНК (ярлык) из веб-папки в оперативную память
echo "🔗 Создание симлинка..."
ln -sf /tmp/data.json /opt/share/nginx/html/data.json

# 6. Запускаем демон сбора данных
echo "▶️ Запуск демона..."
/opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh

echo ""
echo "✅ Установка успешно завершена!"
echo "🌐 Открой в браузере: http://192.168.1.1:7777/dash.html"
