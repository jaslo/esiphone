// PhoneSupport.swift  (iPhone target)

import Foundation
import WatchConnectivity
import Security
import SwiftUI
import WidgetKit
import CryptoKit


extension Notification.Name {
    static let eversenseDataUpdated = Notification.Name("eversenseDataUpdated")
}

// ---------------------------------------------------------------------------
// MARK: - Keychain helper
// ---------------------------------------------------------------------------

enum EversenseKeychain {
    private static let service = "com.vtable.esiphone.eversense"

    static func save(username: String, password: String) {
        set(username, key: "username")
        set(password, key: "password")
    }

    static func load() -> (username: String, password: String)? {
        guard
            let username = get("username"),
            let password = get("password")
        else { return nil }
        return (username, password)
    }

    static func saveSettings(nsURL: String, nsSecret: String, pushURL: String) {
        set(nsURL,    key: "nsURL")
        set(nsSecret, key: "nsSecret")
        set(pushURL,  key: "pushURL")
    }

    static func loadSettings() -> (nsURL: String, nsSecret: String, pushURL: String) {
        return (
            nsURL:    get("nsURL")    ?? "",
            nsSecret: get("nsSecret") ?? "",
            pushURL:  get("pushURL")  ?? ""
        )
    }

    static func clear() {
        delete("username")
        delete("password")
        delete("nsURL")
        delete("nsSecret")
        delete("pushURL")
    }

