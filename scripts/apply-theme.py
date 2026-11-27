#!/usr/bin/env python3
"""Generate Material 3 Expressive palettes from a wallpaper via matugen v4
and render Noctalia-compatible app templates from ~/.config/quickshell/templates/."""
import json
import os
import re
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

CONFIG = Path.home() / ".config"
QS_DIR = CONFIG / "quickshell"
GB_CONFIG_DIR = CONFIG / "expressive-shell"
QS_COLORS = GB_CONFIG_DIR / "colors.json"
QS_TEMPLATE_ROOTS = [
    Path.home() / ".local" / "state" / "expressive-shell" / "templates",
    GB_CONFIG_DIR / "templates",
]
UMBRIEL_COLORS = CONFIG / "umbriel" / "expressive-colors.toml"

PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}")


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def get_hex(colors: dict, key: str, mode: str, fallback: str) -> str:
    entry = colors.get(key)
    if isinstance(entry, dict):
        sub = entry.get(mode) or entry.get("default")
        if isinstance(sub, dict) and sub.get("color"):
            return sub["color"]
        if isinstance(sub, str):
            return sub
    return fallback


def build_palette(colors: dict, mode: str) -> dict:
    fb = {
        "dark": ("#80d5c4", "#00372f", "#005045", "#9cf2e0", "#0e1513", "#1a211f", "#dee4e1", "#bec9c5", "#3f4946"),
        "light": ("#006b5d", "#ffffff", "#9cf2e0", "#00201b", "#f5fbf8", "#e9efec", "#171d1b", "#3f4946", "#bec9c5"),
    }[mode]
    keys = [
        ("primary", fb[0]),
        ("on_primary", fb[1]),
        ("primary_container", fb[2]),
        ("on_primary_container", fb[3]),
        ("secondary", fb[0]),
        ("on_secondary", fb[1]),
        ("secondary_container", fb[2]),
        ("on_secondary_container", fb[3]),
        ("tertiary", fb[0]),
        ("on_tertiary", fb[1]),
        ("tertiary_container", fb[2]),
        ("on_tertiary_container", fb[3]),
        ("surface", fb[4]),
        ("surface_dim", fb[4]),
        ("surface_bright", fb[5]),
        ("surface_container_lowest", fb[4]),
        ("surface_container_low", fb[5]),
        ("surface_container", fb[5]),
        ("surface_container_high", fb[5]),
        ("surface_container_highest", fb[5]),
        ("on_surface", fb[6]),
        ("on_surface_variant", fb[7]),
        ("outline", fb[7]),
        ("outline_variant", fb[8]),
        ("inverse_surface", fb[6]),
        ("inverse_on_surface", fb[4]),
        ("inverse_primary", fb[2]),
        ("background", fb[4]),
        ("on_background", fb[6]),
        ("shadow", "#000000"),
        ("scrim", "#000000"),
        ("error", "#ffb4ab" if mode == "dark" else "#ba1a1a"),
        ("on_error", "#690005" if mode == "dark" else "#ffffff"),
        ("error_container", "#93000a" if mode == "dark" else "#ffdad6"),
        ("on_error_container", "#ffdad6" if mode == "dark" else "#410002"),
    ]
    out = {}
    # Include every role matugen v4 emits natively (surface_variant, *_fixed, source_color, etc.)
    for k, entry in colors.items():
        if isinstance(entry, dict):
            sub = entry.get(mode) or entry.get("default")
            if isinstance(sub, dict) and sub.get("color"):
                out[k] = sub["color"]
            elif isinstance(sub, str):
                out[k] = sub

    # Ensure core roles always have safe fallbacks
    for k, default in keys:
        out.setdefault(k, get_hex(colors, k, mode, default))

    # Noctalia extra color aliases (used by umbriel, terminals, community templates)
    out.setdefault("surface_variant", out["surface_container_highest"])
    out.setdefault("terminal_background", out["surface_container_lowest"])
    out.setdefault("terminal_foreground", out["on_surface"])
    out.setdefault("terminal_cursor", out["primary"])
    out.setdefault("terminal_selection_background", out["primary_container"])
    out.setdefault("terminal_selection_foreground", out["on_primary_container"])
    out.setdefault("surface_tint", out["primary"])
    out["live_pill"] = "#4cd964" if mode == "dark" else "#5be078"
    out["on_live_pill"] = "#002108"
    return out


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) < 6:
        return (0, 0, 0)
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def format_color_prop(hex_color: str, prop: str) -> str:
    h = hex_color if hex_color.startswith("#") else "#" + hex_color
    stripped = h.lstrip("#")
    r, g, b = hex_to_rgb(h)
    if prop == "hex":
        return h
    if prop == "hex_stripped":
        return stripped
    if prop == "rgb":
        return f"rgb({r}, {g}, {b})"
    if prop == "rgba":
        return f"rgba({r}, {g}, {b}, 1.0)"
    if prop == "red":
        return str(r)
    if prop == "green":
        return str(g)
    if prop == "blue":
        return str(b)
    return h


