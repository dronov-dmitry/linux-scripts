for p in \
  com.xiaomi.mipicks \
  com.miui.android.fashiongallery \
  com.xiaomi.discover \
  com.miui.msa.global
do
  echo "Обрабатываю $p..."

  result=$(adb shell pm uninstall -k --user 0 "$p" 2>&1)

  if echo "$result" | grep -q "Success"; then
    echo "  ✓ Удалён"
  else
    echo "  ! Удаление невозможно: $result"
    echo "  → Отключаю пакет..."

    adb shell pm disable-user --user 0 "$p"

    if [ $? -eq 0 ]; then
      echo "  ✓ Отключён"
    else
      echo "  ✗ Не удалось отключить"
    fi
  fi
done

echo "Готово."
