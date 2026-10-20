# wificam_T23N

Экспериментальная прошивка и Web UI для Wi‑Fi камеры на **Ingenic T23/T23N**.  
Experimental firmware and Web UI for an **Ingenic T23/T23N** Wi‑Fi camera.

> **Status:** Linux 3.10.14 kernel build = **SUCCESS**. SD/rootfs tooling, Wi‑Fi/IP UI, camera-service integration and on-demand SSH/VPN controls are in the repository.

## Принципы / Design rules

- камера и сенсор инициализируются ОС при загрузке; Web UI не занимается ручным определением сенсора;
- 20 GiB SD выделяется только под фото/видео/события;
- всё остальное место карты получает ROOTFS для Linux, приложений, VPN, SSH и логов;
- SSH, WireGuard и AmneziaWG выключены по умолчанию;
- выключенный optional service не запускает постоянный userspace process;
- Wi‑Fi меняется через test + DHCP + rollback;
- текущие SSID, IPv4, gateway и DNS видны в Web UI;
- штатную SPI/NOR/NAND не стирать до успешной обратимой SD/RAM загрузки.

## Build

```sh
sh scripts/build_all.sh
```

Known-good kernel artifacts:

```sh
sh scripts/export_known_good.sh
```

Для полного rootfs нужен базовый BusyBox/Linux userspace:

```sh
BASE_ROOTFS=/path/to/base-rootfs.tar.gz sh scripts/build_all.sh
```

## Thingino SD/MMC build

Текущий проверяемый путь сборки использует pinned Thingino commit `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97` и профиль `galayou_g2_t23n_sc2336_atbm6012bx`. Web UI PegineLab WIFICAM обязателен в итоговом образе.

Current validated build path uses pinned Thingino commit `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97` and camera profile `galayou_g2_t23n_sc2336_atbm6012bx`. The PegineLab WIFICAM Web UI is mandatory in the final image.

```sh
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
PUBLISH=1 sh scripts/build_thingino_wificam_image.sh
```

Если Buildroot сообщает `Your PATH contains spaces, TABs, and/or newline`, не удаляйте checkout Thingino: повторите сборку с чистым `PATH`, как выше. / If Buildroot reports that error, do not reclone Thingino; re-run with the clean `PATH` above.

## SD-карта / SD card

Форматирование уничтожает данные на выбранной карте.

```sh
sudo sh scripts/prepare_sd.sh \
  /dev/sdX --yes \
  ~/myipcam/build/kernel/arch/mips/boot/uImage \
  out/wificam-rootfs.tar.gz
```

Разметка вычисляется автоматически:

| Partition | Size | FS | Purpose |
|---|---:|---|---|
| p1 BOOT | 128 MiB | FAT32 | uImage / boot |
| p2 ROOTFS | all remaining space | ext4 | Linux, apps, configs, VPN, SSH, logs |
| p3 MEDIA | 20 GiB | ext4 | recordings, snapshots, events |

MEDIA:

```text
/mnt/media/
├── recordings/
├── snapshots/
└── events/
```

Размер MEDIA можно переопределить, но по умолчанию он фиксирован на 20 GiB:

```sh
MEDIA_GIB=20 sudo -E sh scripts/prepare_sd.sh ...
```

## Web UI

```text
Browser
   |
   v
HTML / CSS / JavaScript
   |
   v
BusyBox httpd + CGI JSON API
   |
   +--> Wi-Fi / IP / DHCP
   +--> Camera service managed by OS
   +--> MEDIA storage
   +--> SSH on demand
   +--> WireGuard wg0 on demand
   +--> AmneziaWG awg0 on demand
   |
   v
Linux 3.10.14 / Ingenic T23/T23N
```

Меню:

```text
Dashboard / Главная
Live view / Видео
Recording / Запись
Image / Изображение
Network / Wi‑Fi / IP
  └─ SSH
  └─ WireGuard
  └─ AmneziaWG
Storage / SD
System
Firmware update
Logs
```

### Optional services

Управляет:

```text
wificam-service-ctl
```

Autostart включается только marker-файлом:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

VPN configs:

```text
/data/vpn/wg0.conf
/data/vpn/awg0.conf
```

Если marker отсутствует, `S91wificam-services` не запускает соответствующий сервис после reboot.

## Wi‑Fi / IP

```text
scan SSID
   ↓
enter password
   ↓
new wpa_supplicant profile
   ↓
association + DHCP
   ↓
IPv4?
  ├─ yes → keep
  └─ no  → restore last-good
```

Web UI показывает SSID, IPv4/CIDR, default gateway и DNS.

## Web password

По умолчанию Web UI не стартует без пароля:

```sh
printf '%s' 'NEW_PASSWORD_HERE' | wificam-set-web-password admin
/etc/init.d/S90wificam start
```

## Screenshots / Скриншоты

### Dashboard
![Dashboard](docs/screenshots/dashboard.svg)

### Wi‑Fi
![Wi-Fi](docs/screenshots/wifi.svg)

### Optional services
![Optional services](docs/screenshots/services.svg)

### Storage
![Storage](docs/screenshots/storage.svg)

## Structure

```text
.
├── scripts/
│   ├── build_kernel.sh
│   ├── build_all.sh
│   ├── export_known_good.sh
│   ├── package_rootfs_overlay.sh
│   ├── assemble_rootfs.sh
│   └── prepare_sd.sh
├── rootfs/
│   ├── etc/init.d/
│   │   ├── S90wificam
│   │   └── S91wificam-services
│   ├── etc/wificam/wificam.conf
│   └── usr/bin/
│       ├── wificam-camera-ctl
│       ├── wificam-service-ctl
│       └── wificam-set-web-password
├── web/
│   ├── index.html
│   ├── styles.css
│   ├── app.js
│   └── cgi-bin/api
└── docs/
    ├── BUILD_RU.md / BUILD_EN.md
    ├── HARDWARE_AND_SD_RU.md / HARDWARE_AND_SD_EN.md
    ├── WIFI_ARCHITECTURE_RU.md / WIFI_ARCHITECTURE_EN.md
    ├── WEB_STACK_RU.md / WEB_STACK_EN.md
    ├── STORAGE_SERVICES_RU.md / STORAGE_SERVICES_EN.md
    └── screenshots/
```

## Documentation

**Русский**
- [Сборка ядра](docs/BUILD_RU.md)
- [Плата и SD](docs/HARDWARE_AND_SD_RU.md)
- [Wi‑Fi/IP/VPN](docs/WIFI_ARCHITECTURE_RU.md)
- [Web UI/API](docs/WEB_STACK_RU.md)
- [Storage и optional services](docs/STORAGE_SERVICES_RU.md)

**English**
- [Kernel build](docs/BUILD_EN.md)
- [Board and SD](docs/HARDWARE_AND_SD_EN.md)
- [Wi‑Fi/IP/VPN](docs/WIFI_ARCHITECTURE_EN.md)
- [Web UI/API](docs/WEB_STACK_EN.md)
- [Storage and optional services](docs/STORAGE_SERVICES_EN.md)

## Known-good kernel build

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
