sudo bash -c '
set -e

echo "=== [1/5] Обновление списков и установка утилит ==="
apt update -y
apt install -y wget curl gpg apt-transport-https

echo -e "\n=== [2/5] Установка KolourPaint и Telegram ==="
apt install -y kolourpaint telegram-desktop

echo -e "\n=== [3/5] Настройка репозитория Vivaldi ==="
wget -qO- https://repo.vivaldi.com/archive/vivaldi-256bit.gpg | gpg --dearmor --yes -o /usr/share/keyrings/vivaldi-browser.gpg
echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=amd64] https://repo.vivaldi.com/archive/deb/ stable main" | tee /etc/apt/sources.list.d/vivaldi.list > /dev/null

echo -e "\n=== [4/5] Настройка репозитория VSCodium ==="
wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor --yes -o /usr/share/keyrings/vscodium-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg arch=amd64] https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/debs vscodium main" | tee /etc/apt/sources.list.d/vscodium.list > /dev/null

echo -e "\n=== [5/5] Установка Vivaldi и VSCodium ==="
apt update -y
apt install -y vivaldi-stable codium

echo -e "\n=========================================="
echo "   Установка успешно завершена!          "
echo "=========================================="
'