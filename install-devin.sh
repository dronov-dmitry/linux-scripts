#!/usr/bin/env bash
set -euo pipefail

DEB="/tmp/opencode/devin.deb"
URL="https://windsurf-stable.codeiumdata.com/linux-x64-deb/stable/7e8e528a3057dcf000527b80072c9be7ea90a08d/Devin-linux-x64-3.7.25.deb"

# Уже установлен — просто показываем статус и выходим, sudo не нужен.
if command -v devin-desktop >/dev/null; then
  echo "OK: Devin Desktop уже установлен. Версия: $(devin-desktop --version 2>/dev/null | head -1 || echo n/a)"
  echo "Запуск: devin-desktop  | меню приложений → Devin"
  echo "Открыть папку телефона: devin-desktop /home/kat/phone-dev"
  exit 0
fi

echo "==> Скачиваю Devin Desktop (.deb)..."
mkdir -p /tmp/opencode
curl -sL --max-time 180 -o "$DEB" "$URL"
ls -lh "$DEB"

echo "==> Устанавливаю пакет (нужен пароль sudo)..."
sudo dpkg -i "$DEB" || sudo apt-get install -f -y

echo "==> Проверяю..."
if command -v devin-desktop >/dev/null; then
  echo "OK: Devin Desktop установлен. Версия: $(devin-desktop --version 2>/dev/null || echo n/a)"
  echo "Запуск (как приложение):  devin-desktop   или  меню приложений → Devin"
  echo "CLI (терминал):           devin --help"
  echo "Открыть папку телефона:   devin-desktop /home/kat/phone-dev"
else
  echo "!! Бинарник не найден — проверь установку вручную."
fi
