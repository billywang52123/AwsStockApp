import SwiftUI

// MARK: - App Button
struct AppButton: View {
    let title: String
    var icon: String? = nil
    var backgroundColor: Color = AppColor.primary
    var textColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.triggerSelection()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(textColor)
            .cornerRadius(16)
            .shadow(color: backgroundColor.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - App Card
struct AppCard<Content: View>: View {
    var backgroundColor: Color = AppColor.cardBackground
    let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(20)
        .background(backgroundColor)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Emotion Badge
struct EmotionBadge: View {
    let level: String
    
    var color: Color {
        switch level {
        case "穩定": return AppColor.secondary
        case "有點波動": return Color(hex: "85C1E9")
        case "有點緊張": return AppColor.warning
        case "焦慮偏高": return Color(hex: "E59866")
        case "需要冷靜一下": return AppColor.danger
        default: return AppColor.primary
        }
    }
    
    var body: some View {
        Text(level)
            .font(.system(.caption, design: .rounded))
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Explanation Block
struct ExplanationBlock: View {
    let title: String
    let content: String
    var systemIcon: String = "info.circle"
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemIcon)
                .font(.title3)
                .foregroundColor(AppColor.primary)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)
                
                Text(content)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .background(AppColor.primary.opacity(0.05))
        .cornerRadius(16)
    }
}

// MARK: - Disclaimer View
struct DisclaimerView: View {
    var body: some View {
        Text("內容僅供資訊參考，不構成投資建議。")
            .font(.system(.caption, design: .rounded))
            .foregroundColor(AppColor.textSecondary.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(.top, 16)
            .padding(.horizontal, 16)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(AppColor.textSecondary.opacity(0.5))
            
            Text(title)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(AppColor.textPrimary)
            
            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            AppButton(title: buttonTitle, icon: "plus", action: action)
                .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - Error State View
struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(AppColor.danger)
            
            Text("連線或處理發生問題")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
            
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            AppButton(title: "重新整理", icon: "arrow.clockwise", action: retryAction)
                .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColor.primary))
                
                Text(message)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(AppColor.cardBackground)
            .cornerRadius(24)
            .shadow(radius: 20)
            .padding(40)
        }
    }
}
