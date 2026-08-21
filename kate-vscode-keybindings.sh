#!/usr/bin/env bash
# Applies VS Code-style bindings to Kate.
# Idempotent: safe to run multiple times. Requires python3.
set -euo pipefail

KATE_UI="$HOME/.local/share/kxmlgui5/kate/kateui.rc"
KATEPART_UI="$HOME/.local/share/kxmlgui5/katepart/katepart5ui.rc"
FILETREE_UI="$HOME/.local/share/kxmlgui5/katefiletree/ui.rc"
KATER="$HOME/.config/katerc"
KDE_GLOBALS="$HOME/.config/kdeglobals"
KATE_LAUNCHER="$HOME/.local/share/applications/org.kde.kate.desktop"
KOVERRIDE="$HOME/.config/klanguageoverridesrc"
PROFILE="$HOME/.profile"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required." >&2
    exit 1
fi

TS="$(date +%Y%m%d%H%M%S)"
for f in "$KATE_UI" "$KATEPART_UI" "$FILETREE_UI" "$KATER" "$KDE_GLOBALS" "$KATE_LAUNCHER" "$KOVERRIDE" "$PROFILE"; do
    [ -f "$f" ] && cp "$f" "$f.bak-$TS"
done

python3 - "$KATEPART_UI" "$KATE_UI" "$KATER" "$KDE_GLOBALS" "$KOVERRIDE" <<'PY'
import re
import os
import sys

katepart_ui, kate_ui, kater, kde_globals, koverride = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

EDITOR_ACTIONS = [
    ("tools_toggle_comment", "Ctrl+Q"),
    ("edit_create_multi_cursor_down", "Ctrl+Alt+Down"),
    ("edit_create_multi_cursor_up", "Ctrl+Alt+Up"),
    ("tools_scripts_moveLinesDown", "Alt+Down"),
    ("tools_scripts_moveLinesUp", "Alt+Up"),
    ("tools_unindent", "Ctrl+["),
    ("tools_indent", "Ctrl+]"),
]

MAIN_ACTIONS = [
    ("file_rename", "F2"),
    ("file_quit", ""),
    ("view_next_tab", "Ctrl+Tab"),
    ("view_prev_tab", "Ctrl+Shift+Tab"),
    ("view_history_back", "Alt+Left"),
    ("view_history_forward", "Alt+Right"),
]

MDI_ACTIONS = {
    "kate_mdi_sidebar_visibility": "Ctrl+1",
    "kate_mdi_toolview_kate_private_plugin_katekonsoleplugin": "Ctrl+2",
    "kate_mdi_hide_toolviews": "Ctrl+3",
}

PROJECT_ACTIONS = {
    "restoreProjectsForSessions": "true",
}

KATE_LANG_ACTIONS = {
    "kate": "ru",
}

ACTION_TAG = re.compile(r"<Action\b[^>]*>")
ATTR = re.compile(r'(name|shortcut)\s*=\s*"([^"]*)"')

def parse_action(tag):
    d = dict(ATTR.findall(tag))
    return d.get("name", ""), d.get("shortcut", "")

def serialize_action(name, shortcut, indent):
    return "%s<Action shortcut=\"%s\" name=\"%s\"/>" % (indent, shortcut, name)

