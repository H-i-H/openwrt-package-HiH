# 踩坑笔记

## 编译环境
- SDK: 25.12.6（产物为 .apk；路由器安装用 apk add --allow-untrusted）
- 目标: x86/64、bcm27xx/bcm2711（树莓派4）、rockchip/armv8（R4S）
- kmod 只兼容同内核版本固件（当前 kmod-oaf 对应 6.12.112）

## 已解决的问题
1. 下载依赖源码失败（mirror2 超时/404）→ 重试；或浏览器从 sources.openwrt.org 下载
   丢进 ~/sdk/<平台>-sdk/dl/ 再编译
2. xray-core 26.11+ 要求 Go ≥ 1.27，SDK 自带 1.26 →
   a. nano feeds/packages/lang/golang/golang-values.mk
      GO_DEFAULT_VERSION:=1.26 改为 1.27
   b. rm -f staging_dir/hostpkg/stamp/.golang_installed
      rm -rf build_dir/hostpkg/golang-1.27
   c. ./scripts/feeds install -f golang1.27
   d. make package/golang1.27/compile V=s（先编出 Go 1.27，十几分钟）
   e. 验证: ls staging_dir/hostpkg/lib/go-1.27/bin/ 应有 go
3. kmod 编译前需: make target/linux/prepare

## 待办
- [ ] sing-box / hysteria 等按需补编
- [ ] honk（Rust + eBPF，编译耗时以小时计，仅 64 位 + 新内核 + 需 vmlinux-btf）
- [ ] R4S、树莓派 4 平台编译
- [ ] 真机/虚拟机验收
