#!/usr/bin/env python3
# OpenAD5X updater
#
# Moonraker's update manager keeps the checkout in /usr/data/openad5x/ad5x-fs
# current. Whenever its commit changes, and no print is running, this applies it:
#   printer files   fs/usr/data/openad5x/<part> laid over /usr/data/openad5x/<part>
#                   the way the installer lays them (manifests in .installed/):
#                   files you changed are saved in backups/updater first, files
#                   the update dropped are removed only if you never changed them.
#                   firmwareExe also goes to /usr/prog/PROGRAM/software/firmwareExe.
#   config          each file in fs/usr/data/config is merged into the live config
#                   with git merge-file, against the copy applied last time, so your
#                   edits and the SAVE_CONFIG calibration stay. A file that can't be
#                   merged cleanly is left alone, with the update next to it as
#                   <file>.update. Klipper restarts afterwards.
#   board firmware  mcu-firmware/ad5x is flashed with ad5x-mcu-flash when the boards
#                   don't report its VERSION (once per version, checksums first).
# Moonraker restarts itself when one of its modules changed. Startup script changes
# apply at the next boot.
# Log: /tmp/openad5x-updater.log
#
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
#
# Made for the OpenAD5X project
#
# This file may be distributed under the terms of the MIT license.
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path("/usr/data/openad5x")
CHECKOUT = HOME / "ad5x-fs"
FILES = CHECKOUT / "fs" / "usr" / "data" / "openad5x"
TEMPLATE = CHECKOUT / "fs" / "usr" / "data" / "config"
FIRMWARE = CHECKOUT / "mcu-firmware" / "ad5x"
CONFIG = HOME / "klipper" / "config"
BASES = CONFIG / ".openad5x-updater" / "base"  # the installer (steps/04-kalico.sh) saves the first copies here
MANIFESTS = HOME / ".installed"
STATE = HOME / ".updater"
BACKUP = HOME / "backups" / "updater"
FIRMWARE_EXE = Path("/usr/prog/PROGRAM/software/firmwareExe")
LOG = Path("/tmp/openad5x-updater.log")
MOONRAKER = "http://127.0.0.1:7125"
PARTS = ("startup", "firmware", "moonraker", "fluidd", "mcu-flash", "loadcell", "nginx", "grumpyscreen")
EXECUTABLE = re.compile(r"(\.sh|/firmwareExe|/ad5x-mcu-flash)$")
SAVE_CONFIG = re.compile(rb"^#\*# <-+ SAVE_CONFIG -+>", re.M)
GIT = "/opt/bin/git" if os.access("/opt/bin/git", os.X_OK) else "git"
CHECK_EVERY = 60


def log(msg: str) -> None:
    with LOG.open("a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")


def md5(path: Path) -> str:
    return hashlib.md5(path.read_bytes()).hexdigest()


def write_file(path: Path, data: bytes, mode=None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".updater-new")
    tmp.write_bytes(data)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def moonraker(path: str, method: str = "GET"):
    req = urllib.request.Request(MOONRAKER + path, method=method, data=b"" if method == "POST" else None)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r).get("result")
    except Exception:
        return None


def printer_busy() -> bool:
    res = moonraker("/printer/objects/query?print_stats=state")
    state = ((res or {}).get("status") or {}).get("print_stats", {}).get("state")
    return state in ("printing", "paused")


