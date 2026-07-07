import yfinance as yf
import logging
from datetime import datetime, date
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

class YahooFinanceService:
    @staticmethod
    def fetch_live_price(symbol: str) -> Optional[Dict[str, Any]]:
        """
        Fetches live/daily closing price and daily percentage change for a given symbol from Yahoo Finance.
        Handles both TWSE (.TW) and OTC (.TWO) tickers, as well as TAIEX (^TWII).
        """
        if symbol.isdigit():
            ticker_symbol = f"{symbol}.TW"
        elif symbol == "TAIEX":
            ticker_symbol = "^TWII"
        else:
            ticker_symbol = symbol
            
        try:
            logger.info(f"Querying Yahoo Finance for: {ticker_symbol}")
            ticker = yf.Ticker(ticker_symbol)
            # Query history for 5 days to reliably handle weekends, holidays, and previous-close calculations
            hist = ticker.history(period="5d")
            
            if hist.empty and symbol.isdigit():
                logger.info(f"Empty result for {ticker_symbol}, trying OTC suffix (.TWO)...")
                ticker_symbol = f"{symbol}.TWO"
                ticker = yf.Ticker(ticker_symbol)
                hist = ticker.history(period="5d")
                
            if not hist.empty:
                # Retrieve the last available day of history
                latest = hist.iloc[-1]
                close_price = float(latest["Close"])
                volume = int(latest["Volume"]) if "Volume" in latest else 0
                
                # Compare the last day's close with the previous day's close for the official daily percentage change
                if len(hist) >= 2:
                    prev_close = float(hist.iloc[-2]["Close"])
                    change_percent = ((close_price - prev_close) / prev_close) * 100
                else:
                    open_price = float(latest["Open"]) if "Open" in latest else close_price
                    change_percent = ((close_price - open_price) / open_price * 100) if open_price else 0.0
                
                logger.info(f"Successfully retrieved {symbol} from Yahoo Finance: Price={close_price:.2f}, Change={change_percent:.2f}%")
                return {
                    "close_price": close_price,
                    "change_percent": change_percent,
                    "volume": volume
                }
            else:
                logger.warning(f"No historical price data found on Yahoo Finance for {symbol}")
                return None
        except Exception as e:
            logger.error(f"Failed to fetch live price for {symbol} via Yahoo Finance: {str(e)}")
            return None
