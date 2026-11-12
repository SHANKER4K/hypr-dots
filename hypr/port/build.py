#!/usr/bin/env python3
"""Regenerate ~/.config/hypr/hyprland.lua from the hyprlang rice.

Hyprland 0.57 dropped .conf configs; this expands $vars the way hyprlang did
(including alpha suffixes: $primarye6 = $primary .. "e6"), runs every module
through hyprlang2lua (wasm, local copy), and concatenates them in source order
so shared `local`s stay in scope.

  ./build.sh              # regenerate + verify + install hyprland.lua
  ./build.sh --dry-run    # regenerate + verify only (writes ./hyprland.lua)

The .conf files remain the source of truth. Values from scheme/current.conf are
baked in at build time, so re-run this after changing the colour scheme.
"""
import re
import subprocess
import sys
from pathlib import Path

HYPR = Path.home() / ".config/hypr"
BASE = Path(__file__).resolve().parent
WORK = BASE / "work"
OUT_FILE = BASE / "hyprland.lua"
VAR_RE = re.compile(r"\$([A-Za-z0-9_-]+)")
DEF_RE = re.compile(r"^\s*\$([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*$")

GESTURES_LUA = """-- Hand-written: 0.57 has no `gesture = ..., dispatcher` action.
hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.15,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
    },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "special" })
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function() hl.dsp.exec_cmd("caelestia toggle specialws") end,
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function() hl.dsp.exec_cmd("systemctl suspend-then-hibernate") end,
})
"""

HEADER = """-- hyprland.lua — generated from the hyprlang rice by port/build.sh
-- (Hyprland 0.57 removed .conf configs). Single file on purpose: hyprlang
-- shared one variable namespace across sourced files, but hyprlang2lua emits
-- per-module `local`s. Edit ~/.config/hypr/hyprland/*.conf + variables.conf,
-- then run ~/.config/hypr/port/build.sh to regenerate this file.
-- Colour values are baked in from scheme/current.conf at build time.
"""


def fix_layer_rules(text: str) -> str:
    # converter keeps the v1 `match:namespace X` matcher inside the value
    text = re.sub(r'namespace = "match:namespace ([^"]+)"', r'namespace = "\1"', text)
    text = text.replace(
        '    -- TODO: manual review — unmapped layer rule: "no_anim true"\n',
        "    no_anim = true,\n",
    )
    return text


def fix_binds(text: str) -> str:
    # converter invented a `prev` field; the API only has `next` (bool)
    text = text.replace("cycle_next({ prev = true })", "cycle_next({ next = false })")
    # lock_active is deprecated in 0.57, group.lock() toggles by default
    text = text.replace('group.lock_active({ action = "toggle" })', "group.lock()")
    # source wrote mods as "SUPER + Shift"; converter doubled the separator
    text = text.replace('"SUPER + + + SHIFT + W"', '"SUPER + SHIFT + W"')
    return text


def strip_comment(value: str) -> str:
    return re.sub(r"\s+#.*$", "", value).strip()


def expand(text: str, table: dict[str, str]) -> str:
    def repl(m: re.Match) -> str:
        name = m.group(1)
        if name in table:
            return table[name]
        # hyprlang longest-prefix rule: $surfaced4 = $surface .. "d4"
        for size in range(len(name) - 1, 0, -1):
            if name[:size] in table:
                return table[name[:size]] + name[size:]
        return m.group(0)  # undeclared: leave for sh ($HOME, $XDG_*)

    return VAR_RE.sub(repl, text)


def expand_file(path: Path, table: dict[str, str]) -> str:
    out = []
    for line in path.read_text().splitlines():
        m = DEF_RE.match(line)
        if m:
            table[m.group(1)] = expand(strip_comment(m.group(2)), table)
            # emit expanded: the converter can't resolve alpha suffixes itself
            out.append(f"${m.group(1)} = {table[m.group(1)]}")
            continue
        out.append(expand(line, table))
    return "\n".join(out) + "\n"


