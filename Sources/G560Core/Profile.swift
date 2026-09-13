import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var lighting: LightingConfig
    public var volume: Double          // 0…1
    public var woofer: Int             // 0…100
    public var eq: [Int]               // 10밴드 dB

    public static func makeDefault(name: String) -> Profile {
        Profile(id: UUID(), name: name,
                lighting: .soundReactive(ZoneColors(all: RGB(255, 255, 255)), sensitivity: 1.5, splitBands: false),
                volume: OutputVolume.get() ?? 0.3,   // 현재 시스템 볼륨 그대로 — 갑자기 커지지 않게
                woofer: G560.factoryWoofer, eq: G560.factoryEQ)
    }
}

/// profiles.json 하나. 파일이 없거나 깨지면 기본 프로필 1개로 시작.
public struct ProfileStore {
    public var profiles: [Profile]
    public var activeID: UUID?
    let url: URL

    private struct File: Codable { var profiles: [Profile]; var activeID: UUID? }

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("G560Studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    public init(url: URL = ProfileStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let f = try? JSONDecoder().decode(File.self, from: data), !f.profiles.isEmpty {
            profiles = f.profiles
            activeID = f.activeID ?? f.profiles[0].id
        } else {
            let p = Profile.makeDefault(name: "기본")
            profiles = [p]
            activeID = p.id
        }
    }

    public var active: Profile? { profiles.first { $0.id == activeID } }

    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(profiles: profiles, activeID: activeID)).write(to: url, options: .atomic)
    }
}
