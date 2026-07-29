# ServerBox Android

[English](README.md)

這是 [lollipopkit/flutter_server_box](https://github.com/lollipopkit/flutter_server_box)
的 Android 個人維護 fork，主要改善 SSH 背景連線、雙欄檔案管理與
Material 3 Expressive 介面。

> [!IMPORTANT]
> 這是獨立維護的非官方 fork，不是 ServerBox 官方版本，也不會自動跟隨
> upstream App 的更新通道。

## 下載

正式簽章的 Android APK 會發布在
[GitHub Releases](https://github.com/qcxg/flutter_server_box/releases)。

- Android 7.0 或更新版本（`minSdk 24`）
- target Android 16 / API 36
- 目前發布 `arm64-v8a` APK
- 套件名稱：`tech.lolli.toolbox`

Release 簽章憑證 SHA-256：

```text
7B:CA:1D:11:65:A9:78:FB:F8:EA:F2:E3:1D:2D:F8:4A:B9:A2:A3:6D:B4:A7:CE:04:DF:33:49:31:36:41:31:D8
```

如果 APK 不是直接從本倉庫下載，安裝前請先核對指紋。

## 這個 fork 的主要修改

- 使用 Android foreground service、wake lock、重連與明確退出流程，提升
  SSH 在背景與熄屏時的連線穩定度。
- 改善 Android terminal 輸入：IME 個人化學習、刪除鍵異常、連線狀態提示，
  以及可整段或逐行傳送的本機命令緩衝區。
- MT 風格左右雙欄檔案工作區：本機與遠端同時展示、路徑可編輯、多選、
  檔案旁情境選單、直接上傳下載、每台伺服器保留獨立 SFTP session，以及
  傳輸完成系統 Toast。
- 強化文字編輯器：更多格式高亮、跟隨主題的色彩、外部 App 開啟、儲存後
  背景上傳與遠端暫存檔清理。
- 重寫伺服器卡片、選擇器、設定、程式片段、載入動畫、平板側欄與玻璃導航，
  採用 Material 3 Expressive 視覺。
- 首頁、SSH 與 SFTP 共用同一份伺服器在線狀態。
- 移除 upstream App 更新檢查；本 fork 只透過此倉庫發布。

## SSH 與 SFTP

SFTP 是 SSH File Transfer Protocol，直接運作在加密的 SSH 連線內，通常
共用相同的主機、連接埠、帳號、金鑰與 host-key 驗證。遠端目錄回應本來就
包含常見的大小和修改時間，因此顯示這些資訊不需要為每個檔案再發一次請求。

## 建置

目前只維護 Android：

```bash
git clone --recurse-submodules https://github.com/qcxg/flutter_server_box.git
cd flutter_server_box
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi \
  --target-platform android-arm64
```

正式建置需要私有的 `android/key.properties` 與 keystore，簽章材料不會提交
到 Git。版本 tag 會由
[GitHub Actions](.github/workflows/release-android.yml) 使用加密 Secrets 建置。

## Fork 與上游同步

本倉庫保留 upstream Git 歷史和 GitHub fork 關係。可以繼續取得
`lollipopkit/flutter_server_box` 的新功能，但由於 Android lifecycle、
terminal、檔案管理與 UI 已有大量客製，應先在獨立同步分支合併、處理衝突並
通過測試，再加入本 fork 的 `main`。

另外兩個被修改的 submodule 也有獨立 fork：

- [qcxg/fl_lib](https://github.com/qcxg/fl_lib)
- [qcxg/xterm.dart](https://github.com/qcxg/xterm.dart)

其餘未修改的 submodule 仍使用原作者倉庫。

## 致謝與授權

ServerBox 由
[lollipopkit 與所有貢獻者](https://github.com/lollipopkit/flutter_server_box)
開發，本 fork 保留原始版權與來源說明。

本專案使用 [GNU Affero General Public License v3.0](LICENSE)。
