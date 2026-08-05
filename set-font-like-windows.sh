#!/usr/bin/env bash

set -e

echo "=== Настройка четких шрифтов (Windows Style) ==="

# 1. Создание каталога и очистка старых конфигов
mkdir -p "$HOME/.config/fontconfig"
rm -f "$HOME/.config/fontconfig/fonts.conf"

# 2. Запись правильного XML-файла Fontconfig
cat << 'EOF' > "$HOME/.config/fontconfig/fonts.conf"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
  </match>
  <match target="font">
    <edit name="hinting" mode="assign">
      <bool>true</bool>
    </edit>
  </match>
  <match target="font">
    <edit name="autohint" mode="assign">
      <bool>false</bool>
    </edit>
  </match>
  <match target="font">
    <edit name="hintstyle" mode="assign">
      <const>hintfull</const>
    </edit>
  </match>
  <match target="font">
    <edit name="rgba" mode="assign">
      <const>rgb</const>
    </edit>
  </match>
  <match target="font">
    <edit name="lcdfilter" mode="assign">
      <const>lcddefault</const>
    </edit>
  </match>
</fontconfig>
EOF

# 3. Применение параметров GTK / GNOME
if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.interface font-antialiasing 'rgba' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-hinting 'full' 2>/dev/null || true
fi

# 4. Обновление ресурсов X11
XRESOURCES="$HOME/.Xresources"
touch "$XRESOURCES"
sed -i '/Xft/d' "$XRESOURCES" 2>/dev/null || true

cat << 'EOF' >> "$XRESOURCES"
Xft.autohint: 0
Xft.lcdfilter: lcddefault
Xft.hintstyle: hintfull
Xft.hinting: 1
Xft.antialias: 1
Xft.rgba: rgb
EOF

if command -v xrdb &> /dev/null; then
    xrdb -merge "$XRESOURCES" 2>/dev/null || true
fi

# 5. Сброс кэша шрифтов
fc-cache -fv > /dev/null

echo "=== Готово! Проверка текущих параметров: ==="
fc-match -v Sans | grep -E "(antialias|hinting|hintstyle|rgba|lcdfilter)"