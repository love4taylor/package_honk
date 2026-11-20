#
# OpenWrt package: honk (https://github.com/love4taylor/honk/tree/nw)
#
# Based on daeuniverse/openwrt-packages/honk at
# 8c6ed9bd00a99d7662cfd5bf15fb4eed393ce689.
#
# OpenWrt downloads and verifies the pinned nw branch snapshot below; no local
# src checkout is required. Update the revision, date and SHA-256 together.
#
# build.sh builds the patched doona UI pinned in .github/ci/pins.env and the eBPF
# object with the nightly pinned in crates/honk-ebpf/rust-toolchain.toml, compiles
# honk-core with the crate's own pinned stable toolchain, and uses the OpenWrt
# cross gcc/g++ of the SDK (TARGET_CROSS) for BoringSSL, SQLite and the final
# link. Cargo fetches dependencies locked in Cargo.lock. HONK_BUILD_VERSION
# identifies the nw snapshot in the binary, including its full source revision.
#
# The binary is built with the full feature set: the crate defaults
# (clash-api, jemalloc, rprx) plus ebpf and native-ui. native-ui embeds the
# pinned doona dashboard at build time and implies native-api.
#
# The package also installs an OpenWrt procd init script (files/honk.init), its
# UCI configuration (files/honk.config) and a minimal /etc/honk/config.dae with
# the embedded UI enabled on the LAN. The service does not start at boot by
# default: after adding nodes and routing rules, set the UCI option
# honk.config.enabled to 1 and start it. files/honk.uci-defaults sets that
# option, keeping the boot setting of earlier versions (the option, or the
# rc.d link of the versions that used it).
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

# $(CURDIR) points at the buildroot root, and $(MAKEFILE_LIST) grows with every
# included file, so the package directory has to be resolved before the first
# include. abspath keeps it valid when a recipe runs from another directory.
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_SOURCE_DATE:=2026-11-20
PKG_SOURCE_VERSION:=817bdf28b814fbcab7a947bc30826d2d46652f08
PKG_VERSION:=0.1.0_beta6_p$(subst -,,$(PKG_SOURCE_DATE))
PKG_RELEASE:=1

PKG_SOURCE_SUBDIR:=honk-$(PKG_SOURCE_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/love4taylor/honk/tar.gz/$(PKG_SOURCE_VERSION)?
PKG_HASH:=b4a9184f7cba2be0c2f40196845ab4989ba1937d34474006656d5fb98df426bc

# Keep this revision aligned with DOONA_REVISION in Honk's .github/ci/pins.env.
DOONA_REVISION:=4c1f6f3fc1523558d595c363ba677494844030e3
DOONA_SOURCE:=doona-$(DOONA_REVISION).tar.gz

# build.rs accepts its version label through GITHUB_REF. This identifies a
# branch snapshot; it does not assert that the repository contains such a tag.
HONK_BUILD_VERSION:=v0.1.0-beta.6-nw-$(PKG_SOURCE_VERSION)

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

include $(INCLUDE_DIR)/package.mk

define Download/doona
  FILE:=$(DOONA_SOURCE)
  URL:=https://codeload.github.com/Zakkaus/doona/tar.gz/$(DOONA_REVISION)?
  HASH:=2c6783763919c1d30c0a49b058a9baf9d1e58cc2f94af864d87b5a2a27f5fce7
endef

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine (honk-core) with embedded UI
  URL:=https://github.com/love4taylor/honk/tree/nw
  LICENSE:=GPL-3.0-only
  # honk-core is linked against the musl and the C++ runtime of OpenWrt. Its
  # eBPF datapath needs TC-bpf and a veth pair plus the daens namespace, and
  # its NFQUEUE staging uses nftables queue expressions over nfnetlink_queue.
  # Its BTF comes from vmlinux-btf, as for dae. The geo packages ship the dat
  # files; this package links them into /usr/share/honk, which honk searches
  # before the dae locations.
  DEPENDS:=+libstdcpp +kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +vmlinux-btf +v2ray-geoip +v2ray-geosite
endef

define Package/honk/description
 honk is an eBPF transparent proxy engine. honk-core embeds its eBPF object and
 needs kernel BTF for CO-RE relocations, which vmlinux-btf provides. This
 build enables the Clash API, the native API and the embedded doona dashboard
 (native-ui), which is served at /ui on the native API listener. Sources are
 pinned to the love4taylor/honk nw branch with NW3 outbound support.
endef

define Build/Compile
	HONK_SRC="$(PKG_BUILD_DIR)" \
	HONK_VERSION="$(PKG_VERSION)" \
	HONK_BUILD_VERSION="$(HONK_BUILD_VERSION)" \
	HONK_ARCH_PACKAGES="$(ARCH_PACKAGES)" \
	HONK_DOONA_SOURCE="$(DL_DIR)/$(DOONA_SOURCE)" \
	OPENWRT_CC="$(TARGET_CROSS)gcc" \
	OPENWRT_CXX="$(TARGET_CROSS)g++" \
	sh "$(PKG_DIR)/build.sh"
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

# apk replaces a conffile the user never edited with the packaged one, which
# has no option enabled, so the boot setting is saved here for
# files/honk.uci-defaults. The apk pre-install and pre-upgrade scripts are
# made from this (pre-upgrade without the shebang line, after PKG_UPGRADE=1).
define Package/honk/preinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT}" ] || exit 0
enabled="$$(uci -q get honk.config.enabled)"
[ -z "$$enabled" ] || echo "$$enabled" > /tmp/honk-autostart
exit 0
endef

# With apk this runs after default_postinst, in post-install and, sourced, in
# post-upgrade, after uci-defaults has set option enabled. The restart picks
# up a new binary of an enabled service; the init script's package guard keeps
# default_postinst from starting a disabled one.
define Package/honk/postinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT}" ] || exit 0
case "$$(uci -q get honk.config.enabled)" in
1|on|true|yes|enabled) /etc/init.d/honk restart ;;
esac
exit 0
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.uci-defaults $(1)/etc/uci-defaults/90-honk-autostart
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	printf '%s\n' '/etc/honk/data/' > $(1)/lib/upgrade/keep.d/honk
	# v2ray-geoip/geosite install the files under /usr/share/v2ray. honk's
	# find_dat looks in /usr/share/honk before /usr/share/dae.
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))
$(eval $(call Download,doona))
