include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Captive Portal Management
LUCI_DEPENDS:=+luci-base +nodogsplash
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=John Cyrill Corsanes <jccorsanes@protonmail.com>

include ../../luci.mk

define Package/luci-app-captive-portal/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	chmod +x /usr/lib/captive-portal/binauth.sh
	[ -f /etc/uci-defaults/80_captive-portal ] && sh /etc/uci-defaults/80_captive-portal
	/etc/init.d/rpcd restart
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
