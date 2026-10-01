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
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: SettingsForm
    @ObservedObject var forward: ForwardMonitor
    @ObservedObject var signIn: SignInModel

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
            form.launchAtLogin = model.launchAtLogin
            form.quietFrom = AppModel.clock(model.notifyPrefs.quiet.from)
            form.quietTo = AppModel.clock(model.notifyPrefs.quiet.to)
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        Text("GitHub · Linear").font(.headline)
        Text("앱 자신의 토큰을 Keychain에만 보관합니다. 지금은 로그인만 되고 데이터는 가져오지 않습니다.")
            .font(.caption).foregroundStyle(.secondary)
        TextField("GitHub App client ID", text: $form.githubClientText).onSubmit(applyGitHubClient)
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
