#!/usr/bin/env bash
set -euo pipefail

QSS="$HOME/.config/kate-dark.qss"
KATERC="${XDG_CONFIG_HOME:-$HOME/.config}/katerc"
DESKTOP_SRC="/usr/share/applications/org.kde.kate.desktop"
DESKTOP_DST="$HOME/.local/share/applications/org.kate.kate.desktop"

msg() { printf '%s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    msg "Ошибка: не запускай через sudo — настройки пишутся в домашний каталог пользователя."
    msg "Просто: bash $0"
    exit 1
fi

command -v kate >/dev/null 2>&1 || { msg "Ошибка: kate не найдена"; exit 1; }

if pgrep -x kate >/dev/null 2>&1 || pgrep -x kwrite >/dev/null 2>&1; then
    msg "ВНИМАНИЕ: Kate/KWrite запущены. Скрипт перезапишет настройки, поэтому"
    msg "лучше закрыть их сейчас и перезапустить после выполнения скрипта."
fi

mkdir -p "$(dirname "$KATERC")" "$HOME/.local/share/applications" "$(dirname "$QSS")"
[ -f "$KATERC" ] && cp "$KATERC" "$KATERC.bak.$(date +%Y%m%d%H%M%S)"

set_cfg() {
    local group="$1" key="$2" val="$3"
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file katerc --group "$group" --key "$key" "$val"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file katerc --group "$group" --key "$key" "$val"
    else
        python3 - "$KATERC" "$group" "$key" "$val" <<'PYEOF'
import sys, configparser, os
path, group, key, val = sys.argv[1:5]
cp = configparser.ConfigParser(interpolation=None, strict=False)
cp.optionxform = str
cp.read(path, encoding="utf-8")
if not cp.has_section(group):
    cp.add_section(group)
cp.set(group, key, val)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    cp.write(f, space_around_delimiters=False)
os.replace(tmp, path)
PYEOF
    fi
}

set_cfg "KTextEditor Renderer" "Auto Color Theme Selection" "false"
set_cfg "KTextEditor Renderer" "Color Theme" "Breeze Dark"
msg "[ok] Тема области редактора: Breeze Dark ($KATERC)"

cat > "$QSS" <<'QSSEOF'
* {
    outline: none;
}
QWidget {
    background-color: #2a2e32;
    color: #d8dcde;
    selection-background-color: #3daee9;
    selection-color: #ffffff;
}
QMenuBar {
    background-color: #2a2e32;
}
QMenuBar::item {
    background: transparent;
    padding: 4px 8px;
}
QMenuBar::item:selected {
    background-color: #3daee9;
    color: #ffffff;
}
QMenu {
    background-color: #31363b;
    border: 1px solid #464c52;
}
QMenu::item {
    padding: 4px 24px 4px 8px;
}
QMenu::item:selected {
    background-color: #3daee9;
    color: #ffffff;
}
QMenu::separator {
    height: 1px;
    background: #464c52;
    margin: 3px 6px;
}
QToolBar {
    background: #2a2e32;
    border: none;
    spacing: 2px;
}
QStatusBar {
    background: #2a2e32;
}
QPushButton {
    background-color: #31363b;
    border: 1px solid #464c52;
    border-radius: 3px;
    padding: 4px 12px;
}
QPushButton:hover {
    background-color: #3a4046;
    border-color: #3daee9;
}
QPushButton:pressed {
    background-color: #3daee9;
}
QLineEdit, QSpinBox, QComboBox, QPlainTextEdit {
    background-color: #232629;
    border: 1px solid #464c52;
    border-radius: 3px;
    padding: 2px 4px;
}
QComboBox QAbstractItemView {
    background-color: #31363b;
    selection-background-color: #3daee9;
}
QTabBar::tab {
    background: #2a2e32;
    padding: 4px 10px;
    border: 1px solid #464c52;
}
QTabBar::tab:selected {
    background: #31363b;
    border-bottom: 2px solid #3daee9;
}
QToolTip {
    background-color: #31363b;
    color: #d8dcde;
    border: 1px solid #464c52;
}
QScrollBar:vertical {
    background: #232629;
    width: 10px;
}
QScrollBar::handle:vertical {
    background: #545d66;
    min-height: 30px;
    border-radius: 3px;
}
QScrollBar:horizontal {
    background: #232629;
    height: 10px;
}
QScrollBar::handle:horizontal {
    background: #545d66;
    min-width: 30px;
    border-radius: 3px;
}
QTreeView, QListView, QTableView {
    alternate-background-color: #262b30;
}
QSSEOF
msg "[ok] Тёмная таблица стилей: $QSS"

if [ -f "$DESKTOP_SRC" ]; then
    sed "s|^Exec=kate|Exec=kate -stylesheet $QSS|" "$DESKTOP_SRC" > "$DESKTOP_DST"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    msg "[ok] Ярлык Kate теперь всегда запускает её с тёмной темой ($DESKTOP_DST)"
else
    msg "[!] Не найден $DESKTOP_SRC — запускай вручную: kate -stylesheet $QSS"
fi

if ! grep -q 'QT_QPA_PLATFORMTHEME' "$HOME/.profile" 2>/dev/null; then
    printf '\n# Qt-приложения следуют тёмной теме GTK\nexport QT_QPA_PLATFORMTHEME=gtk3\n' >> "$HOME/.profile"
    msg "[ok] В ~/.profile добавлен export QT_QPA_PLATFORMTHEME=gtk3 (для других Qt-приложений)"
fi

msg ""
msg "Готово. Перезапусти Kate (или запусти: kate -stylesheet $QSS)."
