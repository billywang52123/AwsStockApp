import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    let onCompletion: () -> Void
    
    var body: some View {
        VStack {
            // Top Bar with Skip Button
            HStack {
                Spacer()
                if viewModel.currentPageIndex < viewModel.cards.count - 1 {
                    Button(action: {
                        viewModel.completeOnboarding()
                        onCompletion()
                    }) {
                        Text("略過")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "A9A49B"))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }
                } else {
                    Text("略過")
                        .font(.system(size: 14))
                        .foregroundColor(.clear)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
            
            Spacer()
            
            // Swipeable Cards container
            TabView(selection: $viewModel.currentPageIndex) {
                ForEach(0..<viewModel.cards.count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 20) {
                        // Card Icon Background & Emblem
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(getCardIconBg(index))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: getIconForCard(index))
                                .font(.system(size: 24))
                                .foregroundColor(getCardIconColor(index))
                        }
                        .padding(.bottom, 8)
                        
                        // Serif Header Text
                        Text(viewModel.cards[index].0)
                            .font(.system(size: 23, weight: .bold, design: .serif))
                            .foregroundColor(AppColor.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Body Text
                        Text(viewModel.cards[index].1)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                    .padding(32)
                    .frame(width: 296, height: 380)
                    .background(AppColor.cardBackground)
                    .cornerRadius(28)
                    .shadow(color: Color(hex: "786446").opacity(0.1), radius: 24, x: 0, y: 12)
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Disable default page dots
            .frame(height: 420)
            
            // Custom option A page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<viewModel.cards.count, id: \.self) { index in
                    Capsule()
                        .fill(viewModel.currentPageIndex == index ? AppColor.primary : Color(hex: "D8D3C8"))
                        .frame(width: viewModel.currentPageIndex == index ? 20 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.currentPageIndex)
                }
            }
            .padding(.vertical, 16)
            
            Spacer()
            
            // Bottom Action buttons
            VStack(spacing: 16) {
                if viewModel.currentPageIndex == viewModel.cards.count - 1 {
                    AppButton(title: "開始了解我的持股", icon: "arrow.right") {
                        viewModel.completeOnboarding()
                        onCompletion()
                    }
                    .padding(.horizontal, 24)
                } else {
                    AppButton(title: "下一步", icon: "arrow.right") {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            viewModel.currentPageIndex += 1
                        }
                        HapticManager.shared.triggerSelection()
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
    }
    
    private func getIconForCard(_ index: Int) -> String {
        switch index {
        case 0: return "chart.line.downtrend.xyaxis"
        case 1: return "doc.text.magnifyingglass"
        case 2: return "sparkles"
        default: return "sparkles"
        }
    }
    
    private func getCardIconBg(_ index: Int) -> Color {
        switch index {
        case 0: return Color(hex: "EEEEFA")
        case 1: return Color(hex: "EAF2EC")
        case 2: return Color(hex: "F4EFE4")
        default: return Color(hex: "EEEEFA")
        }
    }
    
    private func getCardIconColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color(hex: "7B7FD4")
        case 1: return Color(hex: "6E9A7F")
        case 2: return Color(hex: "E4B384")
        default: return Color(hex: "7B7FD4")
        }
    }
}
