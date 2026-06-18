# luci-app-captive-portal — Agent Instructions

## Project Overview

LuCI web interface for managing captive portal authentication on OpenWrt routers.
Supports both **nodogsplash** and **openNDS** daemons.
Guest accounts stored in UCI config. BinAuth reads directly from UCI (no external API, no jq/curl).

**License:** Apache 2.0
**Companion project:** [MyAdminCaptiva](https://github.com/jcchikikomori/MyAdminCaptiva) (Next.js admin console, same feature set but standalone)
**Splash page inspiration:** [nodogsplash-mod](https://github.com/jcchikikomori/nodogsplash-mod) (GPL-2.0 — do NOT copy code, write fresh)

---

## License Constraints

- **All code must be Apache 2.0 compatible.**
- **DO NOT** copy or port code from nodogsplash-mod (GPL-2.0). Write fresh implementations inspired by the design.
- **DO NOT** include GPL-2.0 licensed code in this project.
- The binauth script and splash page must be written from scratch.

---

## Directory Structure

```
luci-app-captive-portal/
├── Makefile
├── AGENTS.md
├── LICENSE
├── README.md
├── htdocs/
│   ├── luci-static/resources/view/captive-portal/
│   │   ├── status.js                    # Dashboard: service status + controls
│   │   ├── accounts.js                  # Guest accounts CRUD table
│   │   ├── settings.js                  # Daemon config (form.Map)
│   │   └── clients.js                   # Active client sessions
│   └── captive-portal/                  # Splash page assets (served by daemon)
│       ├── splash.html
│       ├── splash.css
│       ├── splash.js
│       └── status.html
├── root/
│   ├── etc/
│   │   └── uci-defaults/80_captive-portal
│   └── usr/
│       ├── lib/captive-portal/
│       │   └── binauth.sh              # Auth hook (reads from UCI)
│       └── share/
│           ├── luci/menu.d/luci-app-captive-portal.json
│           └── rpcd/
│               ├── acl.d/luci-app-captive-portal.json
│               └── ucode/captive-portal.uc
└── po/templates/captive-portal.pot
```

---

## UCI Config Schema (`/etc/config/captive-portal`)

```
config service
    option daemon 'nodogsplash'          # 'nodogsplash' | 'opennds'
    option interface 'lan'
    option auth_method 'both'            # 'password' | 'mac' | 'both'
    option portal_name 'Guest WiFi'
    option max_client_time '0'           # 0 = unlimited
    option gatewayname 'CaptivePortal'
    option default_upload_limit '0'      # bytes, 0 = unlimited
    option default_download_limit '0'    # bytes, 0 = unlimited
    option default_timeout '1200'        # seconds

config guest 'guest1'
    option username 'guestuser'
    option password 'ph4hhw0rDd'
    option mac ''                        # empty = no binding
    option upload_limit '0'
    option download_limit '0'
    option timeout '1200'
    option auth_method 'password'        # 'password' | 'mac' | 'both'
    option enabled '1'
```

---

## LuCI Views

| Page | JS File | Pattern | Description |
|------|---------|---------|-------------|
| Status | `status.js` | RPC + `E()` | Service state, daemon type, interface, client count, uptime. Start/Stop/Restart buttons. |
| Guest Accounts | `accounts.js` | RPC + TableSection | CRUD table: username, password, MAC, upload/download (formatted KB/MB/GB), timeout, auth method, enabled toggle. |
| Settings | `settings.js` | `form.Map` (UCI) | Daemon selector, interface, auth method, portal name, gateway name, default limits/timeout. |
| Clients | `clients.js` | RPC + `E()` table | Live table: IP, MAC, username, uptime, traffic used, disconnect/block buttons. |

### Menu Path

```
admin/services/captive-portal/           -> Status (firstchild)
admin/services/captive-portal/accounts   -> Guest Accounts
admin/services/captive-portal/settings   -> Settings
admin/services/captive-portal/clients    -> Connected Clients
```

---

## RPC Backend (`captive-portal.uc`)

Ub us object: `luci.captive-portal`

| Method | Description |
|--------|-------------|
| `get_status` | Service running/stopped, daemon type, uptime, client count |
| `get_clients` | Active sessions (parse ndsctl/openndsctl status output) |
| `disconnect_client` | Kick client by MAC/IP |
| `get_accounts` | Read all guest sections from UCI |
| `add_account` | Create new guest account in UCI |
| `update_account` | Modify existing guest account |
| `delete_account` | Remove guest account |
| `restart_service` | Restart nodogsplash/openNDS daemon |

The backend must detect which daemon is configured and call the appropriate control binary (`ndsctl` for nodogsplash, `openndsctl` for openNDS).

---

## BinAuth Script (`binauth.sh`)

- Located at `/usr/lib/captive-portal/binauth.sh`
- Called by nodogsplash/openNDS on auth attempt
- Reads guest accounts directly from UCI using `uci show` / `uci get`
- No external dependencies (no jq, no curl, no API calls)
- Handles `auth_client` method: validate username + password, check MAC binding, output `timeout upload_limit download_limit`
- Handles deauth/logging events: `client_auth`, `client_deauth`, `idle_deauth`, `timeout_deauth`, `ndsctl_auth`, `ndsctl_deauth`, `shutdown_deauth`

---

## Splash Page

Fresh HTML5/CSS/JS implementation inspired by nodogsplash-mod design:
- Responsive mobile-first layout
- Username + password login form
- Terms & conditions modal
- Device info display (manufacturer, browser via JS)
- Uses nodogsplash/openNDS template variables: `$gatewayname`, `$authaction`, `$tok`, `$redir`, `$clientmac`, `$nclients`
- Post-login status page (`status.html`)

---

## ACL Permissions

```json
{
  "luci-app-captive-portal": {
    "description": "Grant access to Captive Portal management",
    "read": {
      "ubus": { "luci.captive-portal": ["*"] },
      "uci": ["captive-portal", "nodogsplash", "opennds"]
    },
    "write": {
      "uci": ["captive-portal", "nodogsplash", "opennds"],
      "ubus": { "luci.captive-portal": ["*"], "service": ["*"] }
    }
  }
}
```

---

## Implementation Order

| Step | Task | Status |
|------|------|--------|
| 1 | Scaffolding (Makefile, LICENSE, README, directory structure) | pending |
| 2 | UCI defaults + Menu JSON + ACL JSON | pending |
| 3 | RPC ucode backend (`captive-portal.uc`) | pending |
| 4 | Settings view (`settings.js`) | pending |
| 5 | Guest Accounts view (`accounts.js`) | pending |
| 6 | Status view (`status.js`) | pending |
| 7 | Clients view (`clients.js`) | pending |
| 8 | BinAuth script (`binauth.sh`) | pending |
| 9 | Splash page (HTML/CSS/JS) | pending |
| 10 | Translation template (`captive-portal.pot`) | pending |

---

## Code Conventions

- LuCI JS files: use tabs for indentation (per LuCI convention)
- Wrap all user-facing strings in `_()` for translation
- Use `'require view'`, `'require form'`, `'require rpc'` module declarations
- RPC calls via `rpc.declare({ object, method })`
- UCI access via `uci.load()`, `uci.sections()`, `uci.get()` in JS; `cursor()` in ucode
- Shell scripts: POSIX sh compatible (no bashisms), use `#!/bin/sh`
- Bandwidth values stored as bytes; format to human-readable (KB/MB/GB) in the JS view
- MAC addresses normalized to uppercase for comparison

---

## Key Design Decisions

1. **UCI-native storage** — Guest accounts in `/etc/config/captive-portal`, survives reboots, CLI-accessible
2. **Dual daemon support** — RPC backend detects configured daemon, calls appropriate control binary
3. **No external dependencies** — binauth uses `uci` CLI instead of jq/curl/API
4. **Fresh splash page** — Inspired by nodogsplash-mod but written from scratch (Apache 2.0 clean)
5. **BinAuth over FAS** — Use BinAuth for authentication hook (simpler, no external web server needed)
