# luci-app-captive-portal

Captive Portal Management Console for OpenWrt.

LuCI web interface for managing captive portal authentication, supporting both **nodogsplash** and **openNDS** daemons.

## Features

- **Dashboard** — Service status, daemon type, connected clients, uptime
- **Guest Accounts** — CRUD management with username/password, MAC binding, bandwidth limits, session timeout
- **Settings** — Daemon selector, interface, auth method, portal configuration
- **Connected Clients** — Live session table with disconnect/block actions
- **Blacklist** — Manage blocked MAC addresses; add manually or block directly from Connected Clients
- **Blocked Page** — Dedicated splash page informing users when their device has been blacklisted
- **BinAuth Integration** — Authentication hook reading directly from UCI config (no external dependencies)
- **Custom Splash Page** — Mobile-first responsive login page with terms & conditions

### Recent improvements

- Bandwidth limits are displayed and entered in **Mbps**.
- Account passwords are masked by default with a **reveal toggle**.
- Password fields follow **WCAG 2+** best practices and are password-manager friendly (`autocomplete="new-password"`, proper labels, ARIA attributes).

## Requirements

- OpenWrt with LuCI installed
- nodogsplash or openNDS package

## Installation

### From source

```bash
# Copy files to your OpenWrt device
scp -r root/* root@192.168.1.1:/
scp -r htdocs/* root@192.168.1.1:/www/

# Run UCI defaults to create initial config
ssh root@192.168.1.1 "sh /etc/uci-defaults/80_captive-portal"
```

### From packages

```bash
opkg update
opkg install luci-app-captive-portal
```

## Configuration

After installation, access the LuCI web interface:

```
http://192.168.1.1/cgi-bin/luci/admin/services/captive-portal/
```

Navigate to **Settings** to configure the daemon and interface.

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

## Companion Projects

- [MyAdminCaptiva](https://github.com/jcchikikomori/MyAdminCaptiva) — Next.js admin console with same feature set
- [nodogsplash-mod](https://github.com/jcchikikomori/nodogsplash-mod) — Splash page design inspiration (GPL-2.0)
