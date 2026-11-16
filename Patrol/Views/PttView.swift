import SwiftUI

/// 对讲页：iOS 无悬浮窗，改为全屏/Present 的对讲界面，按住说话。
struct PttView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ptt = PttService.shared
    @State private var talking = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(talking ? Color.orange : Color(hex: 0x1B5E20))
                        .frame(width: 140, height: 140)
                        .shadow(radius: 8)
                    VStack {
                        Image(systemName: talking ? "waveform.circle.fill" : "radio.fill")
                            .font(.system(size: 50)).foregroundColor(.white)
                        Text(talking ? "讲话中" : "按住说话")
                            .foregroundColor(.white).font(.headline)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !talking { talking = true; ptt.startTalk() } }
                        .onEnded { _ in talking = false; ptt.stopTalk() }
                )

                VStack(spacing: 8) {
                    Text(ptt.status.rawValue).font(.subheadline).foregroundColor(.secondary)
                    if !ptt.speakerName.isEmpty {
                        Text("🎧 \(ptt.speakerName) 正在讲话…").foregroundColor(.green)
                    }
                    if !ptt.message.isEmpty { Text(ptt.message).font(.caption).foregroundColor(.orange) }
                }

                Text("提示：iOS 不支持悬浮窗，请保持本页打开进行对讲；切到其他 App 时仅能收听。")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)

                Spacer()
            }
            .navigationTitle("对讲机")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } }
            }
        }
        .onAppear { ptt.connect() }
    }
}
