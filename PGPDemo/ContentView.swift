import SwiftUI
import ObjectivePGP

/// Personal on-device demo. Nothing is sent off the phone.
struct ContentView: View {
    @StateObject private var model = DemoModel()

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This app uses the ObjectivePGP library already in this repository. It generates a key on the phone, encrypts the message, then decrypts it again.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Text("Message")
                    .font(.headline)
                TextEditor(text: $model.message)
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.4))
                    )
                    .disabled(model.isBusy)

                Button(action: model.run) {
                    if model.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Encrypt and decrypt on this phone")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.message.isEmpty)

                Text("Result")
                    .font(.headline)
                ScrollView {
                    Text(model.output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .navigationTitle("PGP Demo")
        }
        .navigationViewStyle(.stack)
    }
}

@MainActor
final class DemoModel: ObservableObject {
    @Published var message = "Hello from my iPhone"
    @Published var output = "Tap the button to generate a key, encrypt this message, and decrypt it on the phone."
    @Published var isBusy = false

    private var key: Key?

    func run() {
        let text = message
        isBusy = true
        output = key == nil
            ? "Generating a 2048-bit key on this phone. The first run can take a little while."
            : "Encrypting on this phone..."

        let existingKey = key
        Task.detached {
            do {
                let result = try Self.roundTrip(text, existingKey: existingKey)
                await MainActor.run {
                    self.key = result.key
                    self.output = result.text
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.output = "Failed: \(error.localizedDescription)"
                    self.isBusy = false
                }
            }
        }
    }

    private struct RoundTrip {
        let key: Key
        let text: String
    }

    private static func roundTrip(_ text: String, existingKey: Key?) throws -> RoundTrip {
        let key = existingKey ?? makeKey()
        guard let data = text.data(using: .utf8) else {
            throw DemoError.notUTF8
        }

        let encrypted = try ObjectivePGP.encrypt(data, addSignature: false, using: [key])
        let armored = Armor.armored(encrypted, as: .message)
        let decrypted = try ObjectivePGP.decrypt(encrypted, andVerifySignature: false, using: [key])
        let plain = String(data: decrypted, encoding: .utf8) ?? "(plaintext was not UTF-8)"

        let summary = """
        Key ID: \(key.keyID.longIdentifier)
        Decrypted: \(plain)

        Armored message:
        \(armored)
        """
        return RoundTrip(key: key, text: summary)
    }

    private static func makeKey() -> Key {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return generator.generate(for: "Phone Demo <demo@localhost>", passphrase: nil)
    }
}

private enum DemoError: LocalizedError {
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "The message could not be encoded as UTF-8."
        }
    }
}