def render_noctalia_template(text: str, palettes: dict, mode: str, image: str, config_dir: Path) -> str:
    """Render Noctalia / matugen `{{colors.<role>.<variant>.<format>}}` placeholders."""
    def repl(match: re.Match) -> str:
        expr = match.group(1)
        if expr == "image":
            return image
        if expr == "mode":
            return mode
        if expr == "config_dir":
            return str(config_dir)

        parts = expr.split(".")
        if parts[0] == "colors" and len(parts) >= 2:
            role = parts[1]
            variant = mode
            fmt = "hex"
            if len(parts) == 3:
                if parts[2] in ("dark", "light", "default"):
                    variant = mode if parts[2] == "default" else parts[2]
                else:
                    fmt = parts[2]
            elif len(parts) >= 4:
                variant = mode if parts[2] == "default" else parts[2]
                fmt = parts[3]

            pal = palettes.get(variant, palettes[mode])
            color = pal.get(role)
            if color:
                return format_color_prop(color, fmt)
        return match.group(0)

    return PLACEHOLDER_RE.sub(repl, text)


def expand_template_path(raw: str, base_dir: Path) -> Path:
    env_xdg = os.environ.get("XDG_CONFIG_HOME") or str(CONFIG)
    s = raw.replace("{{ config_dir }}", str(base_dir)).replace("{{config_dir}}", str(base_dir))
    s = s.replace("$XDG_CONFIG_HOME", env_xdg).replace("${XDG_CONFIG_HOME}", env_xdg)
    s = os.path.expandvars(os.path.expanduser(s))
    p = Path(s)
    if not p.is_absolute():
        p = (base_dir / p).resolve()
    return p


def run_dynamic_cmd(cmd: str, base_dir: Path) -> str:
    expanded = cmd.replace("{{ config_dir }}", str(base_dir)).replace("{{config_dir}}", str(base_dir))
    proc = subprocess.run(expanded, shell=True, cwd=str(base_dir), capture_output=True, text=True, check=False)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def load_enabled_templates() -> set[str]:
    state_path = GB_CONFIG_DIR / "settings.json"
    if not state_path.is_file():
        return set()
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
        enabled = data.get("enabledTemplates")
        if isinstance(enabled, list):
            return {str(x) for x in enabled}
    except Exception:
        pass
    return set()


def find_template_manifests() -> list[Path]:
    manifests: list[Path] = []
    seen: set[Path] = set()
    valid_names = {"builtin.toml", "templates.toml", "template.toml"}
    for root in QS_TEMPLATE_ROOTS:
        if not root.is_dir():
            continue
        for p in sorted(root.rglob("*.toml")):
            if p.name not in valid_names:
                continue
            try:
                rel_depth = len(p.relative_to(root).parts)
            except ValueError:
                continue
            if rel_depth <= 3 and p not in seen:
                seen.add(p)
                manifests.append(p)
    return manifests


def process_noctalia_templates(palettes: dict, mode: str, image: str) -> None:
    enabled_set = load_enabled_templates()
    if not enabled_set:
        return

    for manifest in find_template_manifests():
        base_dir = manifest.parent
        try:
            doc = tomllib.loads(manifest.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"apply-theme: failed parsing {manifest}: {exc}", file=sys.stderr)
            continue

        catalog = doc.get("catalog") if isinstance(doc.get("catalog"), dict) else {}
        templates = doc.get("templates")
        if not isinstance(templates, dict):
            continue

        # Community templates define a single [catalog.<id>] covering all [templates.*] in that file;
        # builtin.toml defines multiple [catalog.<id>] matching [templates.<id>].
        single_cat_id = next(iter(catalog.keys())) if len(catalog) == 1 else None

        for name, cfg in templates.items():
            if not isinstance(cfg, dict) or cfg.get("enabled", True) is False:
                continue

            cat_id = name if name in catalog else (single_cat_id or name)
            if name not in enabled_set and cat_id not in enabled_set:
                continue

            in_raw = cfg.get("input_path")
            if not in_raw and cfg.get("input_path_dynamic"):
                in_raw = run_dynamic_cmd(str(cfg["input_path_dynamic"]), base_dir)
            if not in_raw:
                continue

            in_path = expand_template_path(str(in_raw), base_dir)
            if not in_path.is_file():
                continue

            out_raw = cfg.get("output_path")
            if not out_raw and cfg.get("output_path_dynamic"):
                out_raw = run_dynamic_cmd(str(cfg["output_path_dynamic"]), base_dir)
            if not out_raw:
                continue

            out_list = out_raw if isinstance(out_raw, list) else [out_raw]
            rendered = render_noctalia_template(
                in_path.read_text(encoding="utf-8"),
                palettes,
                mode,
                image,
                base_dir,
            )

            # For multi-client bundles (like Discord), only write to clients whose config dir exists
            # so we don't spam empty folders for uninstalled clients.
            multi_bundle = single_cat_id is not None and len(templates) > 3
            wrote_any = False
            for out_entry in out_list:
                out_path = expand_template_path(str(out_entry), base_dir)
                if multi_bundle and not out_path.parent.exists() and not out_path.parent.parent.exists():
                    continue
                atomic_write(out_path, rendered)
                wrote_any = True

            post_hook = cfg.get("post_hook")
            if post_hook and wrote_any:
                cmd = str(post_hook).replace("{{ config_dir }}", str(base_dir)).replace("{{config_dir}}", str(base_dir))
                subprocess.run(cmd, shell=True, cwd=str(base_dir), capture_output=True, check=False)


