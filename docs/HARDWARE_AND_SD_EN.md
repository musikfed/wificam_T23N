# Board compatibility and safe validation

## Target hardware

This build targets cameras based on the **Ingenic T23/T23N** SoC family using MIPS/XBurst and Linux 3.10.x.

At this stage only the kernel build itself is confirmed. A particular board is considered compatible only after checking:

- SoC marking;
- RAM type and size;
- SPI NOR/NAND flash;
- UART boot log;
- image sensor;
- Wi-Fi chipset;
- GPIO/reset/power-enable wiring;
- U-Boot boot path.

## Before removing or disabling SPI flash

Prefer a reversible UART + SD test first.

1. Read a full dump of the original flash.
2. Store multiple copies and SHA-256 hashes.
3. Record the exact flash part number and supply voltage.
4. Save U-Boot `printenv` and the complete boot log.
5. Do not erase or overwrite the factory flash before SD boot works.

Physically removing the flash chip should be treated as a diagnostic option only when the board cannot select an alternate boot source in another way. After removal, verify whether BootROM/U-Boot falls back to SD. Without the board schematic this must not be assumed.

## U-Boot information to collect

```text
version
printenv
bdinfo
mmc list
part list mmc 0
help fatload
help ext4load
help bootm
```

## Proposed SD layout

| Partition | Size | FS | Purpose |
|---|---:|---|---|
| p1 BOOT | 128 MiB | FAT32 | uImage, boot config |
| p2 ROOTFS | 1 GiB | ext4 | Linux root filesystem |
| p3 DATA | 256 MiB | ext4 | settings, update, persistent data |
| p4 RECORDINGS | remaining | ext4 | video, events, snapshots |

Actual offsets and boot arguments must be derived from the camera's own U-Boot environment.

## First boot

The first test should load `uImage` from SD into RAM and execute `bootm` without modifying the original flash.
