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
                        TextField("이름", text: name).textFieldStyle(.plain).onSubmit { try? state.store.save() }
                        Spacer()
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
                        state.applied = p
                        try? state.store.save()
                    }
                }
                LabeledContent("저장") {
                    Text("하단 '동기화'가 활성 프로필에 저장합니다").font(.caption).foregroundStyle(.secondary)
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
