import SwiftUI

/// 手写签名画板：采集笔画，导出 PNG base64
struct SignatureView: View {
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []

    var body: some View {
        NavigationView {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                    Canvas { context, size in
                        var path = Path()
                        for stroke in strokes + [current] {
                            guard let first = stroke.first else { continue }
                            path.move(to: first)
                            for p in stroke.dropFirst() { path.addLine(to: p) }
                        }
                        context.stroke(path, with: .color(.black), lineWidth: 3.5)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in current.append(v.location) }
                            .onEnded { _ in
                                if !current.isEmpty { strokes.append(current); current = [] }
                            }
                    )
                    if strokes.isEmpty && current.isEmpty {
                        Text("请在框内手写签名").foregroundColor(.gray)
                    }
                }
                .frame(height: 220).padding()

                HStack {
                    Button("清除") { strokes = []; current = [] }
                    Spacer()
                    Button("保存签名") {
                        let img = renderSignature()
                        onSave(img)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty && current.isEmpty)
                }.padding()
            }
            .navigationTitle("手写签名")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
            }
        }
    }

    private func renderSignature() -> String {
        let all = strokes + [current]
        let w: CGFloat = 600, h: CGFloat = 260
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let path = UIBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            for stroke in all {
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for p in stroke.dropFirst() { path.addLine(to: p) }
            }
            path.stroke()
        }
        return image.pngData()?.base64EncodedString() ?? ""
    }
}
