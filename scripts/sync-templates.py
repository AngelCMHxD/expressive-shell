#!/usr/bin/env python3
"""Download or update Noctalia core & community Matugen templates into
~/.local/state/expressive-shell/templates/."""

import shutil
import subprocess
import sys
from pathlib import Path

BASE_DIR = Path.home() / ".local" / "state" / "expressive-shell" / "templates"
BUILTIN_DIR = BASE_DIR / "noctalia-builtin"
CORE_REPO_CACHE = Path.home() / ".cache" / "expressive-shell" / "noctalia-core-repo"
COMMUNITY_DIR = BASE_DIR / "community-templates"

CORE_URL = "https://github.com/noctalia-dev/noctalia.git"
COMMUNITY_URL = "https://github.com/noctalia-dev/community-templates.git"


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def sync_core():
    CORE_REPO_CACHE.parent.mkdir(parents=True, exist_ok=True)
    if (CORE_REPO_CACHE / ".git").is_dir():
        run(["git", "pull", "--ff-only"], cwd=CORE_REPO_CACHE)
    else:
        if CORE_REPO_CACHE.exists():
            shutil.rmtree(CORE_REPO_CACHE, ignore_errors=True)
        res = run([
            "git", "clone", "--depth", "1", "--filter=blob:none", "--sparse",
            CORE_URL, str(CORE_REPO_CACHE),
        ])
        if res.returncode == 0:
            run(["git", "sparse-checkout", "set", "assets/templates"], cwd=CORE_REPO_CACHE)

    src = CORE_REPO_CACHE / "assets" / "templates"
    if src.is_dir():
        BUILTIN_DIR.parent.mkdir(parents=True, exist_ok=True)
        if BUILTIN_DIR.exists():
            shutil.rmtree(BUILTIN_DIR, ignore_errors=True)
        shutil.copytree(src, BUILTIN_DIR)
        return True
    return False


def sync_community():
    COMMUNITY_DIR.parent.mkdir(parents=True, exist_ok=True)
    if (COMMUNITY_DIR / ".git").is_dir():
        res = run(["git", "pull", "--ff-only"], cwd=COMMUNITY_DIR)
        return res.returncode == 0
    if COMMUNITY_DIR.exists():
        shutil.rmtree(COMMUNITY_DIR, ignore_errors=True)
    res = run(["git", "clone", "--depth", "1", COMMUNITY_URL, str(COMMUNITY_DIR)])
    return res.returncode == 0


def main():
    if not shutil.which("git"):
        print("git not installed", file=sys.stderr)
        sys.exit(1)
    ok_core = sync_core()
    ok_comm = sync_community()
    print(f"core={'ok' if ok_core else 'fail'} community={'ok' if ok_comm else 'fail'}")


if __name__ == "__main__":
    main()
