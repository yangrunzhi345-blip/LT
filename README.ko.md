# LT Dialogue

[![Flutter](https://img.shields.io/badge/Flutter-app-02569B?logo=flutter)](https://flutter.dev/) [![Latest release](https://img.shields.io/github/v/release/yangrunzhi345-blip/LT)](https://github.com/yangrunzhi345-blip/LT/releases/latest)

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

LT Dialogue는 AI 대화형 이야기, 세계관, 캐릭터를 만드는 로컬 우선 작업 공간입니다.

재사용할 자료를 만들고 리소스 스냅샷으로 Adventure를 시작하세요. 이야기를 읽으면서 변하는 캐릭터와 세계 상태도 확인할 수 있습니다. LT는 Flutter, Dart, Riverpod, SQLite를 사용합니다.

![LT Dialogue 로고](logo.png)

## 주요 기능

- 스트리밍 턴, 행동 선택, 분기, 저장된 세션 복구를 지원하는 대화형 Adventure.
- 검색 가능한 Resource Library와 구조화 편집 및 AI 생성을 위한 Resource Studio.
- 라이브러리에서 Adventure로 전달되어 실행 중 변하고 서사 컨텍스트에 반영되는 캐릭터 관계.
- 대시보드, 개체 상태, 타임라인, 턴별 변화를 제공하는 Runtime State Hub.
- 번역과 읽어주기. 모델을 다운로드해 사용하는 로컬 신경망 TTS도 선택 가능.
- 반응형 탐색: 데스크톱 사이드바의 최근 Adventure와 작은 화면의 간결한 탐색으로 Adventure, Resource Library, 런타임 상태, 설정에 접근.

## 대화형 Adventure

생성 마법사에서 세계관, 주인공, 동료, NPC를 선택하고 시작 장면과 준비 상태를 확인합니다. 선택한 리소스는 Adventure 전용 스냅샷이 되므로 이후 라이브러리 편집이 기존 Adventure를 조용히 덮어쓰지 않습니다.

플레이 중 서사 스트리밍, 행동 선택, 분기 생성, 활성 캐릭터 전환, 저장된 세션 재개를 지원합니다. 북마크, 메시지 편집, 주사위 판정, 대화 가져오기/내보내기, 컨텍스트 요약으로 긴 이야기를 관리할 수 있습니다.

## Resource Library와 Resource Studio

세계관, 캐릭터 카드, NPC를 생성, 가져오기, 검색, 필터링, 관리합니다. 자료는 순서가 있는 `Resource → Section → Part` 구조를 따릅니다.

Resource Studio는 Section 추가와 정렬, Part 편집, 스트리밍 생성, 수동 저장, 자동 저장, 초안 복구를 제공합니다. 실패한 Part 하나 또는 전체를 재시도하고 리비전 기록을 확인하거나 복원할 수 있습니다. 검증과 준비 상태를 통해 Adventure에서 사용 가능한지 확인합니다.

용량 도구로 리소스 크기를 확인하고 압축 후보를 생성한 뒤 검토하여 명시적으로 게시할 수 있습니다. 압축이 현재 내용을 자동으로 교체하지는 않습니다. 라이브러리는 휴지통과 복원도 제공합니다.

## 캐릭터, 관계, 런타임 상태

라이브러리에서 캐릭터 관계를 관리하고 기존 캐릭터를 바탕으로 연관 캐릭터를 생성할 수 있습니다. 선택한 캐릭터 간 관계를 Adventure 스냅샷으로 복사하면 플레이 중에도 변화할 수 있습니다. 현재 관계 상태는 서사 컨텍스트와 가중치 기반 토큰 예산 계획에 반영되어 관련 변화가 이후 AI 이야기에 영향을 줄 수 있습니다. 이후 라이브러리 관계 편집이 해당 스냅샷을 조용히 바꾸지 않습니다.

활성 Adventure의 Runtime State Hub는 대시보드, 캐릭터와 세계 상태, 장소, 세력, 관계, 추적 상태, 타임라인, 턴 기록을 제공합니다. 이야기와 함께 기록된 변화와 개체 이력을 확인할 수 있습니다.

## AI 생성 파이프라인

OpenAI-compatible 엔드포인트, 모델, API 키를 설정합니다. 리소스 생성과 가져오기는 계획, 블루프린트, 후보 확인, Part 스트리밍 생성, 검증을 거치며 실패 작업의 복구와 재시도를 지원합니다. 각 흐름에 따라 수동 입력, 붙여넣은 텍스트, 파일 내용 텍스트 참조, 기존 리소스를 사용할 수 있습니다.

Adventure 생성은 리소스 스냅샷, 최근 서사, 요약, 런타임 상태를 컨텍스트 예산 안에서 구성합니다. 구조화된 상태 출력을 파싱하고 검증한 뒤 승인된 변화를 저장하여 이후 턴에 사용합니다.

## 읽어주기와 로컬 신경망 TTS

기본 모드는 시스템 TTS입니다. Enhanced / Neural TTS는 선택 사항이며 Sherpa/ONNX로 기기에서 음성을 합성합니다. 신경망 모델은 APK에 포함되지 않고 자동으로 다운로드되지 않습니다. 설정 → 읽어주기 → 모델 관리에서 직접 다운로드해야 합니다. 모델 관리에서 설치 상태, 다운로드 진행률, 디스크 사용량을 확인하고 다운로드 취소나 모델 삭제를 할 수 있습니다.

내레이터와 기본 캐릭터 음성을 선택하고 자동 음성 배정을 켜거나 캐릭터/NPC 자료 상세 화면에서 개별 음성을 지정할 수 있습니다. 사용 가능한 음성과 언어는 설치된 모델에 따라 다릅니다. 신경망 음성, 모델, 런타임을 사용할 수 없으면 사용 가능한 시스템 백엔드가 있을 때 시스템 TTS로 대체됩니다.

Linux 시스템 읽어주기는 사용 가능한 Speech Dispatcher를 사용합니다. 대화 번역은 설정한 텍스트 모델이 처리하며 TTS와 별개입니다.

## 로컬 우선 아키텍처

리소스, Adventure, 메시지, 리비전, 앱 설정은 주로 로컬 SQLite에 저장됩니다. API 키는 앱 수준에서 암호화하여 로컬에 저장합니다. 전체 데이터베이스 암호화나 운영체제 자격 증명 저장소 사용을 의미하지 않습니다.

AI 텍스트 생성과 번역은 필요한 컨텍스트를 설정한 엔드포인트로 전송하며, 해당 서비스는 원격일 수 있습니다. 신경망 모델 다운로드에는 네트워크가 필요하지만 설치된 신경망 TTS 모델은 로컬에서 음성을 합성할 수 있습니다. 로컬 우선 저장이 모든 AI 기능의 오프라인 실행을 뜻하지는 않습니다.

## 다국어 지원

UI는 English, 简体中文, 繁體中文, 日本語, 한국어를 지원합니다. 첫 실행 또는 설정에서 언어를 선택할 수 있습니다. 번역 소스는 [`lib/l10n/`](lib/l10n/)에 있습니다.

## 설치

### Android Release 다운로드

[Latest Release](https://github.com/yangrunzhi345-blip/LT/releases/latest)에서 정식 서명된 APK를 다운로드하세요. 현재 공식 사전 빌드 릴리스는 **Android ARM64 / arm64-v8a만** 제공합니다. 이 릴리스 흐름은 Windows, Linux, macOS, iOS 설치 파일을 배포하지 않습니다.

버전별 정보와 서명 및 업그레이드 안내는 [`docs/releases/`](docs/releases/)를 확인하세요. 이전 Debug 서명 빌드에서 이동할 때 Android 서명 규칙으로 제거가 필요하다면 먼저 데이터를 백업하거나 내보내세요.

### 소스에서 실행

저장소에는 소스 개발을 위한 Android, Linux, Windows, macOS, iOS 플랫폼 프로젝트가 있습니다. 각 플랫폼 도구가 필요하며 서비스 가용성도 다릅니다. 현재 Android 설정은 네이티브 라이브러리를 ARM64로 제한합니다.

Git, Flutter stable, 대상 플랫폼의 네이티브 도구를 준비하세요. `pubspec.yaml`은 Dart `>=3.0.0 <4.0.0`을 선언하지만 현재 [`pubspec.lock`](pubspec.lock)은 **Flutter >=3.44.0 및 Dart >=3.12.0 <4.0.0**을 요구합니다. 이번 확인 환경은 Flutter 3.44.8 / Dart 3.12.2입니다.

```bash
git clone https://github.com/yangrunzhi345-blip/LT.git
cd LT
flutter pub get
flutter run
```

대상을 지정하려면 `flutter devices`로 확인한 뒤 `flutter run -d <device-id>`를 실행하세요. AI 생성 전에 첫 실행 과정이나 설정에서 모델 서비스를 구성하세요.

## 개발

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

개발 중에는 관련 테스트를 우선 실행하세요. 저장소 CI는 서식, 정적 분석, Flutter 테스트를 확인합니다. 작업 규칙은 [`AGENTS.md`](AGENTS.md)를 참고하세요.

## 프로젝트 구조

- [`lib/features/`](lib/features/): 기능별 UI와 관련 코드.
- [`lib/application/`](lib/application/): 유스 케이스, 서사 컨텍스트, 오케스트레이션.
- [`lib/domain/`](lib/domain/): 도메인 계약과 모델.
- [`lib/services/`](lib/services/): 영속 저장, 리포지토리, 모델 접근, TTS.
- [`lib/core/`](lib/core/): 공통 라우팅, 테마, UI 기반.
- [`test/`](test/): 자동 테스트. [`docs/`](docs/): 구현 및 개발 문서.

기존 Controller, Provider, Screen, Widget 디렉터리도 이 구조와 함께 사용됩니다. [`lib/main.dart`](lib/main.dart)에서 시작하고 [문서 색인](docs/README.md)을 참고하세요.

## 로드맵

리소스 작성, Adventure 상태 도구, 복구, 플랫폼별 사용성을 계속 개선합니다. 향후 개선 분야이며 추가로 출시된 기능을 뜻하지 않습니다.

## 기여

범위가 명확한 Pull Request를 환영합니다. 동작 변경을 설명하고 사용자 데이터와 자격 증명을 보호하며 관련 문서를 갱신하고 필요한 검사를 실행하세요.

## 라이선스

루트에 `LICENSE` 파일이 없습니다. 재배포나 상업적 사용 전 GitHub를 통해 프로젝트 소유자에게 확인해 주세요.
