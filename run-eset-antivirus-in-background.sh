cat << "EOF" > /tmp/eset_installer_helper.sh
#!/usr/bin/env bash

DOWNLOADS_DIR="$HOME/Downloads"
ESET_FILE=$(ls "$DOWNLOADS_DIR"/eea*.deb 2>/dev/null | head -n 1)

echo "=================================================="
echo "          ИНСТРУКЦИЯ ПО УСТАНОВКЕ ESET           "
echo "=================================================="

if [ -n "$ESET_FILE" ]; then
    echo "[✓] Файл найден: $ESET_FILE"
    echo "[+] Начинаем установку..."
    echo "=================================================="
    sudo apt install "$ESET_FILE"
else
    echo "[!] Файл установки ESET не найден в $DOWNLOADS_DIR"
    echo ""
    echo "ЧТО НУЖНО СДЕЛАТЬ:"
    echo "1. Перейдите на официальный сайт ESET."
    echo "2. Нажмите синюю кнопку 'Download' (скачается файл eea-*.deb)."
    echo "3. Дождитесь завершения скачивания."
    echo "4. Запустите этот скрипт еще раз!"
    echo "=================================================="
    
    # Открываем сайт в браузере по умолчанию
    if command -v xdg-open > /dev/null; then
        echo "[+] Открываем страницу загрузки ESET в браузере..."
        xdg-open "https://www.eset.com/uk/business/download/endpoint-antivirus-linux/" &>/dev/null &
    fi
fi
EOF

chmod +x /tmp/eset_installer_helper.sh
/tmp/eset_installer_helper.sh