include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-captive-portal
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI Captive Portal Management
LUCI_DEPENDS:=+nodogsplash +kmod-sched-core +kmod-ifb +tc
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=John Cyrill Corsanes <jccorsanes@protonmail.com>

include ../../luci.mk

# We have no Lua sources and no .po translations, so the host-only
# build dependencies pulled in by luci.mk (gettext, csstidy, etc.) are
# not needed for this package.
PKG_BUILD_DEPENDS:=

define Package/luci-app-captive-portal/postinst
#!/bin/sh
if [ -z "${IPKG_INSTROOT}" ]; then
	chmod +x /usr/lib/captive-portal/binauth.sh
	chmod +x /usr/lib/captive-portal/sync-blocked-json.sh
	chmod +x /usr/lib/captive-portal/tc-helper.sh
	[ -f /etc/uci-defaults/80_captive-portal ] && sh /etc/uci-defaults/80_captive-portal
	[ -x /usr/lib/captive-portal/sync-blocked-json.sh ] && /usr/lib/captive-portal/sync-blocked-json.sh
	/etc/init.d/rpcd stop
	sleep 2
	/etc/init.d/rpcd start
	/etc/init.d/uhttpd restart
fi
exit 0
endef

define Package/luci-app-captive-portal/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	uci delete captive-portal 2>/dev/null
	uci commit captive-portal 2>/dev/null
	/etc/init.d/rpcd restart
fi
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
