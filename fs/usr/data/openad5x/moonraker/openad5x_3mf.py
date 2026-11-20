# OpenAD5X 3MF uploads for Moonraker
#
# OrcaSlicer and Bambu Studio send a sliced print as a 3MF ("name.gcode.3mf"):
# a zip with each sliced plate as Metadata/plate_<n>.gcode and its picture as
# Metadata/plate_<n>.png. Moonraker only takes G-code files and refuses it.
#
# On an upload to the print files, the lowest-numbered sliced plate is taken out
# of the 3MF and stored as a plain .gcode under the same name. If that G-code has
# no thumbnail of its own, the plate picture is written at the top of it in the
# "; thumbnail begin" form Moonraker reads, so Fluidd and the touchscreen show it.
# Every other upload goes on to Moonraker untouched.
#
# Loaded as [openad5x_3mf] from Moonraker's components folder.
#
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
#
# Made for the OpenAD5X project
#
# This file may be distributed under the terms of the MIT license.
from __future__ import annotations

import base64
import logging
import os
import re
import shutil
import struct
import tempfile
import zipfile
from typing import TYPE_CHECKING, Any, Dict, Optional, Tuple

if TYPE_CHECKING:
    from ..confighelper import ConfigHelper
    from .file_manager.file_manager import FileManager

PLATE_GCODE = re.compile(r"/?Metadata/plate_(\d+)\.gcode")
HEAD_BYTES = 256 * 1024
CHUNK = 1024 * 1024
THUMB_LINE = 78


def gcode_name(filename: str) -> str:
    """part.gcode.3mf and part.3mf both become part.gcode"""
    stem = filename[:-len(".3mf")]
    return stem if stem.lower().endswith(".gcode") else stem + ".gcode"


def pick_plate(zf: zipfile.ZipFile) -> Tuple[str, Optional[str]]:
    names = zf.namelist()
    plates = []
    for name in names:
        match = PLATE_GCODE.fullmatch(name)
        if match:
            plates.append((int(match.group(1)), name))
    if not plates:
        raise ValueError("it has no sliced plate; slice it and send it again")
    number, gcode = min(plates)
    folder = gcode[:gcode.rindex("/") + 1]
    picture = f"{folder}plate_{number}.png"
    return gcode, (picture if picture in names else None)


def thumbnail_block(png: bytes) -> bytes:
    # width and height from the PNG's IHDR chunk
    if png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
        return b""
    width, height = struct.unpack(">II", png[16:24])
    data = base64.b64encode(png).decode("ascii")
    lines = [f"; thumbnail begin {width}x{height} {len(data)}"]
    lines += [f"; {data[i:i + THUMB_LINE]}" for i in range(0, len(data), THUMB_LINE)]
    lines += ["; thumbnail end", ";", ""]
    return "\n".join(lines).encode("ascii")


def to_gcode(path: str) -> None:
    """Replaces the uploaded 3MF at path with its first plate's G-code."""
    fd, out_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".gcode")
    try:
        with zipfile.ZipFile(path) as zf, os.fdopen(fd, "wb") as out:
            gcode, picture = pick_plate(zf)
            with zf.open(gcode) as src:
                head = src.read(HEAD_BYTES)
                if picture is not None and b"thumbnail begin" not in head:
                    out.write(thumbnail_block(zf.read(picture)))
                out.write(head)
                shutil.copyfileobj(src, out, CHUNK)
    except BaseException:
        os.remove(out_path)
        raise
    os.replace(out_path, path)


class OpenAD5X3mf:
    def __init__(self, config: ConfigHelper) -> None:
        self.server = config.get_server()
        fm: FileManager = self.server.lookup_component("file_manager")
        self.moonraker_finalize = fm.finalize_upload
        setattr(fm, "finalize_upload", self.finalize_upload)

    async def finalize_upload(self, form_args: Dict[str, Any]) -> Dict[str, Any]:
        filename = str(form_args.get("filename", ""))
        root = str(form_args.get("root", "gcodes")).lower()
        if root == "gcodes" and filename.lower().endswith(".3mf"):
            upload = form_args["tmp_file_path"]
            try:
                await self.server.get_event_loop().run_in_thread(to_gcode, upload)
            except Exception as e:
                try:
                    os.remove(upload)
                except OSError:
                    pass
                raise self.server.error(f"Cannot use {filename}: {e}", 400)
            form_args = dict(form_args, filename=gcode_name(filename))
            logging.info(f"OpenAD5X: {filename} stored as {form_args['filename']}")
        return await self.moonraker_finalize(form_args)


def load_component(config: ConfigHelper) -> OpenAD5X3mf:
    return OpenAD5X3mf(config)
