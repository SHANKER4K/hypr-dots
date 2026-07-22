# hypr-dots

My Hyprland dotfiles — keyboard-driven, RTL-aware, Material You themed.

![Scheme](https://img.shields.io/badge/scheme-Material%20You-7c7cd4)
![WM](https://img.shields.io/badge/WM-Hyprland-8a8aff)
![Terminal](https://img.shields.io/badge/terminal-foot-eee)

## 📸 Overview

- **WM:** Hyprland with dwindle layout
- **Bar:** Waybar (auto-hide)
- **Launcher:** Fuzzel
- **Notifications:** Mako (with DND/focus modes)
- **Shell:** Caelestia (custom shell/sidebar/OSD/lock)
- **Clipboard:** Cliphist (text + images)
- **Colour:** Material You dark scheme (blue-purple palette)
- **Wallpaper:** Caelestia → swaybg
- **Eye care:** 20-20-20 break daemon + hyprsunset night light
- **Languages:** English + Arabic (toggle via Super+Space)

## 📁 What's in here

```
.config/
├── hypr/              # Hyprland config (entry point + modules)
│   ├── hyprland/      # Split configs: env, input, keybinds, rules, etc.
│   ├── scheme/        # Material You colour palettes
│   └── scripts/       # eye-break, wallpaper, notification helpers
├── waybar/            # Bar config, styling, modules, scripts
└── mako/              # Notification daemon config
```

## 🚀 Installation

### 1. Install dependencies

**Arch / Arch-based:**
```bash
# Core
sudo pacman -S hyprland hyprlock hyprpicker hyprshot foot fuzzel waybar mako \
               swaybg cliphist wl-clipboard playerctl jq fish wireplumber \
               gnome-keyring polkit-gnome geoclue trash-cli

# AUR (use yay / paru)
yay -S hyprsunset app2unit qtengine-git

# Optional but recommended
yay -S ttf-jetbrains-mono-nerd adw-gtk-theme papirus-icon-theme starship
```

**Debian/Ubuntu:** Use your distro's equivalents. Hyprland needs to be from a PPA or built from source.

### 2. Clone the configs

```bash
git clone https://github.com/SHANKER4K/hypr-dots ~/.config
```

This will create `~/.config/hypr/`, `~/.config/waybar/`, and `~/.config/mako/`.

### 3. Create caelestia user configs (required for startup)

```bash
mkdir -p ~/.config/caelestia
touch ~/.config/caelestia/hypr-vars.conf
touch ~/.config/caelestia/hypr-user.conf
```

These are sourced by Hyprland — they can be empty but must exist.

### 4. Install external apps (optional, update keybinds if you skip)

| App | Keybind | Notes |
|-----|---------|-------|
| Zen Browser | `Super+W` | `flatpak run app.zen_browser.zen` |
| VS Code / Codium | `Super+E` | |
| Obsidian | `Super+R` | |
| Telegram | `Super+T` | |
| Thunar | `Super+F` | File manager |
| Btop | `Ctrl+Shift+Escape` | System monitor (special ws) |
| Equibop / Vesktop | `Super+D` | Discord client (special ws) |

### 5. Laptop-specific changes

**`hypr/hyprland/monitors.conf`** — update monitor names and layouts for your laptop:
```
monitor = eDP-1, preferred, auto, 1
monitor = , preferred, auto, 1
```

**`hypr/hyprland/input.conf`** — tweak touchpad if needed.

### 6. ⚠️ Caelestia dependency

This config uses **Caelestia** (my custom shell) for:
- Lock screen (hyprlock wrapper with prayer + eye break)
- Sidebar, OSD, session menu
- Special workspace toggles
- Wallpaper management
- Screen recording, brightness control, colour picker

You'll need to install it separately or replace those keybinds. The configs
stay functional without it — just the lock screen, sidebar, and OSD features
won't work until Caelestia is installed.

### 7. Start Hyprland

```bash
# From TTY
Hyprland

# Or use a login manager (SDDM / greetd recommended)
```

## ⌨️ Keybindings

| Keys | Action |
|------|--------|
| `Super+Return` | Terminal (foot) |
| `Super+W` | Browser |
| `Super+E` | Editor |
| `Super+F` | File manager |
| `Super+Space` | Switch keyboard layout (EN/AR) |
| `Super+A` | Fuzzel launcher |
| `Super+#` | Go to workspace # |
| `Super+Alt+#` | Move window to workspace # |
| `Super+Z` / `Super+X` | Move / Resize mode |
| `Super+C` | Close window |
| `Super+L` | Lock screen |
| `Super+P` | Pin window |
| `Super+Up` | Fullscreen |
| `Super+S` | Screenshot region |
| `Super+Print` | Full screenshot |
| `Super+V` | Clipboard history |
| `Super+.` | Emoji picker |
| `Ctrl+Super+Space` | Play/Pause media |
| `Super+Shift+N` | Toggle DND |
| `Super+Alt+N` | Toggle Focus mode |
| `Ctrl+Alt+Delete` | Session menu |
| See `hypr/hyprland/keybinds.conf` for all bindings. |

## 🎨 Colour Scheme

Auto-generated from wallpaper via Material You (Material Colour Utilities).
Uses a dark blue-purple palette. Scheme files in `hypr/scheme/`.

## 📝 Notes

- **Animations disabled** — old GPU performance trade-off (enable in `hypr/hyprland/animations.conf`)
- **Blur & shadows disabled** — same reason
- The `hypr/scheme/current.conf` is a generated copy — edit `default.conf` instead
- 20-20-20 eye break daemon runs automatically (`eye-break.sh`)
- Prayer lock screen for salah times (triggered via prayer daemon)

## 🔗 Related

- [Caelestia](https://github.com/caelestia-dots/caelestia) — full dots project (includes foot, fish, btop, vscode, zen configs)
