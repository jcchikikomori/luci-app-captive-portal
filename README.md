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
- **UCI-native Authentication** — A local FAS (`fas_auth`) validates guest credentials directly against UCI config (no external dependencies); `binauth.sh` handles post-auth logging only
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
**nodogsplash**, and the two packages `CONFLICTS` with each other at the
opkg level — they can never both be installed. Because postinst cannot
safely force-remove a running daemon's package mid-upgrade, existing
installs must go through the following order (**confirmed on real
hardware** — `opkg remove nodogsplash` alone fails first, since the
*old* `luci-app-captive-portal` package itself still depends on it):

```bash
opkg remove luci-app-captive-portal
opkg remove nodogsplash
opkg update
opkg install luci-app-captive-portal_2.0.0-r1_all.ipk
```

Guest accounts and other settings under `/etc/config/captive-portal`
survive this (verified on real hardware) — package removal does not
actually wipe them.

## Configuration

After installation, access the LuCI web interface:

```
http://192.168.1.1/cgi-bin/luci/admin/services/captive-portal/
```

Navigate to **Settings** to configure the interface and other portal defaults.

## Firewall / Port Requirements

The captive portal login flow (splash page + `fas_auth`) is served by a
**second `uhttpd` instance on port 2080**, running on the router itself
(this is a deliberate design choice — see `CLAUDE.md`'s Key Design
Decision #5 — to avoid needing any external/remote FAS server or new
opkg package). This creates a requirement most OpenWrt captive-portal
packages don't have: **guest-network clients must be allowed to reach
port 2080 on the router, before they've authenticated.**

openNDS protects the router from pre-auth guest clients using its own
walled garden — a fixed, hardcoded list of "essential" ports (its own
built-in webserver port, DNS, DHCP, SSH, HTTPS) enforced in a *separate,
legacy `ip` family nftables table it manages directly* (`nds_filter`),
independently of and evaluated *before* OpenWrt's normal `firewall`
(fw4) configuration. Port 2080 is not on that built-in list, so without
an explicit exception, guest devices get `net::ERR_CONNECTION_REFUSED`
trying to load the splash page — even though the LAN/admin network can
reach it just fine (different firewall zone).

The fix — adding port 2080 to openNDS's own `users_to_router` option —
is applied automatically by `80_captive-portal`'s uci-defaults script:

```
uci show opennds | grep users_to_router
# opennds.@opennds[0].users_to_router='allow tcp port 2080'
```

If guest devices still can't reach the splash page after installing,
confirm this UCI value is present and that `opennds` has been restarted
since it was set (`/etc/init.d/opennds restart`); on affected devices
you can inspect openNDS's own compiled ruleset directly with
`nft list table ip nds_filter` and look for a `dport 2080 accept` rule
in the `ndsRTR` chain.

## License

Apache 2.0 — See [LICENSE](LICENSE) for details.

## Companion Projects

- [MyAdminCaptiva](https://github.com/jcchikikomori/MyAdminCaptiva) — Next.js admin console with same feature set
- [nodogsplash-mod](https://github.com/jcchikikomori/nodogsplash-mod) — Splash page design inspiration (GPL-2.0)
