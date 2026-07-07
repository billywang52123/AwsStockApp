import SwiftUI

struct UserScenarioView: View {
    @StateObject private var viewModel = UserScenarioViewModel()
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("選擇您目前的情境")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(AppColor.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            Text("我們將依此為您客製化每日的情緒報告與提示。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .padding(.horizontal, 24)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.scenarios, id: \.self) { scenario in
                        let isSelected = viewModel.selectedScenario == scenario
                        
                        Button(action: {
                            viewModel.selectScenario(scenario)
                        }) {
                            HStack {
                                Text(scenario)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(isSelected ? .semibold : .regular)
                                    .foregroundColor(isSelected ? AppColor.primary : AppColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineSpacing(4)
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppColor.primary)
                                        .font(.title3)
                                } else {
                                    Circle()
                                        .stroke(AppColor.textSecondary.opacity(0.4), lineWidth: 1.5)
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(isSelected ? AppColor.primary.opacity(0.08) : AppColor.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isSelected ? AppColor.primary : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 3)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            if viewModel.selectedScenario != nil {
                AppButton(title: "下一步", icon: "arrow.right") {
                    onSelect()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(AppColor.background.edgesIgnoringSafeArea(.all))
    }
}
