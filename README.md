# Expressive Shell (Quickshell + Umbriel)

A Material 3 Expressive (Android 17 Desktop / Googlebook OS inspired) Wayland desktop shell built with **Quickshell** for the **Umbriel** compositor.

> This is kinda heavily vibe-coded. I'm daily driving it, but it can be rough around the edges. (mainly light theme, as that's not well tested)

---

## Features

- Bar: Clock + Calendar shade, workspace + scratchpad indicators, media pill, background apps, notifications and control center
- Dock: Can be fixed, pop-up or disabled. Has pinned and running apps. You can right-click on the launcher or bar to pin or unpin an app
- Control Center (Quick Settings): Well, it's quick settings, no need to explain much. It follows the design principle of Android 17
- Notifications: Has a `org.freedesktop.Notifications` server with per-app grouping, image previews, action rows, and collapsible notifs
- Screenshot & Annotation Tool: Frozen fullscreen region picker with pen, highlighter, line, arrows, rectangle, circle, text, numbered markers, eraser, color picker, eyedropper, undo/redo, and automatic clipboard copy + save. Optional.
- Calendar + Google Calendar: Has some colored event dots and your agenda synced via GNOME Online Accounts (`goa-daemon`). Optional.
- Lock Screen & Polkit Agent: Lock screen that also has `fprintd` fingerprint verification. A polkit dialog is also avaiable, with fingerprint support too. Optional.
- Clipboard History: This is pretty much `cliphist` but with a pretty interface, kinda barebones. Optional.
- Dynamic Material 3 Theming: `matugen` palette extraction from your active wallpaper, and uses Noctalia-compatible app templates. Matugen is kinda coupled, so best to have it :P

---

## Dependencies

### Core (please make sure you have these :c)
```bash
sudo pacman -S quickshell matugen python python-pillow pipewire wireplumber libpulse networkmanager bluez-utils brightnessctl zenity
```

### Optional (features might not be available, but overall the shell still works)
| Feature | Packages |
| --- | --- |
| Screenshots and annotations | `grim` `wl-clipboard` |
| Clipboard history | `cliphist` `wl-clipboard` |
| Idle auto-lock and sleep | `swayidle` |
| Google Calendar support | `gnome-online-accounts` `gnome-online-accounts-gtk` |
| Animated wallpapers | `awww` |
| Power profiles tile | `power-profiles-daemon` |
| Fingerprint support | `fprintd` |

```bash
# Install all optional packages at once (Arch / CachyOS)
sudo pacman -S grim wl-clipboard cliphist swayidle gnome-online-accounts gnome-online-accounts-gtk power-profiles-daemon fprintd
```

---

## Umbriel Setup (`~/.config/umbriel/config.toml`)

### Autostart
```toml
[general]
autostart = [
  "qs",
  "wl-paste --type text --watch cliphist store",
  "wl-paste --type image --watch cliphist store",
  "python3 ~/.config/quickshell/scripts/idle-manager.py",
]
```

### Keybinds (Optional, you decide what you want or don't want)
```toml
[binds]
"Mod" = { action = "spawn qs ipc call shell toggle launcher", repeat = false }
"Mod+L" = { action = "spawn qs ipc call shell lock", repeat = false }
"Mod+V" = { action = "spawn qs ipc call shell toggle clipboard", repeat = false }
"Mod+W" = { action = "spawn qs ipc call shell toggle wallpapers", repeat = false }
"Mod+Ctrl+Shift+S" = { action = "spawn qs ipc call shell toggle quicksettings", repeat = false }
"Print" = { action = "spawn qs ipc call shell toggle screenshot", repeat = false }
"XF86PowerOff" = { action = "spawn qs ipc call shell toggle session", allow_when_locked = true, repeat = false } # if you want this keybind, make sure to disable the power key handling from logind!!! :P
```

---

## IPC

Commands follow `qs ipc call shell <command> [arg]`:

| Command | Description |
| --- | --- |
| `toggle launcher` | Toggle the app launcher |
| `toggle wallpapers` | Toggle the wallpaper picker |
| `toggle clipboard` | Toggle clipboard history |
| `toggle screenshot` | Open screenshot & annotation overlay |
| `toggle quicksettings` | Toggle Control Center |
| `toggle notifications` | Toggle Notifications shade |
| `toggle calendar` | Toggle Calendar & agenda shade |
| `toggle keyboard` | Toggle Keyboard layout picker |
| `toggle media` | Toggle Media player card |
| `toggle session` | Toggle Power / Session overlay |
| `toggle theme` | Switch between Dark and Light mode |
| `toggle widgets` | Show/hide desktop widgets |
| `toggle awww` | Toggle animated (`awww`) vs static wallpaper |
| `lock` | Lock the session immediately |
| `nextWallpaper` | Switch to the next wallpaper |
| `cycleDock` | Cycle dock mode (`always` → `popup` → `off`) |
| `setDock <mode>` | Set dock mode (`always`, `popup`, or `off`) |

---

## Guides

It has a GUI settings panel, you probably won't get lost there :D

---

## Config Layout

Everything is inside `~/.config/expressive-shell/`: 

```text
settings.json       # Preferences
colors.json         # Current Matugen palette
templates/          # User templates, any Noctalia template should work
```

## Screenshots

### Control Panel
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/562dc7f4-e80a-4b79-9be1-2ce9b0390806" />

### Music Player
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/da859b0b-3c89-4d96-9b43-5da4d24e9a51" />

### Settings
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/687fb4e2-1332-4c3f-896d-0c870abad9f4" />

### Calendar
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/354f3a25-91ae-4c3b-a6b1-5087a7f890cc" />

### Launcher
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/40d81787-5c83-45ea-8878-4ed94ef66400" />

### Wallpaper Picker
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/53cef8ea-777c-46be-8912-1fce214afbf5" />

### Notifications
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/118aca09-7452-4fcc-9de1-a81995f955e0" />

### Screenshot tool
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/3530b404-a0c8-4599-b6c8-bacc764b2d08" />



