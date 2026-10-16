# wificam_T23N

Экспериментальная прошивка для Wi‑Fi камеры на **Ingenic T23/T23N**.  
Experimental firmware project for an **Ingenic T23/T23N** Wi‑Fi camera.

> **Статус / Status:** kernel build SUCCESS. Следующий этап — безопасная проверка загрузки с SD через UART/U‑Boot без перезаписи штатной flash.

## Документация / Documentation

### Русский
- [Сборка ядра](docs/BUILD_RU.md)
- [Совместимость платы, SPI-flash и SD-карта](docs/HARDWARE_AND_SD_RU.md)
- [Архитектура Wi‑Fi, смена сети и паролей](docs/WIFI_ARCHITECTURE_RU.md)

### English
- [Kernel build](docs/BUILD_EN.md)
- [Board compatibility, SPI flash and SD card](docs/HARDWARE_AND_SD_EN.md)
- [Wi‑Fi architecture, network and password changes](docs/WIFI_ARCHITECTURE_EN.md)

## Web UI

![WIFICAM T23N web UI mockup](docs/UI_MOCKUP.svg)

Планируемое меню:

```text
Dashboard
Live view
Recording
Image
Network
  └─ Wi‑Fi
Storage / SD
System
Firmware update
Logs
```

## Архитектура / Architecture

```text
Browser / Web UI
       |
       v
 HTTP/JSON API
       |
  +----+----------------------+----------------+
  |                           |                |
Network service         Camera service   Storage service
  |                           |                |
wpa_supplicant              ISP/ENC        SD card
udhcpc/DHCP                RTSP/HLS      recordings/events
  |
 wlan0
```

### Безопасная смена Wi‑Fi / Safe Wi‑Fi switching

```text
scan SSID
   ↓
enter password
   ↓
temporary profile
   ↓
associate + DHCP
   ↓
success? ── yes ──> save profile
   |
   no
   ↓
rollback to previous network
   ↓
optional Recovery AP
```

Wi‑Fi пароль не возвращается из API в открытом виде. Администраторский пароль хранится только как стойкий hash.  
Wi‑Fi passwords are never returned as plaintext. The administrator password is stored only as a strong hash.

## Known-good kernel image

```text
Image:        uImage.lzma
Linux:        3.10.14
Architecture: MIPS
Compression:  LZMA
Load Address: 0x80010000
Entry Point:  0x803c7960
Size:         1739320 bytes
SHA-256:      7ba1c4b0a3ea28d3a7a89cd14330fe1968a0ac63166b08c2d9e715541432565f
```

**Важно / Important:** этот результат подтверждает успешную сборку ядра, но не подтверждает совместимость каждой ревизии T23/T23N-платы. Перед прошивкой проверяются UART boot log, U‑Boot environment, RAM, flash, sensor, Wi‑Fi chipset и GPIO.
