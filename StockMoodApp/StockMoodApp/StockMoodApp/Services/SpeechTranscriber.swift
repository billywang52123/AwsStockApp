import AVFoundation
import Combine
import Speech
import SwiftUI

/// 裝置端語音轉文字(spec 08 · 19b)。
///
/// 隱私鐵則:`requiresOnDeviceRecognition = true`,語音只在 iPhone 上轉成文字,
/// 錄音不上傳、不落地;後端只收得到轉出的純文字。
/// partial result 即時回填逐字稿卡;偵測 3 秒無新語音 → 自動觸發「說完了」。
@MainActor
final class SpeechTranscriber: NSObject, ObservableObject {

    enum Failure {
        case permissionDenied      // 麥克風或語音辨識權限被拒 → 導向設定/手動輸入
        case unavailable           // 裝置不支援 zh-TW 裝置端辨識 → 導向手動輸入
        case recognitionFailed     // 辨識中斷/失敗 → 安撫文案 + 可重試

        var message: String {
            switch self {
            case .permissionDenied:
                return "需要麥克風和語音辨識權限才能用說的,可以到設定開啟,或改用手動輸入"
            case .unavailable:
                return "這台裝置暫時無法在手機上做語音辨識,改用手動輸入就可以"
            case .recognitionFailed:
                return "沒聽清楚,再說一次試試"
            }
        }
    }

    @Published var transcript = ""
    @Published var isRecording = false
    /// 即時輸入音量 0...1(19b 波形綁定用)
    @Published var audioLevel: CGFloat = 0
    @Published var failure: Failure?

    /// 3 秒靜音自動結束時呼叫(等同手動點「說完了」,light haptic 由呼叫端做)
    var onAutoFinish: (() -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private static let silenceInterval: TimeInterval = 3

    // MARK: - Permissions

    /// 要求語音辨識 + 麥克風權限;任一被拒回 false(19a:被拒時導向手動/截圖入口)
    static func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Recording

    func start() {
        failure = nil
        transcript = ""

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            // 隱私承諾是「錄音不離開手機」,裝置端不支援時寧可失敗也不改走雲端辨識
            failure = .unavailable
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                let level = Self.rmsLevel(of: buffer)
                Task { @MainActor [weak self] in self?.audioLevel = level }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stop()
            failure = .recognitionFailed
            return
        }

        isRecording = true
        restartSilenceTimer()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.transcript {
                        self.transcript = text
                        self.restartSilenceTimer()  // 有新語音 → 重算 3 秒靜音
                    }
                }
                if error != nil {
                    // 有拿到部分文字就當成功結束(常見於使用者停頓後系統收尾)
                    if self.transcript.isEmpty { self.failure = .recognitionFailed }
                    self.stop()
                    if !self.transcript.isEmpty { self.onAutoFinish?() }
                }
            }
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stop()
                HapticManager.shared.triggerImpact(style: .light)
                self.onAutoFinish?()
            }
        }
    }

    private nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frames))
        // 把 -50dB...0dB 映射到 0...1,講話音量落在中段,波形才有起伏
        let db = 20 * log10(max(rms, 0.000_01))
        return CGFloat(min(max((db + 50) / 50, 0), 1))
    }
}
