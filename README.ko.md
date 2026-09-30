# atc-app

[English](README.md) · **한국어**

[atc](https://github.com/chaehy5665/atc)(AI 코딩 세션 관제판)의 macOS 메뉴 막대 앱입니다. 작업 이름은 **ANNUNCIATOR**로, 조종석의 MASTER WARNING / MASTER CAUTION 경고등 패널에서 따왔습니다.

메뉴 막대에 있다가 atc가 SUPERVISOR를 부를 때 불이 켜집니다.

- MASTER WARNING(빨강)이나 MASTER CAUTION(호박색) 경고등과 개수, 가장 많이 쓴 ACCOUNT의 FUEL 사용률
- 누르면 켜진 항목(LAMP)이 AIRCRAFT·FLIGHT·STAND와 함께 보이고, DISPATCH 판정 대기, 마지막 RTS, 일하는 세션도 보입니다
- 항목을 누르면 브라우저에서 알맞은 atc 탭이 열립니다
- 새 WARNING·CALL이면 macOS 알림, 톤, 음성 콜아웃

atc를 읽기만 합니다. 승인과 스위치는 atc 화면에서 합니다.

> 상태(2026-09-29): 설계만 있습니다. [docs/design.md](docs/design.md)를 보세요. 아직 만든 것은 없습니다.

## 연결

atc는 도는 컴퓨터의 `127.0.0.1:7700`에만 듣습니다. Mac에서는 SSH 로컬 포워딩을 켜 둡니다(`ssh -N -L 7700:127.0.0.1:7700 <호스트>`, 또는 atc의 `docs/guide/menubar.md`에 있는 launchd 에이전트). 앱은 `http://localhost:7700`에만 말하고 포트를 열지 않습니다.

앱이 이 포워드를 만들고 지켜볼 수도 있습니다(ATC-204). 설정의 **SSH 호스트**에 SSH 대상(`host` 또는 `user@host`, 영문·숫자·`.`·`_`·`-`만)을 넣으세요. **설치/복구**는 `~/Library/LaunchAgents/dev.atc.forward.plist`를 쓰고(`/usr/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o BatchMode=yes -L 7700:127.0.0.1:7700 <호스트>`, `RunAtLoad`, `KeepAlive`) `launchctl bootstrap gui/<uid>`로 올리고, **다시 시작**은 `launchctl kickstart -k`를 씁니다. atc에 닿지 않는 동안 팝오버가 포워드 상태와 맞는 버튼을 보여 줍니다. 7700을 이미 다른 것(손으로 연 `ssh -L`, 편집기의 포트 포워딩)이 쓰고 있으면 PID와 명령을 알려 주고 건드리지 않습니다. 기본은 빈칸이고, 비어 있으면 앱은 아무것도 하지 않습니다. `sudo`를 쓰지 않고 plist에 키·암호를 넣지 않습니다. `BatchMode=yes`라서 암호가 있는 키는 바로 실패하니 키체인에 넣으세요(`ssh-add --apple-use-keychain <키>`). atc에는 GET과 SSE만 보내고, `launchctl`·`lsof`는 Mac에서 로컬로 돕니다. 확인 목록: [docs/mac-checklist-forward.md](docs/mac-checklist-forward.md). atc를 LAN에 열지 마세요. atc에는 로그인이 없습니다.

## 빌드와 실행 (Mac)

```sh
Tools/build-app.sh      # swift build -c release, Annunciator.app 묶기, ad-hoc 서명, ~/Applications에 복사
```

```sh
open ~/Applications/Annunciator.app
```

1. atc로 가는 SSH 포워딩을 켜 둡니다. `/api/supervisor-summary`(ATC-153)가 배포된 atc여야 합니다.
2. `Tools/build-app.sh`를 실행합니다(Xcode 명령줄 도구 필요). 명령줄 도구만 있으면 앱은 SwiftUI 매크로(`@State`, `#Preview` 등)를 쓸 수 없습니다(Xcode 플러그인이 필요합니다). `ObservableObject`와 `@ObservedObject`는 됩니다. `Tools/test-linux.sh`가 이를 검사합니다.
3. 앱을 엽니다. 회색 `✈ —`는 atc에 닿지 않는다는 뜻이고, 스스로 다시 연결합니다(1초부터 두 배씩, 최대 30초).
4. 항목을 누르면 팝오버가 열립니다. 위쪽 고정 띠(MASTER WARNING·MASTER CAUTION·ADVISORY 개수, PENDING·NEEDS YOU 칩, FUEL 막대, RTS와 작업 수 한 줄) 아래에 LAMP 목록이 스크롤됩니다(WARNING은 항상 펼침, CAUTION은 처음 5개, ADVISORY는 접힘이고 선택은 기억합니다). LAMP마다 경과 시간이 붙습니다. 톱니 버튼(⌘,)의 설정에서 atc URL(기본 `http://localhost:7700`)과 로그인 시 실행을 정합니다.

## RADIO monitor

설정의 **RADIO monitor** 스위치(기본 꺼짐)를 켜면 atc RADIO의 주파수 하나(기본 `TOWER`, `DELIVERY`·`GROUND`·`COMPANY`도 가능)를 브라우저 탭 없이 앱이 재생합니다.

- **소음:** 브라우저와 같은 선택: 호출만(기본), 답 없는 호출만, 전부.
- **재생:** 앱이 `topics=radio` SSE 연결을 따로 열고, 새 무전마다 `GET /api/radio/<id>.wav`(atc가 문구 템플릿으로 만든 음성. 앱은 자유 텍스트로 음성을 만들지 않습니다)를 받아 한 번에 하나씩 재생합니다. 큐는 5개까지이고 넘치면 오래된 것부터 버립니다.
- **알림이 먼저:** WARNING·CALL의 소리나 음성이 나오면 RADIO는 멈추고 알림이 끝나면 이어갑니다. 조용한 시간(알림과 같은 설정)에는 RADIO도 재생하지 않고 대기분을 버립니다.
- **다시 재생 안 함:** 켠 뒤, 또는 마지막 (재)연결 뒤에 기록된 무전만 듣습니다. atc에 닿지 않는 동안은 재생하지 않고, 돌아와도 그 사이 무전은 재생하지 않습니다. 나중에 응답이 붙은 호출을 두 번 재생하지 않습니다.
- **팝오버:** 켜져 있는 동안 상태 줄 아래에 `RADIO ● TOWER` 줄이 마지막 무전의 head(`TOWER → GOLF · GO AROUND · ATC-147`)를 보입니다. 메뉴 막대 제목은 바뀌지 않습니다.
- 설정은 UserDefaults(`radio.on`, `radio.freq`, `radio.noise`)에 저장합니다. 앱은 atc를 읽기만 합니다(GET, SSE).
- 앱이 재생하는 동안 브라우저 RADIO 탭의 LISTEN은 꺼 두세요. 켜 두면 두 번 들립니다.

Mac에서 직접 빌드한 앱에는 격리(quarantine) 표시가 없어 Developer ID 없이 열립니다.

코어 테스트는 `Tools/test-linux.sh`(Docker)로 Linux에서 돕니다.

CI(`.github/workflows/ci.yml`)는 모든 PR과 `main` 푸시에서 돕니다. `mac` 잡은 macOS 러너에서 앱 타깃을 빌드하고 `swift test`를 돌리고, `linux` 잡은 `Tools/test-linux.sh`(코어 테스트와 SwiftUI 매크로 검사)를 돌립니다. PR은 두 잡이 모두 초록이어야 합니다. CI는 실행 중 동작(화면, 소리, 알림)을 볼 수 없어서, 그것은 `docs/`의 체크리스트로 Mac에서 확인합니다.

## 라이선스

GPL-3.0-or-later, [LICENSE](LICENSE). atc는 자기 라이선스를 가진 별개의 프로그램이고, 앱은 HTTP로만 이야기합니다. 다른 GPL-3.0 프로젝트에서 가져온 코드는 저작권 표시를 그대로 두고, 파일에 출처를 적습니다.
