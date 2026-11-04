# WIFICAM T23N 0.2_test: build and physical validation

**Do not replace the hardware-booted 0.1_test recovery baseline.** This is an unverified firmware candidate, not a release.

Before the first test build, merge the private-Wi-Fi guard fix into `mymarrchWFcam` (the only intended candidate branch), and ensure YadroKreator has candidate-only artifact selection from PR #14. The production builder is Ubuntu 24.04 on Huananzhi. Do not run Linux cross compilation using native Windows Python. Acer remains the Hombo3 Windows orchestration host.

Log into CORE as the normal user (not sudo):

```bash
cd /1tbdisk/PegineLab/projects/YadroKreator
git status --short
bash scripts/project-control.sh status
bash start.sh
bash deploy.sh --check
bash deploy.sh --apply
```

Run `deploy.sh --apply` only **after** the builder update is merged to its main branch and no uncommitted code/build jobs conflict. Opening `http://192.168.0.100:62404/` over trusted LAN/VPN, select **WIFICAM T23N → t23n_sd → mymarrchWFcam → WIFICAM_WEBRTC=0 → New build**. The builder pins the current source SHA, uses `PUBLISH=0`, does not flash SD and stores the generated SD disk image only in the current isolated job's `out/candidate-sd/` or `out/private-sd/` (when private local Wi-Fi provisioning is present). The public generic build must not require any private WPA2 configuration.

Run preflight: verify SHA256, MBR, MSPL LBA34, FAT16 BOOT/uImage LBA2048 and ext4 ROOTFS LBA34816, then download the validated full raw `.img` in Artifacts. On Acer Windows choose the **camera microSD** in Rufus raw/DD mode or balenaEtcher and write the entire image starting at LBA0. Never select an SSD or ordinary PC installer USB. Preserve the old known-booting card for recovery. Windows ext4 format prompts must be cancelled.

Physically verify the T23N SD root `/dev/mmcblk0p2`, DHCP/Wi-Fi and SSH, :8090 Web UI plus CGI JSON execution (never raw script output), SC2336 RTSP video, microphone track, audible quiet speaker output through Raptor rac/play, PTZ STOP, IR-cut/night mode and cold reboot. Only then test the external Acer/CORE conversational vision and audio assistant. T23N runs neither YOLO nor Ollama.

Never publish embedded Wi-Fi credentials, private `.img`/rootfs nor tokens; do not claim hardware verification from GitHub CI.
