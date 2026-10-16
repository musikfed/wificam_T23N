# Архитектура Wi‑Fi и смена сети

## Слои

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

Веб-интерфейс не должен напрямую редактировать `wpa_supplicant.conf`. Он отправляет запрос backend API, а backend валидирует настройки, временно применяет их и только после успешного подключения сохраняет как постоянные.

## Рекомендуемый сценарий смены Wi‑Fi

1. Пользователь открывает **Сеть → Wi‑Fi**.
2. Камера сканирует доступные SSID.
3. Пользователь выбирает сеть и вводит пароль.
4. Backend создает временный профиль.
5. Камера пытается подключиться.
6. После DHCP выполняется проверка локальной связи.
7. При успехе профиль сохраняется.
8. При ошибке выполняется rollback к предыдущей рабочей сети.

Это предотвращает потерю доступа к камере из-за опечатки в пароле.

## API

```text
GET  /api/network/status
GET  /api/network/wifi/scan
POST /api/network/wifi/test
POST /api/network/wifi/apply
POST /api/network/wifi/rollback
POST /api/network/ap/enable
```

Пароли Wi‑Fi не возвращаются через API в открытом виде и не пишутся в обычные web/server logs.

## Recovery AP

Если камера не может подключиться к сохраненной сети несколько раз подряд, она поднимает временную recovery-точку доступа, например:

```text
WIFICAM-T23N-XXXX
```

Через нее можно снова открыть web UI и выбрать новую сеть.

## Смена пароля администратора

```text
POST /api/auth/password
```

Backend принимает текущий пароль и новый пароль, проверяет требования к длине, сохраняет только стойкий password hash и завершает старые web-сессии.
