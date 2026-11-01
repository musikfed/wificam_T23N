# PegineLab WIFICAM T23 SD — 0.1_test

**Type:** prerelease / тестовый релиз  
**Hardware date:** 2026-10-21  
**Release snapshot:** `release/0.1_test`  
**Snapshot commit:** `07aebd598f5bbf641d4817f7de924cba41277449`

## Что это за релиз

Это первый сохранённый бинарный milestone, который **реально загрузился с SD на целевой T23N-камере**.

Подтверждено на железе:
- direct SD boot;
- DOS/MBR;
- SPL/MSPL на LBA34;
- U-Boot proper на LBA86;
- FAT16 p1 с `/uImage`;
- ext4 rootfs на `/dev/mmcblk0p2`;
- SSH/Dropbear;
- PegineLab WIFICAM удалось запустить и открыть на реальной камере.

## Firmware image

```text
Thingino/thingino-t23-sd.bin
size:   84934656 bytes
SHA256: f9f50a8595d4fe629ed787483188319000d2780bd3c6dee56fef4de5e754f6be
```

Проверочная сумма:

```text
Thingino/thingino-t23-sd.bin.sha256
```

Записывать как **полный disk image с LBA0**. Для готового `.bin` не использовать `seek=34`.

```sh
sudo sh scripts/write_thingino_wificam_sd.sh /dev/sdX
```

## Важные известные ограничения этого exact binary

Этот `.bin` был собран **до** последних runtime-исправлений PegineLab. После аппаратного запуска были найдены и исправлены в исходниках:
- конфликт PegineLab с Thingino на TCP 8080 — PegineLab перенесена на 8090;
- BusyBox `httpd` подхватывал Thingino `/etc/httpd.conf` и подменял webroot;
- рабочий формат BusyBox-конфига подтверждён как:
  ```text
  H:/usr/share/wificam-web
  /:admin:Wificam12345
  ```
- исправлена несовместимая генерация CSRF через `od -A/-N`;
- добавлена поддержка Raptor в PegineLab;
- SSH/Dropbear защищён как обязательный recovery-канал;
- API/CGI, preview/audio/control ещё требуют доводки и повторной сборки.

Поэтому `0.1_test` — **исторически важный hardware-booted prerelease**, а не финальный пользовательский образ.

Для старой записанной карты есть recovery-скрипт в актуальной ветке:

```text
scripts/camera_fix_wificam_0_1_test.sh
```

## Тестовые доступы после recovery

```text
Thingino SSH:
  root / root

PegineLab WIFICAM:
  http://CAMERA_IP:8090/
  admin / Wificam12345
```

## Next

Следующий prerelease должен быть собран заново из текущего `mymarrchWFcam` и получить новый SHA256 после аппаратной проверки. Предлагаемое имя: `0.2_test`.
