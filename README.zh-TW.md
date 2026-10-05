# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Latest release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue 是本機優先的 AI 互動敘事、世界觀與角色創作工作台。

建立可重複使用的資料，從資源快照啟動 Adventure 冒險，在閱讀故事時查看角色與世界狀態的變化。LT 使用 Flutter、Dart、Riverpod 與 SQLite。

![LT Dialogue 標誌](logo.png)

## 核心功能

- 支援串流回合、行動選擇、分支與已儲存工作階段復原的互動冒險。
- 可搜尋的 Resource Library 資料庫，以及支援結構化編輯與 AI 生成的 Resource Studio。
- 角色關係從資料庫進入冒險，在執行期間變化並參與敘事上下文。
- Runtime State Hub 提供儀表板、實體狀態、時間軸與逐回合變化。
- 翻譯與朗讀，包括需下載模型的選用本機神經 TTS。
- 響應式導覽：桌面側欄包含最近冒險，小螢幕使用精簡導覽；可進入 Adventure、資料庫、執行狀態與設定。

## 互動冒險

透過建立精靈選擇世界觀、主角、同行角色與 NPC，設定開場並檢查就緒狀態。選取的資源形成冒險專屬快照，後續資料庫編輯不會靜默改寫既有冒險。

執行期間支援串流敘事、行動選擇、建立分支、切換目前角色，以及恢復已儲存的工作階段。書籤、訊息編輯、擲骰、對話匯入匯出與上下文摘要為長篇故事提供輔助。

## 資料庫與 Resource Studio

建立、匯入、搜尋、篩選與管理世界觀、角色卡及 NPC。資源採用有序的 `Resource → Section → Part` 結構。

Resource Studio 提供章節新增與排序、Part 編輯、串流生成、手動儲存、自動儲存與草稿復原。可重試單一失敗 Part 或全部失敗 Part，查看版本歷史並還原版本。驗證與就緒狀態協助判斷資源能否用於冒險。

容量工具支援查看資源大小、生成壓縮候選，經審閱後明確發布；壓縮不會自動取代目前內容。資料庫也提供回收筒與還原。

## 角色、關係與執行狀態

在資料庫管理角色關係，並以既有角色生成關聯角色。選取角色之間的關係可以複製到冒險快照，在執行期間繼續變化。目前關係狀態進入敘事上下文與加權 Token 預算規劃，因此相關變化可以影響後續 AI 敘事。後續資料庫關係編輯不會靜默改變這份快照。

目前冒險的 Runtime State Hub 提供儀表板、角色與世界狀態、地點、勢力、關係、追蹤狀態、時間軸及回合歷史。可結合故事查看已記錄的變化與實體歷史。

## AI 生成流程

設定 OpenAI-compatible 服務位址、模型與 API Key。資源建立與匯入經過規劃、藍圖、候選確認、Part 串流生成與驗證，失敗工作支援復原及重試。不同流程可使用手動輸入、貼上文字、檔案文字參考或既有資源。

冒險生成在上下文預算內組裝資源快照、近期敘事、摘要與執行狀態。結構化狀態輸出經解析與驗證後，接受的變化才會持久化並用於後續回合。

## 朗讀與本機神經 TTS

預設使用系統 TTS。Enhanced / Neural TTS 為選用模式，使用 Sherpa/ONNX 在裝置上合成語音。神經模型不隨 APK 內建，也不會自動下載；需在設定 → 朗讀 → 模型管理中主動下載。模型管理顯示安裝狀態、下載進度與磁碟用量，支援取消下載及移除模型。

可選擇旁白與預設角色聲音，啟用角色聲音自動分配，或在角色/NPC 資源詳情中綁定聲音。可用聲音與語言取決於已安裝模型。神經聲音、模型或執行環境不可用時，若有可用系統後端，會回退至系統 TTS。

Linux 系統朗讀使用可用的 Speech Dispatcher。對話翻譯由已設定的文字模型完成，與 TTS 相互獨立。

## 本機優先架構

資源、冒險、訊息、版本與應用程式設定主要持久化於本機 SQLite。API Key 經應用程式層加密後儲存在本機；這不表示整個資料庫已加密，也不表示金鑰存放於作業系統憑證庫。

AI 文字生成與翻譯會向你設定的服務傳送所需上下文，該服務可能位於遠端。神經模型下載需要網路，安裝後的神經 TTS 模型可在本機合成語音。本機優先儲存不代表所有 AI 功能都能離線執行。

## 多語言支援

UI 支援 English、简体中文、繁體中文、日本語與 한국어。首次啟動或設定中可選擇語言。翻譯原始檔位於 [`lib/l10n/`](lib/l10n/)。

## 安裝

### 下載 Android Release

從 [Latest Release](https://github.com/yangrunzhi345-blip/LT/releases/latest) 下載正式簽署 APK。目前官方預編譯發行僅提供 **Android ARM64 / arm64-v8a**。此發行流程目前不提供 Windows、Linux、macOS 或 iOS 安裝套件。

各版本詳情及簽署、升級說明見 [`docs/releases/`](docs/releases/)。從較舊的 Debug 簽署版本遷移時，若 Android 簽署規則要求解除安裝，請先備份或匯出資料。

### 從原始碼執行

專案包含 Android、Linux、Windows、macOS 與 iOS 平台工程，供原始碼開發使用；仍需對應工具鏈，服務可用性也因平台而異。目前 Android 設定將原生函式庫限制為 ARM64。

需要 Git、Flutter stable 與目標平台原生工具鏈。`pubspec.yaml` 宣告 Dart `>=3.0.0 <4.0.0`，但目前 [`pubspec.lock`](pubspec.lock) 要求 **Flutter >=3.44.0、Dart >=3.12.0 <4.0.0**。本次檢查使用 Flutter 3.44.8 / Dart 3.12.2。

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter run
```

需要指定目標時，先用 `flutter devices` 查看裝置，再執行 `flutter run -d <device-id>`。AI 生成前，在首次啟動流程或設定中配置模型服務。

## 開發

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

開發時優先執行針對性測試；專案 CI 檢查格式、靜態分析與 Flutter 測試。專案工作規範見 [`AGENTS.md`](AGENTS.md)。

## 專案結構

- [`lib/features/`](lib/features/)：功能 UI 與相關功能程式碼。
- [`lib/application/`](lib/application/)：用例、敘事上下文與流程編排。
- [`lib/domain/`](lib/domain/)：領域契約與模型。
- [`lib/services/`](lib/services/)：持久化、Repository、模型存取與 TTS。
- [`lib/core/`](lib/core/)：共用路由、主題與 UI 基礎。
- [`test/`](test/)：自動化測試；[`docs/`](docs/)：實作與開發文件。

既有 Controller、Provider、Screen 與 Widget 目錄仍與上述邊界並存。從 [`lib/main.dart`](lib/main.dart) 開始，更多說明見[文件索引](docs/README.md)。

## 路線圖

後續工作聚焦資料創作、冒險狀態工具、復原能力與跨平台體驗。這些是持續改善方向，不是額外已交付能力。

## 貢獻

歡迎聚焦的 Pull Request。請說明行為變化，保護使用者資料與憑證，更新相關文件，並在提出 PR 前執行必要檢查。

## 授權

專案目前沒有根目錄 `LICENSE` 檔案。重新分發或商業使用前，請透過 GitHub 聯絡專案擁有者。
