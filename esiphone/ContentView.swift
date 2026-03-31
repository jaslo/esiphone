// ContentView.swift  (iPhone target)

import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var data       = ComplicationData.load()
    @State private var isLoading  = false
    @State private var errorMessage: String?
    @State private var needsLogin = EversenseKeychain.load() == nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Eversense CGM")
                    .font(.title2).fontWeight(.semibold)

                VStack(spacing: 8) {
                    Text(data.displayText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("Updated \(data.ageDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    Task { await refresh() }
                } label: {
                    Label(isLoading ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || needsLogin)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 24) {
                    Button("Sign out", role: .destructive) {
                        EversenseKeychain.clear()
                        needsLogin = true
                    }
                    .font(.caption)

                    NavigationLink("Nightscout Settings") {
                        NightscoutSettingsView()
                    }
                    .font(.caption)
                }
            }
            .padding()
            .sheet(isPresented: $needsLogin) {
                CredentialsView {
                    needsLogin = false
                    Task { await refresh() }
                }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        await APIClient.fetchAndSync()
        data = ComplicationData.load()
        isLoading = false
    }
}
