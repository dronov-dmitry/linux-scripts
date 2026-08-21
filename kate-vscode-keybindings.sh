#!/usr/bin/env bash
# Applies VS Code-style bindings to Kate.
# Idempotent: safe to run multiple times. Requires python3.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    if [ -n "${SUDO_USER:-}" ]; then
        echo "ERROR: don't run this script with sudo (you are: $SUDO_USER)." >&2
        echo "It must modify YOUR home, not /root. Run it as a regular user:" >&2
        echo "  bash '$0'" >&2
    else
        echo "ERROR: running as root - \$HOME is /root, not the user's home." >&2
        echo "Run it as a regular user:" >&2
        echo "  bash '$0'" >&2
    fi
    exit 1
fi

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

KXMLGUI_DIR="$HOME/.local/share/kxmlgui5"
mkdir -p "$KXMLGUI_DIR/kate" "$KXMLGUI_DIR/katepart"

if [ ! -f "$KATEPART_UI" ]; then
    cat > "$KATEPART_UI" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="KatePartView" version="101" translationDomain="ktexteditor5">
<MenuBar>
  <Menu name="file" noMerge="1"><text>&amp;File</text>
    <Action name="file_save" group="save_merge" />
    <Action name="file_save_as" group="save_merge" />
    <Action name="file_save_as_with_encoding" group="save_merge" />
    <Action name="file_save_copy_as" group="save_merge" />
    <Action name="file_reload" group="revert_merge" />
    <Menu name="file_export" group="print_merge"><text>Export/Print</text>
      <Action name="file_print" group="print_merge" />
      <Action name="file_print_preview" group="print_merge" />
      <Action name="file_export_html" group="print_merge" />
    </Menu>
  </Menu>

  <Menu name="edit" noMerge="1"><text>&amp;Edit</text>
    <Action name="edit_undo" group="edit_undo_merge" />
    <Action name="edit_redo" group="edit_undo_merge" />
    <Separator group="edit_undo_merge" />
    <Action name="edit_cut" group="edit_paste_merge" />
    <Action name="edit_copy" group="edit_paste_merge" />
    <Action name="edit_copy_html" group="edit_paste_merge" />
    <Action name="edit_paste" group="edit_paste_merge" />
    <Action name="edit_paste_selection" group="edit_paste_merge" />
    <Action name="edit_swap_with_clipboard" group="edit_paste_merge" />
    <Action name="clipboard_history_paste" group="edit_paste_merge" />/>
    <Separator group="edit_select_merge" />
    <Action name="view_input_modes" group="edit_select_merge" />
    <Action name="set_insert" group="edit_select_merge" />
    <Action name="tools_toggle_write_lock" group="edit_select_merge" />
    <Separator group="edit_select_merge" />
    <Action name="edit_find" group="edit_find_merge" />
    <Menu name="edit_find_menu" group="edit_find_merge"><text>Find Variants</text>
      <Action name="edit_find_next" group="edit_find_merge" />
      <Action name="edit_find_prev" group="edit_find_merge" />
      <Action name="edit_find_selected" group="edit_find_merge" />
      <Action name="edit_find_selected_backwards" group="edit_find_merge" />
    </Menu>
    <Action name="edit_replace" group="edit_find_merge" />
    <Separator group="edit_find_merge" />
  </Menu>

  <Menu name="selection" noMerge="1"><text>Selection</text>
    <Action name="edit_select_all" group="edit_selection" />
    <Action name="edit_deselect" group="edit_selection" />
    <Action name="set_verticalSelect" group="edit_selection" />
    <Separator group="edit_selection"/>
    <Action name="tools_toggle_comment" group="edit_selection" />
    <Action name="tools_join_lines" group="edit_selection" />
    <Menu name="capitalization" group="edit_selection"><text>Capitalization</text>
      <Action name="tools_uppercase" group="edit_selection" />
      <Action name="tools_lowercase" group="edit_selection" />
      <Action name="tools_capitalize" group="edit_selection" />
    </Menu>
    <Separator group="edit_selection"/>
    <Action name="tools_cleanIndent" group="edit_selection" />
    <Action name="tools_formatIndent" group="edit_selection" />
    <Action name="tools_alignOn" group="edit_selection" />
    <Action name="tools_apply_wordwrap" group="edit_selection" />
    <Separator group="edit_selection"/>
    <Action name="edit_create_multi_cursor_up" group="edit_selection"/>
    <Action name="edit_create_multi_cursor_down" group="edit_selection"/>
    <Action name="edit_create_multi_cursor_from_sel" group="edit_selection"/>
    <Action name="edit_find_multicursor_next_occurrence" group="edit_selection"/>
    <Action name="edit_find_multicursor_all_occurrences" group="edit_selection"/>
  </Menu>

  <Menu name="view" noMerge="1"><text>&amp;View</text>
    <Action name="view_inc_font_sizes" group="view_operations" />
    <Action name="view_dec_font_sizes" group="view_operations" />
    <Action name="view_reset_font_sizes" group="view_operations" />
    <Separator group="view_operations" />
    <Menu name="view_menu_word_wrap" group="view_operations"><text>Word Wrap</text>
      <Action name="view_dynamic_word_wrap" group="view_operations" />
      <Action name="dynamic_word_wrap_indicators" group="view_operations" />
      <Action name="view_static_word_wrap" group="view_operations" />
      <Action name="view_word_wrap_marker" group="view_operations" />
    </Menu>
    <Menu name="view_menu_borders" group="view_operations"><text>Borders</text>
      <Action name="view_border" group="view_operations" />
      <Action name="view_line_numbers" group="view_operations" />
      <Action name="view_scrollbar_marks" group="view_operations" />
      <Action name="view_scrollbar_minimap" group="view_operations" />
      <Action name="view_scrollbar_minimap_all" group="view_operations" />
    </Menu>
    <Separator group="view_operations" />
    <Menu name="codefolding" group="view_operations"><text>&amp;Code Folding</text>
      <Action name="view_folding_markers" group="view_operations" />
      <Separator group="view_operations" />
      <Action name="folding_toggle_current" group="view_operations" />
      <Action name="folding_toggle_in_current" group="view_operations" />
      <Action name="folding_expandall" group="view_operations" />
      <Separator group="view_operations" />
      <Action name="folding_toplevel" group="view_operations" />
      <Action name="folding_expandtoplevel" group="view_operations" />
    </Menu>
    <Separator group="view_operations" />
    <Action name="view_auto_reload" group="view_operations" />
    <Action name="view_non_printable_spaces" group="view_operations" />
    <Action name="view_word_count" group="view_operations" />
  </Menu>

  <Menu name="go" noMerge="1"><text>&amp;Go</text>
    <Action name="go_goto_line" group="edit_goto"/>
    <Separator group="edit_goto" />
    <Action name="Previous Editing Line" group="edit_goto2"/>
    <Action name="Next Editing Line" group="edit_goto2"/>
    <Separator group="edit_goto2" />
    <Action name="modified_line_up" group="edit_goto2"/>
    <Action name="modified_line_down" group="edit_goto2"/>
    <Separator group="edit_goto2" />
    <Action name="to_matching_bracket" group="edit_goto2" />
    <Action name="select_matching_bracket" group="edit_goto2" />
    <Separator group="edit_goto2" />
    <Action name="bookmarks" group="edit_goto2" />
  </Menu>

  <Menu name="tools" noMerge="1"><text>&amp;Tools</text>
    <Action name="tools_mode" group="tools_operations" />
    <Action name="tools_highlighting" group="tools_operations" />
    <Action name="tools_indentation" group="tools_operations" />
    <Separator group="tools_operations" />
    <Action name="set_encoding" group="tools_operations" />
    <Action name="add_bom" group="tools_operations" />
    <Action name="set_eol" group="tools_operations" />
    <Separator group="tools_operations" />
    <Action name="tools_scripts" group="tools_operations2" />
    <Separator group="tools_operations2" />
    <Action name="switch_to_cmd_line" group="tools_operations2" />
    <Separator group="tools_operations2" />
    <Action name="tools_invoke_code_completion" group="tools_operations2" />
    <Menu name="wordcompletion" group="tools_operations2"><text>Word Completion</text>
      <Action name="doccomplete_fw" />
      <Action name="doccomplete_bw" />
      <Action name="doccomplete_sh" />
    </Menu>
    <Separator group="tools_operations2" />
    <Menu name="spelling" group="tools_spelling"><text>Spelling</text>
      <Action name="tools_toggle_automatic_spell_checking" group="tools_spelling" />
      <Action name="tools_spelling" group="tools_spelling" />
      <Action name="tools_spelling_from_cursor" group="tools_spelling" />
      <Action name="tools_spelling_selection" group="tools_spelling" />
      <Action name="tools_change_dictionary" group="tools_spelling" />
      <Action name="tools_clear_dictionary_ranges" group="tools_spelling" />
    </Menu>
  </Menu>

  <Menu name="settings" noMerge="1"><text>&amp;Settings</text>
    <Action name="view_schemas" group="color" />
    <Action name="set_confdlg" group="configure_merge" />
  </Menu>
