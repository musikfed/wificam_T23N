# PegineLab T23N — lazy Web UI without competing with Hombo3

**Status:** implemented in development branch `main`, not in the
published `0.1_test` SD binary. Build and hardware validation are still required.

## Design

The Thingino/Raptor camera stays active for Hombo3 Windows CameraHub on
Acer, using RTSP ch0/ch1 and separate audio. Web UI :8090 is only a
control/status frontend until the operator explicitly clicks
**Start preview / ▶ Смотреть видео**. Opening the Live/PTZ page does
not automatically subscribe to camera frames.

```text
T23N ISP / RVD
   +-- RSD RTSP 554 -> Acer Windows Hombo3/YOLO (continues independently)
   +-- RHD native MJPEG -> authenticated :8090 CGI /cgi-bin/live.mjpg
                                +-- Web browser only while explicitly viewing
```

Loading the dashboard does not set an image `src`; status JSON is polled
at most once per 60 seconds while visible on status/network/system pages;
services are loaded when opening Network, not at bootstrap.

Start preview opens a single persistent CGI/curl reader from RHD. If
MJPEG fails, a JPEG snapshot fallback is requested **after** the
preceding frame finishes, at most every 2 seconds. Tab switch,
stop button, `visibilitychange(hidden)`, and `pagehide` all
clear the image source and timer, causing the browser to abort its
MJPEG HTTP request. It never resumes automatically on tab return.
No camera service start/stop button is shown in the video panel.

When Hombo3's browser UI is hidden or navigates away, its browser
WebSocket/MJPEG connection and decoded Blob URLs are released; **the
backend CameraHub RTSP reader remains active** for autonomous vision.

Releasing the Web viewer does NOT mean dropping all Linux kernel page
cache or terminating Raptor; doing so would disrupt the main video
stream and motor response. The CGI `exec curl` must be observed on
actual BusyBox httpd hardware to confirm process termination after
client disconnect; otherwise this is a remaining hardware bug.

## Acceptance on physical hardware

After building and booting a **new** SD image, while Hombo3 receives
RTSP video:

1. Load :8090 dashboard and Live page without starting preview:
   verify no additional `curl /mjpeg` or web video traffic.
2. Start preview: one web MJPEG session plus ongoing Hombo3 RTSP.
3. Stop preview, navigate away, hide or close tab: confirm that the
   web connection exits and Hombo3 frames remain stable.
4. Return to visible browser: preview remains off until clicked.
5. Measure CPU load, RSS, network throughput, PTZ reaction and FPS;
   measure separately for Hombo-only, Hombo+Web and after-close.
6. Verify CGI JSON, SSH, RTSP/audio after reboot.

Read-only on T23N SSH:

```sh
pidof rvd rsd rhd rad motors-daemon
ps w | grep -E '[c]url.*mjpeg|[h]ttpd|[r]vd|[r]sd|[r]hd'
cat /proc/loadavg
free
netstat -tn 2>/dev/null | grep -E ':554|:8090'
```

Mock browser tests: `node scripts/test_web_lazy_preview.js`.
Physical stream/CGI termination is not yet verified. Do not
disable RVD/RSD/RAD/RHD, PTZ motors, Wi-Fi or SSH to save resources.
