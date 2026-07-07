import SwiftUI

struct SplashView: View {
    @State private var opacity = 0.0
    @State private var scale = 0.85
    let onCompletion: () -> Void
    
    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Logo Icon
                ZStack {
                    Circle()
                        .fill(AppColor.primary.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(AppColor.primary)
                }
                .scaleEffect(scale)
                
                Text("StockMood")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(AppColor.textPrimary)
                
                Text("每天看懂你的股票情緒")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                self.opacity = 1.0
                self.scale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    onCompletion()
                }
            }
        }
    }
}
