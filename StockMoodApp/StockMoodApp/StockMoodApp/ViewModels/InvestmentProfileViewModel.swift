import Foundation
import SwiftUI
import Combine

// MARK: - 16a 投資風格問卷
@MainActor
class StyleQuizViewModel: ObservableObject {
    @Published var questionnaire: QuestionnaireRead?
    @Published var currentIndex = 0
    /// key = 題目 id(snake_case)、value = 選項 code
    @Published var answers: [String: String] = [:]
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var submittedProfile: InvestmentProfileRead?
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    var questions: [QuestionnaireQuestion] { questionnaire?.questions ?? [] }
    var currentQuestion: QuestionnaireQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }
    var isLastQuestion: Bool { currentIndex == questions.count - 1 }
    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(questions.count)
    }
    var currentAnswer: String? {
        guard let q = currentQuestion else { return nil }
        return answers[q.id]
    }
    var allAnswered: Bool {
        !questions.isEmpty && questions.allSatisfy { answers[$0.id] != nil }
    }

    func load() async {
        isLoading = true
        hasError = false
        do {
            let read = try await container.investmentProfileService.getQuestionnaire()
            questionnaire = read
            // 預填舊答案(APIClient convertFromSnakeCase 會把字典 key 轉成 camelCase,還原成題目 id)
            if let saved = read.currentAnswers {
                var normalized: [String: String] = [:]
                for (key, value) in saved {
                    normalized[Self.snakeCased(key)] = value
                }
                answers = normalized
            }
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load questionnaire failed: \(error)")
        }
        isLoading = false
    }

    func select(option code: String) {
        guard let q = currentQuestion else { return }
        answers[q.id] = code
        HapticManager.shared.triggerImpact(style: .light)
    }

    func goNext() {
        guard currentIndex < questions.count - 1 else { return }
        withAnimation(.easeOut(duration: 0.25)) { currentIndex += 1 }
    }

    func goBack() -> Bool {
        guard currentIndex > 0 else { return false }
        withAnimation(.easeOut(duration: 0.25)) { currentIndex -= 1 }
        return true
    }

    /// 交卷:成功後回傳結果供 push 16b
    func submit() async -> Bool {
        guard allAnswered else { return false }
        isSubmitting = true
        hasError = false
        do {
            submittedProfile = try await container.investmentProfileService.submitQuestionnaire(answers: answers)
            HapticManager.shared.triggerImpact(style: .medium)
            isSubmitting = false
            return true
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Submit questionnaire failed: \(error)")
            isSubmitting = false
            return false
        }
    }

    static func snakeCased(_ key: String) -> String {
        var result = ""
        for char in key {
            if char.isUppercase {
                result.append("_")
                result.append(Character(char.lowercased()))
            } else {
                result.append(char)
            }
        }
        return result
    }
}

// MARK: - 16b/16d/16e 目前風格、習慣與轉變歷史
@MainActor
class InvestmentProfileViewModel: ObservableObject {
    @Published var profile: InvestmentProfileRead?
    @Published var promptContext: PromptContextRead?
    @Published var history: [HabitSnapshotRead] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var hasError = false
    @Published var errorMessage = ""

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    func load() async {
        if profile == nil { isLoading = true }
        hasError = false
        do {
            async let profileTask = container.investmentProfileService.getProfile()
            async let historyTask = container.investmentProfileService.getHistory(limit: 20)
            let (profileResult, historyResult) = try await (profileTask, historyTask)
            profile = profileResult
            history = historyResult
            // 沒收到推播也能補點紅點:最新快照有風格轉變且未看過 → 點亮
            StyleShiftCenter.shared.sync(history: historyResult)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load investment profile failed: \(error)")
        }
        // AI 口吻預覽獨立失敗不擋整頁
        promptContext = try? await container.investmentProfileService.getPromptContext()
        isLoading = false
    }

    /// 16e 手動重算習慣快照後重載
    func refreshSnapshot() async {
        isRefreshing = true
        do {
            _ = try await container.investmentProfileService.refresh()
            await load()
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Refresh habit snapshot failed: \(error)")
        }
        isRefreshing = false
    }

    /// 測驗偏好與實際持股習慣是否一致(16d 一致性對照卡)
    var styleConsistent: Bool {
        guard let profile else { return true }
        // 尚未分類或尚待觀察時不判定為不一致
        if profile.preferenceStyle.code == "unclassified" || profile.observedStyle.code == "unclassified" {
            return true
        }
        return profile.preferenceStyle.code == profile.observedStyle.code
    }

    /// 16e 轉變對照:最近兩筆快照(current, previous)
    var latestShift: (previous: HabitSnapshotRead?, current: HabitSnapshotRead?) {
        (history.count > 1 ? history[1] : nil, history.first)
    }
}
