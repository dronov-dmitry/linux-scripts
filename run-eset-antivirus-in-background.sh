cat << "EOF" > /tmp/eset_installer_helper.sh
#!/usr/bin/env bash

DOWNLOADS_DIR="$HOME/Downloads"
# Ищем любая разновидность файла инсталлятора ESET (.bin или .deb)
ESET_BIN=$(ls "$DOWNLOADS_DIR"/eea*.bin "$DOWNLOADS_DIR"/*eset*.bin 2>/dev/null | head -n 1)
ESET_DEB=$(ls "$DOWNLOADS_DIR"/eea*.deb "$DOWNLOADS_DIR"/*eset*.deb 2>/dev/null | head -n 1)

echo "=================================================="
echo "          ИНСТРУКЦИЯ ПО УСТАНОВКЕ ESET           "
echo "=================================================="

if [ -n "$ESET_BIN" ]; then
    echo "[✓] Найден .bin файл: $ESET_BIN"
    echo "[+] Выдаем права и запускаем установку..."
    echo "=================================================="
    chmod +x "$ESET_BIN"
    sudo "$ESET_BIN"
elif [ -n "$ESET_DEB" ]; then
    echo "[✓] Найден .deb пакет: $ESET_DEB"
    echo "[+] Запускаем установку пакета..."
    echo "=================================================="
    sudo apt install "$ESET_DEB"
else
    echo "[!] Инсталлятор ESET не найден в $DOWNLOADS_DIR"
    echo ""
    echo "ЧТО НУЖНО СДЕЛАТЬ:"
    echo "1. Скачайте файл с официального сайта ESET."
    echo "2. Убедитесь, что файл сохранился в папку Загрузки (Downloads)."
    echo "3. Запустите этот скрипт еще раз!"
    echo "=================================================="
    
    if command -v xdg-open > /dev/null; then
        echo "[+] Открываем страницу загрузки ESET в браузере..."
        xdg-open "https://www.eset.com/uk/business/download/endpoint-antivirus-linux/" &>/dev/null &
    fi
fi
EOF

chmod +x /tmp/eset_installer_helper.sh
/tmp/eset_installer_helper.sh