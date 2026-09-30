# atc-app 작업 규칙

atc-app(ANNUNCIATOR, macOS 메뉴 막대 앱)을 고치는 세션이 지키는 규칙이다. 설계는 [docs/design.md](docs/design.md)에 있다. 관제(DISPATCH·TOWER·FUEL)는 atc가 하고, 작업은 atc Linear 팀(ATC)의 이슈로 온다.

## 작업 위치

- `/home/c10/projects/atc-app`(main 체크아웃)에서 코드를 고치거나 브랜치를 바꾸지 않는다. 여기서 `git clean`·맨 `git stash`를 쓰지 않는다.
- 작업은 `origin/main` 기준 워크트리에서 한다.
  - 직접 만들 때: `git -C /home/c10/projects/atc-app worktree add /home/c10/projects/worktrees/atc-app-<작업> -b claude/<작업> origin/main`.
  - 백그라운드 세션: `EnterWorktree name=atc-<n>-<짧은 이름>`(`.claude/worktrees/` 안). 이름에 key(`atc-<n>`)를 넣는다.
- 끝난 워크트리는 `git worktree remove <경로>`로 치운다.
- atc의 운영 상태 `~/.local/state/atc/`와 운영 서버(7700)에 쓰지 않는다. 7700의 GET을 읽어 fixture를 만드는 것은 된다. 경로·토큰·이메일은 지우고 넣는다.

## 검증

- **순수 코어(`ATCCore`, Foundation만)**는 Linux에서 Docker로 빌드·테스트한다. 호스트에 Swift가 없다. 명령은 `Tools/test-linux.sh`(`swift build`, `swift test`, 고정한 `swift` 이미지. N0에서 정한다).
- **앱 타깃(AppKit·SwiftUI)**은 Linux에서 빌드할 수 없다. PR 본문에 "Mac에서 빌드·화면 확인 안 함"을 적고, 무엇을 보면 되는지 목록으로 남긴다. SUPERVISOR가 머지한 뒤 Mac에서 `Tools/build-app.sh`로 확인한다.
- 로직은 코어에 두고 테스트한다. 앱 타깃에는 배치와 시스템 호출만 둔다.
- 공개 저장소다. PR·이슈·브랜치에 스크린샷을 올리지 않는다. 확인한 화면은 글로 적는다.

## 코드

- Swift 5.9+, macOS 14+. SwiftPM만 쓴다(Xcode 프로젝트 없음). **외부 의존성은 두지 않는다.** 필요하면 먼저 사용자에게 묻는다.
- **앱 타깃은 SwiftUI 매크로를 쓰지 않는다**(`@State`, `#Preview` 등). SUPERVISOR의 Mac은 Xcode 없이 명령줄 도구만 쓰는데, 매크로 플러그인(`SwiftUIMacros`)은 Xcode에만 있어 빌드가 깨진다(ATC-163).
  - 화면 상태는 `ObservableObject` + `@Published`로 두고 `@ObservedObject`로 받는다.
  - `main.swift`의 최상위 코드에서 `@MainActor` 타입을 만들 때는 `MainActor.assumeIsolated { … }` 안에서 한다.
  - `Tools/test-linux.sh`의 `FORBIDDEN_MACROS`가 앱 소스(주석 포함)에서 금지 매크로를 찾으면 실패한다. 새로 막힌 매크로를 찾으면 거기에 더한다.
- 공개되지 않은 시스템 API(private framework, MediaRemote, HID 이벤트 등)를 쓰지 않는다.
- atc는 **읽기만** 한다: GET과 SSE(`/api/events`). 쓰기 요청을 보내지 않는다. 쓰기는 따로 인증 설계를 채택한 뒤다(design.md N5).
- 서버가 정한 등급·문구·숫자를 그대로 보인다. atc의 규칙을 앱에서 다시 계산하지 않는다.
- 번들 ID와 코드에 실제 이름·이메일·회사명을 넣지 않는다(번들 ID는 `dev.atc.annunciator`).
- 코드 주석은 영어로 짧게 쓴다.

## 라이선스

- 이 저장소는 GPL-3.0-or-later다. 새 파일 머리에 `// SPDX-License-Identifier: GPL-3.0-or-later`를 둔다.
- 다른 프로젝트의 코드를 가져올 때는 GPL-3.0과 맞는 라이선스(GPL-3.0, MIT, Apache-2.0, BSD 등)만 쓰고, 원래 저작권 표시를 그대로 두며 파일 머리에 출처(저장소·파일·커밋)를 적는다. 맞지 않거나 라이선스가 없는 코드는 가져오지 않는다.

## git과 PR

- 커밋 메시지와 PR 제목·본문은 영어로 쓴다. attribution 줄(Co-Authored-By 등)을 넣지 않는다. PR 본문 끝은 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- PR은 Draft로 올리지 않는다. 끝나지 않은 일이면 올리지 말고 보고한다.
- 팀 세션과 ENGINEERING은 머지하지 않는다. 이 저장소는 SUPERVISOR가 머지한다(atc MCC의 대상이 아니다).
- PR 제목의 `ATC-n`은 그 PR이 끝내는 이슈만 적는다(Linear가 머지 때 닫는다).
- 바뀐 동작은 `CHANGELOG.md`의 `[Unreleased]`에 적는다(첫 코드 PR이 파일을 만든다).

## 용어와 교신

- 항공 용어는 영어로 쓴다(AIRCRAFT, FLIGHT, STAND, READBACK, MASTER WARNING, LAMP …). SUPERVISOR가 읽는 글(사용자와의 대화, 앱 화면의 한국어 문구)은 한국어, 세션끼리 주고받는 글은 영어다.
- atc OCC의 `[DISPATCH D-xxxx]` FLIGHT PLAN에는 `READBACK D-xxxx`(못 하면 `UNABLE D-xxxx — 사유`), TOWER의 `[ATC C-xxxx]` CLEARANCE에는 끝줄이 청하는 답(`READBACK`·`UNABLE`·`STANDBY`·`ROGER`)으로 답한다. 규칙 전문은 atc 저장소의 `CLAUDE.md` "교신"이다.
- 끝낸 일의 보고는 일을 맡긴 세션에만 보낸다. 머리는 `[TEAM_X → OCC] ARRIVED ATC-n · PR <URL>`, 이어서 `TIER user`, `TESTS <통과>/<전체> (linux core) · app: not built on Linux`, `DISCRETION …`, `BLOCKED …`.
- 팀 세션은 Linear에 쓰지 않는다. 다른 팀 세션에 메시지를 보내지 않는다.
