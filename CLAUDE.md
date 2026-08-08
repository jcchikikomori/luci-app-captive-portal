# luci-app-captive-portal — Agent Instructions

## Project Overview

LuCI web interface for managing captive portal authentication on OpenWrt routers, built on **openNDS**. There is no dual-daemon runtime toggle (see Key Design Decision #2). Guest accounts are stored in UCI config. Authentication itself is decided by a minimal local FAS (`fas_auth` ubus method plus a dedicated `uhttpd` listener) that calls `ndsctl auth` on success; `binauth.sh` is retained only for post-auth logging/bookkeeping (see Key Design Decision #5).

**License:** Apache 2.0
**Companion project:** [MyAdminCaptiva](https://github.com/jcchikikomori/MyAdminCaptiva) (Next.js admin console, same feature set but standalone)
**Splash page inspiration:** [nodogsplash-mod](https://github.com/jcchikikomori/nodogsplash-mod) (GPL-2.0 — do NOT copy code, write fresh)

---

## License Constraints

- **All code must be Apache 2.0 compatible.**
- **DO NOT** copy or port code from nodogsplash (GPL-2.0) and openNDS (GPL-2.0). Write fresh implementations inspired by the design.
- **DO NOT** include GPL-2.0 licensed code in this project.
- The binauth script and splash page must be written from scratch.

---

## Directory Structure

```
luci-app-captive-portal/
├── Makefile
├── build.sh                               # SDK build script
├── deploy.sh                              # Manual deploy script
├── CLAUDE.md
├── LICENSE
├── README.md
├── htdocs/
│   ├── luci-static/resources/view/captive-portal/
│   │   ├── status.js                    # Dashboard: service status + controls
│   │   ├── accounts.js                  # Guest accounts CRUD table
│   │   ├── settings.js                  # Service settings (form.Map)
│   │   └── clients.js                   # Active client sessions
│   └── captive-portal/                  # Splash page assets (served by the dedicated FAS uhttpd listener, see Key Design Decision #5)
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
    option daemon 'opennds'              # always 'opennds' — single-daemon, no runtime toggle (see Key Design Decision #2)
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
| ------ | --------- | --------- | ------------- |
| Status | `status.js` | RPC + `E()` | Service state, interface, gateway name, uptime, connected client count, raw daemon status text. Restart Service button — no daemon-type selector (daemon is fixed to openNDS). |
| Guest Accounts | `accounts.js` | RPC + TableSection | CRUD table: username, password, MAC, upload/download (formatted KB/MB/GB), timeout, auth method, enabled toggle. |
| Settings | `settings.js` | `form.Map` (UCI) | Interface (populated via `get_network_devices`), authentication method, gateway name, max client time, default upload/download limits, default timeout — no daemon selector (daemon is fixed to openNDS). |
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

Ubus object: `luci.captive-portal`

| Method | Description |
| -------- | ------------- |
| `get_status` | Service running/stopped, uptime, client count, raw daemon status text, and current config (interface, gateway name) |
| `get_daemon_status` | Raw `ndsctl status` output (only when the service is running) |
| `get_network_devices` | Enumerate network interfaces (excludes `lo`) for the Settings interface picker |
| `get_clients` | Active client sessions, parsed from `ndsctl json` |
| `disconnect_client` | Deauth a client by MAC (preferred) or IP via `ndsctl deauth` |
| `block_client` | Deauth the client, then add its MAC to the `blocked` UCI list and resync `blocked.json` |
| `get_blocked` | Read all `blocked` sections from UCI |
| `add_blocked` | Add a new blocked MAC (deauthing any active session for it) |
| `update_blocked` | Modify a blocked entry's MAC and/or enabled state |
| `delete_blocked` | Remove a blocked entry |
| `get_accounts` | Read all guest sections from UCI |
| `add_account` | Create a new guest account in UCI |
| `update_account` | Modify an existing guest account |
| `delete_account` | Remove a guest account |
| `fas_auth` | **Unauthenticated.** Validates the client's MAC against the `blocked` list and its credentials/MAC against the `guest` sections, then calls `ndsctl auth <mac> <sessiontimeout>` on success — the actual authentication decision point (see Key Design Decision #5) |
| `sync_daemon_config` | Push UCI service settings into `config opennds` (gatewayname, gatewayinterface, sessiontimeout, binauth, FAS settings); implemented by `sync_opennds_config()` |
| `restart_service` | Sync config, restart the `opennds` init script, and resync QoS (qosify/sqm) bandwidth limits |

`ndsctl` is the single control binary used for every daemon operation above — there is no `ndsctl`-for-nodogsplash vs `openndsctl`-for-openNDS branching (see Key Design Decision #2).

---

## BinAuth Script (`binauth.sh`)

- Located at `/usr/lib/captive-portal/binauth.sh`
- **Logging-only.** openNDS invokes BinAuth strictly *after* an authentication decision has already been made — it cannot gate, approve, or deny a client login (confirmed via upstream docs; see Key Design Decision #5). Credential validation happens in the `fas_auth` ubus method before openNDS ever calls this script.
- Reads nothing from UCI at call time; it only appends structured log lines to `/tmp/captive-portal/binauth.log`
- No external dependencies (no jq, no curl, no API calls)
- Dispatches on openNDS's BinAuth methods: `auth_client` (logged only — its username/password arguments are deprecated by openNDS and have no effect on access), `client_auth`, `client_deauth`, `idle_deauth`, `timeout_deauth`, `downquota_deauth`, `upquota_deauth`, `shutdown_deauth`

---

## Splash Page

Fresh HTML5/CSS/JS implementation inspired by nodogsplash-mod design:

- Responsive mobile-first layout
- Username + password login form
- Terms & conditions modal
- Device info display (manufacturer, browser via JS)
- openNDS has no `$var` template-substitution mechanism for a static FAS splash page. Instead, openNDS redirects the client's browser to `splash.html` with session info appended as a query string (`clientip`, `clientmac`, `gatewayname`, `gatewayaddress`, `clientif`, `authdir`, `redir`, `tok`/`hid`), which `splash.js` reads via `URLSearchParams`
- `splash.js` submits credentials to the `fas_auth` ubus method over `/ubus` (JSON-RPC, anonymous session ID) instead of a plain `$authaction` form post, then navigates to the `redir` target on success
- Post-login status page (`status.html`), which reads the same query-string convention for any session info it displays

---

## ACL Permissions

```json
{
  "luci-app-captive-portal": {
    "description": "Grant access to Captive Portal management",
    "read": {
      "ubus": { "luci.captive-portal": ["*"] },
      "uci": ["captive-portal", "opennds"]
    },
    "write": {
      "uci": ["captive-portal", "opennds"],
      "ubus": { "luci.captive-portal": ["*"], "service": ["*"] }
    }
  },
  "unauthenticated": {
    "description": "Public FAS authentication endpoint for openNDS",
    "read": {
      "ubus": { "luci.captive-portal": ["fas_auth"] }
    }
  }
}
```

---

## Implementation Order

| Step | Task | Status |
| ------ | ------ | -------- |
| 1 | Scaffolding (Makefile, LICENSE, README, directory structure) | completed |
| 2 | UCI defaults + Menu JSON + ACL JSON | completed |
| 3 | RPC ucode backend (`captive-portal.uc`) | completed |
| 4 | Settings view (`settings.js`) | completed |
| 5 | Guest Accounts view (`accounts.js`) | completed |
| 6 | Status view (`status.js`) | completed |
| 7 | Clients view (`clients.js`) | completed |
| 8 | BinAuth script (`binauth.sh`) | completed |
| 9 | Splash page (HTML/CSS/JS) | completed |
| 10 | Translation template (`captive-portal.pot`) | completed |

---

## Build & Deploy

### Target Environment

- **OpenWrt Version:** 24.10.2 (r28739-d9340319c6)
- **LuCI Version:** openwrt-24.10 branch 26.081.63927~e56e710
- **Target Platform:** ramips/mt7621

### Option A: SDK Build (produces .ipk)

```bash
./build.sh
```

This will:

1. Download the OpenWrt SDK for ramips/mt7621 if not present
2. Copy package files into the SDK
3. Build the ipk package
4. Output the ipk location for installation

### Option B: Manual Deploy (for development)

```bash
./deploy.sh [device-ip]
# Default: ./deploy.sh 192.168.1.1
```

This copies files directly to the device and restarts services.

### Installation (from ipk)

```bash
# Copy ipk to router
scp bin/packages/*/luci/luci-app-captive-portal*.ipk root@192.168.1.1:/tmp/

# Install
ssh root@192.168.1.1 'opkg install /tmp/luci-app-captive-portal*.ipk'
```

### Post-Installation

1. Log out and back into LuCI to clear cache
2. Navigate to **Services > Captive Portal**
3. Configure interface in **Settings**
4. Add guest accounts in **Guest Accounts**

### Testing rpcd/ucode Logic Locally

`captive-portal.uc` runs under `ucode`, which isn't installed on a typical dev machine. For any change touching `popen()`/shell-command construction (e.g. `fas_auth`), don't rely on static review alone: build a real `ucode` interpreter from source (`apt install libjson-c-dev`, then build `github.com/jow-/ucode` with cmake) and execute the actual script against crafted/edge-case inputs — this is how the `fas_auth` command-injection fix was verified, not just reasoned about.

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
- When creating a UCI section that must be addressable by a fixed name later, use `uci set <config>.<name>=<type>`, not `uci add <config> <type>` — the latter creates an anonymous section, not one named `<type>` (this caused a real bug in the FAS uhttpd listener creation).

---

## Key Design Decisions

1. **UCI-native storage** — Guest accounts in `/etc/config/captive-portal`, survives reboots, CLI-accessible
2. **Single-daemon design (openNDS only)** — The RPC backend hardcodes its control binary (`ndsctl`) and service name (`opennds`) as constants; there is no runtime daemon detection or branching. The captive-portal daemon packages available in OpenWrt mutually CONFLICT with each other, so a dual-daemon toggle was never something this package could actually need to support at runtime.
3. **No external dependencies** — binauth uses `uci` CLI instead of jq/curl/API
4. **Fresh splash page** — Inspired by nodogsplash-mod but written from scratch (Apache 2.0 clean)
5. **Local FAS handles authentication, not BinAuth** — openNDS's BinAuth hook cannot gate authentication: per upstream documentation it only runs as a post-authentication notification, and `auth_client`'s username/password arguments are explicitly deprecated and have no effect on whether a client is granted access (see `docs/plans/analysis/opennds-verification-findings.md`). Authentication is instead handled by a minimal **local FAS**: a dedicated `uhttpd` listener instance (`uhttpd.captive_portal_fas`, port 2080) serves the splash assets and the `/ubus` endpoint pre-login; `splash.js` posts credentials to the `fas_auth` ubus method (reachable unauthenticated via the ACL's `unauthenticated` group), which validates the request against the `blocked` and `guest` UCI sections and calls `ndsctl auth <mac> <sessiontimeout>` on success. `binauth.sh` is retained only to log post-auth/deauth events — it has no bearing on the auth decision itself. This design was chosen over openNDS's built-in PHP-based FAS examples or a ThemeSpec script to satisfy the project's zero-new-package constraint: the target device has 8MB of flash and no PHP available (`fas_secure_enabled` level 2+ requires PHP), so reusing the existing uhttpd/ucode/rpcd stack already on the device avoided adding any new package dependency.

   **Accepted risk — no anti-spoofing token verification.** `fas_secure_enabled` is set to `0` (plain, not `1`/hashed) because level 1 implies openNDS sends a hashed `hid` token that the FAS is expected to verify before trusting client-supplied identifiers, and `fas_auth` does not implement that verification (it would require reverse-engineering openNDS's hid hashing scheme against a real device — not done here). Practical effect: `fas_auth` trusts the `mac` value exactly as supplied by the HTTP caller, with no cryptographic proof that the caller actually controls that MAC address — a client with valid guest credentials (which, for a guest WiFi, are meant to be shared) can request network access be granted to an arbitrary MAC of their choosing, not just their own device. Mitigated but not eliminated: `fas_auth` strictly validates that `mac` is a well-formed MAC address (rejecting anything else, including shell metacharacters) before it is ever used, which closes the command-injection risk that a malformed value would otherwise create in the underlying `ndsctl auth` shell call, but format validation alone doesn't prove *ownership* of that MAC. Implementing `hid` verification (or deriving the client's MAC server-side from their source IP via the ARP/neighbor table instead of trusting the request body) is the natural follow-up hardening step before relying on this in a hostile-guest-network environment.

   **TODO:** openNDS's `auth_restore` feature (automatic reauthentication of previously-authenticated clients after an `opennds` daemon restart) is driven by the stock `binauth_log.sh` script; replacing it with our own `binauth.sh` forfeits this behavior, and it has not been reimplemented. Revisit if reauth-after-restart becomes a hard requirement.

---

## Compatibility note

- This package targets **openNDS only**. The daemon migration is complete; there is no dual-daemon code path left to maintain.

---

## TODOs / Outstanding items

1. Building this software
2. This is supposed to be a submodule (standalone module) of the author's fork of LuCI (<https://github.com/jcchikikomori/luci>), since the dependencies are sitting there.
3. Testing this software on the actual OpenWRT software with LuCI installed
4. Software compatibility, particularly on non-x86 platforms (ramips/mt7621, ARMv7, etc.)
5. **`auth_restore` forfeited** — openNDS's `auth_restore` reauth-after-daemon-restart feature relies on the stock `binauth_log.sh`; replacing it with our logging-only `binauth.sh` forfeits this behavior, and it has not been reimplemented.
6. **Per-client rate/quota limits not wired into `ndsctl auth`** — `fas_auth` only passes `sessiontimeout` to `ndsctl auth`; the guest account's `upload_limit`/`download_limit` fields have no confirmed unit mapping onto `ndsctl`'s `uploadrate`/`downloadrate` (kb/s) or `uploadquota`/`downloadquota` (kB) parameters, and that mapping has not been verified against a real device. Per-client bandwidth enforcement currently relies solely on the QoS sync (`sync_qos_config`, via qosify/sqm), which applies the *default* limits globally rather than per guest account.
7. **7-key config duplication not consolidated** — The same 7 UCI keys (`gatewayname`, `gatewayinterface`, `sessiontimeout`, `binauth`, `fasport`, `faspath`, `fas_secure_enabled`) are set independently in `captive-portal.uc`'s `sync_opennds_config()`, `root/etc/init.d/captive-portal`'s `sync_opennds()`, and `root/etc/uci-defaults/80_captive-portal`. This migration did not consolidate them into a single source of truth; a future refactor should extract a shared helper.
8. **`fas_auth` has no anti-spoofing token verification** — see Key Design Decision #5's "Accepted risk" note. `fas_auth` validates that `mac` is well-formed (blocking command injection) but not that the caller actually controls that MAC. Follow-up: implement openNDS's `hid` token verification, or derive the client's MAC server-side from their source IP (ARP/neighbor table) instead of trusting the request body.
9. **`fas_auth` has no rate limiting** — repeated failed login attempts against the unauthenticated `fas_auth` endpoint are not throttled or locked out. Follow-up: add a failed-attempt counter (keyed by IP or MAC) with backoff/lockout.
10. ~~`uhttpd.captive_portal_fas` and the rpcd `"unauthenticated"` ACL group convention are unverified against a live device~~ — **confirmed working on real hardware** (OpenWrt 24.10.2, ramips/mt7621): the FAS listener binds on port 2080, serves the splash assets and `/ubus`, and the `unauthenticated` ACL group correctly grants anonymous access to `fas_auth` only. Two real bugs were found and fixed in the process: (a) `sync_opennds_config()`/`sync_opennds()`/uci-defaults never set `opennds.@opennds[0].enabled`, so a pre-existing or otherwise-disabled `opennds` config section left the daemon never starting — now explicitly set to `'1'` in all three places; (b) uci-defaults created the uhttpd instance with `add uhttpd captive_portal_fas` (creates an *anonymous* section of that type, not a section *named* `captive_portal_fas`), so every subsequent `set uhttpd.captive_portal_fas.*` silently failed — fixed to `set uhttpd.captive_portal_fas=uhttpd` (named-section syntax).
11. **Minor unexplained `uci: Invalid argument` messages during `opennds`/`captive-portal` restart** — cosmetic, non-blocking (service starts, FAS listener works, auth flow works); traced away from our own scripts (uci-defaults, init.d, tc-helper.sh all ran clean under `sh -x`) — likely internal to openNDS's own startup/firewall-hook chain. Not investigated further; revisit if it turns out to correlate with an actual functional issue later.
12. **`ndsctl auth <mac>` requires a MAC openNDS already has a pending session for** — confirmed on real hardware: calling `fas_auth` with a MAC that never actually made an HTTP request through the captive portal fails (`ndsctl auth` correctly refuses an unknown client). This is expected upstream behavior, not a bug — `fas_auth` is only ever reachable in practice via the real FAS redirect flow (which guarantees a pending session already exists), but worth documenting so it isn't mistaken for a defect during future testing.
13. **`postrm`'s `uci delete captive-portal` is a no-op** — the Makefile's `Package/luci-app-captive-portal/postrm` runs `uci delete captive-portal` with no section argument, which does not actually wipe the config (confirmed on real hardware — guest-account data survived a real package removal). Needs a decision: iterate real sections, `rm -f /etc/config/captive-portal`, or explicitly document that config is meant to survive removal.

---

## References

- <https://opennds.readthedocs.io/en/stable/index.html>
- `docs/plans/analysis/opennds-verification-findings.md` — upstream verification of `ndsctl`, BinAuth, UCI schema, and FAS behavior that this migration's design is based on
