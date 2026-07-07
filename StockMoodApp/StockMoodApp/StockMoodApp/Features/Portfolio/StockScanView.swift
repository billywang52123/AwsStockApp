import SwiftUI
import PhotosUI
import UIKit

// MARK: - GPT Scanned Stock Result
struct ScannedStockResult {
    let stock: Stock
    let cost: String
    let shares: String
}

// MARK: - API Response Models
private struct ScanAPIResponse: Codable {
    let success: Bool
    let stocks: [ScanAPIStock]
    // 對帳單所屬券商(9d 匯入合併「來源 chip」);辨識不出時為 nil
    let broker: String?
    let rawText: String?
    let message: String?
}
private struct ScanAPIStock: Codable {
    let symbol: String
    let name: String
    let shares: String?
    let cost: String?
}

// MARK: - Stock Scan View (Real Camera + Photo Library + GPT-4o-mini OCR)
struct StockScanSimulatorView: View {
    let onImport: ([ScannedStockResult]) -> Void
    /// 走 9d 合併流程完成時呼叫(已直接寫入後端,不經過手動編輯頁)
    var onMergeCompleted: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    // Photo picker
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    // "camera"（拍攝對帳單）或 "photo"（相簿截圖），後端據此解鎖對應成就
    @State private var imageSource = "photo"
    
