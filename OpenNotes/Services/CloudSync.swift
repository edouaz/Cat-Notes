import SwiftUI
import CryptoKit
import Security

struct CloudConfiguration: Decodable {
    let url: URL
    let publishableKey: String
    static func isPublicKey(_ key: String) -> Bool {
        if key.hasPrefix("sb_publishable_") { return true }
        let parts = key.split(separator: ".")
        guard parts.count == 3 else { return false }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return payload["role"] as? String == "anon"
    }
    static func load() -> CloudConfiguration? {
        guard let file = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: file), let config = try? PropertyListDecoder().decode(Self.self, from: data),
              config.url.scheme == "https", !config.publishableKey.isEmpty,
              Self.isPublicKey(config.publishableKey) else { return nil }
        return config
    }
}
struct AuthSession: Codable {
    struct User: Codable { let id: UUID }
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: User
    var savedAt: Date? = Date()
    var expired: Bool { Date().timeIntervalSince(savedAt ?? .distantPast) > Double(expires_in - 60) }
}
struct RemoteRevision: Codable {
    let id: UUID
    let owner_id: UUID
    let notebook_id: UUID
    let parent_id: UUID?
    let checksum: String
    let object_path: String
}
struct CloudLink: Codable {
    var modifiedAt: Date?
    var remoteID: UUID
    var revision: UUID?
    var checksum: String
}
struct SyncConflict: Codable, Identifiable {
    var id = UUID()
    let localID: UUID
    let remoteCopyID: UUID
}
struct SyncState: Codable {
    var conflicts: [SyncConflict]?
    var owner: UUID?
    var links: [String: CloudLink] = [:]
    var seen: Set<UUID> = []
}

