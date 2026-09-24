# LT Dialogue

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue는 Flutter와 Dart로 만든 로컬 우선 AI 인터랙티브 스토리텔링 플랫폼입니다. 구조화된 리소스 라이브러리, AI 세계관·캐릭터 생성, 상태를 보존하는 Adventure 세션을 하나의 앱에 담았습니다. 리소스, 모험, 메시지, 리비전, 설정은 기본적으로 기기의 SQLite에 저장됩니다.

![LT Dialogue 로고](logo.png)

## 주요 기능

- **인터랙티브 Adventure**: 세계관, 캐릭터, NPC를 스냅샷으로 조립하고 스트리밍과 분기를 지원하는 이야기를 이어 갑니다.
- **세계관과 캐릭터 리소스**: 재사용 가능한 세계관, 캐릭터 카드, NPC 자료를 만들고 관리합니다.
- **AI 생성 파이프라인**: 계획, 블루프린트 확인, Part 생성, 검증, 재시도, 복구를 거쳐 리소스를 만들거나 가져옵니다.
- **Resource Studio**: 섹션과 Part 편집, 생성 진행률 확인, 초안 복구, 리비전 확인, 압축 결과 게시를 지원합니다.
- **상태 기반 스토리**: 검증된 턴 결과로 장면, 캐릭터, 세계 항목, 분기 등의 실행 상태를 갱신합니다.
- **읽기 지원**: 대화를 번역하고 플랫폼 TTS로 읽을 수 있습니다. Linux 데스크톱에서는 사용 가능한 경우 Speech Dispatcher를 사용합니다.
- **탐색 중심 UI**: Resource Library, Resource Studio, Adventure, 설정을 데스크톱과 작은 화면에 맞게 배치합니다.

## 아키텍처 개요

```text
Flutter 페이지와 Widget
        ↓
Controller, Riverpod Provider, 애플리케이션 유스케이스
        ↓
도메인 계약, 엔진, Repository, 모델 게이트웨이
        ↓
SQLite + 설정된 OpenAI-compatible 서비스 + 플랫폼 서비스
```

저장소는 아키텍처를 단계적으로 정리하는 중입니다. 새로운 `features/`, `application/`, `domain/`과 기존 디렉터리가 함께 존재하며 하나의 디렉터리가 전체 아키텍처라고 가정하지 않습니다.

## AI 생성 시스템

LT는 설정한 OpenAI-compatible 모델 엔드포인트에 직접 연결합니다. 설정에서 Base URL, 모델, API Key를 지정하며 키는 앱의 보안 로컬 저장 경로를 사용합니다. 리소스 생성과 가져오기는 직접 입력, 붙여넣기 또는 파일 텍스트, 기존 리소스, 계획 세션, 구조화된 블루프린트, 스트리밍 생성, 검증, 복구를 지원합니다.

Adventure 응답에는 서사 본문과 구조화된 상태 데이터가 포함됩니다. 앱은 다음 턴이나 로컬 데이터베이스에 반영하기 전에 구조화된 결과를 검증합니다.

## 캐릭터와 세계

리소스 모델은 다음과 같습니다.

```text
Resource → Section → Part
```

세계관에는 규칙, 장소, 세력 등을 저장하고 캐릭터 카드와 NPC에는 재사용 가능한 인물 정보와 관계를 저장합니다. Adventure 시작 시 Adventure 전용 스냅샷을 만들기 때문에 이후 라이브러리 편집이 기존 모험을 조용히 바꾸지 않습니다.

## Resource Library와 읽기 경험

Resource Library는 검색, 유형 필터, 상세 보기, 수동 편집, AI 생성, 가져오기, 자동 저장, 초안 복구, 리비전 기록, 휴지통, 용량 확인, 압축 후보를 지원합니다. Resource Studio는 섹션과 Part를 편집하고 생성하는 작업 공간입니다.

Adventure 세션은 스트리밍 출력, 선택적 reasoning 표시, 행동 선택, 분기, 북마크, 캐릭터 전환, 주사위 판정, 메시지 편집, 컨텍스트 요약, 대화 가져오기/내보내기, 번역, 읽어주기를 지원합니다.

## 다국어 지원

UI는 English, 간체 중국어, 번체 중국어, 일본어, 한국어를 지원합니다. 번역 파일은 [`lib/l10n/`](lib/l10n/)에 있으며 첫 실행과 설정에서 언어를 선택할 수 있습니다.

## 스크린샷

현재 UI 스크린샷은 저장소에 포함되어 있지 않습니다. 위 이미지는 추적 중인 프로젝트 로고입니다. 안정적인 캡처 세트가 준비되면 추가합니다.

## 설치 및 실행

Git, Flutter stable(Dart `>=3.0.0 <4.0.0`), 대상 플랫폼 도구 체인이 필요합니다.

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter devices
flutter run -d linux       # windows / macos도 가능
# flutter run -d android
# flutter run -d ios
```

첫 실행 후 설정에서 DeepSeek 또는 다른 OpenAI-compatible 서비스를 구성합니다. 제품 지원 플랫폼은 Linux, Windows, Android, macOS, iOS입니다.

## 개발

```bash
dart format .
flutter analyze
flutter test
flutter test benchmark/core_benchmark.dart
```

주요 진입점은 [`lib/main.dart`](lib/main.dart), [`lib/core/router/app_router.dart`](lib/core/router/app_router.dart), [`docs/README.md`](docs/README.md)입니다.

## 로드맵

리소스 작성, Adventure 상태 관리, 복구 동작, 크로스 플랫폼 지원을 계속 개선합니다. 범용 tool-calling agent, 그래프·벡터 데이터베이스, 리소스 간 자율 판단은 현재 제공되는 기능이 아닙니다.

## 기여

작고 범위를 명확히 한 Pull Request를 환영합니다. 변경 내용을 설명하고 사용자 데이터와 인증 정보를 보호하며 코드 변경에 맞춰 문서를 갱신하고 관련 format·analyze·test를 실행해 주세요.

## 라이선스

루트에 `LICENSE` 파일이 없습니다. 재배포나 상업적 사용 전 GitHub를 통해 프로젝트 소유자에게 확인해 주세요.
