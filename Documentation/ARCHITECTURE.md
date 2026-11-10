# 结构

单工程，iPhone，iOS 17+。`xcodegen` 从 `project.yml` 生成工程。验证命令是 `make test`。这台机器的 `xcodebuild` 需要 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，Makefile 已经带上。

## 模块

- `Models`：SwiftData 的 Vehicle、Trip、Expense、TripRevision、RatePeriod，以及值类型 `TripDraft`。
- `TrackMath`：路径过滤和长度。
- `RateBook` / `LedgerMath`：税率匹配、金额、汇总、导出范围和导出前检查。
- `TripEdits`：保存前的 revision、切分、合并。
- `TripLibrary`：唯一的 SwiftData 写入口。
- `TripRecorder`：使用期间定位，并把未结束行程写到 Application Support 的 `active-trip.json`。进程被杀掉后不自动开定位，等用户选择继续或结束。
- `PurchaseManager`：StoreKit 2。商品配置在 `FairMile/Resources/Products.storekit`。
- `CSVExporter` / `PDFExporter`：本地文件，再用系统分享送出。PDF 由 UIGraphicsPDFRenderer 绘制，用 PDFKit 打开。

界面从 `RootView` 进四个标签：Log、Trips、Export、Settings。记录用全屏覆盖，编辑是行程本身。

## 存储

默认 `ModelConfiguration(..., cloudKitDatabase: .none)`。iCloud 开关只写入 UserDefaults，下次启动才尝试 `.automatic`。没有 iCloud capability 时初始化失败，回退到同名本地库。`FairMile/Resources/FairMile.entitlements` 里是容器 `iCloud.app.fairmile.ios`，默认不挂到 target 上，避免没有开发者账号时签名失败。要打开同步：在签名里启用 iCloud 和 CloudKit，把该 entitlements 文件设为 Code Signing Entitlements，容器 ID 与 Bundle ID `app.fairmile.ios` 一致。

CloudKit 不接受 Decimal。英里、金额、税率都用整数。轨迹和收据照片用 Data。

## 上架前仍要人来做

名称和商标没有核完。Apple Developer Program、App Store Connect 里的三个商品、试用、排除中国大陆，以及真机跑一周行程，都不在这个仓库里。
