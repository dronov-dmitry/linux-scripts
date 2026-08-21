#!/usr/bin/env bash
# Назначает клавишу Super (Windows) на открытие стартового меню Zorin Menu
# вместо переключения между рабочими пространствами (обзор GNOME).
set -euo pipefail

EXT="zorin-menu@zorinos.com"
SCHEMA="org.gnome.shell.extensions.zorin-menu"

command -v gnome-extensions >/dev/null || { echo "Ошибка: это не сессия GNOME"; exit 1; }

gnome-extensions info "$EXT" >/dev/null 2>&1 || {
    echo "Ошибка: расширение Zorin Menu не установлено"; exit 1;
}

gnome-extensions enable "$EXT"
gsettings set "$SCHEMA" super-hotkey true

echo "Готово. Клавиша Super теперь открывает стартовое меню Zorin Menu."
echo "Если не сработало сразу — перезапустите GNOME Shell (Alt+F2 -> r) или перелогиньтесь."
