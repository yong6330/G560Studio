import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var lighting: LightingConfig
    public var volume: Double          // 0…1
    public var woofer: Int             // 0…100
    public var eq: [Int]               // 10밴드 dB

    /// 장치 공장 초기값 (factory-defaults.json 실측: 우퍼 40, EQ flat) + 기본 조명(사운드 반응 레인보우).
    public static func factory() -> Profile {
        Profile(id: UUID(), name: "공장 초기값",
                lighting: .soundReactive(.rainbow(speed: 0.05), sensitivity: 1.5, split: .none),
                volume: 0.2,   // ponytail: 개발 중 고정. 배포 전 OutputVolume.get() ?? 0.3
                woofer: G560.factoryWoofer, eq: G560.factoryEQ)
    }

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
    public var schedule: [ScheduleRule] = []
    public var scheduleEnabled = false
    public var appRules: [AppRule] = []
    public var appRulesEnabled = false
    let url: URL

    private struct File: Codable {
        var profiles: [Profile]; var activeID: UUID?
        var schedule: [ScheduleRule]?; var scheduleEnabled: Bool?
        var appRules: [AppRule]?; var appRulesEnabled: Bool?
    }

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("G560Studio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    public init(url: URL = ProfileStore.defaultURL) {
        self.url = url
        if let raw = try? Data(contentsOf: url),
           let data = Self.migrate(raw),
           let f = try? JSONDecoder().decode(File.self, from: data), !f.profiles.isEmpty {
            profiles = f.profiles
            activeID = f.activeID ?? f.profiles[0].id
            schedule = f.schedule ?? []
            scheduleEnabled = f.scheduleEnabled ?? false
            appRules = f.appRules ?? []
            appRulesEnabled = f.appRulesEnabled ?? false
        } else {
            let p = Profile.makeDefault(name: "기본")
            profiles = [p]
            activeID = p.id
        }
    }

    /// 구버전 파일 호환: screenSampler 페이로드를 ScreenOptions 형태로 감싼다.
    static func migrate(_ data: Data) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]] else { return data }
        for i in profiles.indices {
            if var l = profiles[i]["lighting"] as? [String: Any], let ss = l["screenSampler"] as? [String: Any], ss["_0"] == nil {
                l["screenSampler"] = ["_0": ss]; profiles[i]["lighting"] = l
            }
        }
        root["profiles"] = profiles
        return try? JSONSerialization.data(withJSONObject: root)
    }

    public var active: Profile? { profiles.first { $0.id == activeID } }

    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(profiles: profiles, activeID: activeID, schedule: schedule, scheduleEnabled: scheduleEnabled,
                            appRules: appRules, appRulesEnabled: appRulesEnabled)).write(to: url, options: .atomic)
    }
}