    private static func set(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    key,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Glucose trend
// ---------------------------------------------------------------------------

enum GlucoseTrend: Int {
    case stale        = 0
    case fallingFast  = 1
    case falling      = 2
    case flat         = 3
    case rising       = 4
    case risingFast   = 5
    case fallingRapid = 6
    case risingRapid  = 7

    var arrow: String {
        switch self {
        case .stale:                      return "?"
        case .fallingRapid, .fallingFast: return "↓↓"
        case .falling:                    return "↓"
        case .flat:                       return "→"
        case .rising:                     return "↑"
        case .risingFast, .risingRapid:   return "↑↑"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Eversense API client
// ---------------------------------------------------------------------------

actor EversenseClient {

    private enum Endpoint {
        static let login       = URL(string: "https://usiamapi.eversensedms.com/connect/token")!
        static let userDetails = URL(string: "https://usapialpha.eversensedms.com/api/care/GetFollowingPatientList")!
    }

    private enum ClientCredentials {
        static let id     = "eversenseMMAAndroid"
        static let secret = "6ksPx#]~wQ3U"
    }

    private let username: String
    private let password: String
    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    private func login() async throws {
        var request = URLRequest(url: Endpoint.login, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "grant_type":    "password",
            "client_id":     ClientCredentials.id,
            "client_secret": ClientCredentials.secret,
            "username":      username,
            "password":      password,
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EversenseError.loginFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int?
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        tokenExpiry = Date().addingTimeInterval(Double(token.expires_in ?? 43200) - 60)
    }

    private func ensureTokenValid() async throws {
        if accessToken == nil || Date() >= tokenExpiry {
            try await login()
        }
    }

    func fetchDisplayText() async throws -> String {
        try await ensureTokenValid()
        guard let token = accessToken else { throw EversenseError.notAuthenticated }

        var request = URLRequest(url: Endpoint.userDetails, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            accessToken = nil
            throw EversenseError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct PatientEntry: Decodable {
            let CurrentGlucose: Int?
            let GlucoseTrend: Int?
            let IsTransmitterConnected: Bool?
        }
        let entries = try JSONDecoder().decode([PatientEntry].self, from: data)
        guard let first = entries.first else { throw EversenseError.noData }

        guard first.IsTransmitterConnected == true else { return "No signal" }

        let glucose = first.CurrentGlucose ?? 0
        let trend   = GlucoseTrend(rawValue: first.GlucoseTrend ?? 0) ?? .stale
        return "\(glucose) \(trend.arrow)"
    }
}

// MARK: - Errors

enum EversenseError: LocalizedError {
    case loginFailed(String)
    case notAuthenticated
    case requestFailed(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .loginFailed(let msg):   return "Login failed: \(msg)"
        case .notAuthenticated:       return "Sign in to Eversense first"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .noData:                 return "No patient data returned"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - APIClient
// ---------------------------------------------------------------------------

enum APIClient {
    static func fetchData() async throws -> ComplicationData {
        guard let creds = EversenseKeychain.load() else {
            throw EversenseError.notAuthenticated
        }
        let client = EversenseClient(username: creds.username, password: creds.password)
        let text   = try await client.fetchDisplayText()
        return ComplicationData(displayText: text, lastUpdated: Date())
    }

    static func fetchAndSync() async {
        do {
            let data = try await fetchData()
            data.save()
            PhoneSessionManager.shared.send(data)
            WidgetCenter.shared.reloadAllTimelines()
            await NightscoutClient.upload(data)
        } catch {
            print("Fetch failed: \(error)")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Phone → Watch session manager
// ---------------------------------------------------------------------------

final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()
    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
    }

    func send(_ data: ComplicationData) {
        guard let s = session, s.activationState == .activated, s.isWatchAppInstalled else { return }
        do {
            try s.updateApplicationContext(data.toContext())
        } catch {
            print("WCSession updateApplicationContext error: \(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

// ---------------------------------------------------------------------------
// MARK: - Nightscout SGV uploader
// ---------------------------------------------------------------------------

enum NightscoutClient {
    static func upload(_ data: ComplicationData) async {
        let settings = EversenseKeychain.loadSettings()
        guard
            !settings.nsURL.isEmpty,
            !settings.nsSecret.isEmpty,
            let url = URL(string: "\(settings.nsURL.trimmingCharacters(in: .init(charactersIn: "/")))/api/v1/entries")
        else {
            print("Nightscout not configured, skipping upload")
            return
        }

        let parts     = data.displayText.split(separator: " ")
        guard let sgv = Int(parts.first ?? "") else { return }
        let direction = trendDirection(from: parts.last.map(String.init) ?? "")

        let entry: [String: Any] = [
            "type":       "sgv",
            "sgv":        sgv,
            "date":       Int(data.lastUpdated.timeIntervalSince1970 * 1000),
            "dateString": ISO8601DateFormatter().string(from: data.lastUpdated),
            "direction":  direction,
            "device":     "ESiPhone"
        ]

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let hash = settings.nsSecret.data(using: .utf8)
            .map { Insecure.SHA1.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
            ?? settings.nsSecret
        request.setValue(hash, forHTTPHeaderField: "api-secret")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [entry])
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode != 200 { print("Nightscout upload failed: HTTP \(http.statusCode)") }
            }
        } catch {
            print("Nightscout upload error: \(error)")
        }
    }

    private static func trendDirection(from arrow: String) -> String {
        switch arrow {
        case "↑↑": return "DoubleUp"
        case "↑":  return "SingleUp"
        case "→":  return "Flat"
        case "↓":  return "SingleDown"
        case "↓↓": return "DoubleDown"
        default:   return "NotComputable"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Push service registration
// ---------------------------------------------------------------------------

enum PushRegistration {
    static func register(token: String) async {
        let settings = EversenseKeychain.loadSettings()
        guard
            !settings.pushURL.isEmpty,
            let url = URL(string: "\(settings.pushURL.trimmingCharacters(in: .init(charactersIn: "/")))/register")
        else {
            print("Push service URL not configured")
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode != 200 { print("Push registration failed: HTTP \(http.statusCode)") }
            }
        } catch {
            print("Push registration error: \(error)")
        }
    }
    static func unregister(token: String) async {
        let settings = EversenseKeychain.loadSettings()
        guard
            !settings.pushURL.isEmpty,
            let url = URL(string: "\(settings.pushURL.trimmingCharacters(in: .init(charactersIn: "/")))/unregister")
        else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("Unregister failed: HTTP \(http.statusCode)")
            }
        } catch {
            print("Unregister error: \(error)")
        }
    }
    
}

// ---------------------------------------------------------------------------
// MARK: - Nightscout settings view
// ---------------------------------------------------------------------------

struct NightscoutSettingsView: View {
    @State private var nsURL    = ""
    @State private var nsSecret = ""
    @State private var pushURL  = ""
    @State private var saved    = false

    var body: some View {
        Form {
            Section("Nightscout") {
                TextField("URL  e.g. https://yoursite.up.railway.app", text: $nsURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("API Secret", text: $nsSecret)
                    .textContentType(.password)
            }
            Section("Push Service") {
                TextField("Railway push service URL", text: $pushURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            Section {
                Button("Save") {
                    EversenseKeychain.saveSettings(
                        nsURL:    nsURL,
                        nsSecret: nsSecret,
                        pushURL:  pushURL
                    )
                    saved = true
                }
                .frame(maxWidth: .infinity)
            }
            if saved {
                Section {
                    Text("✅ Saved")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Nightscout Settings")
        .onAppear {
            let settings = EversenseKeychain.loadSettings()
            nsURL    = settings.nsURL
            nsSecret = settings.nsSecret
            pushURL  = settings.pushURL
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Credentials view
// ---------------------------------------------------------------------------

struct CredentialsView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    var onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Eversense account") {
                    TextField("Email", text: $username)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Sign in").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                }
            }
            .navigationTitle("Connect Eversense")
        }
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = EversenseClient(username: username, password: password)
            _ = try await client.fetchDisplayText()
            EversenseKeychain.save(username: username, password: password)
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