</MenuBar>

<Menu name="ktexteditor_popup" noMerge="0">
  <Action name="spelling_suggestions" group="popup_operations" />
  <Separator group="popup_operations" />
  <Action name="edit_cut" group="popup_operations" />
  <Action name="edit_copy" group="popup_operations" />
  <Action name="edit_paste" group="popup_operations" />
  <Action name="edit_paste_selection" group="popup_operations" />
  <Action name="edit_swap_with_clipboard" group="popup_operations" />
  <Separator group="popup_operations" />
  <Action name="tools_scripts_Editing" group="popup_operations" />
  <Separator group="popup_operations" />
  <Action name="bookmarks" group="popup_operations" />
  <Separator group="popup_operations" />
  <Action name="tools_create_snippet" group="popup_operations" />
  <Separator group="popup_operations" />
</Menu>

<ToolBar name="mainToolBar" noMerge="1"><text>Main Toolbar</text>
  <Action name="file_save" group="file_operations" />
  <Action name="file_save_as" group="file_operations" />
  <Action name="edit_undo" group="edit_operations" />
  <Action name="edit_redo" group="edit_operations" />
</ToolBar>

<ActionProperties scheme="Default">
</ActionProperties>
</gui>
XML
    echo "OK: seeded $KATEPART_UI (default UI from KTextEditor 5.115)"
