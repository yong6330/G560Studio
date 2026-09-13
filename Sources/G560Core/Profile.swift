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
                lighting: .soundReactive(.rainbow(speed: 0.05), sensitivity: 1.5, split: .none),
                volume: 0.2, woofer: 20,   // ponytail: 개발 중 고정(아파트). 배포 전 volume=OutputVolume.get(), woofer=factoryWoofer 로
                eq: G560.factoryEQ)
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
