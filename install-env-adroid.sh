#!/usr/bin/env bash
# =============================================================================
#  Установка окружения для того чтобы собирать apk на Ubuntu/Debian
#  Запуск:  sudo bash install-env.sh
#  Что делает:
#   1) ставит системные пакеты (build tools, Java, git, gh)
#   2) скачивает и устанавливает Android commandline-tools + SDK + NDK
#   3) проверяет результат
# =============================================================================
set -euo pipefail

echo "==> [1/6] Обновляем пакеты"
apt-get update
apt-get -y upgrade

echo "==> [2/6] Ставим базовые зависимости сборки"
# Build tools: autotools, cmake, gcc/g++ и т.п.
apt-get -y install \
    automake ant autopoint build-essential cmake \
    libtool-bin patch pkg-config protobuf-compiler ragel \
    subversion unzip zip flex python3 python3-pip wget curl \
    gettext autoconf m4 gawk bison bzip2 \
    file gperf nasm p7zip-full ca-certificates || true

# 32-битные библиотеки (нужны старым бинарям Android SDK)
dpkg --add-architecture i386 || true
apt-get update
apt-get -y install libc6:i386 libstdc++6:i386 zlib1g:i386 || \
    echo "  (i386 libs не найдены - не критично для новых версий)"

echo "==> [3/6] Ставим Java (нужна для Gradle vlc-android)"
# Gradle 9/AGP 9 требуют JDK 17+. Ставим 17 и 21, скрипт setup-env.sh выберет.
apt-get -y install openjdk-17-jdk openjdk-17-jre openjdk-21-jdk openjdk-21-jre || true

echo "==> [4/6] Ставим GitHub CLI (gh)"
# gh нужен для форка/PR; если у вас свой токен - можно пропустить
if command -v gh >/dev/null 2>&1; then
    echo "  gh уже установлен"
else
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list
    apt-get update
    apt-get -y install gh
fi

echo "==> [5/6] Устанавливаем Android SDK/NDK в /opt/android-sdk"
SDK_ROOT="${ANDROID_HOME:-/opt/android-sdk}"
# Версии для текущего master vlc-android (compileSdk 36, build-tools 36)
NDK21="21.4.7075529"     # NDK для ветки VLC 3.x
NDK28="28.2.13676358"    # NDK для ветки VLC 4.x
CMDLINE_VERSION="11076708"

mkdir -p "$SDK_ROOT"
cd /tmp

if [ ! -f "/tmp/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip" ]; then
    echo "  Скачиваем commandline-tools..."
    curl -fsSL -o "commandlinetools-linux-${CMDLINE_VERSION}_latest.zip" \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_VERSION}_latest.zip"
fi
mkdir -p "$SDK_ROOT/cmdline-tools"
unzip -o -q "commandlinetools-linux-${CMDLINE_VERSION}_latest.zip" -d "$SDK_ROOT/cmdline-tools"
if [ ! -d "$SDK_ROOT/cmdline-tools/latest" ]; then
    mv "$SDK_ROOT/cmdline-tools/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
fi

yes | "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null || true
echo "yes" > "$SDK_ROOT/licenses/android-sdk-license"

echo "  Устанавливаем SDK packages (platform 36, build-tools 36, NDK 21 + 28)"
# --licenses автоматически принимает лицензии; пакеты ставятся по одному,
# чтобы каждая ошибка была видна отдельно.
for pkg in \
    "platform-tools" \
    "build-tools;36.0.0" \
    "platforms;android-36" \
    "ndk;$NDK21" \
    "ndk;$NDK28"; do
    echo "    + $pkg"
    "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --install "$pkg" </dev/null \
        | { grep -v "^Info:" || true; } || echo "    ! сбой установки $pkg (продолжаем)"
done

echo "==> [6/6] Даём пользователю права на SDK (чтобы не нужен был sudo)"
LSUSER="${SUDO_USER:-$USER}"
chown -R "$LSUSER":"$LSUSER" "$SDK_ROOT" 2>/dev/null || true

echo ""
echo "================================================"
echo "  ПРОВЕРКА УСТАНОВКИ"
echo "================================================"
java -version 2>&1 | head -1 || echo "НЕТ Java (проблема)"
git --version 2>&1 || echo "НЕТ git"
gh --version 2>&1 | head -1 || echo "НЕТ gh"
echo "  SDK packages:"
ls "$SDK_ROOT/platforms" 2>/dev/null | sed 's/^/    platform: /'
ls "$SDK_ROOT/build-tools" 2>/dev/null | sed 's/^/    build-tools: /'
ls "$SDK_ROOT/ndk" 2>/dev/null | sed 's/^/    ndk: /'
[ -x "$SDK_ROOT/platform-tools/adb" ] && echo "  adb: OK" || echo "  adb: НЕТ"
echo ""
echo "  ANDROID_HOME=$SDK_ROOT"
echo "================================================"
echo "  ВСЁ ГОТОВО. В обычном shell (без sudo) выполните один раз:"
echo "    source ~/vlc-setup/setup-env.sh"
echo "  затем сборка APK:"
echo "    bash ~/vlc-setup/build-apk.sh"