    // Scan state: 0 = choose, 1 = scanning/uploading, 2 = result, 3 = error, 4 = 9d merge decision
    @State private var scanStep = 0
    @State private var scanProgress = 0.0
    @State private var scannedStocks: [ScanAPIStock] = []
    @State private var scannedBroker: String? = nil
    /// true = 裝置端 Vision 辨識成功,圖片沒離開手機(spec 05)
    @State private var recognizedOnDevice = false
    @State private var mergeViewModel: ImportMergeViewModel? = nil
    @State private var errorMessage: String? = nil
    @State private var recognizedCount = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        switch scanStep {
                        case 0: sourcePickerView
                        case 1: scanningView
                        case 2: resultView
                        case 4: mergeDecisionView
                        default: errorView
                        }
                    }
                    .padding(.top, 20)
                    .animation(.easeInOut(duration: 0.3), value: scanStep)
                }
            }
            .navigationTitle("AI 對帳單識別")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(AppColor.textSecondary)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(image: $selectedImage) {
                    showCamera = false
                    if selectedImage != nil { uploadAndScan() }
                }
                .edgesIgnoringSafeArea(.all)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item = item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        selectedImage = uiImage
                        uploadAndScan()
                    }
                }
            }
        }
    }
    
    // MARK: - Source Picker
    private var sourcePickerView: some View {
        VStack(spacing: 20) {
            // Image preview or placeholder
            if let img = selectedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColor.primary.opacity(0.06))
                        .frame(height: 140)
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 48))
                            .foregroundColor(AppColor.primary.opacity(0.5))
                        Text("上傳對帳單或截圖\nGPT-4o-mini 自動識別股票代號與成本")
                            .font(.system(.caption, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(AppColor.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
            }
            
            VStack(spacing: 12) {
                Text("選擇對帳單匯入方式")
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(AppColor.textPrimary)
                
                // 相機
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .medium)
                    imageSource = "camera"
                    showCamera = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text("拍攝實體對帳單").fontWeight(.bold)
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary)
                    .cornerRadius(14)
                }
                
                // 相簿
                Button(action: {
                    HapticManager.shared.triggerImpact(style: .medium)
                    imageSource = "photo"
                    showPhotoPicker = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled").font(.title3)
                        Text("從相簿選擇對帳單截圖").fontWeight(.bold)
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(AppColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary.opacity(0.10))
                    .cornerRadius(14)
                }
                
                // 模型標籤
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(AppColor.primary)
                    Text("優先在你的手機上辨識,必要時才交給雲端 AI")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(AppColor.textSecondary)
                }
                .padding(.top, 4)

                // 10d 就地說明:在按下匯入前講清楚,不藏在條款裡
                TrustNote(text: "只辨識代號與股數,辨識完即刪除;不取得帳號或下單權限")
                    .padding(.top, 2)
            }
            .padding(24)
            .background(AppColor.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color(hex: "786446").opacity(0.04), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 24)
        }
    }
    
    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 24) {
            ZStack(alignment: .top) {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 220, height: 220)
                        .clipped()
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.primary.opacity(0.4), lineWidth: 2))
                } else {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 100))
                        .foregroundColor(AppColor.primary.opacity(0.5))
                        .frame(width: 220, height: 220)
                        .background(AppColor.cardBackground)
                        .cornerRadius(16)
                }
                
                // Laser line
                Rectangle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color(hex: "7B7FD4").opacity(0.85), Color.clear]),
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: 210, height: 3)
                    .offset(y: scanProgress)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scanProgress)
            }
            .frame(width: 220, height: 220)
            .onAppear { scanProgress = 210 }
            
            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColor.primary))
                Text("GPT-4o-mini 正在分析對帳單...")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                Text("AI 識別股票代號、股數與成本中")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(AppColor.textSecondary.opacity(0.7))
            }
        }
    }
    
    // MARK: - Result View
    private var resultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: scannedStocks.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(scannedStocks.isEmpty ? AppColor.warning : Color(hex: "6E9A7F"))
                    .font(.title2)
                Text(scannedStocks.isEmpty
                     ? "未識別到持股，請手動輸入"
                     : "成功識別 \(scannedStocks.count) 筆持股！")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppColor.textPrimary)
            }

            // spec 05:裝置端辨識成功 → 圖片沒離開手機;結果不對可改走雲端
            if recognizedOnDevice {
                VStack(alignment: .leading, spacing: 8) {
                    TrustNote(text: "在你的手機上辨識完成,圖片沒有上傳")

                    Button {
                        uploadAndScan(forceCloud: true)
                    } label: {
                        Text("結果不對?改用雲端 AI 重新辨識")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(AppColor.primary)
                    }
                }
            }
            
            if !scannedStocks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(scannedStocks, id: \.symbol) { stock in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(stock.name) (\(stock.symbol))")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColor.textPrimary)
                                if let shares = stock.shares {
                                    Text("\(shares) 股")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundColor(AppColor.textSecondary)
                                }
                            }
                            Spacer()
                            if let cost = stock.cost {
                                Text("成本: $\(cost)")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColor.primary)
                            }
                        }
                        .padding(12)
                        .background(AppColor.background)
                        .cornerRadius(10)
                    }
                }
                .padding(.vertical, 8)
                
                // Import button
                Button(action: importResults) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("匯入持股列表").fontWeight(.bold)
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary)
                    .cornerRadius(14)
                }
            }
            
            // Retry button
            Button(action: {
                selectedImage = nil
                selectedPhotoItem = nil
                scannedStocks = []
                scanStep = 0
            }) {
                Text("重新選擇圖片")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .padding(24)
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color(hex: "786446").opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Error View
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(AppColor.danger)
            Text("識別失敗")
                .font(.system(.headline, design: .serif))
                .foregroundColor(AppColor.textPrimary)
            Text(errorMessage ?? "AI 分析發生錯誤，請重試。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Button(action: {
                selectedImage = nil
                selectedPhotoItem = nil
                errorMessage = nil
                scanStep = 0
            }) {
                Text("重新嘗試")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.primary)
                    .cornerRadius(14)
            }
        }
        .padding(24)
        .background(AppColor.cardBackground)
        .cornerRadius(16)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Scan(裝置端 Vision 優先,fallback 雲端 GPT · spec 05)
    private func uploadAndScan(forceCloud: Bool = false) {
        guard let image = selectedImage else { return }
        HapticManager.shared.triggerImpact(style: .medium)
        scanStep = 1

        Task {
            // 1) 先在手機上辨識 —— 成功就不上傳圖片
            if !forceCloud, let onDevice = await ReceiptTextScanner.scan(image),
               !onDevice.holdings.isEmpty {
                await MainActor.run {
                    scannedStocks = onDevice.holdings.map {
                        ScanAPIStock(symbol: $0.symbol, name: $0.name, shares: $0.shares, cost: $0.cost)
                    }
                    scannedBroker = onDevice.broker
                    recognizedOnDevice = true
                    HapticManager.shared.triggerNotification(type: .success)
                    scanStep = 2
                }
                return
            }

            // 2) 裝置端辨識不到 → 上傳雲端(TLS,後端即用即刪、不落地 log)
            await uploadToCloud(image)
        }
    }

    private func uploadToCloud(_ image: UIImage) async {
            do {
                // Compress image for faster upload (max 1024px, 85% quality)
                let compressed = compressImage(image, maxDimension: 1024, quality: 0.85)
                guard let imageData = compressed.jpegData(compressionQuality: 0.85) else {
                    throw URLError(.cannotDecodeContentData)
                }
                
                // Build multipart/form-data request
                let boundary = "Boundary-\(UUID().uuidString)"
                let baseURL = APIClient.shared.baseURL
                guard let url = URL(string: "\(baseURL)/scan/receipt?source=\(imageSource)") else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                // Identify the user so OCR achievements land in the right account
                APIClient.attachAuthHeaders(to: &request)
                
                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                body.append(imageData)
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw URLError(.badServerResponse)
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let scanResponse = try decoder.decode(ScanAPIResponse.self, from: data)
                
                await MainActor.run {
                    scannedStocks = scanResponse.stocks
                    scannedBroker = scanResponse.broker
                    recognizedOnDevice = false
                    HapticManager.shared.triggerNotification(type: .success)
                    scanStep = 2
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    HapticManager.shared.triggerNotification(type: .error)
                    scanStep = 3
                }
            }
    }

    private func importResults() {
        Task {
            // 先比對現有持股:有紀錄就走 9d 合併決策(分帳加總/取代/略過),
            // 全新用戶或辨識不到股數時,退回原本的手動編輯流程。
            let holdings = (try? await DependencyContainer.shared.holdingService.getHoldings()) ?? []
            let scanned = scannedStocks.compactMap { s -> (symbol: String, name: String, shares: Int, cost: Double?)? in
                guard !s.symbol.isEmpty,
                      let shares = Int((s.shares ?? "").filter(\.isNumber)), shares > 0 else { return nil }
                return (symbol: s.symbol, name: s.name, shares: shares, cost: Double(s.cost ?? ""))
            }

            if holdings.isEmpty || scanned.isEmpty {
                await MainActor.run { legacyImport() }
            } else {
                await MainActor.run {
                    mergeViewModel = ImportMergeViewModel(
                        scanned: scanned, detectedBroker: scannedBroker, holdings: holdings)
                    scanStep = 4
                }
            }
        }
    }

    /// 原始流程:把辨識結果丟回持股編輯頁讓用戶確認後逐筆新增
    private func legacyImport() {
        let results = scannedStocks.compactMap { stock -> ScannedStockResult? in
            guard !stock.symbol.isEmpty else { return nil }
            return ScannedStockResult(
                stock: Stock(symbol: stock.symbol, name: stock.name, market: .tw, industry: ""),
                cost: stock.cost ?? "",
                shares: stock.shares ?? ""
            )
        }
        onImport(results)
    }

    // MARK: - 9d 匯入合併決策
    @ViewBuilder
    private var mergeDecisionView: some View {
        if let vm = mergeViewModel {
            ImportMergeView(viewModel: vm) {
                dismiss()
                onMergeCompleted?()
            }
        }
    }
    
    private func compressImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        if ratio >= 1.0 { return image }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Camera Picker (UIImagePickerController wrapper)
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onDismiss: () -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.onDismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
        }
    }
}
