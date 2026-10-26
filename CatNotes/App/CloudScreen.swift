import SwiftUI

struct CloudScreen: View {
    @ObservedObject var cloud: CloudSync
    @Environment(\.dismiss) private var dismiss
    init(store: LibraryStore) { self.cloud = store.cloud }
    var body: some View {
        NavigationStack {
            Form {
                Section("Synchronisation Supabase") {
                    Text(cloud.status)
                    if !cloud.configured { Text("Ajoutez Config/Supabase.plist et appliquez la migration SQL. Les carnets restent disponibles hors ligne.") }
                    else if cloud.signedIn {
                        Button("Associer et synchroniser cette bibliothèque") { Task { await cloud.bindAndSync() } }
                        Button("Réessayer maintenant") { Task { await cloud.sync() } }
                        Button("Se déconnecter", role: .destructive) { cloud.signOut() }
                    } else {
                        TextField("E-mail", text: $cloud.email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Mot de passe", text: $cloud.password).textContentType(.password)
                        Button("Se connecter") { Task { await cloud.authenticate(signup: false) } }
                        Button("Créer un compte") { Task { await cloud.authenticate(signup: true) } }
                    }
                }.disabled(cloud.running)
                if !cloud.conflicts.isEmpty {
                    Section("Conflits conservés") {
                        ForEach(cloud.conflicts) { conflict in
                            VStack(alignment: .leading) {
                                Text("Version locale et copie distante préservées")
                                Button("Garder les deux") { cloud.resolve(conflict, keep: 0) }
                                Button("Garder la locale") { cloud.resolve(conflict, keep: 1) }
                                Button("Garder la distante") { cloud.resolve(conflict, keep: 2) }
                            }
                        }
                    }
                }
                Section { Text("Les versions distantes sont récupérées en copies distinctes. Aucune version locale n’est remplacée. L’app reprend les envois au retour au premier plan. Une bibliothèque est associée à un seul compte.").font(.caption) }
            }.navigationTitle("Compte et cloud").toolbar { Button("Fermer") { dismiss() } }
        }
    }
}
