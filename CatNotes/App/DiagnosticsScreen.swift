import SwiftUI
import Darwin

struct DiagnosticsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("debugLogging") private var enabled = true
    @State private var exporting = false
    @State private var share: ShareFile?
    @State private var error: String?
    @State private var clearing = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Mode diagnostic") {
                    Toggle("Enregistrer les événements", isOn: $enabled)
                        .onChange(of: enabled) { Diagnostics.shared.setEnabled($0) }
                    Text("Activé par défaut pour cette version de test. Conserve localement démarrage, navigation, sauvegardes, erreurs et réglages techniques. Aucun texte, image, nom de carnet ou trait manuscrit n’est enregistré.").font(.footnote)
                }
                Section("Partager un problème") {
                    Button { Task { await export() } } label: { Label(exporting ? "Préparation…" : "Exporter les logs / AirDrop", systemImage: "square.and.arrow.up") }.disabled(exporting)
                    Text("Reproduisez le problème, puis exportez le fichier JSON et choisissez AirDrop ou Enregistrer dans Fichiers. Les événements récents sont conservés après relancement ; aucun envoi automatique.").font(.footnote)
                    Text("Après un crash natif, joignez aussi le rapport CatNotes .ips dans Réglages iPad → Confidentialité et sécurité → Analyse et améliorations → Données d’analyse. Les logs décrivent le parcours, sans remplacer la pile du crash.").font(.footnote)
                }
                Section("Stockage local") {
                    Text("Journal tournant limité à environ 1 Mo. Les derniers événements peuvent manquer après une interruption brutale.").font(.footnote)
                    Button("Effacer les logs", role: .destructive) { clearing = true }
                }
            }.navigationTitle("Diagnostic").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Fermer") { dismiss() } }
                .sheet(item: $share) { ActivitySheet(url: $0.url) }
                .alert("Diagnostic", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
                .confirmationDialog("Effacer les logs locaux ?", isPresented: $clearing, titleVisibility: .visible) {
                    Button("Effacer", role: .destructive) { Task { do { try await Diagnostics.shared.clear() } catch { self.error = error.localizedDescription } } }
                }
        }
    }
    private func export() async {
        exporting = true; defer { exporting = false }
        var system = utsname(); uname(&system)
        let machine = withUnsafePointer(to: &system.machine) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        let defaults = UserDefaults.standard
        let metadata = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                        "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                        "bundle": Bundle.main.bundleIdentifier ?? "?", "os": UIDevice.current.systemVersion,
                        "machine": machine, "toolbar": "CatNotes",
                        "fingerDrawing": String(defaults.bool(forKey: "fingerDrawing")), "verticalPaging": String(defaults.bool(forKey: "verticalPaging")),
                        "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled)]
        Diagnostics.shared.record("diagnostics.export")
        do { share = ShareFile(url: try await Diagnostics.shared.export(metadata: metadata)) }
        catch { self.error = error.localizedDescription }
    }
}
