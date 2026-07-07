"""Achievement catalog — single source of truth for all achievement definitions.

The DB (achievements table) only stores unlock records; everything else
(title, description, rarity, category) lives here so the list can grow
without migrations.

rarity: common | rare | epic | legendary | hidden
hidden achievements show as "？？？" in the app until unlocked.
"""

CATEGORY_NAMES = {
    "anxiety": "焦慮程度成就",
    "pnl": "總損益成就",
    "single": "單一持股成就",
    "combo": "持股組合成就",
    "import": "匯入功能成就",
    "theme": "題材／產業成就",
}


def _a(key, title, description, icon, category, rarity, hidden=False):
    return {
        "key": key,
        "title": title,
        "description": description,
        "icon": icon,
        "category": category,
        "rarity": rarity,
        "hidden": hidden,
    }


ACHIEVEMENTS = [
    # ── 1. 焦慮程度成就 ────────────────────────────────────────────
    _a("ANXIETY_DROP_3", "睡得著嗎", "今日總損益低於 -3%", "moon.zzz.fill", "anxiety", "common"),
    _a("ANXIETY_DROP_5", "開始冒汗", "今日總損益低於 -5%", "drop.fill", "anxiety", "common"),
    _a("ANXIETY_DROP_8", "心跳加速", "今日總損益低於 -8%", "heart.fill", "anxiety", "rare"),
    _a("ANXIETY_DROP_10", "手機不敢打開", "今日總損益低於 -10%", "iphone.slash", "anxiety", "rare"),
    _a("ANXIETY_DROP_15", "心態炸裂", "今日總損益低於 -15%", "burst.fill", "anxiety", "epic"),
    _a("ANXIETY_STILL_ALIVE", "冷靜，我還活著", "今日虧損後仍打開 App", "figure.walk", "anxiety", "common"),
    _a("ANXIETY_WATCH_MORE", "越跌越看", "當日虧損超過 -5%，仍查看 3 次以上", "eye.fill", "anxiety", "rare"),
    _a("ANXIETY_DONT_LOOK", "不看就不會跌", "持股虧損中，但 7 天未更新／查看", "eye.slash.fill", "anxiety", "rare"),
    _a("ANXIETY_RADAR_ON", "焦慮雷達啟動", "匯入持股後焦慮指數超過 60", "dot.radiowaves.left.and.right", "anxiety", "common"),
    _a("ANXIETY_MAXED", "焦慮爆表", "焦慮指數超過 90", "gauge.high", "anxiety", "epic"),
    _a("ANXIETY_ZEN", "已進入禪定模式", "焦慮指數低於 10", "leaf.fill", "anxiety", "rare"),
    _a("ANXIETY_STABLE_30D", "情緒穩定大師", "連續 30 天焦慮指數低於 30", "brain.head.profile", "anxiety", "epic"),
    _a("ANXIETY_MONK", "這不是投資，是修行", "持股虧損超過 -30%，但持續追蹤超過 30 天", "hands.sparkles.fill", "anxiety", "epic"),
    _a("ANXIETY_DAILY_14D", "每天看也不會漲", "連續 14 天每天查看持股", "calendar", "anxiety", "rare"),
    _a("ANXIETY_IGNORE_30D", "眼不見為淨", "連續 30 天未更新持股資料", "zzz", "anxiety", "rare"),

    # ── 2. 總損益成就 ─────────────────────────────────────────────
    _a("PNL_UP_100", "買豪宅", "總損益達 +100%", "house.fill", "pnl", "epic"),
    _a("PNL_DOWN_100", "睡公園", "總損益達 -100%", "tree.fill", "pnl", "hidden", hidden=True),
    _a("PNL_UP_5", "小賺便當錢", "總損益達 +5%", "takeoutbag.and.cup.and.straw.fill", "pnl", "common"),
    _a("PNL_UP_10", "晚餐加雞腿", "總損益達 +10%", "fork.knife", "pnl", "common"),
    _a("PNL_UP_50", "財富自由幻覺", "總損益達 +50%", "sparkles", "pnl", "rare"),
    _a("PNL_UP_200", "人生勝利組", "總損益達 +200%", "trophy.fill", "pnl", "legendary"),
    _a("PNL_UP_500", "市場傳說", "總損益達 +500%", "crown.fill", "pnl", "legendary"),
    _a("PNL_DOWN_10", "技術性調整", "總損益低於 -10%", "chart.line.downtrend.xyaxis", "pnl", "common"),
    _a("PNL_DOWN_30", "抄底抄在半山腰", "總損益低於 -30%", "mountain.2.fill", "pnl", "rare"),
    _a("PNL_DOWN_50", "地心探險隊", "總損益低於 -50%", "arrow.down.circle.fill", "pnl", "epic"),
    _a("PNL_COMEBACK", "反敗為勝", "總損益曾為負，後來轉正", "arrow.uturn.up.circle.fill", "pnl", "epic"),
    _a("PNL_FROM_HELL", "從地獄回來", "總損益曾低於 -50%，後來回到 0% 以上", "flame.fill", "pnl", "legendary"),
    _a("PNL_STILL_BREATHING", "我還有呼吸", "總損益曾低於 -80%，後來回升到 -20% 以上", "lungs.fill", "pnl", "legendary"),
    _a("PNL_NOT_SOLD_NOT_LOST", "不賣就不算賠", "未實現損益低於 -50%", "hand.raised.fill", "pnl", "hidden", hidden=True),
    _a("PNL_PAPER_RICH", "帳面富翁", "未實現損益達 +100%", "banknote.fill", "pnl", "epic"),

    # ── 3. 單一持股成就 ────────────────────────────────────────────
    _a("SINGLE_UP_100", "這張有神明保佑", "單一標的損益達 +100%", "hands.and.sparkles.fill", "single", "epic"),
    _a("SINGLE_UP_1000", "十倍奉還", "單一標的損益達 +1000%", "10.circle.fill", "single", "legendary"),
    _a("SINGLE_LIFE_CHANGER", "一張改命", "單一標的獲利金額超過 100 萬", "wand.and.stars", "single", "legendary"),
    _a("SINGLE_CORE_50", "我的核心資產", "單一標的佔總持股超過 50%", "star.circle.fill", "single", "common"),
    _a("SINGLE_ALL_IN_80", "歐印信仰", "單一標的佔總持股超過 80%", "flame.circle.fill", "single", "rare"),
    _a("SINGLE_DOWN_30", "套牢紀念碑", "單一標的損益低於 -30%", "figure.stand", "single", "common"),
    _a("SINGLE_DOWN_50", "股市釘子戶", "單一標的損益低於 -50%", "hammer.fill", "single", "rare"),
    _a("SINGLE_DOWN_70", "這不是坑，是地下室", "單一標的損益低於 -70%", "stairs", "single", "epic"),
    _a("SINGLE_DIAMOND_HAND", "鑽石手觀察員", "單一標的獲利超過 +50%，仍在持股清單中", "suit.diamond.fill", "single", "rare"),
    _a("SINGLE_IRON_LEEK", "鐵韭菜", "單一標的虧損超過 -50%，仍在持股清單中", "carrot.fill", "single", "rare"),
    _a("SINGLE_FAITH", "信仰加持", "單一標的虧損超過 -30%，但持股比例仍超過 30%", "heart.circle.fill", "single", "rare"),
    _a("SINGLE_CARRY_FAMILY", "靠一張撐全家", "單一標的貢獻總獲利 80% 以上", "figure.2.and.child.holdinghands", "single", "epic"),
    _a("SINGLE_BAD_APPLE", "一顆老鼠屎", "單一標的貢獻總虧損 80% 以上", "xmark.seal.fill", "single", "hidden", hidden=True),

    # ── 4. 持股組合焦慮成就 ─────────────────────────────────────────
    _a("COMBO_ALL_RED", "滿江紅", "今日所有持股上漲", "flag.fill", "combo", "rare"),
    _a("COMBO_ALL_GREEN", "一片草原", "今日所有持股下跌", "leaf.arrow.circlepath", "combo", "rare"),
    _a("COMBO_TRAFFIC_LIGHT", "紅綠燈人生", "持股中同時有大賺、大賠、持平標的", "circle.grid.3x3.fill", "combo", "rare"),
    _a("COMBO_ALL_TRAPPED", "全員套牢", "所有持股皆為負報酬", "lock.fill", "combo", "rare"),
    _a("COMBO_ALL_PROFIT", "全員獲利", "所有持股皆為正報酬", "checkmark.seal.fill", "combo", "rare"),
    _a("COMBO_LEEK_FARM", "韭菜園園長", "5 檔以上持股虧損超過 -20%", "laurel.leading", "combo", "epic"),
    _a("COMBO_GODLY", "神仙組合", "5 檔以上持股獲利超過 +20%", "star.fill", "combo", "epic"),
    _a("COMBO_STRESS_TEST", "壓力測試中", "前 3 大持股皆為虧損", "waveform.path.ecg.rectangle", "combo", "rare"),
    _a("COMBO_DIVERSIFIED", "分散焦慮", "持有 20 檔以上標的", "square.grid.4x3.fill", "combo", "rare"),
    _a("COMBO_CONCENTRATED", "集中焦慮", "前 3 大持股佔總市值超過 70%", "scope", "combo", "common"),
    _a("COMBO_BALANCED", "完美平衡", "最大持股佔比低於 20%，且總損益為正", "scalemass.fill", "combo", "epic"),
    _a("COMBO_ONE_INDUSTRY", "一榮俱榮", "單一產業佔比超過 70%", "building.2.fill", "combo", "common"),
    _a("COMBO_INDUSTRY_CRASH", "一跌全跌", "同一產業持股全部下跌", "arrow.down.right.circle.fill", "combo", "rare"),
    _a("COMBO_ETF_SAVIOR", "靠 ETF 續命", "ETF 獲利、個股虧損", "cross.case.fill", "combo", "rare"),
    _a("COMBO_STOCK_SAVIOR", "個股救全家", "個股獲利、ETF 虧損", "figure.wave", "combo", "rare"),

    # ── 5. OCR / 匯入功能成就 ──────────────────────────────────────
    _a("IMPORT_FIRST_OCR", "一鍵面對現實", "第一次使用 OCR 匯入持股", "camera.viewfinder", "import", "common"),
    _a("IMPORT_SCREENSHOT", "截圖勇者", "使用截圖匯入持股", "photo.on.rectangle.angled", "import", "common"),
    _a("IMPORT_RECEIPT", "對帳單召喚師", "匯入券商對帳單", "doc.text.viewfinder", "import", "common"),
    _a("IMPORT_CLEAN_10", "資料清洗大師", "OCR 匯入後成功辨識 10 檔以上", "sparkle.magnifyingglass", "import", "rare"),
    _a("IMPORT_OCR_SAD", "OCR 也看不懂你的慘況", "OCR 匯入後總損益低於 -30%", "questionmark.folder.fill", "import", "hidden", hidden=True),
    _a("IMPORT_AI_REALITY", "AI 幫你面對現實", "OCR 匯入後成功產生焦慮指數", "cpu.fill", "import", "common"),
    _a("IMPORT_INSTANT_PANIC", "匯入即崩潰", "第一次匯入後焦慮指數超過 80", "exclamationmark.triangle.fill", "import", "hidden", hidden=True),
    _a("IMPORT_NO_SAVE", "看完不想存", "匯入後未儲存資料", "trash.fill", "import", "rare"),
    _a("IMPORT_BRAVE", "勇敢面對", "匯入虧損持股後仍完成儲存", "shield.checkered", "import", "common"),
    _a("IMPORT_RICH_DAY", "財富盤點日", "持股總市值超過 1,000 萬", "dollarsign.circle.fill", "import", "epic"),
    _a("IMPORT_MULTI_ACCOUNT", "多帳戶人生", "匯入 2 個以上券商／帳戶資料", "person.2.fill", "import", "rare"),
    _a("IMPORT_FAMILY_BUCKET", "股海全家桶", "單次匯入 30 檔以上持股", "shippingbox.fill", "import", "epic"),
    _a("IMPORT_MANUAL", "手動派", "第一次手動輸入持股", "hand.point.up.left.fill", "import", "common"),
    _a("IMPORT_MANUAL_10", "純手工韭菜", "手動輸入 10 檔以上持股", "keyboard.fill", "import", "rare"),
    _a("IMPORT_SEMI_AUTO", "半自動人生", "同時使用手動輸入與 OCR 匯入", "gearshape.2.fill", "import", "rare"),

    # ── 6. 題材 / 產業成就 ─────────────────────────────────────────
    _a("THEME_AI", "AI 信徒", "持有 AI 相關股", "brain.fill", "theme", "rare"),
    _a("THEME_COMPUTE", "算力即國力", "持有 GPU、AI Server、半導體相關股", "cpu", "theme", "rare"),
    _a("THEME_TSMC", "護國神山巡禮", "持有台積電或半導體龍頭", "mountain.2.circle.fill", "theme", "common"),
    _a("THEME_SPACEX", "上火星", "持有 SpaceX 或太空航太相關標的", "airplane.departure", "theme", "epic"),
    _a("THEME_ROCKET", "火箭乘客", "持有航太／衛星／太空概念股", "paperplane.fill", "theme", "rare"),
    _a("THEME_EV", "電動未來", "持有 EV／電動車相關股", "bolt.car.fill", "theme", "rare"),
    _a("THEME_GREEN", "綠能勇者", "持有綠能／太陽能／風電相關股", "wind", "theme", "rare"),
    _a("THEME_CRYPTO", "幣圈旁觀者", "持有加密貨幣概念股", "bitcoinsign.circle.fill", "theme", "rare"),
    _a("THEME_BANK", "銀行家養成中", "持有金融股", "building.columns.fill", "theme", "common"),
    _a("THEME_REIT", "包租公體驗版", "持有 REITs／不動產相關股", "key.fill", "theme", "rare"),
    _a("THEME_BIO", "醫療救世主", "持有生技／醫療股", "cross.fill", "theme", "rare"),
    _a("THEME_OIL", "石油王候選人", "持有能源／石油相關股", "fuelpump.fill", "theme", "rare"),
    _a("THEME_DEFENSE", "軍工觀察員", "持有國防／軍工相關股", "shield.lefthalf.filled", "theme", "rare"),
    _a("THEME_STAY_HOME", "宅經濟股東", "持有遊戲、電商、串流相關股", "gamecontroller.fill", "theme", "rare"),
    _a("THEME_CLOUD", "雲端包租公", "持有雲端服務相關股", "cloud.fill", "theme", "rare"),
    _a("THEME_APPLE", "果粉股東", "持有 Apple", "applelogo", "theme", "rare"),
    _a("THEME_GOOGLE", "搜尋引擎房東", "持有 Google / Alphabet", "magnifyingglass.circle.fill", "theme", "rare"),
    _a("THEME_META", "社群帝國公民", "持有 Meta", "person.3.fill", "theme", "rare"),
    _a("THEME_AMAZON", "電商帝國小股東", "持有 Amazon", "cart.fill", "theme", "rare"),
    _a("THEME_BUFFETT", "老巴同路人", "持有 Berkshire Hathaway", "person.crop.circle.badge.checkmark", "theme", "epic"),
    _a("THEME_INDEX", "指數教徒", "持有大盤 ETF", "chart.pie.fill", "theme", "common"),
    _a("THEME_DIVIDEND", "高股息信仰者", "持有高股息 ETF", "percent", "theme", "common"),
]

ACHIEVEMENTS_BY_KEY = {a["key"]: a for a in ACHIEVEMENTS}


def get_definition(key: str):
    return ACHIEVEMENTS_BY_KEY.get(key)
