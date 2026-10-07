import Foundation

/// Profil-Kennung dieser Installation — trennt die Daten mehrerer Nutzer in
/// der Web-Ablage (recordings/<profil>/…). Wird einmalig in der App gesetzt.
enum Profile {
    private static let key = "profileId"

    static var id: String {
        get {
            UserDefaults.standard.string(forKey: key) ?? "benni"
        }
        set {
            UserDefaults.standard.set(sanitize(newValue), forKey: key)
        }
    }

    static func sanitize(_ raw: String) -> String {
        let cleaned = raw.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" }
        return cleaned.isEmpty ? "benni" : String(cleaned.prefix(24))
    }
}
