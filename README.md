"# KeenDash" 

/opt/
├── bin/
│   └── sysinfo.sh              ← Сборщик данных (каждые 3 сек)
├── etc/ndm/netfilter.d/
│   └── 200-sysinfo-loop.sh     ← Демон (бесконечный цикл)
└── share/nginx/html/
    ├── index.html              ← Страница "Карточка"
    ├── dash.html               ← Страница "Дашборд"
    └── data.json -> /tmp/data.json  ← СИМЛИНК (указатель)
    
/tmp/
└── data.json                   ← РЕАЛЬНЫЙ файл с данными (в RAM)


Установить скрипт
```
opkg update && opkg install curl && curl -fLsS "https://raw.githubusercontent.com/YaPA24/KeenDash/install.sh" | sh
```


# остановить демон
kill $(cat /var/run/sysinfo-loop.pid) 2>/dev/null
pkill -f sysinfo-loop 2>/dev/null

# удалить файлы
rm -f /opt/bin/sysinfo.sh
rm -f /opt/etc/ndm/netfilter.d/200-sysinfo-loop.sh
rm -f /opt/share/nginx/html/index.html /opt/share/nginx/html/dash.html
rm -f /opt/share/nginx/html/favicon.svg /opt/share/nginx/html/data.json

# очистить временные данные
rm -f /tmp/sysinfo-static.env /tmp/cpu-stat.prev /tmp/data.json /var/run/sysinfo-loop.pid


