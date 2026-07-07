import SwiftUI
import Combine

struct CardDrawView: View {
    @StateObject private var viewModel = CardDrawViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    Text("每日情緒陪伴卡")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.top, 10)
                    
                    Spacer()
                    
                    // Card Visual Container
                    ZStack {
                        if let card = viewModel.cardResult {
                            CardFrontView(card: card) {
                                viewModel.resetCard()
                            }
                            .opacity(viewModel.isFlipped ? 1 : 0)
                        }
                        
                        CardBackViewView()
                            .opacity(viewModel.isFlipped ? 0 : 1)
                    }
                    .frame(width: 300, height: 450)
                    .rotation3DEffect(
                        .degrees(viewModel.isFlipped ? 180 : 0),
                        axis: (x: 0.0, y: 1.0, z: 0.0),
                        perspective: 0.4
                    )
                    .onTapGesture {
                        if !viewModel.isFlipped && !viewModel.isLoading {
                            HapticManager.shared.triggerSelection()
                            Task {
                                await viewModel.drawCard()
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if !viewModel.isFlipped {
                        Text("點擊卡片，翻開今日的專屬陪伴訊息")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                            .padding(.bottom, 30)
                    } else {
                        DisclaimerView()
                            .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 20)
                
                if viewModel.isLoading {
                    LoadingOverlay(message: "正在尋找今天的陪伴卡...")
                }
            }
            .navigationTitle("每日抽卡")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await viewModel.loadCardStatus()
                }
            }
        }
    }
}

// MARK: - Card Back View (Option 1a 暖陽米杏 style)
struct CardBackViewView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Premium graphic motif
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    .frame(width: 110, height: 110)
                
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 88, height: 88)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 12) {
                Text("股感安心卡")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundColor(.white.opacity(0.95))
                    .tracking(8)
                
                Text("每天看懂你的股票情緒")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
            
            Spacer()
            
            Text("點擊翻牌")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .foregroundColor(.white)
                .cornerRadius(99)
                .padding(.bottom, 36)
        }
        .frame(width: 300, height: 450)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "8B8FDD"), Color(hex: "6C70C4")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(32)
        .shadow(color: Color(hex: "7B7FD4").opacity(0.25), radius: 36, x: 0, y: 18)
    }
}

// MARK: - Card Front View (Option 1a 暖陽米杏 style)
struct CardFrontView: View {
    let card: DrawCardResult
    let onReset: () -> Void

    @State private var showFullMessage = false
    // Fits comfortably inside the fixed 300×450 card; longer text gets 查看全部
    private let messageLineLimit = 7

    // Style configurations based on cardType
    private var cardColor: Color {
        switch card.cardType {
        case .calmObserve: return Color(hex: "6E9A7F")
        case .confidenceRestore: return Color(hex: "7B7FD4")
        case .marketImpact: return Color(hex: "E4B384")
        case .volatilityAlert: return Color(hex: "E59866")
        case .stockEvent: return Color(hex: "D47B7B")
        }
    }
    
    private var cardIconBg: Color {
        switch card.cardType {
        case .calmObserve: return Color(hex: "EAF2EC")
        case .confidenceRestore: return Color(hex: "EEEEFA")
        case .marketImpact: return Color(hex: "F4EFE4")
        case .volatilityAlert: return Color(hex: "FDF2E9")
        case .stockEvent: return Color(hex: "FCEAEA")
        }
    }
    
    private var cardIcon: String {
        switch card.cardType {
        case .calmObserve: return "eye.fill"
        case .confidenceRestore: return "heart.fill"
        case .marketImpact: return "globe.asia.australia.fill"
        case .volatilityAlert: return "waveform.path.ecg"
        case .stockEvent: return "exclamationmark.triangle.fill"
        }
    }
    
    private var cardCategoryText: String {
        switch card.cardType {
        case .calmObserve: return "冷靜觀察"
        case .confidenceRestore: return "信心恢復"
        case .marketImpact: return "大盤影響"
        case .volatilityAlert: return "小心震盪"
        case .stockEvent: return "個股事件"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Card Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(cardIconBg)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: cardIcon)
                        .font(.system(size: 22))
                        .foregroundColor(cardColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundColor(AppColor.textPrimary)
                    
                    Text(cardCategoryText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(cardColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(cardIconBg)
                        .cornerRadius(6)
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color(hex: "E6E5DF"))
            
            Spacer()
            
            // Detailed message translated for beginners
            Text(card.message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .lineSpacing(10)
                .multilineTextAlignment(.leading)
                .lineLimit(messageLineLimit)
                .padding(.horizontal, 6)

            if isMessageLikelyTruncated {
                Button {
                    HapticManager.shared.triggerSelection()
                    showFullMessage = true
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(cardColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(cardIconBg)
                    .cornerRadius(99)
                }
            }

            Spacer()
            
            // Test reset helper
            Button(action: onReset) {
                Text("重新抽卡 (測試)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.textSecondary.opacity(0.5))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(8)
            }
            .padding(.bottom, 8)
        }
        // Rotate 180 degrees back so contents aren't mirrored when flipped
        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        .padding(28)
        .frame(width: 300, height: 450)
        .background(AppColor.cardBackground)
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(cardColor.opacity(0.2), lineWidth: 3)
        )
        .shadow(color: Color(hex: "786446").opacity(0.08), radius: 28, x: 0, y: 14)
        .sheet(isPresented: $showFullMessage) {
            CardMessageDetailSheet(
                title: card.title,
                categoryText: cardCategoryText,
                icon: cardIcon,
                color: cardColor,
                iconBg: cardIconBg,
                message: card.message
            )
        }
    }

    /// Rough estimate of whether the message overflows the line limit.
    /// ~14 CJK characters fit per line at 16pt inside the 300pt-wide card.
    private var isMessageLikelyTruncated: Bool {
        card.message.count > messageLineLimit * 14
    }
}

// MARK: - Full message sheet (查看全部)
struct CardMessageDetailSheet: View {
    let title: String
    let categoryText: String
    let icon: String
    let color: Color
    let iconBg: Color
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(iconBg)
                            .frame(width: 48, height: 48)

                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(AppColor.textPrimary)

                        Text(categoryText)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(iconBg)
                            .cornerRadius(6)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(AppColor.textSecondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Divider()
                    .background(Color(hex: "E6E5DF"))
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                // Full message
                ScrollView {
                    Text(message)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(AppColor.textPrimary)
                        .lineSpacing(11)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }

                DisclaimerView()
                    .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
