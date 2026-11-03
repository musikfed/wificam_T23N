# PegineLab WIFICAM — lean Galayou G2 / Ingenic T23N profile

The pinned upstream Thingino device is `galayou_g2_t23n_sc2336_atbm6012bx`, commit `9925f46f73b9c39ec8d2a65134b18c94e6fdfb97`.

**Keep:** T23N SoC, SC2336 ISP/sensor, ATBM6012BX Wi-Fi **over USB DWC2**, 1-bit MMC0 SD root ext4, audio, GPIO/PTZ, IR-cut and recovery SSH. Do not shrink the upstream 23 MiB ISP reserved memory without hardware testing.

**Lean Raptor:** retain RVD video, RSD RTSP, RAD audio, RHD JPEG/MJPEG, ROD OSD, RIC IR-cut, RMR recording and RMD motion. Default to no WebRTC to save resources, with an explicit `WIFICAM_WEBRTC=1` build-time opt-in for browser/low-latency video and bidirectional audio. This is independent of the web UI's LLM mode checkbox. Exclude optional WebTorrent, RTMP, SRT, USB webcam, alternate live555 RTSP and test file source. ONVIF, normal LAN operation and authenticated BusyBox CGI are not disabled.

Factory builds with `PUBLISH=0` keep candidate images in gitignored `out/candidate-sd/` (or private `out/private-sd/` with Wi-Fi credentials); never replace the hardware-booted reference in `Thingino/`.

No measured CPU/RAM speedup is claimed. CI only validates configuration; a physical cold boot and CGI/RTSP/PTZ/audio/night/recording test are still required. The CGI source-disclosure fail-closed gate must remain active.
