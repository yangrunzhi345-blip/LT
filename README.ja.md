# LT Dialogue

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue は Flutter と Dart で構築した、ローカル優先の AI インタラクティブストーリーテリングプラットフォームです。構造化リソースライブラリ、AI による世界観・キャラクター作成、状態を持つ Adventure セッションを一つのアプリにまとめています。リソース、冒険、メッセージ、リビジョン、設定は原則として端末内の SQLite に保存されます。

![LT Dialogue ロゴ](logo.png)

## 主な機能

- **インタラクティブ Adventure**：ガイドに沿って世界観、主人公、同行キャラクターを選び、NPC スナップショット、序章、行動分岐を設定して、準備状態を確認して開始します。プレイ中はストリーミング、行動選択、分岐、キャラクター切替、保存状態からの再開に対応します。
- **世界観とキャラクター**：世界観、キャラクターカード、NPC を作成、インポート、検索、絞り込み、編集できます。リソースは順序を持つ `Resource → Section → Part` 構造で管理します。
- **AI 生成パイプライン**：冪等な作成・インポートセッションを開始し、貼り付けまたはファイルのテキストを入力してブループリントを計画・確認します。設定したモデルで Part を生成し、検証、復旧、再試行を行えます。
- **Resource Studio**：セクションの追加・並べ替え、個別 Part の編集・再試行、ストリーミング進捗、下書き復旧、リビジョン履歴、圧縮候補の公開を一つの編集画面で扱います。
- **状態を持つ物語**：Adventure ごとにメッセージ、シーン状態、キャラクターと NPC のスナップショット、世界エントリ、分岐、要約、実行状態を保存します。構造化されたモデル出力は検証後に次のターンへ反映されます。
- **読書支援**：会話を翻訳し、選択した内容をプラットフォーム TTS で読み上げます。Linux デスクトップでは Speech Dispatcher を検出し、利用可能な音声がない場合は入口を表示しません。
- **ナビゲーション中心 UI**：Adventure、Resource Library、Resource Studio、設定をすぐに切り替えられます。デスクトップはサイドバー、小さい画面はドロワーまたはボトムナビゲーションを使います。

## アーキテクチャ概要

```text
Flutter ページと Widget
        ↓
Controller、Riverpod Provider、アプリケーションユースケース
        ↓
ドメイン契約、エンジン、Repository、モデルゲートウェイ
        ↓
SQLite + 設定済み OpenAI-compatible サービス + プラットフォームサービス
```

リポジトリは段階的にアーキテクチャを整理中です。新しい `features/`、`application/`、`domain/` と既存ディレクトリが共存しており、単一ディレクトリが全体のアーキテクチャだとは扱いません。

## AI 生成システム

LT は設定した OpenAI-compatible モデルエンドポイントへ直接接続します。設定で Base URL、モデル、API Key を指定し、キーはアプリの安全なローカル保存経路を使います。リソース作成・インポートでは、手入力、貼り付けやファイルのテキスト、既存リソース、計画セッション、構造化ブループリント、ストリーミング生成、検証、復旧を利用できます。

Adventure の応答には物語本文と構造化状態データが含まれます。次のターンやローカルデータベースに反映する前に、アプリが構造化結果を検証します。

## キャラクターと世界

リソースモデルは次のとおりです。

```text
Resource → Section → Part
```

世界観にはルール、場所、勢力などを保存し、キャラクターカードと NPC には再利用できる人物情報と関係を保存します。Adventure 開始時に Adventure 固有のスナップショットを作成するため、後のライブラリ編集で既存の冒険が黙って書き換わることはありません。

## Resource Library と読書体験

Resource Library は検索、種類フィルター、詳細、手動編集、AI 作成、インポート、自動保存、下書き復旧、リビジョン履歴、ゴミ箱、容量確認、圧縮候補に対応します。Resource Studio はセクションと Part の編集・生成ワークスペースです。

Adventure セッションはストリーミング出力、任意の reasoning 表示、行動選択、分岐、ブックマーク、キャラクター切替、ダイス判定、メッセージ編集、コンテキスト要約、会話の入出力、翻訳、読み上げに対応します。

## 多言語対応

UI は English、簡体字中国語、繁体字中国語、日本語、韓国語に対応します。翻訳ファイルは [`lib/l10n/`](lib/l10n/) にあり、初回起動と設定から言語を選べます。

## スクリーンショット

現在 UI スクリーンショットはリポジトリに含まれていません。上の画像は追跡されているプロジェクトロゴです。安定したキャプチャセットが用意できた時点で追加します。

## インストールと実行

Git、Flutter stable（Dart `>=3.0.0 <4.0.0`）、対象プラットフォームのツールチェーンが必要です。

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter devices
flutter run -d linux       # windows / macos も可
# flutter run -d android
# flutter run -d ios
```

初回起動後、設定で DeepSeek または別の OpenAI-compatible サービスを設定します。製品対応プラットフォームは Linux、Windows、Android、macOS、iOS です。

## 開発

```bash
dart format .
flutter analyze
flutter test
flutter test benchmark/core_benchmark.dart
```

主な入口は [`lib/main.dart`](lib/main.dart)、[`lib/core/router/app_router.dart`](lib/core/router/app_router.dart)、[`docs/README.md`](docs/README.md) です。

## ロードマップ

リソース作成、Adventure の状態管理、復旧処理、クロスプラットフォーム対応を継続して改善します。汎用 tool-calling agent、グラフ・ベクトルデータベース、リソース横断の自律判断は現在提供済みの機能ではありません。

## コントリビュート

小さく目的を絞った Pull Request を歓迎します。変更内容を説明し、ユーザーデータと認証情報を保護し、コード変更に合わせて文書を更新し、関連する format・analyze・test を実行してください。

## ライセンス

ルートに `LICENSE` ファイルはありません。再配布や商用利用の前に GitHub からプロジェクト所有者へ確認してください。
