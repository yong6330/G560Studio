import Foundation

public struct AppRule: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var profileID: UUID
    public var enabled: Bool

    public init(id: UUID = UUID(), bundleID: String, appName: String, profileID: UUID, enabled: Bool = true) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.profileID = profileID; self.enabled = enabled
    }
}
