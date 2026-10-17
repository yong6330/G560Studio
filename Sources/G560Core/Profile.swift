import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var lighting: LightingConfig
    public var volume: Double          // 0…1
    public var woofer: Int             // 0…100
    public var eq: [Int]               // 10밴드 dB
    public var brightness: Int = 100   // 조명 밝기 0…100 (0x8040)

    enum CodingKeys: String, CodingKey { case id, name, lighting, volume, woofer, eq, brightness }
    public init(id: UUID, name: String, lighting: LightingConfig, volume: Double, woofer: Int, eq: [Int], brightness: Int = 100) {
        self.id = id; self.name = name; self.lighting = lighting; self.volume = OutputVolume.safe(volume); self.woofer = woofer; self.eq = eq; self.brightness = brightness
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        lighting = try c.decode(LightingConfig.self, forKey: .lighting); volume = OutputVolume.safe(try c.decode(Double.self, forKey: .volume))   // 저장된 0(뮤트 직전 값) 방지
        woofer = try c.decode(Int.self, forKey: .woofer); eq = try c.decode([Int].self, forKey: .eq)
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? 100
    }

    /// 장치 공장 초기값 (factory-defaults.json 실측: 우퍼 40, EQ flat) + 기본 조명(사운드 반응 레인보우).
    public static func factory() -> Profile {
        Profile(id: UUID(), name: "공장 초기값",
                lighting: .soundReactive(.rainbow(speed: 0.05), sensitivity: 1.5, split: .none),
                volume: OutputVolume.get() ?? 0.3, woofer: G560.factoryWoofer, eq: G560.factoryEQ)
    }

    public static func makeDefault(name: String) -> Profile {
        Profile(id: UUID(), name: name,
                lighting: .soundReactive(.rainbow(speed: 0.05), sensitivity: 1.5, split: .none),
                volume: OutputVolume.get() ?? 0.3, woofer: G560.factoryWoofer, eq: G560.factoryEQ)
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

    /// 전체(프로필+규칙)를 JSON으로 내보내기 / 가져오기. 가져오면 같은 id는 덮어쓰고 나머지는 추가.
    public func exportData() throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(File(profiles: profiles, activeID: activeID, schedule: schedule, scheduleEnabled: scheduleEnabled,
                                   appRules: appRules, appRulesEnabled: appRulesEnabled))
    }
    public mutating func importData(_ raw: Data) throws {
        guard let data = Self.migrate(raw) else { throw CocoaError(.fileReadCorruptFile) }
        let f = try JSONDecoder().decode(File.self, from: data)
        for p in f.profiles {
            if let i = profiles.firstIndex(where: { $0.id == p.id }) { profiles[i] = p } else { profiles.append(p) }
        }
        for r in f.schedule ?? [] where !schedule.contains(where: { $0.id == r.id }) { schedule.append(r) }
        for r in f.appRules ?? [] where !appRules.contains(where: { $0.id == r.id }) { appRules.append(r) }
        try save()
    }

    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(File(profiles: profiles, activeID: activeID, schedule: schedule, scheduleEnabled: scheduleEnabled,
                            appRules: appRules, appRulesEnabled: appRulesEnabled)).write(to: url, options: .atomic)
    }
}
