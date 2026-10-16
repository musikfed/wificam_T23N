# Wi-Fi, IP and network service architecture

```text
Web UI
  |
  v
CGI JSON API
  |
  +--> wlan0 / wpa_supplicant / udhcpc
  |        └--> SSID, IPv4, gateway, DNS
  |
  +--> SSH              (on demand)
  +--> WireGuard wg0    (on demand)
  +--> AmneziaWG awg0   (on demand)
  |
  +--> Camera service   (OS managed)
  +--> MEDIA storage
```

## Wi-Fi switching

1. Web UI scans SSIDs.
2. User selects a network and enters its password.
3. Backend builds a new `wpa_supplicant` profile.
4. Association + DHCP are attempted.
5. If IPv4 is obtained, keep the new profile.
6. Otherwise restore `wpa_supplicant.conf.last-good`.

Passwords are never returned in plaintext by the API.

## IP

The Web UI displays current:

- SSID;
- IPv4/CIDR;
- default gateway;
- DNS.

The current implementation uses DHCP. Static IP configuration can be added later with the same rollback-safe principle after the first successful SD boot.

## SSH / WireGuard / AmneziaWG

Main rule: **disabled means not started**.

Marker files:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

Without a marker, `S91wificam-services` does not start that feature after reboot.

VPN configs:

```text
/data/vpn/wg0.conf
/data/vpn/awg0.conf
```

`wificam-service-ctl` performs the action and the Web UI accesses it through POST + CSRF.
