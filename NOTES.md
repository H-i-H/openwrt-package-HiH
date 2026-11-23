# 踩坑笔记 · openwrt-package-HiH

> 从零搭建「自用 OpenWrt 软件包 feed + 签名 APK 源」全过程的问题档案。
> 每条按 **症状 → 原因 → 解法** 整理，附举一反三。遇到报错先来这里对号入座。

## 目录

- [一、编译环境与工具链](#一编译环境与工具链)
- [二、网络与下载](#二网络与下载)
- [三、内核模块与 BTF](#三内核模块与-btf)
- [四、Git 与版本管理](#四git-与版本管理)
- [五、GitHub Actions / CI](#五github-actions--ci)
- [六、签名软件源](#六签名软件源)
- [七、设备端使用](#七设备端使用)
- [八、维护纪律速查](#八维护纪律速查)

---

## 一、编译环境与工具链

### 1.1 Go 工具链代差 —— `go.mod requires go >= 1.27`

- **症状**：编 xray-core 报 `requires go >= 1.27 (running go 1.26.9; GOTOOLCHAIN=local)`。
- **原因**：上游包要求的 Go 比 SDK 自带工具链新；OpenWrt 为可复现构建禁止 Go 自动升级（`GOTOOLCHAIN=local`）。
- **解法**：给 SDK 升级默认 Go 并**显式编出工具链**：

```bash
nano feeds/packages/lang/golang/golang-values.mk   # GO_DEFAULT_VERSION:=1.26 → 1.27
rm -f staging_dir/hostpkg/stamp/.golang_installed
rm -rf build_dir/hostpkg/golang-1.27
./scripts/feeds install -f golang1.27
make package/golang1.27/compile V=s -j$(nproc)     # 十几分钟，会自动下载 go 源码
ls staging_dir/hostpkg/lib/go-1.27/bin/            # 有 go / gofmt 即成功
```

- **举一反三**：改了默认版本 ≠ 工具已就位。元包可能只盖章不产出，必须显式编译一次（见 1.2）。

### 1.2 `go: command not found` —— 房子没盖就挂了新门牌

- **症状**：1.1 改完后报 `golang-build.sh: line 107: go: command not found`（Error 127）。
- **原因**：PATH 已指向 `go-1.27/bin`，但该目录是空的——Go 1.27 本体从未被编译。
- **解法**：同 1.1 的显式编译步骤；验证标准是 `ls .../go-1.27/bin/` 有 `go`。

### 1.3 SDK 的 host 工具是"壳脚本" —— apk-bin 搬家即死

- **症状**：CI 里 `dist/apk-bin: line 5: .../lib/ld-linux-x86-64.so.2: No such file or directory`（127）。
- **原因**：SDK 的 host 工具 = 外壳脚本 + 自带动态加载器（`../lib/`），单拷可执行文件就散架。
- **解法**：不搬工具，把活儿安排在 SDK 原地干（签名挪进 build 任务），或全家一起拷（工具 + `lib/` 目录）。
- **举一反三**：任何"从 SDK 抽工具到别处用"的念头，先想这条。

### 1.4 `No rule to make target 'target/linux/prepare'` —— 无效命令

- **症状**：SDK 里执行 `make target/linux/prepare` 直接报无此目标。
- **原因**：SDK 不带完整 target 树；且**编 kmod 根本不需要它**——`make package/oaf/compile` 会自动下载内核源码、准备内核树。
- **解法**：删掉这行，直接编 kmod 包。
- **附赠**：kmod 批量打包末尾的 `Error 1 (ignored)` 是无害告警，构建系统自己声明忽略。

### 1.5 Rust 版本代差 + 源码漂移 —— honk 的双重坑

- **症状**：编 honk 报 `rustc 1.96.0 is not supported ... aya@0.16.0 requires rustc 1.98.0`。
- **原因**：两层——① 工具链代差（同 1.1 型）；② **honk/src 取的是 main 分支，比 Makefile 打包的 tag（v0.1.0-beta.6）超前**，main 的 Cargo.lock 拽进了要新工具链的 aya 0.16。
- **解法**：源码对齐打包版本，而不是去改依赖：

```bash
rm -rf honk/src
git clone --depth 1 --branch v0.1.0-beta.6 https://github.com/daeuniverse/honk honk/src
rm -rf honk/src/.git        # 必须删，否则 GitHub 箭头问题（见 4.1）
```

- **纪律**：打包 Makefile 锁版本的包，源码必须跟 tag 走，不能跟 main。`sync.sh` 已用 `HONK_TAG` 锁定；上游发新版改这一个变量。

---

## 二、网络与下载

### 2.1 `Download failed` / `Connection timed out` —— SDK 拉源码抽风

- **症状**：编译途中 `curl: (28) Connection timed out`、`404`、`No more mirrors to try`。
- **原因**：OpenWrt 源码镜像（mirror2.openwrt.org 等）从国内网络访问不稳定。
- **解法**：优先**重跑**（缓存续传，多数一次即愈）；顽固的从 `https://sources.openwrt.org/` 手动下载报错里点名的文件，丢进 `~/sdk/<平台>-sdk/dl/` 再编。
- **预防**：CI 用 `actions/cache` 的 restore/save 对（`if: always()`）缓存 `dl/`，失败也存。

### 2.2 `Operation not permitted` —— 虚拟机没有外网

- **症状**：VM 里 `apk update` 全线 `wget Failed to send request: Operation not permitted`，随后一串 `no such package`。
- **原因**：测试用"内部交换机"是封闭网段（防止 DHCP 炸真网），天然无外网；而 luci 应用的 19 个运行依赖（socat、lua、dnsmasq-full…）要从官方源下载。
- **解法**：给 VM **加第二块 NAT 网卡**（x86 的 eth1 默认即 WAN，免配置），然后 `apk update` 重装。

### 2.3 `SSL error: The connection indicated an EOF` —— 境外源被掐

- **症状**：VM/设备连 downloads.openwrt.org 时 SSL 握手被重置。
- **原因**：国内网络访问境外站点的典型现象。
- **解法**：换国内镜像（清华，备选中科大）：

```bash
sed -i 's_https\?://downloads.openwrt.org_https://mirrors.tuna.tsinghua.edu.cn/openwrt_' \
  /etc/apk/repositories.d/distfeeds.list
apk update
```

### 2.4 `SSL verify error: certificate is self-signed` —— R4S 时钟漂移

- **症状**：R4S 上所有 HTTPS 突然全线证书验证失败（github.io、downloads.openwrt.org 全挂），而同期 Arch 正常。
- **原因**：R4S 无电池时钟，**重启后时间归零**，时间不对 → 证书校验必挂。
- **解法**：`date -s "2026-11-23 21:30:00"`（按真实时间）后重试；长期确认 NTP 生效（`/etc/init.d/sysntpd restart`）。
- **举一反三**：嵌入式设备 SSL 报错，第一反应查 `date`。

---

## 三、内核模块与 BTF

### 3.1 kmod 内核版本锁定

- **症状**：`kmod-oaf` 只能装进内核恰好匹配的固件（当前 6.12.112 = 官方 25.12.6），否则 apk 拒装。
- **原因**：内核模块的 vermagic 与内核严格绑定，这是保护机制不是毛病。
- **解法**：kmod 用与固件同版本的 SDK 编译；固件升级内核后必须重编 kmod。

### 3.2 vmlinux-btf 是"特制包" —— 必须带参编译

- **症状**：依赖链自动编它时报 `vmlinux-btf: the BTF blob is missing at ''`。
- **原因**：它不"构建"任何东西，只打包现成 BTF 数据；数据靠 make 变量传入：`VMLINUX_BTF_SRC=<blob> VMLINUX_BTF_VERSION=<内核版本>`。而 honk/dae 的依赖链会拽出它，自动编译时没人传参。
- **解法**：`build.sh` 给**所有** make 统一附加这两个变量（用不到的包无感）；BTF 数据来自 daeuniverse Releases 的 `25.12.6-vmlinux-<target>-6.12.112.tar.xz`（魔数 `9feb`，ELF 是 `7f45` 需 `objcopy --dump-section .BTF=` 提取）。
- **底细**：官方内核不带内核内嵌 BTF（`/sys/kernel/btf/vmlinux` 不存在是常态），该包把数据放到 `/usr/lib/debug/boot/vmlinux`，libbpf 自动读取。

### 3.3 R4S 磁盘满 —— `No space left on device`（待办）

- **症状**：装包 65 个挂最后 1 个，`46.1 MiB in 199 packages` 后报满。
- **原因**：官方镜像写卡后 rootfs/overlay 分区固定小尺寸，卡上剩余空间未分配。
- **解法**（待执行）：`fdisk` 删分区重建（同起始扇区）+ `resize2fs`，动手前先 `df -h` + `fdisk -l` 确认布局。树莓派预计同样问题。

---

## 四、Git 与版本管理

### 4.1 文件夹带箭头、点开 404 —— 嵌套 .git

- **症状**：GitHub 上某些文件夹显示 `→`，点进去 404。
- **原因**：`cp -r 源/. 目标/` 把上游仓库的 `.git` 一起拷进来了，git 把它当"子模块指针"（gitlink）而非普通文件。
- **解法**：

```bash
git ls-files -s | awk '$1==160000 {print $4}' | while read p; do
  git rm --cached "$p"; rm -rf "$p/.git"; git add "$p"
done
```

- **预防**：`sync.sh` 内置 `rm -rf <包>/.git`；手动加包后 `find <包> -name .git` 检查。

### 4.2 `scripts/build.sh: No such file or directory`（127）—— 本地有云端无

- **症状**：CI 找不到脚本；`git status` 里躺着 `?? scripts/`。
- **原因**：建好的文件没 `git add`，只在本地存在——"互为备份"的云端那半边缺货。
- **解法**：`git status` 养成习惯；提交前问一句"该进来的都进了吗"。
- **相关**：`push` 被拒（`fetch first`）= 远端有你没有的提交（如网页端改动），`git pull --rebase origin main` 合并后重推。

### 4.3 上游同步的版本锁

- **纪律**：① passwall 的 luci 与 packages 两仓库**同日同步**（版本配套）；② honk 源码跟 `HONK_TAG`（Makefile 打包版本）不跟 main；③ `upstreams.lock` 每次同步自动记录上游 commit，回退找它。

---

## 五、GitHub Actions / CI

### 5.1 `A sequence was not expected` —— matrix 格式

- **症状**：workflow 评估 strategy 时崩溃。
- **原因**：`matrix` 需要**对象**，不能是裸数组。
- **解法**：`echo 'matrix={"include":[{"id":"x86/64"}]}'`（注意 `{"include":[...]}` 外壳）。

### 5.2 行尾注释混入 make 目标 —— `No rule to make target 'package/oaf ...'`

- **症状**：`package/oaf            # 一个目标带出两个包/compile` 这种怪目标名，exit 2。
- **原因**：`build/packages.list` 的行尾注释被当包名读走。
- **解法**：清单禁写行尾注释 + 解析时剥掉：`sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//'`。
- **教训**：本地手点包名编译测不出"整表解析"的 bug——CI 第一次整表跑就抓住了它。

### 5.3 `maximum execution time of 2h30m` —— 超时上限

- **症状**：三个 build 全被处决（`!`），ARM 尤其慢。
- **原因**：冷启动 = SDK + feeds + Go 工具链 + 内核树 + kmod 全家桶，150 分钟不够。
- **解法**：`timeout-minutes: 360`；同时缓存 `dl/` 和 SDK 压缩包加速后续。

### 5.4 缓存失败不保存

- **症状**：任务红了 → 下次依然 `Cache not found`，冷启动重来。
- **原因**：`actions/cache` 默认只在任务全绿时保存。
- **解法**：拆成 `actions/cache/restore` + `actions/cache/save`（`if: always()`），并带 `github.run_id` 防 key 冲突。

### 5.5 `Node.js 20 is deprecated` —— 永久无视

- GitHub 对官方 action 运行时的例行警告，与构建无关。

---

## 六、签名软件源

### 6.1 体系结构

- **签名对象**：只签**索引**（`packages.adb`），不签单个 .apk（与 OpenWrt 官方一致）。
- **密钥**：EC P-256（`openssl ecparam -name prime256v1 -genkey`），私钥存本地 `~/.config/hih-keys/` + GitHub Secret `OPENWRT_APK_PRIVATE_KEY` 双备，永不进 git；公钥 `hih.pem` 开放下载。
- **索引命令**：`apk mkndx --root . --keys-dir . --sign <私钥> --allow-untrusted --output packages.adb ./*.apk`（apk 工具用 SDK 自带的，原地跑）。
- **信任链**：设备 `/etc/apk/keys/` 放公钥 → 从此 `apk add` 免 `--allow-untrusted`。

### 6.2 Pages 根目录 404 是正常的

发布物是"软件源"不是网站（无 index.html）。`apk` 只访问 `<版本>/<架构>/packages.adb` 与 `hih.pem`，根目录 404 无碍；想要门面加个 index.html 即可。

---

## 七、设备端使用

### 7.1 `scp: /usr/libexec/sftp-server: not found`

- **原因**：新版 scp 默认走 SFTP，OpenWrt 精简系统没这组件。
- **解法**：`scp -O`（退回传统协议）。往任何路由器传文件都加它。

### 7.2 `$(apk --print-arch)` 架构名陷阱

- **症状**：配源后 `apk update` 报 404（`wget error 8`），URL 里是 `aarch64/packages.adb`。
- **原因**：`apk --print-arch` 返回 apk 架构名（`aarch64`），OpenWrt 包架构是 `aarch64_generic`——**x86 上两者恰好同名**（`x86_64`），到 ARM 才暴露。
- **解法**：用官方源同款写法取架构名：

```shell
. /etc/openwrt_release
echo "https://h-i-h.github.io/openwrt-package-HiH/25.12.6/${DISTRIB_ARCH}/packages.adb" \
  > /etc/apk/repositories.d/hih.list
```

### 7.3 `install: not found` —— BusyBox 没这命令

用 `mkdir -p` 替代 `install -d`；OpenWrt 上凡是桌面 Linux 习惯命令先想 BusyBox 有没有。

### 7.4 装包报依赖 `no such package`

自编的 luci 应用依赖官方源的运行库（lua、curl、dnsmasq-full…），确保 `apk update` 能连官方源（或国内镜像，见 2.3）；dnsmasq 与 dnsmasq-full 冲突时 `apk del dnsmasq` 再装。

---

## 八、维护纪律速查

| 事项 | 节奏 | 动作 |
|---|---|---|
| 同步上游 | 每月 / 固件编译前 | `bash scripts/sync.sh` → 编译测试 → commit |
| 上游自动跟踪 | 每周一凌晨 | sync.yml 自动开 PR，CI 绿了点合并 |
| 加新包 | 随时 | 本地测过 → `build/packages.list` 加一行 → push |
| 签名私钥 | 一次生成 | 本地 `~/.config/hih-keys/` + GitHub Secret 双备 |
| kmod / vmlinux-btf | 随固件内核 | 内核变了必须重编（6.12.112 ↔ 25.12.6） |
| honk 版本 | 随 Makefile | 改 `HONK_TAG` 后同步，源码必须对齐打包 tag |