def convert(src: Path, dst: Path) -> None:
    r = subprocess.run(
        ["node", str(BASE / "convert.js"), str(src), str(dst)],
        cwd=BASE, capture_output=True, text=True,
    )
    if r.returncode not in (0, 3):
        print(r.stderr, file=sys.stderr)
        raise SystemExit(f"convert failed: {src}")
    print(f"{src.name}: {r.stderr.strip()}")


def build() -> None:
    table: dict[str, str] = {}
    mods = [
        HYPR / "scheme/current.conf",
        HYPR / "variables.conf",
        HYPR / "hyprland/monitors.conf",
        HYPR / "hyprland/env.conf",
        HYPR / "hyprland/general.conf",
        HYPR / "hyprland/input.conf",
        HYPR / "hyprland/misc.conf",
        HYPR / "hyprland/animations.conf",
        HYPR / "hyprland/decoration.conf",
        HYPR / "hyprland/group.conf",
        HYPR / "hyprland/execs.conf",
        HYPR / "hyprland/rules.conf",
        HYPR / "hyprland/gestures.conf",
        HYPR / "hyprland/keybinds.conf",
        HYPR / "hyprland/scrolling.conf",
    ]
    WORK.mkdir(exist_ok=True)
    pieces = []
    for path in mods:
        expanded = WORK / (path.stem + ".conf")
        text = expand_file(path, table)
        if path.name == "keybinds.conf":
            # the whole rice was inside `submap global`, activated by an exec;
            # top-level binds are behaviourally equivalent and simpler here
            drop = {"exec = hyprctl dispatch submap global", "submap = global"}
            text = "\n".join(l for l in text.splitlines() if l.strip() not in drop) + "\n"
        if path.name == "gestures.conf":
            (WORK / "gestures.lua").write_text(GESTURES_LUA)
            print("gestures.conf: hand-written (dispatcher gestures)")
        else:
            expanded.write_text(text)
            convert(expanded, WORK / (path.stem + ".lua"))
            lua = WORK / (path.stem + ".lua")
            out = lua.read_text()
            if path.name == "rules.conf":
                out = fix_layer_rules(out)
            elif path.name == "keybinds.conf":
                out = fix_binds(out)
            elif path.name == "current.conf":
                # every value is a hex colour; keep them strings, not numbers
                out = re.sub(r'^(local [A-Za-z0-9_]+ = )([0-9]+)$', r'\1"\2"', out, flags=re.M)
            lua.write_text(out)
        pieces.append(f"-- ===== {path.name} =====\n" + (WORK / (path.stem + ".lua")).read_text())

    # entry point: sources are inlined above, keep its exec hooks
    main_expanded = WORK / "hyprland.conf"
    main_expanded.write_text(expand_file(HYPR / "hyprland.conf", table))
    convert(main_expanded, WORK / "entry.lua")
    main_txt = (WORK / "entry.lua").read_text()
    idx = main_txt.find('hl.on("')
    hooks = main_txt[idx:] if idx >= 0 else ""

    OUT_FILE.write_text(HEADER + "\n" + "\n".join(pieces) + "\n" + hooks + "\n")
    print(f"wrote {OUT_FILE}")


def verify() -> bool:
    r = subprocess.run(
        ["hyprland", "--verify-config", "--config", str(OUT_FILE)],
        capture_output=True, text=True,
    )
    ok = "config ok" in r.stdout
    print("verify:", "ok" if ok else r.stdout[-800:] + r.stderr[-800:])
    return ok


def main() -> None:
    build()
    if not verify():
        raise SystemExit("refusing to install: config does not verify")
    if "--install" in sys.argv:
        (HYPR / "hyprland.lua").write_text(OUT_FILE.read_text())
        print(f"installed {HYPR / 'hyprland.lua'} — run: hyprctl reload")


if __name__ == "__main__":
    main()
