# Архитектура Wi‑Fi, IP и сетевых сервисов

```text
Web UI
  |
  v
CGI JSON API
  |
  +--> wlan0 / wpa_supplicant / udhcpc
  |        └--> SSID, IPv4, gateway, DNS
  |
  +--> SSH              (по требованию)
  +--> WireGuard wg0    (по требованию)
  +--> AmneziaWG awg0   (по требованию)
  |
  +--> Camera service   (поднят ОС)
  +--> MEDIA storage
```

## Смена Wi-Fi

1. Web UI сканирует SSID.
2. Пользователь выбирает сеть и вводит пароль.
3. Backend создает новый `wpa_supplicant` профиль.
4. Выполняется association + DHCP.
5. Если IPv4 получен — профиль остается.
6. Если нет — возвращается `wpa_supplicant.conf.last-good`.

Пароли не возвращаются через API открытым текстом.

## IP

Web UI показывает текущие:

- SSID;
- IPv4/CIDR;
- default gateway;
- DNS.

На текущем этапе адрес получает DHCP client. Статическую IP-конфигурацию можно добавить отдельным rollback-safe этапом после первого успешного SD boot.

## SSH / WireGuard / AmneziaWG

Ключевой принцип: **выключено = не запущено**.

Marker-файлы:

```text
/data/services/ssh.enabled
/data/services/wireguard.enabled
/data/services/amneziawg.enabled
```

Если marker отсутствует, `S91wificam-services` не запускает сервис после reboot.

VPN конфиги:

```text
/data/vpn/wg0.conf
/data/vpn/awg0.conf
```

Управление выполняет `wificam-service-ctl`, а Web UI вызывает его через POST + CSRF.
