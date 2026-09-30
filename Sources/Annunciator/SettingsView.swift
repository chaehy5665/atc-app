// SPDX-License-Identifier: GPL-3.0-or-later
import ATCCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var urlText = ""
    @State private var urlInvalid = false
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            TextField("atc URL", text: $urlText)
                .onSubmit(apply)
            if urlInvalid {
                Text("http:// 또는 https:// 주소가 아닙니다").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Apply", action: apply)
                Button("Default") {
                    urlText = ATCSettings.defaultURLString
                    apply()
                }
            }
            Divider()
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    model.setLaunchAtLogin(on)
                    launchAtLogin = model.launchAtLogin
                }
            let note = model.launchAtLoginNote
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            urlText = model.baseURL.absoluteString
            launchAtLogin = model.launchAtLogin
        }
    }

    private func apply() {
        urlInvalid = !model.setURL(urlText)
        if !urlInvalid { urlText = model.baseURL.absoluteString }
    }
}
