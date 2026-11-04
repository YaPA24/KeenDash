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


