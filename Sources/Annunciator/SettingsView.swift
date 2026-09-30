// SPDX-License-Identifier: GPL-3.0-or-later
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
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var form: SettingsForm

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
            form.launchAtLogin = model.launchAtLogin
            form.quietFrom = AppModel.clock(model.notifyPrefs.quiet.from)
            form.quietTo = AppModel.clock(model.notifyPrefs.quiet.to)
        }
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

    private func apply() {
        form.urlInvalid = !model.setURL(form.urlText)
        if !form.urlInvalid { form.urlText = model.baseURL.absoluteString }
    }
}
