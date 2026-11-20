# ad5x-files
Config and modules for the FlashForge AD5X running Kalico, with the IFS as an AFC unit. Documentation is in [openad5x](https://github.com/openAD5X/openad5x).

## Contents
- `fs/usr/data/openad5x/firmware/firmwareExe`, `startup/`, `version.txt`: the boot. `firmwareExe` brings the network up and runs `startup/startup.sh`, which starts every script in `startup/scripts/` (NaN byte, clock, Entware, toolhead board, Klippy, Moonraker, nginx, camera, GrumpyScreen). `10-klipper.sh` keeps Klippy running; `startup/commands/` holds the commands GrumpyScreen runs (restart Klipper, the screen or Wi-Fi, support zip)
- `fs/usr/data/config/`: printer config (`printer.base.cfg`, `printer.cfg`, `moonraker.conf`), `macros.cfg` (homing, print start and end, stock AD5X pause and resume, load cell and probe, touchscreen buttons, pause at layer) and `AFC/` (`AFC.cfg`, `AFC_Hardware-IFS.cfg`, `AFC_Macro_Vars.cfg` and `ifs_macros.cfg`)
- The AFC modules, `AFC_IFS.py` (the IFS unit for AFC) and `ad5x_filament_sensor.py` are in `kalico-ad5x` (`klippy/extras`)
- `fs/usr/data/openad5x/mcu-flash/`: `ad5x-mcu-flash` (flashes the mainboard and IFS live from a folder of `mcu-firmware/ad5x` images, and stages the eboard for the next power cycle), and `ifs_capture.py` and `ifs_catch.py`, which it uses to flash the IFS MCU over its serial port
- `fs/usr/data/openad5x/startup/openad5x_updater.py` and `startup/scripts/99-openad5x-updater.sh`: the updater. When Moonraker's update manager pulls this repo into `/usr/data/openad5x/ad5x-fs`, it lays the new files over `/usr/data/openad5x`, merges config updates into your config, and flashes new board firmware
- `fs/usr/data/openad5x/moonraker/`: Moonraker modules, linked in by `20-moonraker.sh`: `openad5x_machine.py` (reboot, shutdown and service restarts on the AD5X) and `openad5x_3mf.py` (sliced 3MF uploads stored as G-code)
- `fs/usr/data/openad5x/nginx/nginx.conf`: Fluidd on port 80, with Moonraker and the camera behind it
- `fs/usr/data/openad5x/fluidd/macros.json`: the Fluidd macro button layout, loaded by `25-fluidd-macros.sh`
- `fs/usr/data/openad5x/loadcell/loadcell.sh`: bed load cell commands used by `macros.cfg`
- `fs/usr/data/openad5x/grumpyscreen/grumpyscreen.cfg`: the GrumpyScreen config, with your own changes in `grumpyscreen.ini` in the config folder
- `mcu-firmware/ad5x/`: AD5X MCU firmware images with `SHA256SUMS`, and the Kalico build configs in `config/`
- `config-docs/`: feature docs for the AFC and IFS config (`IFS.md`)
