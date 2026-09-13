import SwiftUI
import G560Core
import UniformTypeIdentifiers

/// 프로필 + 그 프로필로 자동 전환되는 조건(시간·앱)을 한 곳에.
struct ProfilesTab: View {
    @Environment(AppState.self) var state
    @State private var confirmRestore = false
    @State private var showPicker = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var ioMessage: String?

    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    func addApp(bundleID: String, name: String) {
        guard !state.draftAppRules.contains(where: { $0.bundleID == bundleID }) else { return }
        let pid = state.store.activeID ?? state.store.profiles[0].id
        state.draftAppRules.append(AppRule(bundleID: bundleID, appName: name, profileID: pid))
        state.draftAppRulesEnabled = true
    }

    var body: some View {
        @Bindable var state = state
        Form {
            Section("프로필") {
                ForEach(state.store.profiles) { p in ProfileRow(profile: p) }
                LabeledContent("새 프로필") {
                    Button("현재 설정으로 만들기") {
                        var p = state.draft
                        p.id = UUID(); p.name = "프로필 \(state.store.profiles.count + 1)"
                        state.store.profiles.append(p); state.store.activeID = p.id
                        state.applied = p; state.draft = p
                        try? state.store.save()
                    }
                }
            }

            Section("시간 규칙") {
                Toggle("시간 규칙 사용", isOn: $state.draftScheduleEnabled)
                if state.store.scheduleEnabled, let r = Schedule.activeRule(state.store.schedule, at: Date()),
                   let p = state.store.profiles.first(where: { $0.id == r.profileID }) {
                    LabeledContent("적용 중") {
                        let from = state.store.profiles.first { $0.id == r.fromProfileID }?.name ?? "—"
                        Text("\(String(format: "%02d:%02d", r.hour, r.minute))   \(from) → \(p.name)").foregroundStyle(.secondary)
                    }
                }
                ForEach(state.draftSchedule) { r in
                    ScheduleRow(rule: scheduleBinding(r.id)) { } onDelete: { state.draftSchedule.removeAll { $0.id == r.id } }
                }
                LabeledContent("") {
                    Button("시간 규칙 추가") {
                        let pid = state.store.activeID ?? state.store.profiles[0].id
                        state.draftSchedule.append(ScheduleRule(hour: 22, minute: 0, fromProfileID: pid, profileID: pid))
                        state.draftScheduleEnabled = true
                    }
                }
            }

            Section("앱 규칙") {
                Toggle("앱 규칙 사용", isOn: $state.draftAppRulesEnabled)
                ForEach(state.draftAppRules) { r in
                    AppRuleRow(rule: appBinding(r.id)) { state.draftAppRules.removeAll { $0.id == r.id } }
                }
                LabeledContent("") {
                    Menu("앱 규칙 추가") {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) { addApp(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!) }
                        }
                        Divider()
                        Button("앱 파일 선택…") { showPicker = true }
                    }
                    .fixedSize()
                    .fileImporter(isPresented: $showPicker, allowedContentTypes: [.applicationBundle]) { r in
                        if case .success(let url) = r, let b = Bundle(url: url), let id = b.bundleIdentifier {
                            addApp(bundleID: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        }
                    }
                }
            }

            Section("백업") {
                LabeledContent("프로필과 규칙") {
                    HStack {
                        Button("내보내기…") { showExport = true }
                        Button("가져오기…") { showImport = true }
                    }
                }
                if let m = ioMessage { Text(m).font(.caption).foregroundStyle(.secondary) }
            }
            Section("장치") {
                LabeledContent("공장 초기값") {
                    Button("초기화…", role: .destructive) { confirmRestore = true }
                        .confirmationDialog("장치를 공장 초기값으로 되돌립니다.", isPresented: $confirmRestore) {
                            Button("초기화", role: .destructive) { state.restoreFactory() }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .fileExporter(isPresented: $showExport, document: JSONDocument(data: (try? state.store.exportData()) ?? Data()),
                      contentType: .json, defaultFilename: "G560Studio-profiles") { r in
            ioMessage = (try? r.get()) != nil ? "내보냈습니다." : "내보내기 실패"
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { r in
            do {
                let url = try r.get()
                guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { url.stopAccessingSecurityScopedResource() }
                try state.store.importData(try Data(contentsOf: url))
                state.discardChanges()
                ioMessage = "가져왔습니다: 프로필 \(state.store.profiles.count)개"
            } catch { ioMessage = "가져오기 실패: \(error.localizedDescription)" }
        }
    }

    func scheduleBinding(_ id: UUID) -> Binding<ScheduleRule> {
        Binding(get: { state.draftSchedule.first { $0.id == id } ?? ScheduleRule(hour: 0, minute: 0, profileID: id) },
                set: { r in if let i = state.draftSchedule.firstIndex(where: { $0.id == id }) { state.draftSchedule[i] = r } })
    }
    func appBinding(_ id: UUID) -> Binding<AppRule> {
        Binding(get: { state.draftAppRules.first { $0.id == id } ?? AppRule(bundleID: "", appName: "", profileID: id) },
                set: { r in if let i = state.draftAppRules.firstIndex(where: { $0.id == id }) { state.draftAppRules[i] = r } })
    }
}

/// 프로필 한 줄: 활성 뱃지 · 이름 · 보기 · 적용 · 삭제
struct ProfileRow: View {
    @Environment(AppState.self) var state
    let profile: Profile
    @FocusState private var editing: Bool
    var active: Bool { profile.id == state.store.activeID }
    var name: Binding<String> {
        Binding(get: { profile.name }, set: { n in
            if let i = state.store.profiles.firstIndex(where: { $0.id == profile.id }) { state.store.profiles[i].name = n }
        })
    }
    var body: some View {
        HStack(spacing: 10) {
            Text("활성").font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                .foregroundStyle(.white)
                .opacity(active ? 1 : 0)
            TextField("", text: name, prompt: Text("프로필 이름")).labelsHidden().textFieldStyle(.plain)
                .focused($editing)
                .onSubmit { try? state.store.save(); editing = false }          // Enter → 저장 + 커서 해제
                .onChange(of: editing) { _, on in if !on { try? state.store.save() } }   // 포커스 아웃 → 저장
            Spacer()
            ProfilePeekButton(profile: profile)
            Button("적용") { state.apply(profile) }.controlSize(.small).disabled(active && !state.hasChanges)
            Button { state.deleteProfile(profile.id) } label: { Image(systemName: "trash") }
                .controlSize(.small).disabled(state.store.profiles.count == 1)
        }
    }
}

/// "보기": 프로필 설정값 요약 팝오버 (변경 없이 확인만)
struct ProfilePeekButton: View {
    let profile: Profile
    @State private var show = false

    var lightingText: String {
        func pal(_ p: Palette) -> String {
            switch p { case .rainbow(let sp): return "레인보우 \(String(format: "%.2f", sp))"
                       case .custom(let z): return z.zones.map { "#" + $0.hex }.joined(separator: " ") }
        }
        switch profile.lighting {
        case .off: return "끄기"
        case .screenSampler(let o): return (o.audio ? "다이나믹 샘플러" : "화면 샘플러") + (o.display == nil ? "" : " · 디스플레이 \(o.display!)")
        case .fixed(let p): return "고정 · \(pal(p))"
        case .breathing(let p, let per): return "브리딩 \(String(format: "%.1f", per))초 · \(pal(p))"
        case .soundReactive(let p, let s, let b):
            let split = b == .none ? "" : (b == .bassRear ? " · 저음 뒤" : " · 저음 앞")
            return "사운드 반응 감도 \(String(format: "%.1f", s))\(split) · \(pal(p))"
        }
    }

    var body: some View {
        Button("보기") { show.toggle() }.controlSize(.small)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                        GridRow { Text("조명").foregroundStyle(.secondary); Text(lightingText) }
                        GridRow { Text("밝기").foregroundStyle(.secondary); Text("\(profile.brightness)") }
                        GridRow { Text("볼륨").foregroundStyle(.secondary); Text("\(Int((profile.volume * 100).rounded()))") }
                        GridRow { Text("서브우퍼").foregroundStyle(.secondary); Text("\(profile.woofer)") }
                        GridRow { Text("EQ").foregroundStyle(.secondary); Text(EQPresets.name(for: profile.eq) ?? "Custom") }
                    }
                }
                .padding(14)
                .frame(minWidth: 300, alignment: .leading)
            }
    }
}


/// fileExporter용 JSON 문서
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
