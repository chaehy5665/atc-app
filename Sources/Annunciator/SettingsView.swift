// SPDX-License-Identifier: Apache-2.0
import ATCCore
import SwiftUI

/// Form state as an ObservableObject: SwiftUI state macros need Xcode's plugin (see Tools/test-linux.sh).
@MainActor
final class SettingsForm: ObservableObject {
    @Published var urlText = ""
    @Published var urlInvalid = false
    @Published var launchAtLogin = false
    @Published var quietFrom = ""
    @Published var quietTo = ""
    @Published var quietInvalid = false
    @Published var hostText = ""
    @Published var hostInvalid = false
    @Published var githubClientText = ""
    @Published var githubClientInvalid = false
    @Published var linearClientText = ""
    @Published var linearClientInvalid = false
    @Published var repoText = ""
    @Published var repoRejected: [String] = []
    @Published var teamText = ""
    @Published var teamRejected: [String] = []
    @Published var capText = ""
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: SettingsForm
    @ObservedObject var forward: ForwardMonitor
    @ObservedObject var signIn: SignInModel
    @ObservedObject var work: WorkModel

    var body: some View {
        Form {
            TextField("atc URL", text: $form.urlText)
                .onSubmit(apply)
            if form.urlInvalid {
                Text("http:// 또는 https:// 주소가 아닙니다").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Apply", action: apply)
                Button("Default") {
                    form.urlText = ATCSettings.defaultURLString
                    apply()
                }
            }
            Divider()
            TextField("SSH 호스트 (예: user@host)", text: $form.hostText)
                .onSubmit(applyHost)
            Text("비우면 앱은 SSH 포워드를 건드리지 않습니다.").font(.caption).foregroundStyle(.secondary)
            if form.hostInvalid {
                Text("영문·숫자·. _ - 와 user@ 만 쓸 수 있고 -로 시작할 수 없습니다").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Apply", action: applyHost)
                Button("설치/복구") { forward.install() }.disabled(forward.busy || forward.spec == nil)
                Button("다시 시작") { forward.restart() }.disabled(forward.busy || forward.spec == nil)
                Button("확인") { forward.refresh(force: true) }.disabled(forward.busy || forward.spec == nil)
            }
            if let state = forward.state {
                Text(state.line).font(.caption)
                if !state.hint.isEmpty { Text(state.hint).font(.caption).foregroundStyle(.secondary) }
            }
            if !forward.error.isEmpty { Text(forward.error).font(.caption).foregroundStyle(.red) }
            Text("~/Library/LaunchAgents/dev.atc.forward.plist 하나만 씁니다. 키·암호는 넣지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            accountsSection
            Divider()
            workSection
            Divider()
            Picker("atc 열기", selection: $model.linkPreference) {
                Text("앱 창").tag(LinkPreference.window)
                Text("브라우저").tag(LinkPreference.browser)
            }
            .pickerStyle(.segmented)
            Text("⌥를 누른 채 열면 그때만 브라우저로 열립니다.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("알림 배너 (WARNING·CALL)", isOn: prefBinding(\.notifications))
            Toggle("알림 소리", isOn: prefBinding(\.sound))
            Toggle("음성 (VOICE, atc가 만든 안내 음성)", isOn: prefBinding(\.voice))
            Toggle("조용한 시간 (소리·음성만 끔, 배너는 뜸)", isOn: prefBinding(\.quiet.on))
            HStack {
                TextField("시작", text: $form.quietFrom).frame(width: 70).onSubmit(applyQuiet)
                Text("~")
                TextField("끝", text: $form.quietTo).frame(width: 70).onSubmit(applyQuiet)
                Button("Apply", action: applyQuiet)
            }
            .disabled(!model.notifyPrefs.quiet.on)
            if form.quietInvalid {
                Text("HH:MM 형식이 아닙니다 (예: 22:00)").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("알림 허용 요청") { model.requestNotificationPermission() }
                Button("테스트") { model.testAlert() }
            }
            Text("브라우저의 atc 화면에서 설정의 소리(음성)를 꺼 두세요. 앱과 브라우저가 함께 울리면 두 번 들립니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("메뉴 막대에 FUEL 표시 (기본 꺼짐, 노치가 있으면 폭이 모자랄 수 있음)", isOn: $model.showFuelInTitle)
            Divider()
            Toggle("RADIO monitor (atc 무전을 앱에서 재생)", isOn: radioBinding(\.on))
            Picker("주파수", selection: radioBinding(\.freq)) {
                ForEach(RadioFreq.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .disabled(!model.radioPrefs.on)
            Picker("소음", selection: radioBinding(\.noise)) {
                ForEach(RadioNoise.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(!model.radioPrefs.on)
            Text("켠 뒤에 오는 무전만 재생합니다. WARNING·CALL 알림이 울리면 알림이 먼저이고, 조용한 시간에는 재생하지 않습니다. 브라우저 RADIO 탭의 LISTEN을 켜 두면 두 번 들립니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Launch at login", isOn: $form.launchAtLogin)
                .onChange(of: form.launchAtLogin) { _, on in
                    model.setLaunchAtLogin(on)
                    form.launchAtLogin = model.launchAtLogin
                }
            let note = model.launchAtLoginNote
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            form.urlText = model.baseURL.absoluteString
            form.hostText = forward.host
            forward.refresh(force: true)
            signIn.refresh()
            form.githubClientText = signIn.githubClientID
            form.linearClientText = signIn.linearClientID
            form.repoText = work.repoText
            form.teamText = work.teamText.replacingOccurrences(of: "\n", with: ", ")
            form.capText = String(work.cap)
            form.launchAtLogin = model.launchAtLogin
            form.quietFrom = AppModel.clock(model.notifyPrefs.quiet.from)
            form.quietTo = AppModel.clock(model.notifyPrefs.quiet.to)
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        Text("GitHub · Linear").font(.headline)
        Text("앱 자신의 토큰을 Keychain에만 보관합니다. GitHub는 아래 저장소의 PR 목록을 읽습니다. Linear는 아래 팀의 열린 이슈를 읽습니다.")
            .font(.caption).foregroundStyle(.secondary)
        TextField("GitHub OAuth App client ID", text: $form.githubClientText).onSubmit(applyGitHubClient)
        if form.githubClientInvalid {
            Text("영문·숫자·. _ - 만 쓸 수 있습니다").font(.caption).foregroundStyle(.red)
        }
        HStack {
            Button("Apply", action: applyGitHubClient)
            switch signIn.githubPhase {
            case .signedOut:
                Button("GitHub 로그인") { signIn.signInGitHub() }
            case .working:
                Text("연결 중…").font(.caption)
                Button("취소") { signIn.cancelGitHub() }
            case .waitingForCode:
                Button("취소") { signIn.cancelGitHub() }
            case .signedIn:
                Text("로그인됨").font(.caption)
                Button("로그아웃") { signIn.signOut(.github) }
                Button("GitHub에서 해지…") { signIn.openGitHubRevokePage() }
            }
        }
        if case .waitingForCode(let userCode, let url) = signIn.githubPhase {
            HStack {
                Text(userCode).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                Button("github.com/login/device 열기") { signIn.openVerification(url) }
            }
            Text("브라우저에서 이 코드를 입력하고 승인하세요.").font(.caption).foregroundStyle(.secondary)
        }
        if !signIn.githubMessage.isEmpty { Text(signIn.githubMessage).font(.caption) }
        if !signIn.githubScopeNote.isEmpty { Text(signIn.githubScopeNote).font(.caption) }
        TextField("Linear OAuth client ID", text: $form.linearClientText).onSubmit(applyLinearClient)
        if form.linearClientInvalid {
            Text("영문·숫자·- _ 만 쓸 수 있습니다").font(.caption).foregroundStyle(.red)
        }
        HStack {
            Button("Apply", action: applyLinearClient)
            switch signIn.linearPhase {
            case .signedOut:
                Button("Linear 로그인") { signIn.signInLinear() }
            case .working, .waitingForCode:
                Text("브라우저 창에서 승인하세요…").font(.caption)
                Button("취소") { signIn.cancelLinear() }
            case .signedIn:
                Text("로그인됨").font(.caption)
                Button("로그아웃") { signIn.signOut(.linear) }
            }
        }
        if !signIn.linearMessage.isEmpty { Text(signIn.linearMessage).font(.caption) }
        Text("Linear redirect URI: \(LinearAuth.redirectURI)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }

    @ViewBuilder
    private var workSection: some View {
        Text("GitHub PR 목록 (Work 창)").font(.headline)
        Text("저장소를 한 줄에 하나씩 owner/name 으로 적습니다. 읽기만 하고, 팝오버나 Work 창이 열려 있을 때만 60초마다 가져옵니다.")
            .font(.caption).foregroundStyle(.secondary)
        TextEditor(text: $form.repoText)
            .font(.system(.body, design: .monospaced))
            .frame(height: 70)
            .border(Color.secondary.opacity(0.4))
        if !form.repoRejected.isEmpty {
            Text("owner/name 형식이 아닙니다: " + form.repoRejected.joined(separator: ", ")).font(.caption).foregroundStyle(.red)
        }
        HStack {
            Button("Apply", action: applyRepos)
            Text("시간당 요청 상한").font(.caption)
            TextField("", text: $form.capText).frame(width: 60).onSubmit(applyCap)
            Button("Apply", action: applyCap)
        }
        Text("이번 시간 사용 \(work.usageText). 상한은 \(RateBudget.capRange.lowerBound)~\(RateBudget.capRange.upperBound), 기본 \(RateBudget.defaultCap)(GitHub 한도 5,000의 20%). 304는 세지 않습니다.")
            .font(.caption).foregroundStyle(.secondary)
        Divider()
        Text("Linear 이슈 목록 (Work 창)").font(.headline)
        Text("팀 키를 쉼표나 줄바꿈으로 나눠 적습니다(예: ABC). 읽기 전용(scope read)이고, 팝오버나 Work 창이 열려 있을 때만 60초마다 가져옵니다. Todo(unstarted)와 Started 상태만 읽습니다.")
            .font(.caption).foregroundStyle(.secondary)
        TextField("팀 키", text: $form.teamText).onSubmit(applyTeams)
        if !form.teamRejected.isEmpty {
            Text("팀 키 형식이 아닙니다(영문 대문자·숫자, 10자 이하): " + form.teamRejected.joined(separator: ", ")).font(.caption).foregroundStyle(.red)
        }
        HStack {
            Button("Apply", action: applyTeams)
        }
    }

    private func applyTeams() {
        form.teamRejected = work.setTeams(form.teamText)
        if form.teamRejected.isEmpty { form.teamText = work.teamText.replacingOccurrences(of: "\n", with: ", ") }
    }

    private func applyRepos() {
        form.repoRejected = work.setRepos(form.repoText)
        if form.repoRejected.isEmpty { form.repoText = work.repoText }
    }

    private func applyCap() {
        guard let value = Int(form.capText.trimmingCharacters(in: .whitespaces)) else {
            form.capText = String(work.cap)
            return
        }
        work.setCap(value)
        form.capText = String(work.cap)
    }

    private func applyGitHubClient() {
        form.githubClientInvalid = !signIn.setGitHubClientID(form.githubClientText)
        if !form.githubClientInvalid { form.githubClientText = signIn.githubClientID }
    }

    private func applyLinearClient() {
        form.linearClientInvalid = !signIn.setLinearClientID(form.linearClientText)
        if !form.linearClientInvalid { form.linearClientText = signIn.linearClientID }
    }

    private func prefBinding(_ path: WritableKeyPath<NotifyPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { model.notifyPrefs[keyPath: path] }, set: { model.notifyPrefs[keyPath: path] = $0 })
    }

    private func radioBinding<T>(_ path: WritableKeyPath<RadioPrefs, T>) -> Binding<T> {
        Binding(get: { model.radioPrefs[keyPath: path] }, set: { model.radioPrefs[keyPath: path] = $0 })
    }

    private func applyQuiet() {
        guard let from = QuietHours.minutes(form.quietFrom), let to = QuietHours.minutes(form.quietTo) else {
            form.quietInvalid = true
            return
        }
        form.quietInvalid = false
        model.notifyPrefs.quiet.from = from
        model.notifyPrefs.quiet.to = to
        form.quietFrom = AppModel.clock(from)
        form.quietTo = AppModel.clock(to)
    }

    private func applyHost() {
        form.hostInvalid = !forward.setHost(form.hostText)
        if !form.hostInvalid { form.hostText = forward.host }
    }

    private func apply() {
        form.urlInvalid = !model.setURL(form.urlText)
        if !form.urlInvalid { form.urlText = model.baseURL.absoluteString }
    }
}
