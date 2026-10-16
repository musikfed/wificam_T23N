# SD card, recording and optional services — English

## New SD layout

The card uses a simple layout:

| Partition | Size | FS | Purpose |
|---|---:|---|---|
| BOOT | 128 MiB | FAT32 | `uImage` and boot files |
| ROOTFS | all remaining space except MEDIA | ext4 | Linux, applications, settings, VPN, SSH, logs |
| MEDIA | 20 GiB | ext4 | camera photos, video and events |

On a typical marketed 32 GB card, ROOTFS is roughly 9–10 GiB because the real binary capacity is smaller. Larger cards automatically give all additional space to ROOTFS.

MEDIA is mounted at:

```text
/mnt/media
├── recordings/
├── snapshots/
└── events/
```

## Formatting

```sh
sudo sh scripts/prepare_sd.sh /dev/sdX --yes uImage full-rootfs.tar.gz
```

Default:

```text
MEDIA_GIB=20
```

It can be overridden when needed:

```sh
MEDIA_GIB=20 sudo -E sh scripts/prepare_sd.sh ...
```

The script refuses the running root disk, requires explicit `--yes`, and aborts if too little ROOTFS space would remain.

## Service principle: disabled means no process

Optional features must not consume CPU/RAM continuously.

Therefore:

- SSH is disabled by default;
- WireGuard is disabled by default;
- AmneziaWG is disabled by default;
- enabling a feature from the Web UI starts it and creates a marker under `/data/services`;
- disabling stops it and removes the marker;
- after reboot only services with markers are started.

`S91wificam-services` starts nothing else.

## Config files

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled

/data/vpn/wg0.conf
/data/vpn/awg0.conf
```

Board/rootfs-specific commands can be overridden in `/etc/wificam/wificam.conf`.

WireGuard and AmneziaWG are treated as network interfaces, not mandatory always-running applications. With kernel implementations, the `wg-quick/awg-quick up` helper exits after configuring the interface; CPU cost is mainly incurred while VPN traffic is actually processed.

## Camera

Sensor identification is not a Web UI responsibility. The OS drivers/camera userspace discover and initialize the camera during boot. The Web UI only observes and controls the already available camera service.