@MainActor
final class CloudSync: ObservableObject {
    @Published var status = "Local · no account required"
    @Published var signedIn = false
    @Published var running = false
    @Published var email = ""
    @Published var password = ""
    @Published var enabled = false
    private let config = CloudConfiguration.load()
    private weak var store: LibraryStore?
    private var session: AuthSession?
    private var state = SyncState()
    private var loop: Task<Void, Never>?
    var conflicts: [SyncConflict] { state.conflicts ?? [] }
    var configured: Bool { config != nil }
    init(store: LibraryStore) {
        self.store = store
        if let data = UserDefaults.standard.data(forKey: "cloud-state"), let saved = try? JSONDecoder().decode(SyncState.self, from: data) { state = saved }
        if let data = try? Keychain.read(), let saved = try? JSONDecoder().decode(AuthSession.self, from: data) { session = saved; signedIn = true }
        enabled = UserDefaults.standard.bool(forKey: "cloud-enabled")
        if !configured { status = "Supabase not configured · local storage" }
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if UIApplication.shared.applicationState == .active { await self?.sync() }
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
            }
        }
    }
    func authenticate(signup: Bool) async {
        guard !running else { return }
        running = true; defer { running = false; password = "" }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
            let data = try await request(signup ? "auth/v1/signup" : "auth/v1/token?grant_type=password", method: "POST", body: body, authenticated: false)
            guard var auth = try? JSONDecoder().decode(AuthSession.self, from: data) else {
                status = "Verify your email, then sign in."; return
            }
            auth.savedAt = Date(); try Keychain.write(JSONEncoder().encode(auth))
            session = auth; signedIn = true; status = "Signed in · link the library to sync"
        } catch { status = error.localizedDescription }
    }
    func signOut() {
        guard !running else { return }
        do { try Keychain.delete(); session = nil; signedIn = false; enabled = false; UserDefaults.standard.set(false, forKey: "cloud-enabled"); status = "Signed out · notebooks kept on this device" }
        catch { status = error.localizedDescription }
    }
    func bindAndSync() async {
        guard let session else { return }
        guard state.owner == nil || state.owner == session.user.id else { status = "This library is linked to another account. No data was sent."; return }
        state.owner = session.user.id
        do { try persistState(); enabled = true; UserDefaults.standard.set(true, forKey: "cloud-enabled"); await sync() }
        catch { status = error.localizedDescription }
    }
    func sync() async {
        guard configured, enabled, !running, let store, store.ready, let auth = session, state.owner == auth.user.id else { return }
        running = true; defer { running = false }
        status = "Syncing…"
        do {
            if auth.expired {
                let body = try JSONSerialization.data(withJSONObject: ["refresh_token": auth.refresh_token])
                let data = try await request("auth/v1/token?grant_type=refresh_token", method: "POST", body: body, authenticated: false)
                var renewed = try JSONDecoder().decode(AuthSession.self, from: data); renewed.savedAt = Date()
                try Keychain.write(JSONEncoder().encode(renewed)); session = renewed
            }
            let owner = session!.user.id
            var remote: [RemoteRevision] = []
            var offset = 0
            while true {
                let data = try await request("rest/v1/notebook_revisions?select=id,owner_id,notebook_id,parent_id,checksum,object_path&order=created_at.asc,id.asc&limit=500&offset=\(offset)")
                let batch = try JSONDecoder().decode([RemoteRevision].self, from: data)
                remote.append(contentsOf: batch)
                if batch.count < 500 { break }
                offset += batch.count
            }
            // Immutable remote revisions are imported as separate notebooks; local notes are never replaced.
            for revision in remote where !state.seen.contains(revision.id) {
                guard revision.owner_id == owner, revision.object_path.hasPrefix(owner.uuidString.lowercased() + "/") else { throw CocoaError(.fileReadNoPermission) }
                let archiveData = try await request("storage/v1/object/authenticated/notebooks/" + revision.object_path)
                let downloadedChecksum = await Task.detached(priority: .utility) { Self.checksum(archiveData) }.value
                guard downloadedChecksum == revision.checksum else { throw CocoaError(.fileReadCorruptFile) }
                var archive = try await Task.detached(priority: .utility) { try JSONDecoder().decode(NotebookArchive.self, from: archiveData) }.value
                let localKey = state.links.first { $0.value.remoteID == revision.notebook_id }?.key
                let conflict = localKey != nil
                if conflict { archive.note.title += " · remote revision" }
                let importedID = try await store.importArchive(archive)
                guard await store.flush() else { throw CocoaError(.fileWriteUnknown) }
                if let localKey, let localID = UUID(uuidString: localKey) {
                    state.conflicts = (state.conflicts ?? []) + [SyncConflict(localID: localID, remoteCopyID: importedID)]
                }
                // Copies have their own remote notebook ID if subsequently edited.
                let localArchive = try await store.archive(importedID)
                let checksum = try await Task.detached(priority: .utility) { Self.checksum(try Self.encode(localArchive)) }.value
                state.links[importedID.uuidString] = CloudLink(modifiedAt: localArchive.note.updatedAt, remoteID: importedID, revision: nil, checksum: checksum)
                state.seen.insert(revision.id); try persistState()
            }
            for note in store.library.notes {
                if let link = state.links[note.id.uuidString], link.modifiedAt == note.updatedAt { continue }
                let archive = try await store.archive(note.id)
                let (data, checksum) = try await Task.detached(priority: .utility) {
                    let data = try Self.encode(archive); return (data, Self.checksum(data))
                }.value
                let link = state.links[note.id.uuidString] ?? CloudLink(remoteID: note.id, revision: nil, checksum: "")
                if link.checksum == checksum {
                    state.links[note.id.uuidString]?.modifiedAt = note.updatedAt; try persistState(); continue
                }
                let revisionID = UUID()
                let path = "\(owner.uuidString.lowercased())/\(link.remoteID.uuidString.lowercased())/\(revisionID.uuidString.lowercased()).catnote"
                _ = try await request("storage/v1/object/notebooks/" + path, method: "POST", body: data, contentType: "application/octet-stream")
                let revision = RemoteRevision(id: revisionID, owner_id: owner, notebook_id: link.remoteID, parent_id: link.revision, checksum: checksum, object_path: path)
                _ = try await request("rest/v1/notebook_revisions", method: "POST", body: JSONEncoder().encode(revision))
                state.links[note.id.uuidString] = CloudLink(modifiedAt: note.updatedAt, remoteID: link.remoteID, revision: revisionID, checksum: checksum)
                state.seen.insert(revisionID); try persistState()
            }
            status = conflicts.isEmpty ? "Synced · \(Date().formatted(date: .omitted, time: .shortened))" : "\(conflicts.count) conflict(s) · choose revisions in Account and cloud"
        } catch { status = "Waiting to retry: \(error.localizedDescription)" }
    }
    func resolve(_ conflict: SyncConflict, keep: Int) {
        guard let store else { return }
        if keep == 1 { store.update(conflict.remoteCopyID) { $0.deletedAt = Date() } }
        if keep == 2 { store.update(conflict.localID) { $0.deletedAt = Date() } }
        state.conflicts?.removeAll { $0.id == conflict.id }
        do { try persistState(); status = "Choice saved · discarded revisions remain in Trash" }
        catch { status = error.localizedDescription }
        objectWillChange.send()
    }
    private func persistState() throws { UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: "cloud-state") }
    nonisolated static func encode(_ archive: NotebookArchive) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return try encoder.encode(archive) }
    nonisolated static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json", authenticated: Bool = true) async throws -> Data {
        guard let config, let url = URL(string: path, relativeTo: config.url.absoluteString.hasSuffix("/") ? config.url : config.url.appendingPathComponent("/")) else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if authenticated { guard let session else { throw URLError(.userAuthenticationRequired) }; request.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Supabase", code: code, userInfo: [NSLocalizedDescriptionKey: "Supabase HTTP \(code). Retry or sign in again."])
        }
        return data
    }
}

enum Keychain {
    // Retain the service identifier to preserve sessions across the product rename.
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "fr.catnotes.auth", kSecAttrAccount as String: "supabase"]
    static func read() throws -> Data? {
        var query = query; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return result as? Data
    }
    static func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = query; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        } else if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    static func delete() throws { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) } }
}
