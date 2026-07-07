//
//  Item.swift
//  StockMoodApp
//
//  Created by 王傳瑋 on 2026/7/6.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
