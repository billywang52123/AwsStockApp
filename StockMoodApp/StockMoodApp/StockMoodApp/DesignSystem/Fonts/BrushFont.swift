import SwiftUI

// MARK: - 御神籤書法字型(LXGW WenKai TC 霞鶩文楷,OFL 1.1)
// 原型稿用 Ma Shan Zheng(簡體字集,缺「籤、搖、來」等繁體字),
// 故改用同為毛筆楷書、繁體覆蓋完整的霞鶩文楷 TC;授權見同目錄 OFL.txt。
enum BrushFont {
    static let name = "LXGWWenKaiTC-Regular"

    /// 書法字(標題/籤等/籤筒標籤用);字型檔缺失時自動退回系統 serif
    static func brush(_ size: CGFloat) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}
