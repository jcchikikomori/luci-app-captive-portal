#!/bin/bash
# Build script for luci-app-captive-portal
# Produces an ipk package using the official OpenWrt SDK Docker container.
#
# Environment variables:
#   TARGET    OpenWrt target/subtarget (default: ramips/mt7621)
#   VERSION   OpenWrt version (default: 24.10.2)
#   CONTAINER Override the SDK image (default: openwrt/sdk:<target>-<version>)
#   SKIP_DOCKER_PULL  If non-empty, skip "docker pull" (useful in CI with image caches)

set -euo pipefail

TARGET="${TARGET:-ramips/mt7621}"
VERSION="${VERSION:-24.10.2}"
PKG_NAME="${PKG_NAME:-luci-app-captive-portal}"
SDK_IMAGE="${CONTAINER:-openwrt/sdk:${TARGET//\//-}-${VERSION}}"

echo "=== Building ${PKG_NAME} for OpenWrt ${VERSION} (${TARGET}) ==="
echo "SDK image: ${SDK_IMAGE}"

if [ -z "${SKIP_DOCKER_PULL:-}" ]; then
	echo "Pulling SDK image..."
	docker pull "${SDK_IMAGE}"
fi

docker run --rm --user root \
	-v "$PWD:/workspace" \
	-w /builder \
	"${SDK_IMAGE}" \
	bash -c "
		set -euo pipefail

		# Snapshot-based SDK images ship a setup script instead of the SDK;
		# release images already have the SDK extracted, so this is a no-op.
		[ ! -d ./scripts ] && ./setup.sh

		echo 'Updating feeds...'
		./scripts/feeds update -a
		./scripts/feeds install -a

		# Make luci.mk reachable from package/${PKG_NAME}/Makefile
		ln -sf feeds/luci/luci.mk luci.mk

		echo 'Generating default config...'
		make defconfig

		echo 'Copying package into SDK...'
		rm -rf package/${PKG_NAME}
		mkdir -p package/${PKG_NAME}
		tar -C /workspace \
			--exclude=.git \
			--exclude=.github \
			--exclude=build.sh \
			--exclude=deploy.sh \
			-cf - . | tar -C package/${PKG_NAME} -xf -

		echo 'Building package...'
		make package/${PKG_NAME}/compile V=s -j\$(nproc)

		echo 'Exporting ipk...'
		mkdir -p /workspace/dist
		find bin/packages -name '${PKG_NAME}*.ipk' -exec cp {} /workspace/dist/ \;
	"

IPK_PATH=$(find dist/ -name "${PKG_NAME}*.ipk" -type f 2>/dev/null | head -n1)

if [ -n "${IPK_PATH}" ]; then
	echo ""
	echo "=== Build Complete ==="
	echo "Package built successfully!"
	echo "IPK location: ${IPK_PATH}"
	echo ""
	echo "To install on your device:"
	echo "  1. Copy the ipk to your router:"
	echo "     scp ${IPK_PATH} root@192.168.1.1:/tmp/"
	echo ""
	echo "  2. Install on the router:"
	echo "     ssh root@192.168.1.1 'opkg install /tmp/${PKG_NAME}*.ipk'"
	echo ""
	echo "  3. Access LuCI at: http://192.168.1.1/cgi-bin/luci/admin/services/captive-portal/"
else
	echo "ERROR: Package not found in dist/"
	exit 1
fi
