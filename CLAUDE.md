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

   **Resolved — MAC is no longer client-supplied at all.** `fas_auth` used to accept a `mac` field directly from the HTTP caller, which was both an anti-spoofing gap (no proof the caller controlled that MAC) and, discovered later via real-device testing, simply *never populated* by the splash page in the first place: openNDS does not send a `clientmac` query parameter to the FAS at `fas_secure_enabled=0` at all (confirmed via `logread | grep splashpageurl` — the redirect only carries `authaction`, `gatewayname`, `tok`, `redir`; the client IP is present but only embedded, unescaped, inside `authaction`'s own value). `fas_auth` now accepts an `ip` field instead and derives the MAC server-side via `lookup_mac_by_ip()` (`ip neigh show <ip> dev <interface>`, parsed from the router's own ARP/neighbor table) — this fixes both problems at once: the client no longer needs to know its own MAC (which openNDS never gave it), and the MAC can no longer be spoofed via the request body, since it now comes from what the router's own kernel has observed for that IP, not from client-supplied input. `fas_secure_enabled` remains `0` (plain token) since `fas_auth` still doesn't verify the `hid`/`tok` value itself — that piece of the original accepted-risk note still stands (see TODO).

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
8. ~~`fas_auth` has no anti-spoofing token verification~~ — **mostly resolved**: `fas_auth` no longer trusts a client-supplied `mac` at all (see Key Design Decision #5). Remaining gap: `fas_auth` still doesn't verify openNDS's `hid`/`tok` value, and the client-reported `ip` itself is trusted (mitigated by MAC now coming from the router's own ARP table rather than the request body directly, but a client could still claim a different IP than its own TCP source — not exploitable through the browser-driven flow, since the browser can't fabricate its own IP, but worth noting for anyone calling `fas_auth` directly).
9. **`fas_auth` has no rate limiting** — repeated failed login attempts against the unauthenticated `fas_auth` endpoint are not throttled or locked out. Follow-up: add a failed-attempt counter (keyed by IP or MAC) with backoff/lockout.
10. ~~`uhttpd.captive_portal_fas` and the rpcd `"unauthenticated"` ACL group convention are unverified against a live device~~ — **confirmed working on real hardware** (OpenWrt 24.10.2, ramips/mt7621): the FAS listener binds on port 2080, serves the splash assets and `/ubus`, and the `unauthenticated` ACL group correctly grants anonymous access to `fas_auth` only. Two real bugs were found and fixed in the process: (a) `sync_opennds_config()`/`sync_opennds()`/uci-defaults never set `opennds.@opennds[0].enabled`, so a pre-existing or otherwise-disabled `opennds` config section left the daemon never starting — now explicitly set to `'1'` in all three places; (b) uci-defaults created the uhttpd instance with `add uhttpd captive_portal_fas` (creates an *anonymous* section of that type, not a section *named* `captive_portal_fas`), so every subsequent `set uhttpd.captive_portal_fas.*` silently failed — fixed to `set uhttpd.captive_portal_fas=uhttpd` (named-section syntax).
11. **Minor unexplained `uci: Invalid argument` messages during `opennds`/`captive-portal` restart** — cosmetic, non-blocking (service starts, FAS listener works, auth flow works); traced away from our own scripts (uci-defaults, init.d, tc-helper.sh all ran clean under `sh -x`) — likely internal to openNDS's own startup/firewall-hook chain. Not investigated further; revisit if it turns out to correlate with an actual functional issue later.
12. **`ndsctl auth <mac>` requires a MAC openNDS already has a pending session for** — confirmed on real hardware: calling `fas_auth` with a MAC that never actually made an HTTP request through the captive portal fails (`ndsctl auth` correctly refuses an unknown client). This is expected upstream behavior, not a bug — `fas_auth` is only ever reachable in practice via the real FAS redirect flow (which guarantees a pending session already exists), but worth documenting so it isn't mistaken for a defect during future testing.
13. **`postrm`'s `uci delete captive-portal` is a no-op** — the Makefile's `Package/luci-app-captive-portal/postrm` runs `uci delete captive-portal` with no section argument, which does not actually wipe the config (confirmed on real hardware — guest-account data survived a real package removal). Needs a decision: iterate real sections, `rm -f /etc/config/captive-portal`, or explicitly document that config is meant to survive removal.
14. ~~`fas_secure_enabled` hardcoded `'1'` in the shell scripts, `'0'` in ucode~~ — **fixed**: the 7-key duplication (TODO #7) let this drift after the security fix changed only `captive-portal.uc`'s constant. `root/etc/init.d/captive-portal` and `root/etc/uci-defaults/80_captive-portal` both hardcoded the old `'1'` value independently; now all three agree on `'0'`. A concrete illustration of why TODO #7 (consolidating the duplication) is worth doing eventually.
15. **Guest-network clients could not reach the splash page at all** (`net::ERR_CONNECTION_REFUSED`) — found via real device testing (not simulated): openNDS protects the router from pre-auth guest clients using its own walled garden, a fixed list of "essential" ports (its own built-in webserver port, DNS, DHCP, SSH, HTTPS) enforced in a **separate legacy `ip` family nftables table it manages directly** (`nds_filter`, chains `ndsINP`→`ndsRTR`, hooked at nftables priority `-100` — evaluated *before* OpenWrt's normal fw4-managed firewall chains ever see the packet). Port 2080 (this project's FAS listener) was never on that list. **Fixed** by adding `list users_to_router 'allow tcp port 2080'` to the `opennds` UCI section in `80_captive-portal` — openNDS's own supported mechanism for extending that specific allowlist (confirmed via `nft list table ip nds_filter`, chain `ndsRTR`, after the fix: `tcp dport 2080 ... accept`). A parallel `firewall` (fw4) rule was tried too but found to be inert for this specific issue (the `ip nds_filter` chain's priority -100 hook always wins the race and terminates evaluation first) and a source of its own bug (interface-name vs. firewall-zone-name mismatch when auto-detecting the zone) — removed rather than kept as dead/misleading code. See the README's "Firewall / Port Requirements" section for the user-facing explanation.
16. ~~Splash page could not capture the client's MAC address~~ — **fixed**: confirmed on real hardware that openNDS never sends a `clientmac` query parameter to the FAS at `fas_secure_enabled=0` (only `authaction`/`gatewayname`/`tok`/`redir`; client IP is present but only embedded inside `authaction`'s own value). `splash.js` now extracts `clientip` from `authaction` and sends it as `ip`; `fas_auth` derives the MAC server-side via ARP lookup (`lookup_mac_by_ip()`). Verified end-to-end on real hardware with a real connected device (`ndsctl json` confirmed `"state":"Authenticated"` after a real `fas_auth` call using the ARP-derived MAC). See Key Design Decision #5.
17. **`status.html` reachability is unconfirmed** — this page was written assuming it'd be reached as some kind of post-login status/continue page, but nothing in the current FAS flow actually navigates to it (`splash.js` redirects straight to `redir` on success, not to `status.html`), and openNDS's own `statuspath`/`gatewayfqdn` mechanism (which generates the Error511/status page) was never repointed at it. It may be entirely orphaned/dead code left over from an earlier design. Needs investigation before relying on it or removing it.
18. ~~Connected Clients showed no username/uptime/downloaded/uploaded~~ — **fixed**: `parse_clients_json()` was reading `c.username`/`c.duration`/`c.downloaded`/`c.uploaded` from `ndsctl json`, none of which exist in openNDS's schema (carried over from nodogsplash's field names, never updated during the migration). openNDS tracks no per-client "username" at all (resolved via a best-effort lookup against `guest` sections with a bound MAC — password-only accounts still show `-`); uptime is now computed from `session_start` (a unix timestamp) vs. `time()`; downloaded/uploaded now read the real field names `download_this_session`/`upload_this_session`.
19. ~~Gateway Name displayed a "Node:xxxxxxxx" suffix~~ — **fixed**: openNDS's `enable_serial_number_suffix` defaults to `1` (enabled) and appends a router-MAC-derived serial to `gatewayname` unless explicitly disabled. Now set to `'0'` alongside the other synced keys in all three places (`captive-portal.uc`, init.d, uci-defaults).
20. ~~Captive Portal Status page loaded very slowly~~ — **fixed**: `get_status()` was doing 4 sequential blocking subprocess round-trips (`pidof`, `ps -o etime= -C`, a full `ndsctl json` parse just to count clients, then `ndsctl status` for the raw text). Live-hardware timing (real router, not assumed) found `ndsctl json` alone costing 4-7s and `ndsctl status` 1.8-3s — daemon-side cost (`user`+`sys` time on the `ndsctl` client process was under 0.6s each call; the wall-clock time was spent waiting on the daemon), not our own fork overhead. `ndsctl status`'s text already reports `Uptime: ...` and `Current clients: N`, so `get_status()` now calls `ndsctl status` once and regex-parses both out of it, dropping the redundant `ndsctl json` round-trip entirely. Measured page load dropped from ~8-12s to ~1.7-2.4s. Also found and removed dead code along the way: `ps -o etime= -C` doesn't work at all on this router's busybox (`unrecognized option: o`) — uptime had silently always been empty; `get_uptime()`/`get_client_count()` were both deleted as they're now unused. **Gotcha for future ucode regex work**: an early version of the fix used `/Uptime: (.+)/`; a local ucode build's regex engine treats `.` as not matching newline, but the real router's ucode does match newline with a plain `.` (POSIX `regcomp` default without `REG_NEWLINE`), so the greedy `.+` swallowed the rest of the entire status text into `uptime` — only caught by testing the live ubus response, not the local interpreter build. Fixed with an explicit `[^\n]+` character class, which is unambiguous regardless of the regex engine's dot-matches-newline default. Separately observed (not fixed, out of scope, environment-level): openNDS's own startup takes ~18-30s on this router because its bundled `dnsconfig.sh` retries a dnsmasq ipset/nftset walled-garden hookup that always fails here (`dnsmasq -v` shows `no-ipset no-nftset`; fixing this would mean either `dnsmasq-full` — more flash on an already-89%-full 8MB device — or further investigation into disabling that hookup); this only affects service (re)starts, not the steady-state page-load fix above.
21. ~~Connected Clients page also loaded slowly~~ — **fixed, user-approved tradeoff**: `parse_clients_json()`'s single `ndsctl json` call was itself the bottleneck (5-8s), confirmed via head-to-head live timing against `ndsctl status` on the same daemon, same client count, repeated 5x (`ndsctl json` consistently ~5-6s vs `ndsctl status` ~1.8-3.7s — a real, reproducible 2x gap, not noise). `parse_clients_output()` now calls the new `parse_clients_from_status()`, which parses `ndsctl status`'s per-client text blocks line-by-line instead (deliberately not a multi-line regex — see the dot-matches-newline gotcha in item 20; a line-by-line scan sidesteps it entirely since no individual line ever contains an embedded `\n` for a wildcard to cross). User explicitly chose this over keeping `ndsctl json`, accepting two precision losses: `uptime` is now "time since last activity" (status has no parseable session-start epoch when Preauthenticated, only `-` or a human date string, and ucode has no date-parsing builtin) rather than true session duration; `downloaded`/`uploaded` now come from status's whole-kB fields (×1024) instead of `download_this_session`/`upload_this_session`'s exact byte counts. `parse_clients_json()` (the old json-based implementation) was deleted as dead code — it had no other callers. Measured page load dropped from ~5.5-8.5s to ~1.9-3.6s, verified live on the router (`ubus call`) and in a real browser session (correct IP/MAC/uptime/bytes/Disconnect/Block rendering).

---

## References

- <https://opennds.readthedocs.io/en/stable/index.html>
- `docs/plans/analysis/opennds-verification-findings.md` — upstream verification of `ndsctl`, BinAuth, UCI schema, and FAS behavior that this migration's design is based on
