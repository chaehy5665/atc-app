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

atc는 도는 컴퓨터의 `127.0.0.1:7700`에만 듣습니다. Mac에서는 SSH 로컬 포워딩을 켜 둡니다(`ssh -N -L 7700:127.0.0.1:7700 <호스트>`, 또는 atc의 `docs/guide/menubar.md`에 있는 launchd 에이전트). 앱은 `http://localhost:7700`에만 말하고 포트를 열지 않습니다. atc를 LAN에 열지 마세요. atc에는 로그인이 없습니다.

## 빌드(예정)

```sh
Tools/build-app.sh      # swift build -c release, Annunciator.app 묶기, ad-hoc 서명, ~/Applications에 복사
```

Mac에서 직접 빌드한 앱에는 격리(quarantine) 표시가 없어 Developer ID 없이 열립니다.

## 라이선스

GPL-3.0-or-later, [LICENSE](LICENSE). atc는 자기 라이선스를 가진 별개의 프로그램이고, 앱은 HTTP로만 이야기합니다. 다른 GPL-3.0 프로젝트에서 가져온 코드는 저작권 표시를 그대로 두고, 파일에 출처를 적습니다.
