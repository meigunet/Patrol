# 巡护 App iOS 版 — 构建与安装说明

## 现状

源码已全部写好（约 3900 行 Swift，21 个文件），零第三方依赖，用系统框架（SwiftUI / WebKit / CoreLocation / URLSession / AVFoundation / Network）。
地图页直接复用了安卓端打磨成熟的 `map.html`（Leaflet）+ leaflet.js，通过本地 HTTP 服务托管，图层/航迹/人员点/测距/底图切换等能力与安卓端一致。

但**在当前 Windows 环境无法编译 iOS**（Swift 编译和签名只能在 macOS + Xcode 上做），所以编译验证这一步必须借助云端。

## 三种构建方式（按推荐度）

### 方式一：GitHub Actions 云端构建（免费、推荐）

工程里已备好 `.github/workflows/build-ipa.yml`：用免费 macOS 运行器编译出**未签名 IPA**。

1. 注册一个免费 GitHub 账号（github.com）。
2. 新建一个**公开仓库**（public，macOS 运行器免费时长无限；私有仓库每月也有免费额度，够用）。
3. 把本 `ios-app` 目录的内容上传到仓库根目录（用 Git 或网页上传均可）。
4.  pushing 代码后，进入仓库的 `Actions` 标签页，等 `Build Patrol IPA (unsigned)` 这个任务跑完（约 10–15 分钟）。
5. 在任务详情页底部 `Artifacts` 下载 `Patrol-unsigned-ipa`，解压得到 `Patrol-unsigned.ipa`。

> 首次云端编译如报错，把 Actions 日志里的红色报错文字发我，我逐条修。这是跨平台上架前的正常磨合。

### 方式二：租云 Mac（省心，约 ¥150/月起）

MacinCloud、MacStadium 等按小时/月租 macOS 机器，远程进去装 Xcode，打开 `ios-app/Patrol.xcodeproj`（需先在 `ios-app` 目录执行 `xcodegen generate` 生成工程），连上 Apple ID 直接真机调试/打包。
适合后续要长期维护 iOS 版的情况。

### 方式三：自己买一台 Mac（长期最划算）

Mac mini 是最低门槛。之后正常 Xcode 开发、TestFlight 分发。

## 安装到测试机（无需开发者账号）

用 **Sideloadly**（免费，Windows / Mac 都能装，官网 sideloadly.io）：

1. Windows 电脑安装 Sideloadly + 官网指定的 iTunes / iCloud 桌面版（不要 Microsoft Store 版）。
2. iPhone 用数据线连电脑，iOS 16+ 需先在手机「设置 → 隐私与安全性 → 开发者模式」打开开发者模式。
3. Sideloadly 里选择下载的 `Patrol-unsigned.ipa`，填一个**免费 Apple ID**（建议专门注册一个），点 Start 签名并安装。
4. 免费签名限制：**App 有效期 7 天**、**每台设备最多 3 个 sideload App**、**每 7 天最多注册 10 个新 App ID**。到期前用 Sideloadly 连上手机重新签一次即可（不用卸载，数据保留）。

> 如果需要长期不出问题、装在更多人手机上、或上架 App Store，则需要注册 Apple Developer Program（个人/公司 ¥688/年，企业 ¥1988/年），用 TestFlight 分发。

## iOS 与安卓的功能差异（系统限制，非缺失）

| 功能 | iOS 处理方式 |
|---|---|
| 应用内自动下载安装更新 | iOS 不允许，需重新签名安装或用 TestFlight 更新 |
| 悬浮窗（最小化后对讲圆钮） | iOS 不允许跨 App 悬浮，改为 App 内底部对讲按钮 + 全屏对讲页；切后台只能收听不能按住说话 |
| 后台每 60 秒精确定位上报 | 需用户授权「始终」定位（首次弹「使用期间」，再去系统设置改「始终」）；状态栏会有定位指示箭头；iOS 仍可能在某些省电场景冻结后台，回到前台会立即补报+补心跳 |
| 后台持续录音 | iOS 限制严格，切到后台后对讲退为仅收听 |

其余功能（地图/图层/航迹/任务/开始结束任务/动态表单含拍照水印+签名+定位+地形/记录分组/流水号/提交上报/在线人数/心跳/位置补传/对讲音频/公告/服务器地址切换）均已实现。

## 服务器

沿用现有服务端 `http://36.170.114.144:3000/api/`，无需改动服务端。登录页可切换服务器地址。
