# LT Dialogue

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue は Flutter と Dart で構築した、ローカル優先の AI インタラクティブストーリーテリングプラットフォームです。構造化リソースライブラリ、AI による世界観・キャラクター作成、状態を持つ Adventure セッションを一つのアプリにまとめています。リソース、冒険、メッセージ、リビジョン、設定は原則として端末内の SQLite に保存されます。

![LT Dialogue ロゴ](logo.png)

## 主な機能

- **インタラクティブ Adventure**：世界観、キャラクター、NPC をスナップショットにまとめ、ストリーミングと分岐に対応した物語を続けられます。
- **世界観とキャラクター**：再利用できる世界観、キャラクターカード、NPC データを作成・管理します。
- **AI 生成パイプライン**：計画、ブループリント確認、Part 生成、検証、再試行、復旧を経てリソースを作成・インポートします。
- **Resource Studio**：セクションと Part の編集、生成進捗、下書き復旧、リビジョン確認、圧縮結果の公開に対応します。
- **状態を持つ物語**：検証済みのターン結果でシーン、キャラクター、世界エントリ、分岐などを更新します。
- **読書支援**：会話の翻訳とプラットフォーム TTS による読み上げに対応します。Linux デスクトップでは利用可能な場合 Speech Dispatcher を使います。
- **ナビゲーション中心 UI**：Resource Library、Resource Studio、Adventure、設定をデスクトップと小さい画面に合わせて配置します。

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
