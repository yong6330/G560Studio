import SwiftUI
import G560Core

struct ProfilesTab: View {
    @Environment(AppState.self) var state
    @State private var confirmRestore = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section("프로필") {
                ForEach(state.store.profiles) { p in
                    let active = p.id == state.store.activeID
                    // ponytail: $binding ForEach 는 삭제 시 인덱스 크래시 → id 기반 바인딩
                    let name = Binding(get: { p.name }, set: { n in
                        if let i = state.store.profiles.firstIndex(where: { $0.id == p.id }) { state.store.profiles[i].name = n }
                    })
                    HStack(spacing: 10) {
                        Text("활성").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                            .foregroundStyle(.white)
                            .opacity(active ? 1 : 0)
                        TextField("", text: name, prompt: Text("프로필 이름")).labelsHidden().textFieldStyle(.plain).onSubmit { try? state.store.save() }
                        Spacer()
                        ProfilePeekButton(profile: p)
                        Button("적용") { state.apply(p) }.controlSize(.small).disabled(active && !state.hasChanges)
                        Button { state.deleteProfile(p.id) } label: { Image(systemName: "trash") }
                        .controlSize(.small).disabled(state.store.profiles.count == 1)
                    }
                }
            }
            Section {
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
            Section("장치") {
                LabeledContent("공장 초기값") {
                    Button("초기화…", role: .destructive) { confirmRestore = true }
                        .confirmationDialog("장치를 공장 초기값으로 되돌립니다.",
                                            isPresented: $confirmRestore) {
                            Button("초기화", role: .destructive) { state.restoreFactory() }
                        }
                }
            }
        }
        .formStyle(.grouped)
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
                        GridRow { Text("볼륨").foregroundStyle(.secondary); Text("\(Int((profile.volume * 100).rounded()))") }
                        GridRow { Text("서브우퍼").foregroundStyle(.secondary); Text("\(profile.woofer)") }
                        GridRow {
                            Text("EQ").foregroundStyle(.secondary)
                            Text(EQPresets.name(for: profile.eq) ?? "Custom")
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: 300, alignment: .leading)
            }
    }
}
