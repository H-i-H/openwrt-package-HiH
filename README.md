<div align="center">

# openwrt-package-HiH

**自用 OpenWrt 25.12 软件包源 —— 签名 APK 仓库 + 编译 Feed 双模**

[![Stars](https://img.shields.io/github/stars/H-i-H/openwrt-package-HiH?style=flat-square&color=yellow&label=Stars)](https://github.com/H-i-H/openwrt-package-HiH/stargazers)
[![Last Commit](https://img.shields.io/github/last-commit/H-i-H/openwrt-package-HiH?style=flat-square)](https://github.com/H-i-H/openwrt-package-HiH/commits)
[![Repo Size](https://img.shields.io/github/repo-size/H-i-H/openwrt-package-HiH?style=flat-square)](https://github.com/H-i-H/openwrt-package-HiH)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-25.12.x-0078d4?style=flat-square)](https://openwrt.org)
[![CI](https://img.shields.io/github/actions/workflow/status/H-i-H/openwrt-package-HiH/build.yml?style=flat-square&label=build&logo=github)](https://github.com/H-i-H/openwrt-package-HiH/actions)

一个仓库，两种用法：**设备直装**（签名源，`apk add` 即装）与 **编译集成**（`src-git` 一行接入固件）。

</div>

---

## 简介

收集并维护一批自用 OpenWrt 软件包，提供：

- **签名 APK 软件源**：GitHub Pages 托管，EC 公钥验签，设备上免 `--allow-untrusted` 直装；
- **编译 Feed**：标准 OpenWrt 软件源布局，编固件时一行 `src-git` 接入；
- **自动化**：每周上游同步 PR + CI 三平台（x86_64 / R4S / 树莓派 4）编译签名发布；
- **可复现**：本地脚本与 CI 共用同一套构建逻辑，全量踩坑记录见 [NOTES.md](NOTES.md)。

## 快速开始

### 用法 A · 设备直装（签名源）

在路由器上执行一次（**OpenWrt 25.12.x**）：

```shell
mkdir -p /etc/apk/keys /etc/apk/repositories.d
wget -O /etc/apk/keys/hih.pem https://h-i-h.github.io/openwrt-package-HiH/hih.pem
. /etc/openwrt_release
echo "https://h-i-h.github.io/openwrt-package-HiH/25.12.6/${DISTRIB_ARCH}/packages.adb" \
  > /etc/apk/repositories.d/hih.list
apk update
```

之后即装即用：

```shell
apk add luci-theme-7dollar luci-app-socat quickfile luci-app-quickfile
```

> 架构名务必用 `${DISTRIB_ARCH}`，不要用 `$(apk --print-arch)`（两者不同，详见 [NOTES 7.2](NOTES.md)）。中国大陆网络若 `apk update` 报 SSL 超时，将官方源换为国内镜像（见 [NOTES 2.3](NOTES.md)）。

### 用法 B · 编译固件时作为 Feed

在固件源码根目录**一键添加**（自动去重，重复执行不会写入两遍）：

```bash
grep -q 'openwrt-package-HiH' feeds.conf.default || \
  echo "src-git HiH https://github.com/H-i-H/openwrt-package-HiH.git" >> feeds.conf.default
```

或手动在 `feeds.conf.default` 末尾追加一行：

```text
src-git HiH https://github.com/H-i-H/openwrt-package-HiH.git
```

然后：

```bash
./scripts/feeds update -a
./scripts/feeds install -a -p HiH
make menuconfig    # LuCI → Applications / Themes 中勾选所需包
```

### 二次打包 / 自建签名源

仓库自带完整工具链脚本，可复刻本仓库的签名发布流程：

```bash
bash scripts/build.sh <target>              # 按 build/packages.list 编译（本地/CI 同款）
APK_SIGN_KEY=<私钥> bash scripts/repo.sh    # 签名并组装软件源（repo/ 目录）
```

## 软件包清单

| 包 | 说明 | 来源 |
|---|---|---|
| luci-theme-7dollar | LuCI 主题 | [itsmaiGe/luci-theme-7dollar](https://github.com/itsmaiGe/luci-theme-7dollar) |
| luci-app-socat | 端口转发管理（firewall4 兼容） | [chenmozhijin/luci-app-socat](https://github.com/chenmozhijin/luci-app-socat) |
| quickfile / luci-app-quickfile | 文件管理器（主程序 + Web 界面） | [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile) |
| oaf / open-app-filter / luci-app-oaf | 应用过滤（含 kmod-oaf 内核模块） | [destan19/OpenAppFilter](https://github.com/destan19/OpenAppFilter) |
| luci-app-passwall | 代理前端 | [Openwrt-Passwall/openwrt-passwall](https://github.com/Openwrt-Passwall/openwrt-passwall) |
| xray-core 等 17 个依赖包 | passwall 运行依赖（sing-box、hysteria、chinadns-ng…） | [Openwrt-Passwall/openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages) |
| honk / luci-app-honk / luci-lib-daeuniverse | eBPF 透明代理引擎 + Doona 面板（仅 64 位） | [daeuniverse/openwrt-packages](https://github.com/daeuniverse/openwrt-packages) |
| vmlinux-btf | 内核 BTF 数据（honk / dae 运行依赖） | 数据取自 [daeuniverse releases](https://github.com/daeuniverse/openwrt-packages/releases)，本仓库打包 |
| dae / luci-app-dae / smartdns | 备用（上游附带） | [daeuniverse/openwrt-packages](https://github.com/daeuniverse/openwrt-packages) |

> vmlinux-btf 与 vmlinux-btf-builtin 互斥、按内核二选一：官方内核（无内嵌 BTF）用 vmlinux-btf，内核自带 BTF 的固件（如 ImmortalWrt）用 vmlinux-btf-builtin。

## 支持的目标平台

| 设备 | SDK target | 包架构 | 验证状态 |
|---|---|---|---|
| x86_64 软路由 / 虚拟机 | `x86/64` | `x86_64` | 编译 + 虚拟机实测 |
| NanoPi R4S | `rockchip/armv8` | `aarch64_generic` | 编译 + 真机实测 |
| 树莓派 4 | `bcm27xx/bcm2711` | `aarch64_cortex-a72` | 云端编译 |

## 版本要求

| 项目 | 要求 |
|---|---|
| 固件 | OpenWrt / ImmortalWrt **25.12.x**（apk 包管理；24.10 及以前为 ipk，不适用） |
| 内核 | kmod-oaf、vmlinux-btf 锁定 **6.12.112**（官方 25.12.6）；换内核需重编 |
| honk | 仅 64 位；需 25.12 系内核 + BTF；kmod-veth、kmod-sched-bpf 等依赖安装时自动拉取 |

> honk 装好后，Doona 面板默认监听 `http://<路由器IP>:9527`，首次打开按提示创建用户。

## 仓库结构

```text
├── build/packages.list        # 晋级清单：本地测过的包才进 CI 发布
├── scripts/
│   ├── sync.sh                # 上游同步（honk 版本锁 HONK_TAG）
│   ├── build.sh               # 统一编译脚本（本地与 CI 共用）
│   └── repo.sh                # 签名 + 组装 APK 软件源
├── .github/workflows/
│   ├── build.yml              # 编译·签名·发布（PR 单平台验证 / main 三平台发布）
│   └── sync.yml               # 每周上游同步 → 自动开 PR
├── hih.pem                    # 软件源签名公钥
├── NOTES.md                   # 全量踩坑笔记（症状→原因→解法）
└── <各软件包目录>              # 标准 OpenWrt feed 布局
```

## 维护

- **上游更新**：每周一凌晨自动同步并开 PR，CI 验证绿后合并即自动发布；也可手动 `bash scripts/sync.sh`；
- **加新包**：本地编译 + 真机验收通过 → 在 `build/packages.list` 加一行 → push；
- **排错**：一切报错先查 [NOTES.md](NOTES.md)。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=H-i-H/openwrt-package-HiH&type=Date)](https://star-history.com/#H-i-H/openwrt-package-HiH&Date)

## 致谢

[itsmaiGe](https://github.com/itsmaiGe) · [chenmozhijin](https://github.com/chenmozhijin) · [sbwml](https://github.com/sbwml) · [destan19](https://github.com/destan19) · [Openwrt-Passwall](https://github.com/Openwrt-Passwall) · [daeuniverse](https://github.com/daeuniverse) · [QiuSimons](https://github.com/QiuSimons) 及 OpenWrt 官方项目。

## License

各软件包遵循其上游许可证（多为 GPL-3.0）；仓库脚本与文档随仓库同权。