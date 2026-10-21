# T23N boot/runtime optimization

## Measured hardware baseline

The verified SD boot showed:

```text
RAM total        : 36632 KiB
used             : 14128 KiB
free             : 8656 KiB
buff/cache       : 13848 KiB
rootfs           : 54.7 MiB
rootfs used      : 16.7 MiB (33%)
rootfs available : 33.6 MiB
swap             : 0
```

There is no immediate memory emergency. Finish PegineLab runtime validation
before removing services.

## Raptor services to keep during validation

Keep `rvd`, `rhd`, `rsd`, `rad`, `ric`, `rod`, the motor daemon,
Wi-Fi/DHCP and Dropbear while validating the camera.

PegineLab now detects Raptor `rvd` and captures snapshots with
`raptorctl rvd save jpeg`, so this profile no longer depends on Prudynt.

Thingino's Raptor `preview.html` may report a WebRTC 8554 backend failure
when RWD is not running. That does not mean the sensor/video path is down.
PegineLab preview uses RVD snapshots instead.

## Candidates only after PegineLab is verified

After port 8090, API, snapshot, PTZ/IR/audio are validated, consider disabling:
stock Thingino HTTP/HTTPS, unused ONVIF discovery, unused mDNS, unused motion
watcher, and cron only after checking its jobs.

Never disable all Raptor daemons or remove `rvd` blindly. Apply one change,
reboot, and retest before the next optimization.
