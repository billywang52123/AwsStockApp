import SwiftUI

struct Achievement: Codable, Identifiable {
    var id: String { achievementKey }
    let achievementKey: String
    let title: String
    let description: String
    let iconName: String
    var category: String? = nil
    var categoryName: String? = nil
    var rarity: String? = nil
    var isHidden: Bool? = nil
    let isUnlocked: Bool
    let unlockedAt: String?
}

struct AchievementListView: View {
    @State private var achievements: [Achievement] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // Grid columns layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    // Preserve the catalog's category order
    private var groupedCategories: [(name: String, items: [Achievement])] {
        var order: [String] = []
        var groups: [String: [Achievement]] = [:]
        for ach in achievements {
            let name = ach.categoryName ?? "其他成就"
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(ach)
        }
        return order.map { (name: $0, items: groups[$0] ?? []) }
    }

    private var unlockedCount: Int { achievements.filter { $0.isUnlocked }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("持股焦慮成就")
                    .font(.system(.title2, design: .serif))
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.textPrimary)
                    .padding(.top, 16)

                Text("從「睡得著嗎」到「市場傳說」——每一種市場心情，都值得一枚徽章。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                    .lineSpacing(4)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("正在讀取成就卡...")
                            .padding(.vertical, 40)
                        Spacer()
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(AppColor.danger)
                        Text(error)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                        Button("重試") {
                            Task { await loadAchievements() }
                        }
                        .foregroundColor(AppColor.primary)
                        .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    progressHeader

                    ForEach(groupedCategories, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(group.name)
                                    .font(.system(.headline, design: .serif))
                                    .foregroundColor(AppColor.textPrimary)

                                Spacer()

                                Text("\(group.items.filter { $0.isUnlocked }.count)/\(group.items.count)")
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColor.textSecondary)
                            }
                            .padding(.top, 8)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(group.items) { ach in
                                    AchievementCardView(achievement: ach)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
        .navigationTitle("我的成就")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadAchievements()
            }
        }
    }

    private var progressHeader: some View {
        let total = max(achievements.count, 1)
        let ratio = Double(unlockedCount) / Double(total)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("解鎖進度")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.textPrimary)

                Spacer()

                Text("\(unlockedCount) / \(achievements.count)")
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.primary.opacity(0.1))
                    Capsule()
                        .fill(AppColor.primary)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color(hex: "786446").opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private func loadAchievements() async {
        isLoading = true
        errorMessage = nil

        do {
            let list: [Achievement] = try await APIClient.shared.request("/achievements")
            await MainActor.run {
                self.achievements = list
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "無法連線至伺服器 (\(error.localizedDescription))"
                self.isLoading = false
            }
        }
    }
}

// MARK: - Achievement Card View
struct AchievementCardView: View {
    let achievement: Achievement

    private var style: RarityStyle { RarityStyle.of(achievement.rarity) }

    var body: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? style.color.opacity(0.12) : Color.gray.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: achievement.iconName)
                    .font(.title2)
                    .foregroundColor(achievement.isUnlocked ? style.color : .gray)

                if !achievement.isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.gray)
                        .clipShape(Circle())
                        .offset(x: 18, y: 18)
                }
            }
            .padding(.top, 8)

            // Text Title
            Text(achievement.title)
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(achievement.isUnlocked ? AppColor.textPrimary : AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Rarity chip
            Text(style.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(achievement.isUnlocked ? style.color : .gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background((achievement.isUnlocked ? style.color : Color.gray).opacity(0.1))
                .cornerRadius(6)

            // Description
            Text(achievement.description)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(height: 44)

            Divider()

            // Unlock Status Label
            if achievement.isUnlocked {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "6E9A7F"))

                    Text(achievement.unlockedAt.map { "已達成 \($0)" } ?? "已達成")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "6E9A7F"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("尚未解鎖")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(AppColor.cardBackground)
        .cornerRadius(18)
        .shadow(
            color: Color(hex: "786446").opacity(achievement.isUnlocked ? 0.05 : 0.01),
            radius: 8,
            x: 0,
            y: 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(achievement.isUnlocked ? style.color.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(achievement.isUnlocked ? 1.0 : 0.65)
    }
}
