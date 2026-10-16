# Wi-Fi architecture and network switching

## Layers

```text
Web UI
  |
  v
HTTP/JSON API
  |
  +--> Network service
  |      |
  |      +--> wpa_supplicant
  |      +--> udhcpc/DHCP client
  |      +--> wlan0
  |
  +--> Camera service
  +--> Storage service
  +--> System/update service
```

The web UI must not edit `wpa_supplicant.conf` directly. It sends requests to the backend API. The backend validates the settings, tests them temporarily and persists them only after a successful connection.

## Recommended Wi-Fi change flow

1. Open **Network → Wi-Fi**.
2. Scan available SSIDs.
3. Select a network and enter its password.
4. Backend creates a temporary profile.
5. Camera attempts association.
6. After DHCP, local connectivity is checked.
7. On success, persist the new profile.
8. On failure, roll back to the previous known-good network.

This avoids locking the user out because of a mistyped Wi-Fi password.

## API

```text
GET  /api/network/status
GET  /api/network/wifi/scan
POST /api/network/wifi/test
POST /api/network/wifi/apply
POST /api/network/wifi/rollback
POST /api/network/ap/enable
```

Wi-Fi passwords must never be returned in plaintext by the API or written to normal web/server logs.

## Recovery AP

If the camera repeatedly fails to join its saved network, it can start a temporary recovery access point such as:

```text
WIFICAM-T23N-XXXX
```

The user can reconnect to the web UI and configure a new network.

## Administrator password change

```text
POST /api/auth/password
```

The backend verifies the current password and the new password requirements, stores only a strong password hash, and invalidates previous web sessions.
