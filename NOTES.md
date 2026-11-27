# 踩坑笔记

这份笔记记录了搭建「自用 OpenWrt 软件包 feed + 签名 APK 源」一路踩过的坑。每个坑都按同一个思路整理：先看现象，再找原因，最后给解法。以后遇到报错，先来这里对号入座，能省下大量排查时间。

## 目录

- [一、编译环境与工具链](#一编译环境与工具链)
- [二、网络与下载](#二网络与下载)
- [三、内核模块与 BTF](#三内核模块与-btf)
- [四、Git 与版本管理](#四git-与版本管理)
- [五、GitHub Actions / CI](#五github-actions--ci)
- [六、签名软件源](#六签名软件源)
- [七、设备端使用](#七设备端使用)
- [八、维护纪律速查](#八维护纪律速查)
- [九、honk 补遗](#九honk-补遗)

---

## 一、编译环境与工具链

### 1.1 Go 版本代差：上游要新工具，SDK 只有旧工具

编 xray-core 时会遇到这样的报错：`go.mod requires go >= 1.27 (running go 1.26.9; GOTOOLCHAIN=local)`。意思很直白——新版本的 xray-core 是用 Go 1.27 写的，而 SDK 自带的 Go 只有 1.26.9。更麻烦的是 OpenWrt 故意禁止 Go 自己联网升级（就是报错末尾那个 `GOTOOLCHAIN=local`），因为构建要可复现。所以得我们自己把 SDK 的默认 Go 抬上去：

```bash
nano feeds/packages/lang/golang/golang-values.mk   # 把 GO_DEFAULT_VERSION:=1.26 改成 1.27
rm -f staging_dir/hostpkg/stamp/.golang_installed
rm -rf build_dir/hostpkg/golang-1.27
./scripts/feeds install -f golang1.27
make package/golang1.27/compile V=s -j$(nproc)     # 编译 Go 本体，十几分钟
ls staging_dir/hostpkg/lib/go-1.27/bin/            # 有 go 和 gofmt 就成了
```

有一点要特别注意：**改了默认版本号，不等于新工具已经就位**。构建系统的元包可能只盖了个"已安装"的章，实际什么都没编。所以上面必须有那条显式的 `make package/golang1.27/compile`——不跑它就会掉进下一节的坑。

### 1.2 `go: command not found`：门牌换了，房子没盖

改完默认版本后如果报 `golang-build.sh: line 107: go: command not found`（错误码 127），原因就是上一节说的那件事：编译脚本已经去 `go-1.27/bin` 找 Go 了，但那个目录是空的——Go 1.27 的本体从头到尾没被编译过。按 1.1 把显式编译跑一遍即可，判断标准不变：`ls .../go-1.27/bin/` 里能看到 `go`。

### 1.3 SDK 里的工具是"壳脚本"，搬不走

CI 上出过这么个错：`dist/apk-bin: line 5: .../lib/ld-linux-x86-64.so.2: No such file or directory`。注意报错提到了 `line 5`——说明这个"可执行文件"其实是个脚本。SDK 为了让 host 工具在各种发行版上都能跑，把它们做成了"外壳脚本 + 自带动态加载器"的组合，加载器在旁边的 `lib/` 目录里。只把外壳拷走，它回头找不到自家的加载器就当场去世。

所以要么把全家（工具加 `lib/` 目录）一起搬，要么干脆别搬——让活儿在 SDK 原地干。我们的签名流程选了后者。以后凡是想"从 SDK 抽个工具拿去别处用"，先想起这条。

### 1.4 `make target/linux/prepare` 是条无效命令

SDK 里根本没有这个目标（`No rule to make target`），而且编内核模块也**不需要**它——`make package/oaf/compile` 自己会下载内核源码、把内核树准备好。这条命令是多余的，直接删掉就好。

顺带认识一个无害的告警：kmod 批量打包收尾时会出现 `Error 1 (ignored)`，构建系统自己都说忽略了，不用理会。

### 1.5 honk 的 Rust 代差，详见第九章

这个问题说来话长，从诊断思路到解法都在[第九章](#九honk-战役补遗)完整记录了。其中最值得记住的教训：**判断"源码版本漂移"之前，先去核对 tag 自己的 Cargo.toml**——我们曾想当然地把正版 beta.6 的依赖当成污染，绕了一圈弯路。

---

## 二、网络与下载

### 2.1 `Download failed`：源码下载抽风

编译中途报 `Connection timed out`、`404` 或 `No more mirrors to try`，多半是 OpenWrt 的源码镜像（mirror2.openwrt.org 之类）在当前网络下不稳定。处理起来很简单：**先重跑**，缓存会续传，大多数一次就过。要是某个文件反复失败，就去 `https://sources.openwrt.org/` 手动下载报错里点名的那个文件，丢进 `~/sdk/<平台>-sdk/dl/` 再编——这个目录是下载缓存，里面有的文件构建系统不会再联网。

CI 侧也做了同样的预防：用 `actions/cache` 的 restore/save 组合缓存 `dl/` 目录，注意 save 那步要带 `if: always()`，**失败也存**，不然下次还是冷启动。

### 2.2 `Operation not permitted`：虚拟机没接外网

虚拟机里 `apk update` 全线报 `Failed to send request: Operation not permitted`，紧接着一串 `no such package`。这不是包的问题——我们测试用的"内部交换机"是个封闭网段（防止路由器的 DHCP 砸了真实网络），天然不通互联网，而 luci 应用的十几个运行依赖（socat、lua、dnsmasq-full……）本来就要从官方源下载。

给虚拟机**加第二块网卡、接 NAT** 就好。x86 镜像里 eth1 默认就是 WAN 口，插上自动拿 IP，什么都不用配。

### 2.3 `SSL error: The connection indicated an EOF`：境外站点被掐

连接 downloads.openwrt.org 时 SSL 握手被中途重置，是国内网络访问境外站点的老毛病。换清华镜像基本药到病除：

```bash
sed -i 's_https\?://downloads.openwrt.org_https://mirrors.tuna.tsinghua.edu.cn/openwrt_' \
  /etc/apk/repositories.d/distfeeds.list
apk update
```

清华不通就换中科大（`mirrors.ustc.edu.cn/openwrt`）。这招在真机上同样好使。

### 2.4 `SSL verify error: certificate is self-signed`：先查时间再查网络

R4S 上所有 HTTPS 突然集体证书验证失败，连 github.io 和 downloads.openwrt.org 都挂，而同一网络的电脑一切正常——这个组合拳是**时钟漂移**的典型指纹。R4S 没有电池供电的时钟，每次重启时间归零，时间不对，证书链自然对不上。

```bash
date -s "2026-11-23 21:30:00"    # 按手机上的真实时间填
```

改完时间基本就恢复了，长期靠 NTP（`/etc/init.d/sysntpd restart`）保持。以后嵌入式设备报 SSL 错，第一个动作永远是敲 `date`。

---

## 三、内核模块与 BTF

### 3.1 kmod 认内核，不认别的

`kmod-oaf` 这类内核模块和内核版本是锁死的——当前的模块对应 6.12.112（官方 25.12.6），装到别的内核上 apk 会直接拒装。这是保护机制：内核结构一变，硬塞进去的模块轻则失效重则崩溃。规则就两条：kmod 用和固件同版本的 SDK 编；固件换了内核，kmod 必须重编。

### 3.2 vmlinux-btf：不"编译"，只"打包"，且必须带参

依赖链自动编译 vmlinux-btf 时会报 `the BTF blob is missing at ''`。这个包有点特别——它不构建任何东西，只是把现成的 BTF 数据（eBPF 的"结构体地图"）打包成 .apk。数据从哪来？靠 make 变量传进来：

```bash
make package/vmlinux-btf/compile V=s \
  VMLINUX_BTF_SRC=<BTF文件路径> VMLINUX_BTF_VERSION=<内核版本>
```

麻烦在于 honk、dae 的依赖链会把它拽出来自动编译，而自动编译没人传参。好在有个省心的机制：**make 命令行上的变量会传给整条依赖链**，所以 `build.sh` 给所有 make 统一挂上这两个变量，需要的包自然收到，不需要的毫无感知。

BTF 数据来自 daeuniverse Releases 的 `25.12.6-vmlinux-<target>-6.12.112.tar.xz`，解出来看文件头魔数：`9feb` 就是裸 BTF，直接用；`7f45` 则是 ELF 格式，要先 `objcopy --dump-section .BTF=输出文件` 把 BTF 段抠出来。

背景补充：官方内核不带内嵌 BTF（`/sys/kernel/btf/vmlinux` 不存在是常态），这个包的作用就是把数据放到 `/usr/lib/debug/boot/vmlinux`，libbpf 会自动去那里找，效果等同内核自带。

### 3.3 装包报 `No space left on device`：分区没跟着磁盘走

官方镜像写进 TF 卡（或虚拟盘）后，rootfs/overlay 分区是固定的小尺寸，卡上剩下的空间处于"未分配"状态——8GB 的卡，系统能用的可能只有一两百兆。装几个包就满，很正常。

想扩容得动分区表（fdisk 重建同起始扇区的大分区 + resize2fs），这里有个关键认知：**`qemu-img resize` 只把虚拟磁盘的外壳撑大，分区表不会跟着长**。所以虚拟机测试想扩容，得在开机前或者手动手术。这条目前还是待办，计划在测试虚拟机上先练手，再应用到 R4S 和树莓派。

---

## 四、Git 与版本管理

### 4.1 文件夹带箭头、点开 404：仓库里套了仓库

GitHub 上某些文件夹显示成箭头，点进去 404——这是把上游的 `.git` 目录一起拷进来了（`cp -r 源/. 目标/` 这种拷法会带上隐藏文件）。Git 遇到内嵌的 `.git` 不会把内容当普通文件收录，而是记成一个指向别处的"指针"，于是就显示成链接、点开是空的。

清理办法：

```bash
git ls-files -s | awk '$1==160000 {print $4}' | while read p; do
  git rm --cached "$p"; rm -rf "$p/.git"; git add "$p"
done
```

预防更简单：拷完包随手 `find <包目录> -name .git` 查一下，有就删。我们的 `sync.sh` 里已经内置了这个清理动作。

### 4.2 `No such file or directory`（127）：本地有，云端没有

CI 报找不到 `scripts/build.sh`，本地 `git status` 里却躺着一个 `?? scripts/`——真相是文件建好了但忘了 `git add`，只存在于本地。所谓"本地和 GitHub 互为备份"，缺了哪边都不算数。养成习惯：提交前扫一眼 `git status`，问自己"该进来的都进来了吗"。

另一个相关的小场面：`git push` 被拒（`fetch first`），说明远端有你本地没有的提交（比如在网页上做过修改），`git pull --rebase origin main` 合一下再推就好。

### 4.3 上游同步的三条版本纪律

- passwall 的两个仓库（luci 前端和依赖包）要**同一天一起同步**，它们的版本是配套的；
- 打包 Makefile 锁了版本号的包（比如 honk），源码必须跟 **tag** 走，不能跟 main——main 上的开发进度随时会超出打包脚本的预期；
- `upstreams.lock` 每次同步都会记下各上游的 commit，哪天更新出问题，翻它就能精确回退。

---

## 五、GitHub Actions / CI

### 5.1 `A sequence was not expected`：matrix 要写成对象

workflow 里 `strategy.matrix` 要的是带 `include` 键的对象，写成裸数组（`matrix=[...]`）会在解析阶段直接崩。正确写法是 `matrix={"include":[...]}`。

### 5.2 注释混进了 make 目标：清单里别写行尾注释

`build/packages.list` 里 `oaf` 后面随手写了句行尾注释，构建脚本把整行当包名读走，拼出一个荒谬的 make 目标（`package/oaf            # 一个目标带出两个包/compile`），直接退出。两层防护：清单里只写整行注释；解析时用 `sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//'` 把行尾注释和多余空白都剥掉。

值得记住的是这个 bug 的暴露方式：本地一直是手点包名编译，从没走过"整表解析"这条路，直到 CI 第一次整表跑才把它揪出来。自动化验证的价值就在这。

### 5.3 超时上限：冷启动比想象中慢

三个构建任务同时被处决（`!`），annotations 里写着 `maximum execution time of 2h30m`——不是编译出错，是时间不够。冷启动要下载 SDK、拉 feeds、编 Go 工具链、准备内核树、打包全部 kmod，两半小时真不够。把 `timeout-minutes` 放宽到 360（6 小时），同时缓存 `dl/` 和 SDK 压缩包，后续会快很多。

### 5.4 缓存要在失败时也保存

任务红了，下次还是 `Cache not found`，冷启动从头来——因为 `actions/cache` 默认只在任务全绿时保存。拆成 `actions/cache/restore` 和 `actions/cache/save` 两步，save 那步加 `if: always()`，再带上 `github.run_id` 保证 key 唯一，问题就解决了。

### 5.5 `Node.js 20 is deprecated`：可以永久无视

这是 GitHub 对官方 action 运行时的例行提醒，和构建内容无关，不用管。

---

## 六、签名软件源

### 6.1 体系是怎么运转的

- **签的是索引不是包**：`apk mkndx` 只给 `packages.adb` 签名，单个 .apk 不签——和 OpenWrt 官方的做法一致；
- **密钥管理**：EC P-256（`openssl ecparam -name prime256v1 -genkey` 生成）。私钥存在本地 `~/.config/hih-keys/` 和 GitHub Secret 两处互为备份，永不进 git；公钥 `hih.pem` 对外开放；
- **设备怎么信任**：公钥放进路由器的 `/etc/apk/keys/`，之后 `apk add` 就不再需要 `--allow-untrusted`，还能防篡改、防劫持。

### 6.2 Pages 根目录 404 是正常的

发布的是"软件源"不是网站——只有 `hih.pem` 和 `<版本>/<架构>/packages.adb`、`.apk` 这些文件，没有 index.html，所以根目录 404 是正确反应。apk 这个"客户"从不访问根目录，只认那几个固定地址，不影响任何功能。想要个门面的话，加一个 index.html 就行。

---

## 七、设备端使用

### 7.1 `scp` 报 `sftp-server: not found`：加个 -O

新版 scp 默认走 SFTP 协议，而 OpenWrt 精简系统里没装 sftp-server，握手直接断。给 scp 加上 `-O` 参数退回传统协议即可。往任何路由器传文件都建议带上它。

### 7.2 架构名的陷阱：`apk --print-arch` 不是你想要的

按 `$(apk --print-arch)` 拼软件源地址，`apk update` 报 404，URL 里是 `aarch64/packages.adb`。问题在于 apk 的架构名（`aarch64`）和 OpenWrt 的包架构名（`aarch64_generic`）不是一回事——x86 上两者碰巧都叫 `x86_64`，所以到 ARM 上才暴露。正确写法：

```shell
. /etc/openwrt_release
echo "https://h-i-h.github.io/openwrt-package-HiH/25.12.6/${DISTRIB_ARCH}/packages.adb" \
  > /etc/apk/repositories.d/hih.list
```

### 7.3 `install: not found`：BusyBox 的世界不一样

OpenWrt 的 BusyBox 精简掉了不少桌面 Linux 的常用命令（`install`、`fdisk`、`less` 都可能缺席）。遇到 `command not found` 先想 BusyBox 有没有对应物——`install -d` 换 `mkdir -p` 就好。

### 7.4 装包报依赖 `no such package`

自编的 luci 应用依赖官方源的运行库（lua、curl、dnsmasq-full 等），确保 `apk update` 能连上官方源（或国内镜像）。另外 dnsmasq 和 dnsmasq-full 是同门冤家，冲突时先 `apk del dnsmasq` 再装。

---

## 八、维护纪律速查

| 事项 | 节奏 | 动作 |
|---|---|---|
| 同步上游 | 每月或编固件前 | `bash scripts/sync.sh` → 编译测试 → commit |
| 自动跟踪上游 | 每周一凌晨 | sync.yml 自动开 PR，CI 绿了点合并 |
| 加新包 | 随时 | 本地测过 → `build/packages.list` 加一行 → push |
| 签名私钥 | 一次生成，两地备份 | 本地 `~/.config/hih-keys/` + GitHub Secret |
| kmod / vmlinux-btf | 随固件内核 | 内核变了必须重编（当前对应 25.12.6 / 6.12.112） |
| honk 版本 | 随打包 Makefile | 改 `HONK_TAG` 后同步，源码对齐打包 tag |

---

## 九、honk 补遗

最终 Boss 的完整排障记录，按交手顺序排列。

### 9.1 Rust 工具链代差：抄官方作业，别自己造

编 honk 报 `aya@0.16.0 requires rustc 1.98.0`。SDK 的 lang/rust 停在 1.96，连 openwrt/packages 的 master 也是 1.96——整个 OpenWrt 生态都没有新版可借，一度以为要自己编 Rust 源码（2～3 小时的苦活）。

翻了 daeuniverse 的 CI 才发现人家根本不走这条路：**直接用 rustup 的现成工具链**，分钟级装配。照抄：

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
rustup toolchain install 1.99.1 --profile minimal --target x86_64-unknown-linux-musl
rustup toolchain install nightly-2026-10-20 --profile minimal --component rust-src --component llvm-tools
# 再装 aya-rs 的预编译 bpf-linker，解压进 ~/.cargo/bin
```

版本号以 honk 源码里的 `rust-toolchain.toml` 和 `crates/honk-ebpf/rust-toolchain.toml` 为准。rustup 有个很治愈的机制：进不同目录自动切换工具链——honk 主体用 stable，eBPF 子模块用钦定的 nightly。以后编 R4S 时记得补装 `aarch64-unknown-linux-musl` 目标。

### 9.2 PATH 冒牌货：SDK 的旧 rustc 顶了包

工具链装好后还是报 `rustc 1.96.0`，查来查去发现是 SDK 在捣鬼——make 的内部 PATH 把 `staging_dir/host/bin` 排在最前，那里住着依赖自动拉进来的旧 rustc。我们 export 的 PATH 被压住了。

解法是在被执行的脚本里再夺一次权（`honk/build.sh` 里加一行）：

```bash
[ -x "$HOME/.cargo/bin/cargo" ] && export PATH="$HOME/.cargo/bin:$PATH"
```

规律值得记住：**make 环境会覆盖你 export 的 PATH**，想让自己的工具上位，得在构建脚本内部动手。

### 9.3 bindgen 要 libclang：系统库，不在 Rust 工具链里

报错 `Unable to find libclang`（panic 级别的）。honk 的 C 依赖在构建期要用 bindgen 生成绑定，而 bindgen 需要系统的 `libclang.so`——这东西 rustup 自带的 LLVM 不对外出借。`sudo pacman -S clang` 装上就好。

顺带一条读日志的心法：这次的报错段里既有捷报（`eBPF object embedded`，说明 eBPF 都编成了）也有败报，**别把捷报当成失败点**，真正的判决在最后一行。

### 9.4 apk del 是原子操作：一个错名，整单作废

删除清单里混进一个不存在的包名（源码目录叫 `open-app-filter`，设备上的包其实叫 `appfilter`），apk 报 `No such package` 后**直接中止整个事务**，其余的包一个都没删。想确认设备上的真实包名，用 `apk info | grep 关键词` 查。

### 9.5 失败的安装也会留"心愿单"残渣

`/etc/apk/world` 记录着"用户想要的包"。一次失败的 `apk add` 也会把包名写进去，之后任何 `apk del` 都会先试图满足这个心愿单，满足不了就整单作废。清理残渣：

```bash
sed -i '/^honk/d; /^v2ray-geoip/d' /etc/apk/world
```

### 9.6 双 BTF 包互斥：传包别用通配符

`vmlinux-btf`（带真数据，给官方内核用）和 `vmlinux-btf-builtin`（空占位，给内核自带 BTF 的固件用）是二选一的替代品，同时装会直接冲突。`scp` 时用 `vmlinux-btf*` 通配会把 builtin 也捎上，装包当场报 conflicts。按需精确指定包名。

### 9.7 磁盘扩容与端口接力

两件相关的小事：其一，虚拟盘扩容的真实情况见 3.3——`qemu-img resize` 不会涨分区；其二，腾空间时删掉 nginx 之后，80 端口无人值守，浏览器报 `ERR_CONNECTION_REFUSED`（拒绝连接 = 没人监听，不是被拦）。`/etc/init.d/uhttpd start` 叫醒默认的网页服务器就复活了。删任何 web 服务器之前，先看一眼 `netstat -tlnp | grep ':80 '` 是谁在当家。

### 9.8 上游的 pins.env 没随仓库发布

daeuniverse 的工作流引用 `.github/ci/pins.env`（锁 bpf-linker 的版本和哈希），但仓库里没这个文件。本地构建就退而求其次：bpf-linker 取 aya-rs Releases 的最新版，`sha256sum` 自己记一笔防篡改。真要复现官方的精确版本，等他们把锁文件补上。
### 9.9 CI 静默死亡：GitHub API 速率墙
- 症状：任务在工具链准备段无声失败（exit code 1，前后无任何报错行），日志中段找都找不到。
- 原因：匿名调用 api.github.com 撞上 CI 共享出口 IP 的速率墙；curl 拿回错误 JSON 后
  grep 无匹配 → pipefail 令赋值失败 → set -e 处决脚本，全程零输出。
- 解法：bpf-linker 版本钉死 0.13.0（BPF_LINKER_VERSION 可覆盖），不再查 API。
- 心法：CI 里能不调匿名 API 就不调；set -euo pipefail 下"命令替换赋值"是静默死亡高发区。

## 第十章：自动化产线实战教训（2026-11 固件构建战役）

### 10.1 sed 三连坑：替换文本里的元字符

本周连踩三次，全部出在"替换文本含特殊字符"上：

| 字符 | 在 sed 里的真实语义 | 事故 |
|---|---|---|
| & | 替换文本里代表"整个匹配内容" | `&& break` 被写成"匹配打印两遍 + break"，命令结构被毁 |
| ; | feeds.conf 处理链里被当命令分隔符 | `URL;SHA` 钉版导致 5 个 feed 全部静默消失 |
| / | s/.../.../ 的分隔符 | 替换文本含路径（带 /）时报 unknown option to 's' |

对策三条：
1. 含特殊字符的替换一律换分隔符：sed 's|原文|替换|'；
2. 含 & 的替换文本写 \&，或干脆用 awk 的 print 字面量（零歧义）；
3. sed 找不到匹配时静默跳过——**替换后必须 grep 验证**，否则错误推迟数小时才在编译里暴露。

### 10.2 粘贴渲染病

大段命令粘贴到终端时，渲染层会吞字符：转义括号被改写、heredoc 开头混入碎片、中文被吞。对策：分小块粘贴、每块等提示符回来再贴下一块；粘完 grep 验证关键行。两次事故（发布命令的 find 括号、workflow 花括号）同根同源。

### 10.3 缓存恢复撞上源码克隆

actions/cache 把上轮的下载缓存恢复到工作目录后，git clone 拒绝非空目录（destination exists and is not an empty directory）。对策：改用 git init + fetch --depth 1 提交哈希 + checkout FETCH_HEAD——对已有目录免疫，还省掉整个仓库的历史下载。附带教训：失败缓存（if: always()）两轮实战立功，但它的回流效应要预判。

### 10.4 GITHUB_TOKEN 递归保护

GITHUB_TOKEN 触发的事件不再触发其他 workflow。同步机器人用它开 PR，构建检查永远不会跑，自动合并永远等不到绿灯——不红不闹的静默死锁。对策：给同步流程配 PAT（存 Secret），事件链才通。PAT 用 fine-grained 锁单一仓库最稳，权限选不动时退回 classic 的 repo 域。

### 10.5 feeds 钉版语法

正确写法 URL^提交哈希（^ 对 shell 无意义）；URL;提交哈希 的分号会被拆掉导致 feed 静默消失。验证方法：feeds update 后 git -C feeds/名字 log -1 看实际落点。另一条原则：钉版要钉"验证过的组合"（本地跑通 defconfig 的那套），不是随手查的瞬间。

### 10.6 ttyd 与 libwebsockets 5.1 兼容

症状：ttyd 启动、监听 7681、十几毫秒后 lws_context_destroy 干净退出（退出码 0）。原因：libwebsockets 5.1 起 lws_service 只跑一轮，ttyd 1.7.7 主循环没适配。对策：上游补丁 fddd638（直接驱动 libuv 事件循环），放进包的 patches/ 目录随构建应用。教训：web 终端这类"编译进固件的小服务"要进刷机验收清单，别默认它是好的。

### 10.7 发布 job 的仓库上下文

发布 job 不做 checkout 时，gh 命令推断不出目标仓库（fatal: not a git repository）。对策：job 的 env 里加 GH_REPO: ${{ github.repository }}。附带教训：产物已生成时别整炉重跑——手动走一遍发布（几分钟）比重编 3 小时划算。

### 10.8 尾部截断吞报错

make ... | tail -5 会把真正的错误行截掉，只留结论（如 "lua failed to build"），真凶被吞。看报错用 tail -25，或先落文件再 grep。

### 10.9 软件源自动生成错误地址

构建系统把自定义 feed 按官方镜像模板拼地址（.../snapshots/packages/架构/名字/packages.adb），必然 404，apk update 全程噪音。对策：hih-repo 包首启写入正确地址（按本机架构）+ 删掉自动生成的错误行 + 随包携带签名公钥——编进固件即"拿来即用"，这才是软件源的本意。

### 10.10 多设备发布的三个设计决定

1. 标签用纯日期（2026.11.27），设备短名进资产文件名（HiH-router-r4s-…）——标签认时间、文件认设备；
2. 构建按设备独立：workflow_dispatch 支持只编指定设备，一台失败不拖累别的；
3. 发布按日期"创建或追加"，全部设备到齐才从 beta 转正式；保留 3 个版本，旧的自动清理。更新脚本只认正式版（hih-update），校验和通过才刷机。

### 10.11 术语规范

自造词（基座、放窑、验尸、晋级清单等）让人猜，全部改用直白说法：OpenWrt 源码版本、触发编译、分析报错日志、收录包清单。规则：默认直白，比喻只在助于理解时用且用完即解释。

### 10.12 杂项

- gh 不在 Arch 官方仓库：用 AUR 助手或 GitHub releases 的 tarball；
- python3-pyelftools（u-boot 需要）、cmake/libelf-dev（BTF 需要）容易漏装，已进依赖清单；
- 手动下载的构建产物目录必须进 .gitignore（GitHub 单文件 100MB 限制）；
- make defconfig 会解析所有包的 Makefile，是最快的包语法检查器（本地 10 秒轮替代 3 小时 CI 轮）。
