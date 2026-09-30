// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import SwiftUI

/// Form state as an ObservableObject: SwiftUI state macros need Xcode's plugin (see Tools/test-linux.sh).
@MainActor
final class SettingsForm: ObservableObject {
    @Published var urlText = ""
    @Published var urlInvalid = false
    @Published var launchAtLogin = false
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
            Toggle("Launch at login", isOn: $form.launchAtLogin)
                .onChange(of: form.launchAtLogin) { _, on in
                    model.setLaunchAtLogin(on)
                    form.launchAtLogin = model.launchAtLogin
                }
            let note = model.launchAtLoginNote
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            form.urlText = model.baseURL.absoluteString
            form.launchAtLogin = model.launchAtLogin
        }
    }

    private func apply() {
        form.urlInvalid = !model.setURL(form.urlText)
        if !form.urlInvalid { form.urlText = model.baseURL.absoluteString }
    }
}
