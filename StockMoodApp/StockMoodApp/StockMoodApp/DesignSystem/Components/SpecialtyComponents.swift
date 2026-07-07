import SwiftUI

// MARK: - Anxiety Score Ring
struct AnxietyScoreRing: View {
    let score: Int
    let level: String
    
    @State private var animateProgress: Double = 0.0
    
    private var ringColor: Color {
        if score <= 40 {
            return Color(hex: "6E9A7F") // Low: Calm/Success Green
        } else if score <= 70 {
            return Color(hex: "E4B384") // Medium: Warning Orange
        } else {
            return Color(hex: "D47B7B") // High: Danger Red
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background Circle (196pt)
                Circle()
                    .stroke(AppColor.textSecondary.opacity(0.1), lineWidth: 18)
                    .frame(width: 196, height: 196)
                
                // Foreground Progress (196pt)
                Circle()
                    .trim(from: 0.0, to: CGFloat(animateProgress))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [ringColor.opacity(0.6), ringColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .frame(width: 196, height: 196)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: animateProgress)
                
                // Central Text
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.textPrimary)
                    
                    Text("焦慮度")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            .onAppear {
                self.animateProgress = Double(score) / 100.0
            }
            .onChange(of: score) { _, newScore in
                self.animateProgress = Double(newScore) / 100.0
            }
            
            EmotionBadge(level: level)
                .padding(.top, 4)
        }
    }
}

// MARK: - Market Compare Card
struct MarketCompareCard: View {
    let result: MarketCompareResult
    
    private var isPortfolioUp: Bool { result.portfolioChangePercent >= 0 }
    private var isMarketUp: Bool { result.marketChangePercent >= 0 }
    
    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("大盤表現對比")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)
                
                HStack(spacing: 20) {
                    // Portfolio Change
                    VStack(alignment: .leading, spacing: 4) {
                        Text("我的持股")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                        
                        Text(String(format: "%@%.2f%%", isPortfolioUp ? "+" : "", result.portfolioChangePercent))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(isPortfolioUp ? AppColor.primary : AppColor.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Divider
                    Rectangle()
                        .fill(AppColor.textSecondary.opacity(0.2))
                        .frame(width: 1, height: 40)
                    
                    // Market Change
                    VStack(alignment: .leading, spacing: 4) {
                        Text("加權指數 (TAIEX)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                        
                        Text(String(format: "%@%.2f%%", isMarketUp ? "+" : "", result.marketChangePercent))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(isMarketUp ? AppColor.primary : AppColor.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Text(result.message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
        }
    }
}
