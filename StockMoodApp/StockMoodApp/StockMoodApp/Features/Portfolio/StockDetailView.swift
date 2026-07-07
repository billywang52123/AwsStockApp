import SwiftUI

struct StockDetailView: View {
    let symbol: String
    let name: String
    
    @StateObject private var viewModel: StockDetailViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showAIAnalysisSheet = false
    
    init(symbol: String, name: String) {
        self.symbol = symbol
        self.name = name
        self._viewModel = StateObject(wrappedValue: StockDetailViewModel(symbol: symbol, name: name))
    }
    
    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)
            
            if viewModel.isLoading {
                ProgressView("正在分析個股數據...")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Header Stats Card
                        AppCard {
                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(name)
                                            .font(.system(.title2, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundColor(AppColor.textPrimary)
                                        
                                        Text(symbol)
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundColor(AppColor.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if let price = viewModel.dailyPrice {
                                        let isUp = price.changePercent >= 0
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(String(format: "$%.2f", price.closePrice))
                                                .font(.system(.title2, design: .rounded).monospacedDigit())
                                                .fontWeight(.bold)
                                                .foregroundColor(AppColor.textPrimary)

                                            Text(String(format: "%@%.2f%%", isUp ? "+" : "", price.changePercent))
                                                .font(.system(.body, design: .rounded).monospacedDigit())
                                                .fontWeight(.bold)
                                                .foregroundColor(isUp ? AppColor.primary : AppColor.danger)
                                        }
                                    }
                                }

                                if let price = viewModel.dailyPrice {
                                    HStack {
                                        Spacer()
                                        Text("資料日期 \(price.tradeDate.formatted(.dateTime.month().day()))")
                                            .font(.system(.caption2, design: .rounded))
                                            .foregroundColor(AppColor.textSecondary.opacity(0.7))
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 8)

                                HStack {
                                    Text("對焦慮分數的影響")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)

                                    Spacer()

                                    impactBadge
                                }
                            }
                        }
                        
                        // Explanation block
                        ExplanationBlock(
                            title: "白話狀態翻譯器",
                            content: viewModel.explanation,
                            systemIcon: "character.bubble.fill"
                        )
                        
                        // AI 專家白話分析 按鈕 (以漸層發光卡片形式展現)
                        Button(action: {
                            showAIAnalysisSheet = true
                            Task {
                                await viewModel.fetchAIAnalysis()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.white)
                                Text("AI 專家白話分析")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(hex: "7B7FD4"), Color(hex: "9094E2")]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color(hex: "7B7FD4").opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .padding(.top, 4)
                        
                        // Recommendations
                        if !viewModel.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("關聯股票推薦")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundColor(AppColor.textPrimary)
                                    .padding(.horizontal, 4)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(viewModel.recommendations) { rec in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(rec.name)
                                                    .font(.system(.subheadline, design: .rounded))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColor.textPrimary)
                                                    .lineLimit(1)

                                                Text(rec.symbol)
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundColor(AppColor.textSecondary)

                                                if let industry = rec.industry, !industry.isEmpty {
                                                    Text(industry)
                                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                                        .foregroundColor(AppColor.primary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 3)
                                                        .background(AppColor.primary.opacity(0.08))
                                                        .cornerRadius(6)
                                                }
                                            }
                                            .padding(14)
                                            .frame(width: 140, alignment: .leading)
                                            .background(AppColor.cardBackground)
                                            .cornerRadius(12)
                                            .shadow(color: Color.black.opacity(0.01), radius: 4, x: 0, y: 2)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Back to dashboard
                        AppButton(title: "返回今日情緒雷達", icon: "house.fill") {
                            dismiss()
                        }
                        .padding(.top, 16)
                        
                        DisclaimerView()
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("\(name) 狀態詳情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.loadDetails()
            }
        }
        .sheet(isPresented: $showAIAnalysisSheet) {
            AIAnalysisSheetView(
                symbol: symbol,
                name: name,
                isFetching: viewModel.isFetchingAIAnalysis,
                text: viewModel.aiAnalysisText,
                errorMessage: viewModel.hasError ? viewModel.errorMessage : nil,
                onRetry: {
                    Task { await viewModel.fetchAIAnalysis() }
                }
            )
        }
    }

    // 影響度膠囊：綠（低）/ 橘（中）/ 紅（高），與 EmotionBadge 同語言
    private var impactBadge: some View {
        let (label, color): (String, Color) = {
            switch viewModel.anxietyImpact {
            case "高": return ("影響偏高", AppColor.danger)
            case "中": return ("影響中等", AppColor.warning)
            default: return ("影響偏低", AppColor.secondary)
            }
        }()

        return Text(label)
            .font(.system(.caption, design: .rounded))
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - AI Analysis Sheet View
struct AIAnalysisSheetView: View {
    let symbol: String
    let name: String
    let isFetching: Bool
    let text: String?
    var errorMessage: String? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)

                if isFetching {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("正在整理對應的 GPT 專家白話分析...")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let analysis = text {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundColor(AppColor.primary)
                                Text("AI 專家今日診斷")
                                    .font(.system(.headline, design: .serif))
                                    .foregroundColor(AppColor.textPrimary)
                            }
                            .padding(.top, 10)

                            // 連線失敗時顯示提示（下方仍呈現離線備用內容）
                            if let error = errorMessage {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "wifi.exclamationmark")
                                        .foregroundColor(AppColor.warning)
                                    Text(error)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)

                                    Spacer()

                                    if let onRetry = onRetry {
                                        Button("重試") { onRetry() }
                                            .font(.system(.caption, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundColor(AppColor.primary)
                                    }
                                }
                                .padding(12)
                                .background(AppColor.warning.opacity(0.1))
                                .cornerRadius(12)
                            }

                            // Parse and render the sections
                            let sections = parseAnalysis(analysis)
                            
                            VStack(spacing: 16) {
                                ForEach(sections, id: \.title) { sec in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Image(systemName: sec.icon)
                                                .foregroundColor(AppColor.primary)
                                                .font(.headline)
                                            Text(sec.title)
                                                .font(.system(.body, design: .serif))
                                                .fontWeight(.bold)
                                                .foregroundColor(AppColor.textPrimary)
                                        }
                                        
                                        Text(sec.content)
                                            .font(.system(.body, design: .rounded))
                                            .foregroundColor(AppColor.textSecondary)
                                            .lineSpacing(6)
                                    }
                                    .padding(16)
                                    .background(Color.white)
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
                                }
                            }
                            
                            DisclaimerView()
                                .padding(.top, 10)
                        }
                        .padding(24)
                    }
                } else {
                    // 尚未取得內容（例如首次連線失敗且沒有備用文字）
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundColor(AppColor.textSecondary.opacity(0.5))
                        Text(errorMessage ?? "暫時無法取得 AI 分析")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        if let onRetry = onRetry {
                            Button(action: onRetry) {
                                Text("重新整理")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(AppColor.primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("\(name) AI 分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") { dismiss() }
                        .foregroundColor(AppColor.textSecondary)
                }
            }
        }
    }
    
    // Parses raw GPT block into structural sections
    struct AnalysisSection {
        let title: String
        let icon: String
        let content: String
    }
    
    private func parseAnalysis(_ raw: String) -> [AnalysisSection] {
        var list: [AnalysisSection] = []
        let parts = raw.components(separatedBy: "\n\n")
        
        for part in parts {
            if part.contains("【發生什麼】") {
                let clean = part.replacingOccurrences(of: "【發生什麼】\n", with: "").replacingOccurrences(of: "【發生什麼】", with: "")
                list.append(AnalysisSection(title: "發生什麼", icon: "arrow.left.and.right.circle.fill", content: clean))
            } else if part.contains("【跟你有關】") {
                let clean = part.replacingOccurrences(of: "【跟你有關】\n", with: "").replacingOccurrences(of: "【跟你有關】", with: "")
                list.append(AnalysisSection(title: "與你有關", icon: "heart.text.square.fill", content: clean))
            } else if part.contains("【可以留意】") {
                let clean = part.replacingOccurrences(of: "【可以留意】\n", with: "").replacingOccurrences(of: "【可以留意】", with: "")
                list.append(AnalysisSection(title: "可以留意", icon: "eye.circle.fill", content: clean))
            }
        }
        
        // Fallback in case format doesn't contain braces
        if list.isEmpty {
            list.append(AnalysisSection(title: "AI 白話解讀", icon: "sparkles", content: raw))
        }
        
        return list
    }
}
