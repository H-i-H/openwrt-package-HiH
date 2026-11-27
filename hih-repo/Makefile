include $(TOPDIR)/rules.mk

PKG_NAME:=hih-repo
PKG_VERSION:=25.12.6
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=H-i-H

include $(INCLUDE_DIR)/package.mk

define Package/hih-repo
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=HiH 签名软件源配置（公钥+源地址）
  PKGARCH:=all
endef

define Package/hih-repo/description
 首次启动写入 HiH 软件源的正确地址与签名公钥，
 并清理构建时自动生成的错误地址。编进固件即开箱可用。
endef

define Package/hih-repo/install
$(INSTALL_DIR) $(1)/etc/apk/keys
$(INSTALL_DATA) ./files/hih.pem $(1)/etc/apk/keys/
$(INSTALL_DIR) $(1)/etc/uci-defaults
$(INSTALL_BIN) ./files/96-hih-repo $(1)/etc/uci-defaults/
sed -i 's|@RELEASE@|$(PKG_VERSION)|' $(1)/etc/uci-defaults/96-hih-repo
endef

$(eval $(call BuildPackage,hih-repo))
