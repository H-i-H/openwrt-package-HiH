# openwrt-package-HiH

自用 OpenWrt 软件包 feed，本地测试通过后上传，供固件编译使用。

## 使用方法

feeds.conf.default 里添加：
    src-git HiH https://github.com/H-i-H/openwrt-package-HiH.git

## 包来源对照

| 包 | 上游 |
|---|---|
| luci-theme-7dollar | itsmaiGe/luci-theme-7dollar |
| luci-app-socat | chenmozhijin/luci-app-socat |
| quickfile, luci-app-quickfile | sbwml/luci-app-quickfile |
| oaf, open-app-filter, luci-app-oaf | destan19/OpenAppFilter |
| luci-app-passwall + xray-core/sing-box 等依赖 | Openwrt-Passwall/openwrt-passwall(-packages) |
| honk, luci-app-honk, luci-lib-daeuniverse, vmlinux-btf 等 | daeuniverse/openwrt-packages + daeuniverse/honk |
| dae, luci-app-dae, smartdns | 上游附带，备用 |

## 注意事项

- honk 仅支持 64 位，需内核较新的固件（25.12 系）并依赖 vmlinux-btf
- oaf 含内核模块 kmod，需与固件内核版本一致
- passwall 的 luci 与依赖包需同步更新
