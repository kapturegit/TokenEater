import Foundation

/// The user-facing product name, in one place.
///
/// Read from the bundle first so the app's own UI can never drift from the
/// name macOS shows in the Dock, the menu bar and Notification Center - that
/// name comes from `CFBundleDisplayName`, which `project.yml` owns. The
/// literal is the fallback for the widget extension, whose Info.plist carries
/// no display name of its own.
///
/// Changing the product name means changing it in `project.yml` AND here.
/// The bundle identifier deliberately does NOT follow: it keys the shared
/// state directory, the widget registration and the Keychain items, so
/// renaming it would orphan every one of them.
enum AppBranding {
    static let fallbackName = "Token Kapturing"

    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackName
    }
}
