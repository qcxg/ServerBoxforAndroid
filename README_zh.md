# ServerBox Android

[English](README.md)

[![Android CI](https://github.com/qcxg/flutter_server_box/actions/workflows/analysis.yml/badge.svg)](https://github.com/qcxg/flutter_server_box/actions/workflows/analysis.yml)
[![Release](https://img.shields.io/github/v/release/qcxg/flutter_server_box)](https://github.com/qcxg/flutter_server_box/releases/latest)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)](https://github.com/qcxg/flutter_server_box/releases/latest)
[![License](https://img.shields.io/github/license/qcxg/flutter_server_box)](LICENSE)

ServerBox Android 是一款行動伺服器管理 App，可在同一處監控主機、使用 SSH
終端機、管理檔案及執行常見伺服器操作。本版本只維護 Android，在 ServerBox
成熟基礎上加入 Material 3 Expressive 介面、更可靠的背景連線，以及左右雙欄
檔案工作區。

> [!IMPORTANT]
> 本倉庫是
> [lollipopkit/flutter_server_box](https://github.com/lollipopkit/flutter_server_box)
> 的個人獨立維護非官方 fork，與 ServerBox 原團隊無關，也不由原團隊維護或
> 提供支援。本分支的客製化修改由 Codex 完成。

## 主要功能

### 伺服器總覽

- 監控 CPU、記憶體、儲存空間、網路、負載、運行時間、程序、systemd、
  容器及 ServerBox 支援的其他主機資訊。
- 使用具備輕量在線狀態提示的 Expressive 伺服器卡片；首頁、SSH 與檔案頁
  共用同一份伺服器狀態。
- 手機與平板各自採用適合螢幕尺寸的導航和響應式佈局。

### 為 Android 強化的 SSH

- 使用 Android 前景服務、wake lock、重連與明確的工作階段清理，提高 App
  進入背景或熄屏後的 SSH 連線穩定度。
- 行動版 xterm 終端機提供連線狀態、改善的 Android IME 行為、穩定的刪除鍵
  處理和虛擬按鍵。
- 可先在本機命令緩衝區編輯，再選擇整段傳送多行結構，或依序執行每一個
  非空白行。
- 遠端主機安裝 tmux 後，可使用 tmux 恢復長時間執行的工作。

### 左右雙欄檔案工作區

- 以緊湊的 MT 風格同時瀏覽本機與遠端檔案。
- 為多台伺服器保留各自的遠端工作階段；切換伺服器不會重設本機欄。
- 可直接編輯路徑、多選檔案、在選取項目旁開啟情境選單，並在當前左右欄
  之間傳輸檔案。
- 常見檔案類型具有專用圖示，並以小字顯示大小和最後修改時間。
- 傳輸批次完成或失敗時使用 Android 系統提示通知。

### 整合文字編輯器

- 空檔案和現有文字檔皆可使用跟隨主題的內建編輯器開啟。
- 支援常見設定、標記、資料、腳本與程式碼格式的語法高亮。
- 可切換軟換行與高亮、使用復原／重做，或交給外部 Android App 開啟。
- 儲存後可立即離開，遠端上傳會在背景繼續；成功後自動清除暫存副本。

### 重新設計的介面

- 伺服器卡片、選擇器、設定、程式片段、載入狀態、編輯器與關於頁採用
  Material 3 Expressive 視覺。
- 分層半透明頂部表面與緊湊玻璃導航，在保留觸控區域的同時讓內容延伸至
  其下方。
- 全 App 使用 Android 系統 Toast，保持一致的操作回饋。

## 下載

請從 [GitHub Releases](https://github.com/qcxg/flutter_server_box/releases/latest)
安裝最新正式簽章 APK。

| 項目 | 需求 |
| --- | --- |
| Android | 7.0 或更新版本（`minSdk 24`） |
| Target | Android 16 / API 36 |
| 發布 ABI | `arm64-v8a` |
| 套件名稱 | `com.shiraka.serverbox` |

Release 簽章憑證 SHA-256：

```text
7B:CA:1D:11:65:A9:78:FB:F8:EA:F2:E3:1D:2D:F8:4A:B9:A2:A3:6D:B4:A7:CE:04:DF:33:49:31:36:41:31:D8
```

從其他來源取得 APK 時，請先核對以上指紋。原版、debug key 或其他 fork
簽署的 APK 無法直接覆蓋安裝本版本。

## 專案狀態與支援範圍

本倉庫只維護及發布 Android App。程式內已移除 upstream 更新檢查，新版本
只透過本倉庫發布。部分 Android 系統的省電限制仍可能干擾背景網路；必要時
請為 App 關閉電池最佳化。

> [!NOTE]
> 本分支僅出於個人興趣而維護，目前只在運行 Android 16 的 Pixel 與三星
> 裝置上進行過測試。不保證其他裝置的穩定性，對於收到的問題回饋，也不保證
> 所有問題都能或都會修復。

與此 APK 或客製功能有關的問題，請回報至本 fork，請勿要求 ServerBox
原團隊支援此非官方版本。

## 從原始碼建置

CI 與 Release workflow 使用 Flutter `3.44.6`。

```bash
git clone --recurse-submodules https://github.com/qcxg/flutter_server_box.git
cd flutter_server_box
flutter pub get --enforce-lockfile
flutter analyze lib test
flutter test
flutter build apk --release --split-per-abi \
  --target-platform android-arm64
```

正式簽章還需要私有 Android keystore 和 `android/key.properties`，簽章材料
不會提交到 Git。版本標籤會由
[GitHub Actions](.github/workflows/release-android.yml) 自動測試、編譯、
核對憑證指紋並發布。

## 技術基礎

- Flutter 與 Dart
- Riverpod 響應式狀態管理
- Hive CE 本機持久化資料
- `dartssh2` SSH 與遠端檔案操作
- 客製 `xterm.dart` 終端機
- Android platform channels 前景工作階段與原生整合

本倉庫使用 Git submodule，其中兩項客製依賴由獨立 fork 維護：

- [qcxg/fl_lib](https://github.com/qcxg/fl_lib)
- [qcxg/xterm.dart](https://github.com/qcxg/xterm.dart)

由於本版本大幅修改 Android lifecycle、終端機、檔案管理及 UI，上游更新會
先經過審查和合併驗證，不會直接覆蓋客製內容。

## 致謝與授權

ServerBox 由
[lollipopkit 與原始專案貢獻者](https://github.com/lollipopkit/flutter_server_box)
建立，App 內仍完整保留原作者與貢獻資訊。

本 fork 依 [GNU Affero General Public License v3.0](LICENSE) 發布。
