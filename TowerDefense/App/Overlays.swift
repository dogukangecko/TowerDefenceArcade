import SwiftUI

/// Duraklatma menüsü — oyun ortasında devam/yeniden başlat/çıkış.
struct PauseOverlay: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                // commandPanel parşömeni açık renkli — başlık koyu mürekkep.
                Text("DURAKLATILDI")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.inkPrimary)
                Button(action: onResume) {
                    Label("Devam Et", systemImage: "play.fill")
                        .font(.system(.title3, design: .rounded).bold())
                        .frame(width: 200)
                }
                .buttonStyle(CommandButtonStyle(prominent: true))
                Button(action: onRestart) {
                    Label("Yeniden Başlat", systemImage: "arrow.counterclockwise")
                        .font(.system(.title3, design: .rounded).bold())
                        .frame(width: 200)
                }
                .buttonStyle(CommandButtonStyle())
                Button(action: onExit) {
                    Label("Ana Menü", systemImage: "house")
                        .font(.system(.title3, design: .rounded).bold())
                        .frame(width: 200)
                }
                .buttonStyle(CommandButtonStyle())
            }
            .padding(28)
            .commandPanel()
        }
    }
}

/// Kulesiz dalga başlatma onayı.
struct NoTowerConfirmOverlay: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Hiç kulen yok!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.danger)
                Text("Düşmanlar üssüne kadar yürür ve can kaybedersin.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 14) {
                    Button(action: onConfirm) {
                        Label("Yine de Başlat", systemImage: "play.fill")
                            .font(.system(.body, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle(prominent: true))
                    Button(action: onCancel) {
                        Text("Vazgeç")
                            .font(.system(.body, design: .rounded).bold())
                    }
                    .buttonStyle(CommandButtonStyle())
                }
            }
            .padding(26)
            .commandPanel()
            .padding(40)
        }
    }
}
