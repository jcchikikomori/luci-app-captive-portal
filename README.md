# luci-app-captive-portal

Captive Portal Management Console for OpenWrt.

LuCI web interface for managing captive portal authentication, built on the **openNDS** daemon.

## Features

- **Dashboard** — Service status, daemon type, connected clients, uptime
- **Guest Accounts** — CRUD management with username/password, MAC binding, bandwidth limits, session timeout
- **Settings** — Interface, auth method, portal configuration
- **Connected Clients** — Live session table with disconnect/block actions
- **Blacklist** — Manage blocked MAC addresses; add manually or block directly from Connected Clients
- **Blocked Splash Message** — Splash page hides the login form and shows a blocked message for blacklisted devices
- **BinAuth Integration** — Authentication hook reading directly from UCI config (no external dependencies)
- **Custom Splash Page** — Mobile-first responsive login page with terms & conditions

### Recent improvements

- Bandwidth limits are displayed and entered in **Mbps**.
- Account passwords are masked by default with a **reveal toggle**.
- Password fields follow **WCAG 2+** best practices and are password-manager friendly (`autocomplete="new-password"`, proper labels, ARIA attributes).

## Requirements

- OpenWrt with LuCI installed
- opennds package

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

## Upgrading from nodogsplash

Starting with version 2.0.0, this package depends on **opennds** instead of
**nodogsplash**. Because postinst cannot safely force-remove a running
daemon's package mid-upgrade, existing installs must remove `nodogsplash`
manually before upgrading:

```bash
opkg remove nodogsplash
opkg update
opkg upgrade luci-app-captive-portal
```

## Configuration

After installation, access the LuCI web interface:

```
http://192.168.1.1/cgi-bin/luci/admin/services/captive-portal/
```

Navigate to **Settings** to configure the interface and other portal defaults.

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

## Companion Projects

- [MyAdminCaptiva](https://github.com/jcchikikomori/MyAdminCaptiva) — Next.js admin console with same feature set
- [nodogsplash-mod](https://github.com/jcchikikomori/nodogsplash-mod) — Splash page design inspiration (GPL-2.0)
