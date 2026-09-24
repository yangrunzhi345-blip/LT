# LT Dialogue

[English](README.md) | [簡體中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue 是使用 Flutter 與 Dart 建立、本地優先的 AI 互動敘事平台。它把結構化資料庫、AI 世界觀與角色創作，以及有狀態的 Adventure 冒險整合在同一個應用程式中。資源、冒險、訊息、版本與設定預設儲存在裝置上的 SQLite。

![LT Dialogue 標誌](logo.png)

## 核心功能

- **互動冒險**：將世界觀、角色與 NPC 組裝為冒險快照，繼續進行支援串流輸出與分支的故事。
- **世界與角色資料**：建立和管理可重複使用的世界觀、角色卡與 NPC 資料。
- **AI 生成流程**：透過規劃、藍圖確認、Part 生成、驗證、重試與復原建立或匯入資料。
- **Resource Studio**：編輯章節與 Part、查看生成進度、恢復草稿、檢查版本並發布壓縮結果。
- **有狀態敘事**：冒險回合在驗證後更新場景、角色、世界條目、分支與其他執行狀態。
- **閱讀支援**：翻譯對話並使用平台 TTS 朗讀；Linux 桌面在可用時使用 Speech Dispatcher。
- **導覽優先介面**：資料庫、Resource Studio、Adventure 與設定適配桌面及緊湊螢幕。

## 架構概覽

```text
Flutter 頁面與 Widget
        ↓
Controller、Riverpod Provider 與應用程式用例
        ↓
領域契約、引擎、Repository 與模型閘道
        ↓
SQLite + 已設定的 OpenAI-compatible 服務 + 平台服務
```

專案仍在逐步整理架構。新的 `features/`、`application/`、`domain/` 與既有目錄並存；README 不將任何單一目錄宣稱為完整架構。

## AI 生成系統

LT 直接連接你設定的 OpenAI-compatible 模型服務。在設定中選擇 Base URL、模型與 API Key；金鑰透過應用程式的安全儲存路徑保存在本機。資源建立與匯入支援手動輸入、貼上或檔案文字、既有資源、規劃工作階段、結構化藍圖、串流生成、驗證與復原。

冒險回應包含敘事正文與結構化狀態資料。應用程式會在寫入本機資料庫或進入下一回合前驗證結構化結果。

## 角色與世界

資源模型為：

```text
Resource → Section → Part
```

世界觀保存規則、地點與勢力等設定；角色卡與 NPC 保存可重複使用的人物資料及關係。冒險開始時會建立冒險自己的快照，之後資料庫編輯不會靜默改寫既有冒險。

## 資料庫與閱讀體驗

資料庫支援搜尋、類型篩選、詳情、手動編輯、AI 建立、匯入、自動儲存、草稿恢復、版本歷史、回收站、容量檢查與壓縮候選。Resource Studio 提供章節與 Part 的集中編輯及生成工作區。

Adventure 支援串流輸出、可選 reasoning、行動選項、分支、書籤、角色切換、骰點、訊息編輯、上下文摘要、對話匯入匯出、翻譯與朗讀。

## 多語言支援

目前 UI 支援 English、簡體中文、繁體中文、日本語與한국어。翻譯檔案位於 [`lib/l10n/`](lib/l10n/)，首次啟動和設定中都可以切換語言。

## 螢幕截圖

專案目前沒有提交 UI 截圖；上方是已追蹤的專案標誌。穩定的截圖集合準備好後再補充。

## 安裝與執行

需要 Git、Flutter stable（Dart `>=3.0.0 <4.0.0`）以及目標平台工具鏈。

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter devices
flutter run -d linux       # 或 windows / macos
# flutter run -d android
# flutter run -d ios
```

首次啟動後在設定中配置 DeepSeek 或其他 OpenAI-compatible 服務。支援的產品平台為 Linux、Windows、Android、macOS 與 iOS。

## 開發

```bash
dart format .
flutter analyze
flutter test
flutter test benchmark/core_benchmark.dart
```

入口檔案包括 [`lib/main.dart`](lib/main.dart)、[`lib/core/router/app_router.dart`](lib/core/router/app_router.dart) 和 [`docs/README.md`](docs/README.md)。

## 路線圖

專案將繼續改進資料創作、Adventure 執行狀態、復原行為與跨平台體驗。通用 tool-calling agent、圖資料庫或向量資料庫、跨資源自主決策目前不屬於已交付功能。

## 貢獻

歡迎小範圍、聚焦的 Pull Request。請說明行為變化，保護使用者資料與憑證，隨程式碼同步更新文件，並執行相關格式化、分析和測試。

## 授權

專案目前沒有根目錄 `LICENSE` 檔案。重新分發或商業使用前，請透過 GitHub 聯絡專案擁有者。
