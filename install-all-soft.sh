sudo bash -c '
#!/bin/bash
set -e

clear
echo "=================================================================="
echo "         ИНФОРМАЦИЯ О ДОСТУПНЫХ ПРОГРАММАХ ДЛЯ УСТАНОВКИ         "
echo "=================================================================="
echo "1. KolourPaint       — Простой растровый графический редактор"
echo "                       (удобный аналог MS Paint для Linux)."
echo "2. Telegram Desktop  — Официальный клиент мессенджера Telegram."
echo "3. Vivaldi Browser   — Быстрый и гибко настраиваемый веб-браузер."
echo "4. VSCodium          — Полноценная среда разработки VS Code,"
echo "                       полностью очищенная от телеметрии Microsoft."
echo "=================================================================="
echo ""

echo "Выберите режим установки:"
echo "  [1] Установить ВСЕ программы"
echo "  [2] Указать цифры программ, которые НУЖНО установить (например: 1,3)"
echo "  [3] Указать цифры программ, которые НЕ НУЖНО устанавливать (например: 2,4)"
echo ""
read -p "Введите номер режима (1, 2 или 3): " MODE

# Флаги установки для каждой программы
INST_1=0
INST_2=0
INST_3=0
INST_4=0

case "$MODE" in
  1)
    INST_1=1; INST_2=1; INST_3=1; INST_4=1
    ;;
  2)
    read -p "Введите номера через запятую для УСТАНОВКИ: " IN_NUMS
    IN_NUMS=$(echo "$IN_NUMS" | tr -d " ")
    IFS="," read -ra ADDR <<< "$IN_NUMS"
    for i in "${ADDR[@]}"; do
      case "$i" in
        1) INST_1=1 ;;
        2) INST_2=1 ;;
        3) INST_3=1 ;;
        4) INST_4=1 ;;
      esac
    done
    ;;
  3)
    INST_1=1; INST_2=1; INST_3=1; INST_4=1
    read -p "Введите номера через запятую для ИСКЛЮЧЕНИЯ: " EX_NUMS
    EX_NUMS=$(echo "$EX_NUMS" | tr -d " ")
    IFS="," read -ra ADDR <<< "$EX_NUMS"
    for i in "${ADDR[@]}"; do
      case "$i" in
        1) INST_1=0 ;;
        2) INST_2=0 ;;
        3) INST_3=0 ;;
        4) INST_4=0 ;;
      esac
    done
    ;;
  *)
    echo "Неверный ввод. Завершение работы."
    exit 1
    ;;
esac

if [ "$INST_1" -eq 0 ] && [ "$INST_2" -eq 0 ] && [ "$INST_3" -eq 0 ] && [ "$INST_4" -eq 0 ]; then
  echo "Ни одна программа не выбрана. Выход."
  exit 0
fi

echo -e "\n=== [1/2] Обновление базовых утилит ==="
apt update -y
apt install -y wget curl gpg apt-transport-https

echo -e "\n=== [2/2] Установка выбранных программ ==="

if [ "$INST_1" -eq 1 ]; then
  echo "--> Установка KolourPaint..."
  apt install -y kolourpaint
fi

if [ "$INST_2" -eq 1 ]; then
  echo "--> Установка Telegram..."
  apt install -y telegram-desktop
fi

if [ "$INST_3" -eq 1 ]; then
  echo "--> Настройка репозитория и установка Vivaldi..."
  wget -qO- https://repo.vivaldi.com/archive/vivaldi-256bit.gpg | gpg --dearmor --yes -o /usr/share/keyrings/vivaldi-browser.gpg
  echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=amd64] https://repo.vivaldi.com/archive/deb/ stable main" | tee /etc/apt/sources.list.d/vivaldi.list > /dev/null
  apt update -y
  apt install -y vivaldi-stable
fi

if [ "$INST_4" -eq 1 ]; then
  echo "--> Настройка репозитория и установка VSCodium..."
  wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor --yes -o /usr/share/keyrings/vscodium-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg arch=amd64] https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/debs vscodium main" | tee /etc/apt/sources.list.d/vscodium.list > /dev/null
  apt update -y
  apt install -y codium
fi

echo -e "\n=========================================="
echo "   Выбранный процесс установки завершен! "
echo "=========================================="
'