# Hardware-confirmed BusyBox CGI failure on WIFICAM T23N (2026-11-02)

**Camera evidence:** Linux boots SD ext4 root \`/dev/mmcblk0p2\`; Wi-Fi and SSH work; PegineLab UI and \`cgi-bin/api\` exist; executing the CGI directly returns JSON. However, both \`httpd\` and \`busybox httpd\` on loopback \`127.0.0.1:18090\` returned HTTP 200 with the **literal shell source \`#!/bin/sh\`**. The independent WIFICAM init script correctly refuses to open public \`:8090\` because serving CGI source may disclose sensitive application internals.

This is a **binary CGI capability** defect, not a kernel, SD offset, Wi-Fi or script syntax failure. A Buildroot BusyBox \`.config\` containing \`CONFIG_FEATURE_HTTPD_CGI=y\` is **not runtime evidence**. CGI also requires \`CONFIG_FEATURE_FORCE_APPLETS\` to be disabled, because it needs exec.

This change includes:

- \`scripts/rebuild_busybox_cgi_candidate.sh\`: incremental **BusyBox-only** reconfigure/rebuild in the same pinned Thingino worktree; no kernel rebuild or SD image replacement. Refuses while factory jobs run; stages a candidate under gitignored \`out/candidate-busybox\`.
- \`scripts/camera_smoke_httpd_cgi.sh [candidate_path]\`: real on-camera CGI execution check on **127.0.0.1:18090 only**, requiring exact \`{"ok":true,"cgi":"executed"}\`, and detecting raw CGI source. Cleans up and never replaces system BusyBox.
- \`rootfs/etc/init.d/S90wificam\`: **preflight before binding LAN :8090**. Optional \`WIFICAM_HTTPD_BIN=/absolute/path/to/tested/busybox\` for an isolated binary; default system HTTP server remains unchanged.
- CI shell checks + static assertions, separate from hardware acceptance.

## Incremental build on Huananzhi

Run as regular Ubuntu user, with no active factory jobs:

\`\`\`bash
JOB=/1tbdisk/PegineLab/build/jobs/1a383b6c22584fc1a3c4f0c4e80d20a3/wificam_T23N
SOURCE=/1tbdisk/PegineLab/projects/wificam_T23N

git -C "$SOURCE" fetch origin mymarrchWFcam
git -C "$SOURCE" show origin/mymarrchWFcam:scripts/rebuild_busybox_cgi_candidate.sh \
  > "$JOB/out/rebuild_busybox_cgi_candidate.sh"
sh "$JOB/out/rebuild_busybox_cgi_candidate.sh"
\`\`\`

If the historical per-job BusyBox fragment is missing, this tool intentionally fails: rebuilding with a different configuration would risk the wrong MIPS/ABI. Follow the error; do not run a full factory cleanbuild.

The candidate path is \`$JOB/out/candidate-busybox/busybox-cgi-candidate\`. Copy that and \`scripts/camera_smoke_httpd_cgi.sh\` to **/tmp** on the camera via SSH/SCP (possibly through a PC that has a route to both networks), then on camera:

\`\`\`sh
chmod 700 /tmp/wificam-busybox-cgi
sh /tmp/camera_smoke_httpd_cgi.sh /tmp/wificam-busybox-cgi
\`\`\`

Only **PASS** on actual hardware qualifies the binary for starting WIFICAM.

## After PASS: temporary web UI trial

Copy the updated \`rootfs/etc/init.d/S90wificam\` to camera \`/tmp/S90wificam-cgi\`. Then:

\`\`\`sh
WIFICAM_HTTPD_BIN=/tmp/wificam-busybox-cgi sh /tmp/S90wificam-cgi start
netstat -lnt 2>/dev/null | grep ':8090'
\`\`\`

The updated init script runs a localhost CGI probe **before** opening the LAN port and preserves existing web auth. This test candidate is temporary and disappears on reboot; for a permanent fix, build the hardware-proven BusyBox into a new SD image and test cold boot. Do **not** overwrite \`/bin/busybox\`, disable the source-disclosure guard, or assume a green CI means the camera is fixed.

For Russian end-to-end walkthrough and exact commands, use [CGI_BUSYBOX_HARDWARE_FIX_RU.md](CGI_BUSYBOX_HARDWARE_FIX_RU.md).
