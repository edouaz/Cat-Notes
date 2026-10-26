import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private var importing = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        message.numberOfLines = 0; message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body); message.adjustsFontForContentSizeCategory = true
        let done = UIButton(type: .system)
        done.setTitle("Terminé", for: .normal); done.addTarget(self, action: #selector(finish), for: .touchUpInside)
        retry.setTitle("Réessayer", for: .normal); retry.addTarget(self, action: #selector(receive), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, retry, done]); stack.axis = .vertical; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor), done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
        receive()
    }
    private var completed: Set<Int> = []
    @objc private func receive() {
        guard !importing else { return }; importing = true; retry.isHidden = true
        message.text = "Préparation de l’import…"
        Task { @MainActor in
            defer { importing = false }
            do {
                let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
                guard !providers.isEmpty else { throw CocoaError(.fileReadUnknown) }
                for (index, provider) in providers.enumerated() where !completed.contains(index) {
                    guard let type = provider.registeredTypeIdentifiers.first(where: { identifier in
                        guard let type = UTType(identifier) else { return identifier == "fr.catnotes.notebook" }
                        return type.conforms(to: .pdf) || type.conforms(to: .image) || identifier == "fr.catnotes.notebook"
                    }) else { throw CocoaError(.fileReadUnknown) }
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                            do {
                                if let error { throw error }
                                guard let url else { throw CocoaError(.fileReadUnknown) }
                                // The provider URL expires when this callback returns.
                                try ShareInbox.enqueue(url)
                                continuation.resume()
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                    completed.insert(index)
                }
                message.text = "Prêt. Ouvrez CatNotes pour retrouver vos documents dans des onglets."
            } catch { message.text = "Import impossible : \(error.localizedDescription)"; retry.isHidden = false }
        }
    }
    @objc private func finish() { guard !importing else { return }; extensionContext?.completeRequest(returningItems: nil) }
}
