import SwiftUI

struct CloudScreen: View {
    @ObservedObject var cloud: CloudSync
    @Environment(\.dismiss) private var dismiss
    init(store: LibraryStore) { self.cloud = store.cloud }
    var body: some View {
        NavigationStack {
            Form {
                Section("Supabase sync") {
                    Text(cloud.status)
                    if !cloud.configured { Text("Add Config/Supabase.plist and apply the SQL migration. Notebooks remain available offline.") }
                    else if cloud.signedIn {
                        Button("Link and sync this library") { Task { await cloud.bindAndSync() } }
                        Button("Retry now") { Task { await cloud.sync() } }
                        Button("Sign out", role: .destructive) { cloud.signOut() }
                    } else {
                        TextField("E-mail", text: $cloud.email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $cloud.password).textContentType(.password)
                        Button("Sign in") { Task { await cloud.authenticate(signup: false) } }
                        Button("Create account") { Task { await cloud.authenticate(signup: true) } }
                    }
                }.disabled(cloud.running)
                if !cloud.conflicts.isEmpty {
                    Section("Preserved conflicts") {
                        ForEach(cloud.conflicts) { conflict in
                            VStack(alignment: .leading) {
                                Text("Local revision and remote copy preserved")
                                Button("Keep both") { cloud.resolve(conflict, keep: 0) }
                                Button("Keep local") { cloud.resolve(conflict, keep: 1) }
                                Button("Keep remote") { cloud.resolve(conflict, keep: 2) }
                            }
                        }
                    }
                }
                Section { Text("Remote revisions are downloaded as separate copies. Local revisions are never replaced. Uploads resume when the app returns to the foreground. A library is linked to one account.").font(.caption) }
            }.navigationTitle("Account and cloud").toolbar { Button("Close") { dismiss() } }
        }
    }
}