def merge_xml(path, entries):
    if not os.path.exists(path):
        raise SystemExit("missing file: " + path)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = list(re.finditer(r"(?P<indent>[ \t]*)<ActionProperties(?P<open>[^>]*)>(?P<inner>.*?)</ActionProperties>", text, re.S))
    if not m:
        raise SystemExit("no <ActionProperties> block found in " + path)
    blk = m[-1]
    indent, inner = blk.group("indent"), blk.group("inner")
    merged = {}
    for tag in ACTION_TAG.findall(inner):
        name, shortcut = parse_action(tag)
        if name:
            merged[name] = shortcut
    for name, shortcut in entries:
        merged[name] = shortcut
    action_indent = indent + "  "
    body = "".join(serialize_action(n, s, action_indent) + "\n" for n, s in merged.items())
    new_block = "%s<ActionProperties%s>\n%s%s</ActionProperties>" % (indent, blk.group("open"), body, indent)
    text = text[: blk.start()] + new_block + text[blk.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

def set_ini(path, group, entries):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    else:
        lines = []
    gi = None
    for i, ln in enumerate(lines):
        if ln.strip().lower() == "[" + group.lower() + "]":
            gi = i
            break
    if gi is None:
        lines.append("[" + group + "]")
        gi = len(lines) - 1
        lines.append("")
    end = len(lines)
    for j in range(gi + 1, len(lines)):
        s = lines[j].strip()
        if s.startswith("[") and s.endswith("]"):
            end = j
            break
    found = {}
    for j in range(gi + 1, end):
        ln = lines[j]
        if "=" in ln and not ln.strip().startswith("#"):
            found[ln.split("=", 1)[0].strip()] = j
    for k, v in entries.items():
        line = k + "=" + v
        if k in found:
            lines[found[k]] = line
        else:
            lines.insert(end, line)
            found[k] = end
            end += 1
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

def del_ini_key(path, group, key):
    if not os.path.exists(path):
        return False
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    gi = None
    for i, ln in enumerate(lines):
        if ln.strip().lower() == "[" + group.lower() + "]":
            gi = i
            break
    if gi is None:
        return False
    removed = False
    out = []
    for i, ln in enumerate(lines):
        if i > gi and ln.strip().lower().startswith("[") and ln.strip().endswith("]"):
            out.extend(lines[i:])
            break
        if i > gi and "=" in ln and ln.split("=", 1)[0].strip().lower() == key.lower():
            removed = True
            continue
        out.append(ln)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return removed

merge_xml(katepart_ui, EDITOR_ACTIONS)
print("OK: merged editor actions into", katepart_ui)
merge_xml(kate_ui, MAIN_ACTIONS)
print("OK: merged main-window actions into", kate_ui)
set_ini(kater, "Shortcuts", MDI_ACTIONS)
print("OK: merged MDI actions into", kater)
set_ini(kater, "project", PROJECT_ACTIONS)
print("OK: enabled session project restore in", kater)
if del_ini_key(kde_globals, "Locale", "Language"):
    print("OK: removed Language=ru from [Locale] in", kde_globals)
else:
    print("OK: no Language entry in [Locale] of", kde_globals)
set_ini(koverride, "Language", KATE_LANG_ACTIONS)
print("OK: set per-app language kate=ru in", koverride)
PY

if [ -f "$PROFILE" ] && grep -q '^export LC_ALL="ru_RU.UTF-8"' "$PROFILE"; then
    sed -i 's|^export LC_ALL="ru_RU.UTF-8"|export LC_ALL="en_US.UTF-8"|' "$PROFILE"
    echo "OK: restored $PROFILE (LC_ALL ru_RU.UTF-8 -> en_US.UTF-8)"
else
    echo "OK: $PROFILE already OK (no ru_RU.UTF-8 LC_ALL export)"
fi

mkdir -p "$(dirname "$FILETREE_UI")"
cat > "$FILETREE_UI" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="katefiletreeplugin" library="katefiletreeplugin" version="10" translationDomain="katefiletree">
  <MenuBar>
    <Menu name="go">
      <text>&amp;Go</text>
      <Action name="filetree_prev_document" group="switch_document"/>
      <Action name="filetree_next_document" group="switch_document"/>
      <Action name="filetree_show_active_document" group="switch_document"/>
    </Menu>
  </MenuBar>
  <ActionProperties scheme="Default">
    <Action shortcut="" name="filetree_prev_document"/>
    <Action shortcut="" name="filetree_next_document"/>
  </ActionProperties>
</gui>
XML
echo "OK: freed Alt+Up/Alt+Down in filetree plugin -> $FILETREE_UI"

if [ -f "$KATE_LAUNCHER" ] && grep -q "LANGUAGE=ru" "$KATE_LAUNCHER"; then
    rm -f "$KATE_LAUNCHER"
    echo "OK: removed custom Kate launcher (menu uses the system entry again)"
else
    echo "OK: no custom Kate launcher present"
fi

echo
echo "Applied bindings:"
echo
printf '  %-45s %s\n' "ACTION" "SHORTCUT"
printf '  %-45s %s\n' "-----" "--------"
echo
echo "  -- Editor (katepart5ui.rc) --"
for pair in \
    "tools_toggle_comment|Ctrl+Q" \
    "edit_create_multi_cursor_down|Ctrl+Alt+Down" \
    "edit_create_multi_cursor_up|Ctrl+Alt+Up" \
    "tools_scripts_moveLinesDown|Alt+Down (move line down)" \
    "tools_scripts_moveLinesUp|Alt+Up (move line up)" \
    "tools_unindent|Ctrl+[" \
    "tools_indent|Ctrl+]"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "  -- Main window (kateui.rc) --"
for pair in \
    "file_quit (Ctrl+Q quit)|disabled" \
    "view_next_tab|Ctrl+Tab" \
    "view_prev_tab|Ctrl+Shift+Tab" \
    "view_history_back|Alt+Left" \
    "view_history_forward|Alt+Right"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "  -- MDI tool views (katerc) --"
for pair in \
    "kate_mdi_sidebar_visibility|Ctrl+1" \
    "kate_mdi_toolview_kate_private_plugin_katekonsoleplugin|Ctrl+2" \
    "kate_mdi_hide_toolviews|Ctrl+3"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "  -- Conflict removal (katefiletree/ui.rc) --"
for pair in \
    "filetree_prev_document|disabled (frees Alt+Up)" \
    "filetree_next_document|disabled (frees Alt+Down)"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "  -- Session behavior (katerc) --"
for pair in \
    "restoreProjectsForSessions|true (Restore opened projects)"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "  -- Language (system English, Kate Russian) --"
for pair in \
    "~/.profile LC_ALL|restored to en_US.UTF-8 (English session)" \
    "klanguageoverridesrc|kate=ru (per-app Russian, any launch method)" \
    "Locale/Language (kdeglobals)|removed (was inert)" \
    "custom Kate launcher|removed (menu uses system entry)"; do
    printf '  %-45s %s\n' "${pair%%|*}" "${pair##*|}"
done
echo
echo "NOTE: Kate language is set per-app via ~/.config/klanguageoverridesrc"
echo "(KXmlGui prepends it to \$LANGUAGE at startup). The rest of the system"
echo "follows the session locale: LC_ALL=en_US.UTF-8 in ~/.profile."
echo "Log out and back in for the English session to take effect; Kate stays"
echo "Russian regardless. If the overrides file ever gets clobbered with"
echo "'en_US', just re-run this script to restore kate=ru."
echo "Skipped (no Kate equivalent): debugger, python, problems panel, REPL, editor groups, panes, terminal copy/paste."
echo
echo "NOTE: after enabling session project restore, Kate saves the session"
echo "automatically when it closes. Just close and reopen Kate."
echo
echo "Done. Backups: *.bak-$TS"
echo "Restart Kate for the bindings to take effect."
if pgrep -x kate >/dev/null 2>&1; then
    echo "Kate is running - close and reopen it."
fi