def checkout_commit() -> str:
    r = subprocess.run([GIT, "-C", str(CHECKOUT), "rev-parse", "HEAD"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


# ---- printer files ----------------------------------------------------------

def read_manifest(path: Path) -> dict:
    entries = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            if "  " in line:
                digest, name = line.split("  ", 1)
                entries[name] = digest
    return entries


def lay_over(part: str, stamp: str) -> list:
    src, dest = FILES / part, HOME / part
    manifest_path = MANIFESTS / f"{part}.md5"
    old = read_manifest(manifest_path)
    new, changed = {}, []
    for f in sorted(p for p in src.rglob("*") if p.is_file()):
        rel = f.relative_to(src).as_posix()
        target = dest / rel
        data = f.read_bytes()
        new[rel] = hashlib.md5(data).hexdigest()
        if target.is_file():
            current = md5(target)
            if current == new[rel]:
                continue
            if current != old.get(rel):
                saved = BACKUP / stamp / part / rel
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved)
                log(f"saved your changed {part}/{rel} to {saved}")
        write_file(target, data, 0o755 if EXECUTABLE.search("/" + rel) else 0o644)
        changed.append(rel)
    for rel, digest in old.items():
        target = dest / rel
        if rel not in new and target.is_file() and md5(target) == digest:
            target.unlink()
            changed.append(rel)
    write_file(manifest_path, "".join(f"{d}  {n}\n" for n, d in new.items()).encode())
    return changed


def update_files(stamp: str) -> dict:
    changed = {}
    for part in PARTS:
        if (FILES / part).is_dir():
            files = lay_over(part, stamp)
            if files:
                changed[part] = files
                log(f"{part}: {len(files)} files updated")
    if (FILES / "version.txt").is_file():
        shutil.copyfile(FILES / "version.txt", HOME / "version.txt")
    launcher = HOME / "firmware" / "firmwareExe"
    if "firmware" in changed and launcher.is_file() and FIRMWARE_EXE.parent.is_dir():
        write_file(FIRMWARE_EXE, launcher.read_bytes(), 0o755)
        log("firmwareExe updated; it runs from the next boot")
    return changed


# ---- config -----------------------------------------------------------------

def split_calibration(data: bytes):
    m = SAVE_CONFIG.search(data)
    return (data[:m.start()], data[m.start():]) if m else (data, b"")


def merge(mine: bytes, base: bytes, theirs: bytes):
    """git merge-file: the merged text, or None if it conflicts"""
    folder = STATE / "merge"
    folder.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, data in (("mine", mine), ("base", base), ("theirs", theirs)):
        p = folder / name
        p.write_bytes(data)
        paths.append(str(p))
    r = subprocess.run([GIT, "merge-file", "-p", *paths], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def update_config() -> bool:
    changed = False
    for new_path in sorted(p for p in TEMPLATE.rglob("*") if p.is_file()):
        rel = new_path.relative_to(TEMPLATE)
        live, base_path = CONFIG / rel, BASES / rel
        new = new_path.read_bytes().replace(b"\r\n", b"\n")
        if not live.exists():
            write_file(live, new)
            write_file(base_path, new)
            log(f"config: added {rel}")
            changed = True
            continue
        base = base_path.read_bytes().replace(b"\r\n", b"\n") if base_path.is_file() else None
        if base == new:
            continue
        body, calibration = split_calibration(live.read_bytes().replace(b"\r\n", b"\n"))
        if base is None:
            if body == new:
                write_file(base_path, new)
            else:
                write_file(live.with_name(live.name + ".update"), new)
                log(f"config: {rel} has no earlier copy to merge against; update saved as {rel}.update")
            continue
        merged = new if body == base else merge(body, base, new)
        if merged is None:
            write_file(live.with_name(live.name + ".update"), new)
            log(f"config: {rel} clashes with your changes; left as it is, update saved as {rel}.update")
            continue
        if not merged.endswith(b"\n"):
            merged += b"\n"
        write_file(live, merged + calibration)
        write_file(base_path, new)
        log(f"config: merged {rel}")
        changed = True
    return changed


# ---- board firmware ---------------------------------------------------------

def update_boards() -> None:
    version_file = FIRMWARE / "VERSION"
    if not version_file.is_file():
        return
    version = version_file.read_text().split("\n", 1)[0].strip()
    tried = STATE / "mcu-version"
    if not version or (tried.is_file() and tried.read_text().strip() == version):
        return
    res = moonraker("/printer/objects/query?mcu=mcu_version&mcu%20eboard=mcu_version&mcu%20ifs=mcu_version")
    status = (res or {}).get("status") or {}
    reported = [v.get("mcu_version", "") for v in status.values()]
    if len(reported) == 3 and all(f"-g{version}" in v for v in reported):
        tried.write_text(version)
        return
    for line in (FIRMWARE / "SHA256SUMS").read_text().splitlines():
        if not line.strip():
            continue
        digest, name = line.split(None, 1)
        name = name.lstrip("*")
        if hashlib.sha256((FIRMWARE / name).read_bytes()).hexdigest() != digest:
            log(f"boards: {name} fails its checksum; not flashing {version}")
            tried.write_text(version)
            return
    log(f"boards: flashing {version}")
    r = subprocess.run(["sh", str(HOME / "mcu-flash" / "ad5x-mcu-flash"), str(FIRMWARE)],
                       capture_output=True, text=True)
    log(f"boards: ad5x-mcu-flash exit {r.returncode}; the eboard flashes at the next power cycle")
    tried.write_text(version)


# ---- main -------------------------------------------------------------------

def apply(commit: str) -> None:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    log(f"applying {commit[:8]}")
    files = update_files(stamp)
    if update_config():
        moonraker("/printer/restart", "POST")
        log("Klipper restarted for the new config")
    update_boards()
    if "moonraker" in files:
        log("Moonraker restarting for its updated modules")
        moonraker("/server/restart", "POST")


def main() -> int:
    STATE.mkdir(parents=True, exist_ok=True)
    lock = open(STATE / "lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return 0
    applied_file = STATE / "applied"
    log("updater started")
    while True:
        commit = checkout_commit()
        applied = applied_file.read_text().strip() if applied_file.is_file() else ""
        if commit and commit != applied and not printer_busy():
            try:
                apply(commit)
                applied_file.write_text(commit)
            except Exception as e:
                log(f"update {commit[:8]} failed: {e!r}; trying again later")
        time.sleep(CHECK_EVERY)


if __name__ == "__main__":
    sys.exit(main())
