# OpenAD5X machine provider for Moonraker
#
# The AD5X runs busybox init with no systemd and no sudo, and Moonraker runs as
# root. Moonraker's own providers need systemd or supervisord, so it gets
# "provider: none": no service actions, and reboot and shutdown go through
# sudo. Its container check (PID 1 not named init or systemd) can also block
# reboot and shutdown outright.
#
# Loaded as [openad5x_machine]; 20-moonraker.sh links it into Moonraker's
# components and adds the section. While Moonraker loads, before the provider
# is initialized, it swaps in a provider for the AD5X:
#   reboot, shutdown     busybox reboot, and poweroff or halt (shutdown_action)
#   restart klipper      startup/commands/restart-klipper.sh, the script the
#                        touchscreen's button runs; 10-klipper.sh starts it again
#   restart moonraker    Moonraker exits; 20-moonraker.sh starts it again
# Klipper's reboot_machine and shutdown_machine remote methods are pointed at
# the same provider.
#
# Copyright (C) 2026  sterling motuz <Sterling@dexabyte.ca>
#
# Made for the OpenAD5X project
#
# This file may be distributed under the terms of the MIT license.
from __future__ import annotations

import logging
import os
from typing import TYPE_CHECKING, Any, Dict

from .machine import BaseProvider

if TYPE_CHECKING:
    from ..confighelper import ConfigHelper
    from .machine import Machine

PROVIDER_NAME = "openad5x"
RESTART_KLIPPER = "/usr/data/openad5x/startup/commands/restart-klipper.sh"
# 10-klipper.sh and 20-moonraker.sh restart these whenever they exit, so they
# are always reported as running
SUPERVISED = ("klipper", "moonraker")


def busybox_command(name: str) -> str:
    for folder in ("/sbin", "/bin", "/usr/sbin", "/usr/bin"):
        path = os.path.join(folder, name)
        if os.access(path, os.X_OK):
            return path
    return name


class AD5XProvider(BaseProvider):
    async def initialize(self) -> None:
        for name in SUPERVISED:
            self.available_services[name] = {
                "active_state": "active",
                "sub_state": "running",
            }

    async def _run(self, cmd: str, timeout: float) -> None:
        await self.shell_cmd.exec_cmd(cmd, timeout=timeout, log_complete=False)

    async def shutdown(self) -> None:
        logging.info(f"OpenAD5X: {self.shutdown_action}")
        await self._run(busybox_command(self.shutdown_action), 10.)

    async def reboot(self) -> None:
        logging.info("OpenAD5X: reboot")
        await self._run(busybox_command("reboot"), 10.)

    async def do_service_action(self, action: str, service_name: str) -> None:
        if service_name not in SUPERVISED:
            raise self.server.error(
                f"Service '{service_name}' not available", 404)
        if action != "restart":
            raise self.server.error(
                f"The OpenAD5X startup scripts keep {service_name} running; "
                "only restart is available", 400)
        if service_name == "moonraker":
            logging.info("OpenAD5X: restarting Moonraker")
            self.server.restart(delay=.5)
            return
        logging.info("OpenAD5X: restarting Klipper")
        # the script waits for Klippy to stop and gives 10-klipper.sh time to start it
        await self._run(f"sh {RESTART_KLIPPER}", 30.)

    async def check_virt_status(self) -> Dict[str, Any]:
        return {"virt_type": "none", "virt_identifier": "none"}


class OpenAD5XMachine:
    def __init__(self, config: ConfigHelper) -> None:
        server = config.get_server()
        machine: Machine = server.lookup_component("machine")
        provider = AD5XProvider(config.getsection("machine"))
        machine.sys_provider = provider
        machine.provider_type = PROVIDER_NAME
        machine.system_info["provider"] = PROVIDER_NAME
        machine.inside_container = False
        machine.system_info["virtualization"] = {
            "virt_type": "none", "virt_identifier": "none"}
        # registered with the old provider's methods when the machine component loaded
        remote = server.klippy_connection.remote_methods
        for method, callback in (("reboot_machine", provider.reboot),
                                 ("shutdown_machine", provider.shutdown)):
            if method in remote:
                remote[method] = callback
        logging.info("OpenAD5X machine provider in use")


def load_component(config: ConfigHelper) -> OpenAD5XMachine:
    return OpenAD5XMachine(config)