def build_umbriel_toml(p: dict) -> str:
    def h(k: str, alpha: str = "FF") -> str:
        return p[k].upper() + alpha

    return f"""# Auto-generated by Expressive Quickshell (matugen)
[colors]
background = "{h('surface_container')}"
text_primary = "{h('on_surface')}"
text_muted = "{h('on_surface_variant')}"
accent_primary = "{h('primary')}"
accent_secondary = "{h('secondary')}"
warning = "{h('tertiary')}"
error = "{h('error')}"
insert_hint = "{h('tertiary', '80')}"
backdrop = "{h('surface_container_highest')}"

[colors.border]
focused = "{h('primary')}"
unfocused = "{h('outline_variant')}"
outer = "{h('surface_container_lowest')}"

[colors.overview]
background_tint = "{h('surface_container_lowest', '88')}"
badge = "{h('primary')}"
workspace_background = "{h('surface_container_lowest')}"

[colors.tab_bar]
background = "{h('surface_container')}"
text = "{h('on_surface_variant')}"
active = "{h('primary')}"
active_text = "{h('on_primary')}"
active_unfocused = "{h('surface_container_highest')}"
active_unfocused_text = "{h('on_surface')}"
urgent = "{h('error')}"
urgent_text = "{h('on_error')}"

[colors.title_bar]
background = "{h('surface_container')}"
background_unfocused = "{h('surface_container_lowest')}"
text = "{h('on_surface')}"
text_unfocused = "{h('on_surface_variant')}"
close = "{h('error')}"
close_glyph = "{h('on_error')}"
close_glyph_hover = "{h('on_error')}"
maximize = "{h('primary')}"
maximize_glyph = "{h('on_primary')}"
maximize_glyph_hover = "{h('on_primary')}"
minimize = "{h('secondary')}"
minimize_glyph = "{h('on_secondary')}"
minimize_glyph_hover = "{h('on_secondary')}"

[[window_rule]]
match.is_scratchpad = true
border_color_focused = "{h('tertiary')}"
border_color_unfocused = "{h('tertiary_container')}"
"""


VALID_SCHEMES = {
    "scheme-tonal-spot",
    "scheme-expressive",
    "scheme-vibrant",
    "scheme-fidelity",
    "scheme-content",
    "scheme-fruit-salad",
    "scheme-rainbow",
    "scheme-neutral",
    "scheme-monochrome",
}


def load_matugen_scheme() -> str:
    state_path = GB_CONFIG_DIR / "settings.json"
    if state_path.is_file():
        try:
            data = json.loads(state_path.read_text(encoding="utf-8"))
            scheme = str(data.get("matugenScheme") or "")
            if scheme in VALID_SCHEMES:
                return scheme
        except Exception:
            pass
    return "scheme-tonal-spot"


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: apply-theme.py <image_path> [dark|light]", file=sys.stderr)
        return 1

    img = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] in ("dark", "light") else "dark"
    scheme = load_matugen_scheme()

    proc = subprocess.run(
        [
            "matugen",
            "image",
            img,
            "--source-color-index",
            "0",
            "-t",
            scheme,
            "--json",
            "hex",
            "--dry-run",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        return proc.returncode

    data = json.loads(proc.stdout)
    colors = data.get("colors", {})
    palettes = {
        "dark": build_palette(colors, "dark"),
        "light": build_palette(colors, "light"),
    }
    payload = {
        "dark": palettes["dark"],
        "light": palettes["light"],
        "wallpaper": img,
    }

    atomic_write(QS_COLORS, json.dumps(payload, indent=2) + "\n")
    atomic_write(UMBRIEL_COLORS, build_umbriel_toml(palettes[mode]))
    process_noctalia_templates(palettes, mode, img)
    subprocess.run(["umbriel", "msg", "config-reload"], capture_output=True, check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
