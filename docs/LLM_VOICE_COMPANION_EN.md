# PegineLab WIFICAM T23N — optional external LLM / GPT voice companion

The Dashboard now contains an **LLM / GPT companion** checkbox and an **AI / Voice** page. It is **off by default**, only stores a consent/enable marker in `/opt/wificam/services/llm_companion.enabled`, and does not start inference or transmit video/audio on the T23N. Its state survives a reboot. The gateway online indicator is a recent heartbeat, **not** proof of working talkback.

An external host (PC / Huananzhi) must provide speech-to-text, LLM/GPT and text-to-speech. Camera-side mic audio transport and speaker playback are **not yet hardware-verified**; the current `wificam-camera-ctl` has no playback command. Do not advertise the checkbox as a completed physical voice assistant.

## Existing authenticated camera CGI contract

- `GET /cgi-bin/api?op=assistant_status` returns `enabled`, `connected`, `state`, `backend:external` (requires Basic Auth).
- `POST /cgi-bin/api?op=assistant_toggle` accepts `enabled=1|0&csrf=<token>` (Basic Auth + CSRF).
- `POST /cgi-bin/api?op=assistant_heartbeat` accepts `csrf=<token>` from an authenticated external bridge only when enabled. A heartbeat goes stale after 90 seconds and is stored only in volatile `/var/run`.

The bridge must refrain from capture or upload when disabled, stop media promptly after being disabled, and never store API keys in camera firmware or Git. Restrict the camera's :8090 to trusted LAN/VPN; Basic Auth over plain HTTP is not encryption. CGI source exposure protection remains active.

## Network transport policy

RTSP and Wi-Fi ATBM6012BX/USB DWC2 are preserved; they do not require WebRTC, RTMP, SRT, WebTorrent or USB-webcam. WebRTC **is** useful for browser video and bidirectional low-latency audio: set `WIFICAM_WEBRTC=1` during **firmware build** to opt into Raptor WebRTC/TLS, with potential additional resource cost. The lean default is `WIFICAM_WEBRTC=0`. This compile-time option is separate from the runtime AI toggle.

CI validates the CGI contract only. Physical cold boot, 8090 CGI, microphone input and speaker talkback must be proven separately before a real voice companion is claimed.
