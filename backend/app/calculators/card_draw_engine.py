class CardDrawEngine:
    def draw_by_score(self, score: int) -> dict:
        if score <= 30:
            return {
                "card_type": "CALM_OBSERVE",
                "title": "冷靜觀察卡",
                "message": "今天你的持股情緒相對穩定，可以先用輕鬆的心情看懂市場變化，好好享受今天的生活。",
                "action_text": "查看今天原因"
            }

        if score <= 50:
            return {
                "card_type": "CONFIDENCE_RESTORE",
                "title": "信心恢復卡",
                "message": "今天雖然有些微幅波動，但這是在合理的市場呼吸範圍內。請記得，好公司也需要時間成長。",
                "action_text": "查看今天原因"
            }

        if score <= 70:
            return {
                "card_type": "MARKET_IMPACT",
                "title": "大盤影響卡",
                "message": "今天不是只有你的持股在下跌，整體市場今天都在休息。這不是你的錯，請放寬心看待。",
                "action_text": "查看大盤波動"
            }

        if score <= 85:
            return {
                "card_type": "VOLATILITY_ALERT",
                "title": "小心震盪卡",
                "message": "今天的震盪可能讓你有些不舒服，但市場波動本是常態。請不要在情緒高漲時做任何重大決定。",
                "action_text": "查看影響排行"
            }

        return {
            "card_type": "STOCK_EVENT",
            "title": "個股事件卡",
            "message": "今天特定的股票回檔可能對你的心情造成了較大的衝擊。我們一起把這個事件拆開來分析，不用慌張。",
            "action_text": "查看詳細分析"
        }
