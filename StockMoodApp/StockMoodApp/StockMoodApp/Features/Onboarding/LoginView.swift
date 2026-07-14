import SwiftUI
import AuthenticationServices

struct LoginView: View {
    let onLoginSuccess: () -> Void
    @StateObject private var authService = AuthService.shared
    
    var body: some View {
        ZStack {
            AppColor.background
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 36) {
                Spacer()
                
                // 5a Tarot App Icon Card Design in SwiftUI
                ZStack {
                    // Ghost card (+8 degrees)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color(hex: "9094E2").opacity(0.15), Color(hex: "54589E").opacity(0.15)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 140, height: 210)
                        .rotationEffect(.degrees(8))
                        .offset(x: 10, y: -5)
                    
                    // Main White Card (-6 degrees)
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "E4B384"))
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "E4B384"))
                        }
                        .padding(.horizontal, 6).padding(.top, 6)
                        
                        Spacer()
                        
                        // 3 candlestick K-lines
                        HStack(alignment: .center, spacing: 14) {
                            VStack(spacing: 0) {
                                Rectangle().fill(Color(hex: "D08C8C")).frame(width: 1, height: 12)
                                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "D08C8C")).frame(width: 7, height: 28)
                                Rectangle().fill(Color(hex: "D08C8C")).frame(width: 1, height: 12)
                            }
                            VStack(spacing: 0) {
                                Rectangle().fill(Color(hex: "7B7FD4")).frame(width: 1, height: 18)
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color(hex: "7B7FD4"), lineWidth: 1.5)
                                    .background(Color.white)
                                    .frame(width: 7, height: 42)
                                Rectangle().fill(Color(hex: "7B7FD4")).frame(width: 1, height: 18)
                            }
                            VStack(spacing: 0) {
                                Rectangle().fill(Color(hex: "9DBFAA")).frame(width: 1, height: 10)
                                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "9DBFAA")).frame(width: 7, height: 22)
                                Rectangle().fill(Color(hex: "9DBFAA")).frame(width: 1, height: 10)
                            }
                        }
                        
                        Spacer()
                        
                        HStack {
                            Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "E4B384"))
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: 8)).foregroundColor(Color(hex: "E4B384"))
                        }
                        .padding(.horizontal, 6).padding(.bottom, 6)
                    }
                    .frame(width: 130, height: 195)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color(hex: "54589E").opacity(0.12), radius: 10, x: 0, y: 6)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "E4B384").opacity(0.3), lineWidth: 1))
                    .rotationEffect(.degrees(-6))
                }
                .frame(width: 200, height: 230)
                
                // Title & tagline
                VStack(spacing: 12) {
                    Text("股感安心卡")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(AppColor.textPrimary)
                    
                    Text("每天看懂你的股票情緒\n不用懂線圖，也能知道今天為什麼焦慮。")
                        .font(.system(.subheadline, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .foregroundColor(AppColor.textSecondary)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Login buttons
                VStack(spacing: 14) {
                    if authService.isAuthenticating {
                        ProgressView("登入中...")
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColor.primary))
                            .font(.system(.caption, design: .rounded))
                    } else {
                        // ── Apple Sign-In (Cognito federated IdP via Hosted UI) ──
                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .medium)
                            authService.signInWithCognito(identityProvider: "SignInWithApple", onSuccess: onLoginSuccess)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "apple.logo").font(.title3)
                                Text("使用 Apple 帳號登入").fontWeight(.bold)
                            }
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black)
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                        }

                        // ── Google Sign-In (Cognito federated IdP via Hosted UI) ──
                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .medium)
                            authService.signInWithCognito(identityProvider: "Google", onSuccess: onLoginSuccess)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle.fill").font(.title3)
                                Text("使用 Google 帳號登入").fontWeight(.bold)
                            }
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(AppColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.textSecondary.opacity(0.2), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                        }
                        
                        // ── Cognito Hosted UI (email / password, AWS User Pool) ──
                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .medium)
                            authService.signInWithCognito(onSuccess: onLoginSuccess)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.circle.fill").font(.title3)
                                Text("使用 Email 登入 / 註冊").fontWeight(.bold)
                            }
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColor.primary)
                            .cornerRadius(14)
                            .shadow(color: AppColor.primary.opacity(0.25), radius: 6, x: 0, y: 3)
                        }

                        // ── Guest / Browse Route ──
                        Button(action: {
                            HapticManager.shared.triggerImpact(style: .medium)
                            authService.signInAsGuest()
                            onLoginSuccess()
                        }) {
                            Text("先逛逛 (訪客路徑)")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(AppColor.primary)
                                .padding(.top, 8)
                        }
                    }
                    
                    // Error banner (only shown on real auth failure)
                    if let error = authService.authError {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(AppColor.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}
