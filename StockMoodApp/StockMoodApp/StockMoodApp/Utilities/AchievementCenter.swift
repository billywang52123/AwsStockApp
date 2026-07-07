import SwiftUI
import Combine

// MARK: - Rarity styling shared by the list & unlock popup
struct RarityStyle {
    let label: String
    let color: Color

    static func of(_ rarity: String?) -> RarityStyle {
        switch rarity {
        case "rare": return RarityStyle(label: "稀有", color: AppColor.primary)
        case "epic": return RarityStyle(label: "史詩", color: Color(hex: "E59866"))
        case "legendary": return RarityStyle(label: "傳說", color: Color(hex: "D4A24E"))
        case "hidden": return RarityStyle(label: "隱藏", color: Color(hex: "3A3733"))
        default: return RarityStyle(label: "普通", color: AppColor.secondary)
        }
    }
}

// MARK: - Achievement Center
// Central point that asks the backend to re-evaluate achievement conditions
// and queues newly unlocked ones for the celebration popup.
@MainActor
final class AchievementCenter: ObservableObject {
    static let shared = AchievementCenter()

    @Published var pendingUnlocks: [Achievement] = []

    private var isEvaluating = false

    private init() {}

    /// Call after any action that could change achievement state
    /// (dashboard load, portfolio save, OCR import).
    func evaluate() {
        guard !isEvaluating else { return }
        isEvaluating = true

        Task {
            defer { isEvaluating = false }
            do {
                let newly: [Achievement] = try await APIClient.shared.request("/achievements/evaluate", method: "POST")
                guard !newly.isEmpty else { return }
                pendingUnlocks.append(contentsOf: newly)
                HapticManager.shared.triggerNotification(type: .success)
            } catch {
                print("Achievement evaluate failed: \(error)")
            }
        }
    }

    func dismissPopup() {
        pendingUnlocks = []
    }
}

// MARK: - Unlock celebration popup
struct AchievementUnlockView: View {
    let achievements: [Achievement]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Celebration header
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppColor.warning.opacity(0.15))
                            .frame(width: 84, height: 84)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "D4A24E"))
                    }
                    .padding(.top, 28)

                    Text("成就達成！")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundColor(AppColor.textPrimary)

                    Text(achievements.count == 1
                         ? "你解鎖了 1 個新成就"
                         : "你一口氣解鎖了 \(achievements.count) 個新成就")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(achievements) { ach in
                            unlockCard(ach)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                Button(action: {
                    HapticManager.shared.triggerImpact(style: .medium)
                    onDismiss()
                }) {
                    Text("太好了")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppColor.primary)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func unlockCard(_ ach: Achievement) -> some View {
        let style = RarityStyle.of(ach.rarity)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(style.color.opacity(0.12))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(style.color.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                Image(systemName: ach.iconName)
                    .font(.system(size: 22))
                    .foregroundColor(style.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ach.title)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.textPrimary)

                    Text(style.label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(style.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(style.color.opacity(0.12))
                        .cornerRadius(6)
                }

                Text(ach.description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(14)
        .background(AppColor.cardBackground)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(style.color.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: style.color.opacity(0.08), radius: 10, x: 0, y: 5)
    }
}
