import Foundation

class PortfolioLocalStore {
    static let shared = PortfolioLocalStore()
    private let baseKey = "com.stockmoodapp.portfolio"

    // Portfolio is stored per user so accounts on the same device don't mix
    private var key: String {
        AppPreferenceStore.shared.userScopedKey(baseKey)
    }

    private init() {}

    func loadItems() -> [PortfolioItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            // Seed with TSMC (2330) and CTBC (2891) as default portfolio items for first launch
            let defaultItems = [
                PortfolioItem(id: UUID(), symbol: "2330", name: "台積電", costPrice: 980.0, shares: 1000, createdAt: Date()),
                PortfolioItem(id: UUID(), symbol: "2891", name: "中信金", costPrice: 38.0, shares: 3000, createdAt: Date())
            ]
            saveItems(defaultItems)
            return defaultItems
        }
        do {
            return try JSONDecoder().decode([PortfolioItem].self, from: data)
        } catch {
            print("Failed to decode portfolio items: \(error)")
            return []
        }
    }
    
    func saveItems(_ items: [PortfolioItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to encode portfolio items: \(error)")
        }
    }
}