fi

if [ ! -f "$KATE_UI" ]; then
    cat > "$KATE_UI" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="kate" version="102" translationDomain="kate">
  <MenuBar>
    <Menu name="file" noMerge="1">
      <text>&amp;File</text>
      <Action name="file_new"/>
      <Action name="view_new_view"/>
      <DefineGroup name="new_merge"/>
      <Separator/>
      <Action name="file_open"/>
      <Action name="file_open_recent"/>
      <Action name="file_open_with"/>
      <DefineGroup name="open_merge"/>
      <Separator/>
      <DefineGroup name="save_merge"/>
      <Action name="file_save_all"/>
      <Separator/>
      <DefineGroup name="revert_merge"/>
      <Action name="file_reload_all"/>
      <DefineGroup name="print_merge"/>
      <DefineGroup name="export_merge"/>
      <Separator/>
      <Action name="file_close"/>
      <Action name="file_close_other"/>
      <Action name="file_close_all"/>
      <Action name="file_close_orphaned"/>
      <DefineGroup name="close_merge"/>
      <Separator/>
      <Menu name="file_file_actions"><text>File Actions</text>
        <Action name="file_rename"/>
        <Action name="file_delete"/>
        <Action name="file_compare"/>
        <Separator/>
        <Action name="file_copy_filepath"/>
        <Action name="file_open_containing_folder"/>
        <Action name="file_properties"/>
      </Menu>
      <Separator/>
      <Action name="file_quit"/>
    </Menu>
    <Menu name="edit">
      <text>&amp;Edit</text>
      <DefineGroup name="edit_undo_merge"/>
      <Separator group="edit_undo_merge"/>
      <DefineGroup name="edit_paste_merge"/>
      <Separator/>
      <DefineGroup name="edit_select_merge"/>
      <Separator/>
      <DefineGroup name="edit_find_merge"/>
      <Separator/>
    </Menu>
    <Menu name="selection" append="before_view">
      <text>&amp;Selection</text>
    </Menu>
    <Menu name="go">
      <text>&amp;Go</text>
      <Action name="view_quick_open" />
      <DefineGroup name="view_switch_tab"/>
      <Separator/>
      <DefineGroup name="edit_goto"/>
      <DefineGroup name="switch_document"/>
      <Separator/>
      <Action name="view_next_tab"/>
      <Action name="view_prev_tab"/>
      <Separator/>
      <Action name="view_history_back" />
      <Action name="view_history_forward" />
      <Separator/>
      <DefineGroup name="edit_goto2"/>
    </Menu>
    <Menu name="view">
      <text>&amp;View</text>
      <Menu name="view-split">
        <text>Split View</text>
        <Action name="go_prev_split_view"/>
        <Action name="go_next_split_view"/>
        <Separator/>
        <Action name="go_left_split_view"/>
        <Action name="go_right_split_view"/>
        <Action name="go_upward_split_view"/>
        <Action name="go_downward_split_view"/>
        <Separator/>
        <Action name="view_split_vert"/>
        <Action name="view_split_horiz"/>
        <Action name="view_split_vert_move_doc"/>
        <Action name="view_split_horiz_move_doc"/>
        <Action name="view_split_toggle"/>
        <Separator/>
        <Action name="view_close_current_space"/>
        <Action name="view_close_others"/>
        <Separator/>
        <Action name="view_hide_others"/>
        <Separator/>
        <Action name="view_split_move_left"/>
        <Action name="view_split_move_right"/>
        <Action name="view_split_move_up"/>
        <Action name="view_split_move_down"/>
      </Menu>
      <Separator/>
      <Merge name="kate_mdi_view_actions"/>
      <Separator/>
      <DefineGroup name="view_operations"/>
    </Menu>
    <DefineGroup name="after_view"/>
    <Merge/>
    <DefineGroup name="before_tools"/>
    <Menu name="tools">
      <text>&amp;Tools</text>
      <Action name="tools_external"/>
      <Separator/>
      <DefineGroup name="tools_operations"/>
      <DefineGroup name="tools_konsole"/>
      <Separator group="tools_konsole"/>
      <DefineGroup name="tools_snippet"/>
      <Separator group="tools_snippet"/>
      <DefineGroup name="tools_operations2"/>
      <Separator group="tools_operations2"/>
      <DefineGroup name="tools_git_blame"/>
      <Separator group="tools_git_blame"/>
      <DefineGroup name="tools_spelling"/>
      <DefineGroup name="tools_operations3"/>
    </Menu>
    <Action name="sessions"/>
    <Menu name="settings">
      <text>&amp;Settings</text>
      <Action name="colorscheme_menu" group="color"/>
      <DefineGroup name="color"/>
      <Action name="settings_show_tab_bar" append="show_merge"/>
      <Action name="settings_show_full_path" append="show_merge"/>
      <Action name="settings_show_url_nav_bar" append="show_merge"/>
    </Menu>
    <Menu name="help">
      <text>&amp;Help</text>
      <Action name="help_welcome_page"/>
    </Menu>
  </MenuBar>
  <ToolBar name="mainToolBar" noMerge="1">
    <text>Main Toolbar</text>
    <Action name="file_new"/>
    <Action name="file_open"/>
    <Separator/>
    <DefineGroup name="file_operations"/>
    <Separator/>
    <DefineGroup name="print_merge"/>
    <Separator/>
    <DefineGroup name="edit_operations"/>
    <Separator/>
    <DefineGroup name="find_operations"/>
    <Separator/>
    <DefineGroup name="zoom_operations"/>
  </ToolBar>
  <Merge/>
  <ToolBar noMerge="1" name="hamburgerBar">
    <text>Hamburger Menu Toolbar</text>
    <Spacer/>
    <Action name="hamburger_menu" />
  </ToolBar>
  <Menu name="ktexteditor_popup" noMerge="1">
    <DefineGroup name="popup_operations"/>
    <DefineGroup name="popup_operations2"/>
  </Menu>
  <Menu name="viewspace_popup" noMerge="1">
    <Action name="view_split_vert"/>
    <Action name="view_split_horiz"/>
    <Separator/>
    <Action name="view_close_current_space"/>
    <Separator/>
    <Action name="go_back"/>
    <Action name="go_forward"/>
    <Action name="doc_list"/>
    <Menu name="viewspace_popup_statusbar">
      <text>&amp;Status Bar Items</text>
      <Action name="show_cursor_pos"/>
      <Action name="show_char_count"/>
      <Action name="show_insert_mode"/>
      <Action name="show_select_mode"/>
      <Action name="show_encoding"/>
      <Action name="show_doc_name"/>
    </Menu>
  </Menu>
<ActionProperties scheme="Default">
</ActionProperties>
</gui>
<!-- kate: space-indent on; indent-width 2; replace-tabs on; -->
XML
    echo "OK: seeded $KATE_UI (default UI from Kate 23.08)"
fi

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
    # Reopen last closed file/tab. Action exists since Kate 24.05;
    # on older versions (e.g. 23.08) the entry is ignored.
    ("reopen_latest_closed_document", "Ctrl+Shift+T"),
    # Free Ctrl+Shift+T: it is the default for Split Horizontal,
    # otherwise KXmlGui complains about a conflicting shortcut.
    ("view_split_horiz", ""),
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
    "view_history_forward|Alt+Right" \
    "reopen_latest_closed_document|Ctrl+Shift+T (needs Kate >= 24.05)" \
    "view_split_horiz|disabled (frees Ctrl+Shift+T for reopen)"; do
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
