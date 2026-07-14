# StockMood Database Schema

Generated from RDS database `stockmood` in `us-east-1`.

## CSV Mapping

| Raw Table | Source CSV |
|---|---|
| `raw.raw_00_field_dictionary_and_usage_notes` | `00_Field_Dictionary_and_Usage_Notes.csv` |
| `raw.raw_01_price_valuation_2025` | `01_Price_Valuation_2025.csv` |
| `raw.raw_02_institutional_trading_2025` | `02_Institutional_Trading_2025.csv` |
| `raw.raw_03_return_rate_2025` | `03_Return_Rate_2025.csv` |
| `raw.raw_04_distance_from_high_low_momentum_2025` | `04_Distance_from_High_Low_Momentum_2025.csv` |
| `raw.raw_05_dividend_ex_dividend_2025` | `05_Dividend_Ex_Dividend_2025.csv` |
| `raw.raw_06_consecutive_dividend_stocks_2025` | `06_Consecutive_Dividend_Stocks_2025.csv` |
| `raw.raw_06b_consecutive_dividend_etf_2025` | `06b_Consecutive_Dividend_ETF_2025.csv` |
| `raw.raw_07_industry_classification_mapping` | `07_Industry_Classification_Mapping.csv` |
| `raw.raw_09_wide_table_summary_one_row_per_stock_2025` | `09_Wide_Table_Summary_One_Row_Per_Stock_2025.csv` |
| `raw.raw_10_forum_posts_replies_daily_stats_2025` | `10_Forum_Posts_Replies_Daily_Stats_2025.csv` |

## Table Summary

| Schema | Table | Estimated Rows | Source CSV |
|---|---|---:|---|
| `public` | `achievements` | 29 |  |
| `public` | `card_results` | 0 |  |
| `public` | `daily_packs` | 3 |  |
| `public` | `fortune_results` | 0 |  |
| `public` | `holding_activities` | 0 |  |
| `public` | `market_index_daily` | 2 |  |
| `public` | `portfolio_items` | 5 |  |
| `public` | `push_devices` | 5 |  |
| `public` | `reminder_settings` | 0 |  |
| `public` | `stock_daily_prices` | 13 |  |
| `public` | `stocks` | 10 |  |
| `public` | `watchlist_items` | 0 |  |
| `public` | `watchlists` | 0 |  |
| `raw` | `raw_00_field_dictionary_and_usage_notes` | 40 | `00_Field_Dictionary_and_Usage_Notes.csv` |
| `raw` | `raw_01_price_valuation_2025` | 72462 | `01_Price_Valuation_2025.csv` |
| `raw` | `raw_02_institutional_trading_2025` | 72462 | `02_Institutional_Trading_2025.csv` |
| `raw` | `raw_03_return_rate_2025` | 72462 | `03_Return_Rate_2025.csv` |
| `raw` | `raw_04_distance_from_high_low_momentum_2025` | 64478 | `04_Distance_from_High_Low_Momentum_2025.csv` |
| `raw` | `raw_05_dividend_ex_dividend_2025` | 289 | `05_Dividend_Ex_Dividend_2025.csv` |
| `raw` | `raw_06_consecutive_dividend_stocks_2025` | 266 | `06_Consecutive_Dividend_Stocks_2025.csv` |
| `raw` | `raw_06b_consecutive_dividend_etf_2025` | 34 | `06b_Consecutive_Dividend_ETF_2025.csv` |
| `raw` | `raw_07_industry_classification_mapping` | 300 | `07_Industry_Classification_Mapping.csv` |
| `raw` | `raw_09_wide_table_summary_one_row_per_stock_2025` | 300 | `09_Wide_Table_Summary_One_Row_Per_Stock_2025.csv` |
| `raw` | `raw_10_forum_posts_replies_daily_stats_2025` | 105798 | `10_Forum_Posts_Replies_Daily_Stats_2025.csv` |

## Schema `public`

### `public.achievements`

Estimated rows: `29`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('achievements_id_seq'::regclass)` |
| 2 | `user_id` | `character varying` | `YES` | `` |
| 3 | `achievement_key` | `character varying` | `YES` | `` |
| 4 | `title` | `character varying` | `YES` | `` |
| 5 | `description` | `character varying` | `YES` | `` |
| 6 | `icon_name` | `character varying` | `YES` | `` |
| 7 | `is_unlocked` | `boolean` | `YES` | `` |
| 8 | `unlocked_at` | `date` | `YES` | `` |

Constraints:
- `CHECK` `2200_16508_1_not_null` on ``
- `PRIMARY KEY` `achievements_pkey` on `id`

Indexes:
- `achievements_pkey`: `CREATE UNIQUE INDEX achievements_pkey ON public.achievements USING btree (id)`
- `ix_achievements_achievement_key`: `CREATE INDEX ix_achievements_achievement_key ON public.achievements USING btree (achievement_key)`
- `ix_achievements_id`: `CREATE INDEX ix_achievements_id ON public.achievements USING btree (id)`
- `ix_achievements_user_id`: `CREATE INDEX ix_achievements_user_id ON public.achievements USING btree (user_id)`

### `public.card_results`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('card_results_id_seq'::regclass)` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `trade_date` | `date` | `NO` | `` |
| 4 | `card_type` | `character varying` | `NO` | `` |
| 5 | `title` | `character varying` | `NO` | `` |
| 6 | `message` | `character varying` | `NO` | `` |
| 7 | `action_text` | `character varying` | `NO` | `` |

Constraints:
- `CHECK` `2200_16497_1_not_null` on ``
- `CHECK` `2200_16497_2_not_null` on ``
- `CHECK` `2200_16497_3_not_null` on ``
- `CHECK` `2200_16497_4_not_null` on ``
- `CHECK` `2200_16497_5_not_null` on ``
- `CHECK` `2200_16497_6_not_null` on ``
- `CHECK` `2200_16497_7_not_null` on ``
- `PRIMARY KEY` `card_results_pkey` on `id`

Indexes:
- `card_results_pkey`: `CREATE UNIQUE INDEX card_results_pkey ON public.card_results USING btree (id)`
- `ix_card_results_trade_date`: `CREATE INDEX ix_card_results_trade_date ON public.card_results USING btree (trade_date)`
- `ix_card_results_user_id`: `CREATE INDEX ix_card_results_user_id ON public.card_results USING btree (user_id)`

### `public.daily_packs`

Estimated rows: `3`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('daily_packs_id_seq'::regclass)` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `trade_date` | `date` | `NO` | `` |
| 4 | `opened` | `boolean` | `NO` | `` |
| 5 | `pack_json` | `text` | `NO` | `` |

Constraints:
- `CHECK` `2200_16572_1_not_null` on ``
- `CHECK` `2200_16572_2_not_null` on ``
- `CHECK` `2200_16572_3_not_null` on ``
- `CHECK` `2200_16572_4_not_null` on ``
- `CHECK` `2200_16572_5_not_null` on ``
- `PRIMARY KEY` `daily_packs_pkey` on `id`

Indexes:
- `daily_packs_pkey`: `CREATE UNIQUE INDEX daily_packs_pkey ON public.daily_packs USING btree (id)`
- `ix_daily_packs_trade_date`: `CREATE INDEX ix_daily_packs_trade_date ON public.daily_packs USING btree (trade_date)`
- `ix_daily_packs_user_id`: `CREATE INDEX ix_daily_packs_user_id ON public.daily_packs USING btree (user_id)`

### `public.fortune_results`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('fortune_results_id_seq'::regclass)` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `trade_date` | `date` | `NO` | `` |
| 4 | `session` | `character varying` | `YES` | `` |
| 5 | `stick_number` | `integer` | `NO` | `` |
| 6 | `overall_level` | `character varying` | `NO` | `` |
| 7 | `level_note` | `character varying` | `NO` | `` |
| 8 | `holdings_json` | `text` | `NO` | `` |
| 9 | `summary` | `text` | `NO` | `` |
| 10 | `stance` | `character varying` | `NO` | `` |
| 11 | `stance_note` | `character varying` | `NO` | `` |
| 12 | `notices_json` | `text` | `NO` | `` |

Constraints:
- `CHECK` `2200_16547_10_not_null` on ``
- `CHECK` `2200_16547_11_not_null` on ``
- `CHECK` `2200_16547_12_not_null` on ``
- `CHECK` `2200_16547_1_not_null` on ``
- `CHECK` `2200_16547_2_not_null` on ``
- `CHECK` `2200_16547_3_not_null` on ``
- `CHECK` `2200_16547_5_not_null` on ``
- `CHECK` `2200_16547_6_not_null` on ``
- `CHECK` `2200_16547_7_not_null` on ``
- `CHECK` `2200_16547_8_not_null` on ``
- `CHECK` `2200_16547_9_not_null` on ``
- `PRIMARY KEY` `fortune_results_pkey` on `id`

Indexes:
- `fortune_results_pkey`: `CREATE UNIQUE INDEX fortune_results_pkey ON public.fortune_results USING btree (id)`
- `ix_fortune_results_session`: `CREATE INDEX ix_fortune_results_session ON public.fortune_results USING btree (session)`
- `ix_fortune_results_trade_date`: `CREATE INDEX ix_fortune_results_trade_date ON public.fortune_results USING btree (trade_date)`
- `ix_fortune_results_user_id`: `CREATE INDEX ix_fortune_results_user_id ON public.fortune_results USING btree (user_id)`

### `public.holding_activities`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `character varying` | `NO` | `` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `symbol` | `character varying` | `NO` | `` |
| 4 | `activity_type` | `character varying` | `NO` | `` |
| 5 | `shares_delta` | `integer` | `NO` | `` |
| 6 | `price` | `double precision` | `YES` | `` |
| 7 | `broker` | `character varying` | `YES` | `` |
| 8 | `realized_pnl` | `double precision` | `YES` | `` |
| 9 | `avg_price_after` | `double precision` | `YES` | `` |
| 10 | `created_at` | `timestamp without time zone` | `NO` | `` |

Constraints:
- `CHECK` `2200_16519_10_not_null` on ``
- `CHECK` `2200_16519_1_not_null` on ``
- `CHECK` `2200_16519_2_not_null` on ``
- `CHECK` `2200_16519_3_not_null` on ``
- `CHECK` `2200_16519_4_not_null` on ``
- `CHECK` `2200_16519_5_not_null` on ``
- `PRIMARY KEY` `holding_activities_pkey` on `id`

Indexes:
- `holding_activities_pkey`: `CREATE UNIQUE INDEX holding_activities_pkey ON public.holding_activities USING btree (id)`
- `ix_holding_activities_symbol`: `CREATE INDEX ix_holding_activities_symbol ON public.holding_activities USING btree (symbol)`
- `ix_holding_activities_user_id`: `CREATE INDEX ix_holding_activities_user_id ON public.holding_activities USING btree (user_id)`

### `public.market_index_daily`

Estimated rows: `2`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('market_index_daily_id_seq'::regclass)` |
| 2 | `index_code` | `character varying` | `NO` | `` |
| 3 | `trade_date` | `date` | `NO` | `` |
| 4 | `close_price` | `double precision` | `NO` | `` |
| 5 | `change_percent` | `double precision` | `NO` | `` |

Constraints:
- `CHECK` `2200_16469_1_not_null` on ``
- `CHECK` `2200_16469_2_not_null` on ``
- `CHECK` `2200_16469_3_not_null` on ``
- `CHECK` `2200_16469_4_not_null` on ``
- `CHECK` `2200_16469_5_not_null` on ``
- `PRIMARY KEY` `market_index_daily_pkey` on `id`

Indexes:
- `ix_market_index_daily_index_code`: `CREATE INDEX ix_market_index_daily_index_code ON public.market_index_daily USING btree (index_code)`
- `ix_market_index_daily_trade_date`: `CREATE INDEX ix_market_index_daily_trade_date ON public.market_index_daily USING btree (trade_date)`
- `market_index_daily_pkey`: `CREATE UNIQUE INDEX market_index_daily_pkey ON public.market_index_daily USING btree (id)`

### `public.portfolio_items`

Estimated rows: `5`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `character varying` | `NO` | `` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `symbol` | `character varying` | `NO` | `` |
| 4 | `cost_price` | `double precision` | `YES` | `` |
| 5 | `shares` | `integer` | `YES` | `` |
| 6 | `broker` | `character varying` | `YES` | `` |
| 7 | `status` | `character varying` | `YES` | `` |
| 8 | `source` | `character varying` | `YES` | `` |
| 9 | `created_at` | `timestamp without time zone` | `NO` | `` |
| 10 | `updated_at` | `timestamp without time zone` | `YES` | `` |

Constraints:
- `CHECK` `2200_16479_1_not_null` on ``
- `CHECK` `2200_16479_2_not_null` on ``
- `CHECK` `2200_16479_3_not_null` on ``
- `CHECK` `2200_16479_9_not_null` on ``
- `PRIMARY KEY` `portfolio_items_pkey` on `id`

Indexes:
- `ix_portfolio_items_symbol`: `CREATE INDEX ix_portfolio_items_symbol ON public.portfolio_items USING btree (symbol)`
- `ix_portfolio_items_user_id`: `CREATE INDEX ix_portfolio_items_user_id ON public.portfolio_items USING btree (user_id)`
- `portfolio_items_pkey`: `CREATE UNIQUE INDEX portfolio_items_pkey ON public.portfolio_items USING btree (id)`

### `public.push_devices`

Estimated rows: `5`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `character varying` | `NO` | `` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `platform` | `character varying` | `NO` | `` |
| 4 | `environment` | `character varying` | `NO` | `` |
| 5 | `device_token` | `character varying` | `NO` | `` |
| 6 | `device_token_hash` | `character varying` | `NO` | `` |
| 7 | `sns_endpoint_arn` | `character varying` | `YES` | `` |
| 8 | `enabled` | `boolean` | `NO` | `` |
| 9 | `last_registered_at` | `timestamp without time zone` | `NO` | `` |
| 10 | `created_at` | `timestamp without time zone` | `NO` | `` |
| 11 | `updated_at` | `timestamp without time zone` | `NO` | `` |

Constraints:
- `CHECK` `2200_16558_10_not_null` on ``
- `CHECK` `2200_16558_11_not_null` on ``
- `CHECK` `2200_16558_1_not_null` on ``
- `CHECK` `2200_16558_2_not_null` on ``
- `CHECK` `2200_16558_3_not_null` on ``
- `CHECK` `2200_16558_4_not_null` on ``
- `CHECK` `2200_16558_5_not_null` on ``
- `CHECK` `2200_16558_6_not_null` on ``
- `CHECK` `2200_16558_8_not_null` on ``
- `CHECK` `2200_16558_9_not_null` on ``
- `PRIMARY KEY` `push_devices_pkey` on `id`
- `UNIQUE` `uq_push_device_env_token` on `environment, device_token_hash`

Indexes:
- `ix_push_devices_device_token_hash`: `CREATE INDEX ix_push_devices_device_token_hash ON public.push_devices USING btree (device_token_hash)`
- `ix_push_devices_environment`: `CREATE INDEX ix_push_devices_environment ON public.push_devices USING btree (environment)`
- `ix_push_devices_user_id`: `CREATE INDEX ix_push_devices_user_id ON public.push_devices USING btree (user_id)`
- `push_devices_pkey`: `CREATE UNIQUE INDEX push_devices_pkey ON public.push_devices USING btree (id)`
- `uq_push_device_env_token`: `CREATE UNIQUE INDEX uq_push_device_env_token ON public.push_devices USING btree (environment, device_token_hash)`

### `public.reminder_settings`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `user_id` | `character varying` | `NO` | `` |
| 2 | `enabled` | `boolean` | `NO` | `` |
| 3 | `time_slot` | `character varying` | `NO` | `` |
| 4 | `anxiety_score` | `boolean` | `NO` | `` |
| 5 | `daily_card` | `boolean` | `NO` | `` |
| 6 | `volatility_alert` | `boolean` | `NO` | `` |

Constraints:
- `CHECK` `2200_16488_1_not_null` on ``
- `CHECK` `2200_16488_2_not_null` on ``
- `CHECK` `2200_16488_3_not_null` on ``
- `CHECK` `2200_16488_4_not_null` on ``
- `CHECK` `2200_16488_5_not_null` on ``
- `CHECK` `2200_16488_6_not_null` on ``
- `PRIMARY KEY` `reminder_settings_pkey` on `user_id`

Indexes:
- `ix_reminder_settings_user_id`: `CREATE INDEX ix_reminder_settings_user_id ON public.reminder_settings USING btree (user_id)`
- `reminder_settings_pkey`: `CREATE UNIQUE INDEX reminder_settings_pkey ON public.reminder_settings USING btree (user_id)`

### `public.stock_daily_prices`

Estimated rows: `13`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `integer` | `NO` | `nextval('stock_daily_prices_id_seq'::regclass)` |
| 2 | `symbol` | `character varying` | `NO` | `` |
| 3 | `trade_date` | `date` | `NO` | `` |
| 4 | `close_price` | `double precision` | `NO` | `` |
| 5 | `change_percent` | `double precision` | `NO` | `` |
| 6 | `volume` | `double precision` | `YES` | `` |

Constraints:
- `CHECK` `2200_16458_1_not_null` on ``
- `CHECK` `2200_16458_2_not_null` on ``
- `CHECK` `2200_16458_3_not_null` on ``
- `CHECK` `2200_16458_4_not_null` on ``
- `CHECK` `2200_16458_5_not_null` on ``
- `PRIMARY KEY` `stock_daily_prices_pkey` on `id`

Indexes:
- `ix_stock_daily_prices_symbol`: `CREATE INDEX ix_stock_daily_prices_symbol ON public.stock_daily_prices USING btree (symbol)`
- `ix_stock_daily_prices_trade_date`: `CREATE INDEX ix_stock_daily_prices_trade_date ON public.stock_daily_prices USING btree (trade_date)`
- `stock_daily_prices_pkey`: `CREATE UNIQUE INDEX stock_daily_prices_pkey ON public.stock_daily_prices USING btree (id)`

### `public.stocks`

Estimated rows: `10`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `symbol` | `character varying` | `NO` | `` |
| 2 | `name` | `character varying` | `NO` | `` |
| 3 | `market` | `character varying` | `NO` | `` |
| 4 | `industry` | `character varying` | `NO` | `` |

Constraints:
- `CHECK` `2200_16449_1_not_null` on ``
- `CHECK` `2200_16449_2_not_null` on ``
- `CHECK` `2200_16449_3_not_null` on ``
- `CHECK` `2200_16449_4_not_null` on ``
- `PRIMARY KEY` `stocks_pkey` on `symbol`

Indexes:
- `ix_stocks_symbol`: `CREATE INDEX ix_stocks_symbol ON public.stocks USING btree (symbol)`
- `stocks_pkey`: `CREATE UNIQUE INDEX stocks_pkey ON public.stocks USING btree (symbol)`

### `public.watchlist_items`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `character varying` | `NO` | `` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `watchlist_id` | `character varying` | `NO` | `` |
| 4 | `symbol` | `character varying` | `NO` | `` |
| 5 | `created_at` | `timestamp without time zone` | `NO` | `` |

Constraints:
- `CHECK` `2200_16536_1_not_null` on ``
- `CHECK` `2200_16536_2_not_null` on ``
- `CHECK` `2200_16536_3_not_null` on ``
- `CHECK` `2200_16536_4_not_null` on ``
- `CHECK` `2200_16536_5_not_null` on ``
- `PRIMARY KEY` `watchlist_items_pkey` on `id`

Indexes:
- `ix_watchlist_items_symbol`: `CREATE INDEX ix_watchlist_items_symbol ON public.watchlist_items USING btree (symbol)`
- `ix_watchlist_items_user_id`: `CREATE INDEX ix_watchlist_items_user_id ON public.watchlist_items USING btree (user_id)`
- `ix_watchlist_items_watchlist_id`: `CREATE INDEX ix_watchlist_items_watchlist_id ON public.watchlist_items USING btree (watchlist_id)`
- `watchlist_items_pkey`: `CREATE UNIQUE INDEX watchlist_items_pkey ON public.watchlist_items USING btree (id)`

### `public.watchlists`

Estimated rows: `0`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `id` | `character varying` | `NO` | `` |
| 2 | `user_id` | `character varying` | `NO` | `` |
| 3 | `name` | `character varying` | `NO` | `` |
| 4 | `color` | `character varying` | `YES` | `` |
| 5 | `created_at` | `timestamp without time zone` | `NO` | `` |
| 6 | `updated_at` | `timestamp without time zone` | `YES` | `` |

Constraints:
- `CHECK` `2200_16528_1_not_null` on ``
- `CHECK` `2200_16528_2_not_null` on ``
- `CHECK` `2200_16528_3_not_null` on ``
- `CHECK` `2200_16528_5_not_null` on ``
- `PRIMARY KEY` `watchlists_pkey` on `id`

Indexes:
- `ix_watchlists_user_id`: `CREATE INDEX ix_watchlists_user_id ON public.watchlists USING btree (user_id)`
- `watchlists_pkey`: `CREATE UNIQUE INDEX watchlists_pkey ON public.watchlists USING btree (id)`

## Schema `raw`

### `raw.raw_00_field_dictionary_and_usage_notes`

Estimated rows: `40`

Source CSV: `00_Field_Dictionary_and_Usage_Notes.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `檔案` | `text` | `YES` | `` |
| 2 | `欄位` | `text` | `YES` | `` |
| 3 | `說明` | `text` | `YES` | `` |
| 4 | `來源表` | `text` | `YES` | `` |
| 5 | `取數範圍` | `text` | `YES` | `` |

### `raw.raw_01_price_valuation_2025`

Estimated rows: `72462`

Source CSV: `01_Price_Valuation_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `日期` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `開盤價` | `text` | `YES` | `` |
| 5 | `最高價` | `text` | `YES` | `` |
| 6 | `最低價` | `text` | `YES` | `` |
| 7 | `收盤價` | `text` | `YES` | `` |
| 8 | `漲跌` | `text` | `YES` | `` |
| 9 | `漲幅(%)` | `text` | `YES` | `` |
| 10 | `成交量` | `text` | `YES` | `` |
| 11 | `成交金額(千)` | `text` | `YES` | `` |
| 12 | `股本(百萬)` | `text` | `YES` | `` |
| 13 | `總市值(億)` | `text` | `YES` | `` |
| 14 | `市值比重(%)` | `text` | `YES` | `` |
| 15 | `本益比` | `text` | `YES` | `` |
| 16 | `本益比(近四季)` | `text` | `YES` | `` |
| 17 | `股價淨值比` | `text` | `YES` | `` |
| 18 | `週轉率(%)` | `text` | `YES` | `` |
| 19 | `漲跌停` | `text` | `YES` | `` |

### `raw.raw_02_institutional_trading_2025`

Estimated rows: `72462`

Source CSV: `02_Institutional_Trading_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `日期` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `外資買賣超` | `text` | `YES` | `` |
| 5 | `投信買賣超` | `text` | `YES` | `` |
| 6 | `自營商買賣超` | `text` | `YES` | `` |
| 7 | `買賣超合計` | `text` | `YES` | `` |
| 8 | `外資持股(張)` | `text` | `YES` | `` |
| 9 | `外資持股比率(%)` | `text` | `YES` | `` |
| 10 | `投信持股比率(%)` | `text` | `YES` | `` |
| 11 | `自營商持股比率(%)` | `text` | `YES` | `` |
| 12 | `法人持股比率(%)` | `text` | `YES` | `` |
| 13 | `外資持股市值(百萬)` | `text` | `YES` | `` |
| 14 | `法人持股市值(百萬)` | `text` | `YES` | `` |

### `raw.raw_03_return_rate_2025`

Estimated rows: `72462`

Source CSV: `03_Return_Rate_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `日期` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `還原收盤價` | `text` | `YES` | `` |
| 5 | `日報酬率(%)` | `text` | `YES` | `` |
| 6 | `週報酬率(%)` | `text` | `YES` | `` |
| 7 | `月報酬率(%)` | `text` | `YES` | `` |
| 8 | `季報酬率(%)` | `text` | `YES` | `` |
| 9 | `半年報酬率(%)` | `text` | `YES` | `` |
| 10 | `年報酬率(%)` | `text` | `YES` | `` |
| 11 | `與大盤比年報酬率(%)` | `text` | `YES` | `` |
| 12 | `殖利率(%)` | `text` | `YES` | `` |

### `raw.raw_04_distance_from_high_low_momentum_2025`

Estimated rows: `64478`

Source CSV: `04_Distance_from_High_Low_Momentum_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `日期` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `今年以來新高價` | `text` | `YES` | `` |
| 5 | `今年以來新低價` | `text` | `YES` | `` |
| 6 | `今年以來漲跌幅%` | `text` | `YES` | `` |
| 7 | `近5日漲跌幅%` | `text` | `YES` | `` |
| 8 | `近20日漲跌幅%` | `text` | `YES` | `` |
| 9 | `近60日漲跌幅%` | `text` | `YES` | `` |
| 10 | `股價乖離月線(%)` | `text` | `YES` | `` |
| 11 | `股價乖離季線(%)` | `text` | `YES` | `` |
| 12 | `股價乖離年線(%)` | `text` | `YES` | `` |
| 13 | `股價創歷史新高` | `text` | `YES` | `` |
| 14 | `股價創N日新高` | `text` | `YES` | `` |
| 15 | `股價連N日漲` | `text` | `YES` | `` |

### `raw.raw_05_dividend_ex_dividend_2025`

Estimated rows: `289`

Source CSV: `05_Dividend_Ex_Dividend_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `年度` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `配發次數` | `text` | `YES` | `` |
| 5 | `現金股利合計(元)` | `text` | `YES` | `` |
| 6 | `股票股利合計(元)` | `text` | `YES` | `` |
| 7 | `現金股利殖利率(%)` | `text` | `YES` | `` |
| 8 | `股利發放率(%)` | `text` | `YES` | `` |
| 9 | `除息日` | `text` | `YES` | `` |
| 10 | `除權日` | `text` | `YES` | `` |
| 11 | `除息最後回補日` | `text` | `YES` | `` |
| 12 | `股東會日期` | `text` | `YES` | `` |

### `raw.raw_06_consecutive_dividend_stocks_2025`

Estimated rows: `266`

Source CSV: `06_Consecutive_Dividend_Stocks_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `年度` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `現金股利連N年遞增` | `text` | `YES` | `` |
| 5 | `連續N年發放現金股利` | `text` | `YES` | `` |
| 6 | `現金股利排名` | `text` | `YES` | `` |
| 7 | `現金股利殖利率排名` | `text` | `YES` | `` |

### `raw.raw_06b_consecutive_dividend_etf_2025`

Estimated rows: `34`

Source CSV: `06b_Consecutive_Dividend_ETF_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `年度` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `現金股利連N年遞增` | `text` | `YES` | `` |
| 5 | `連續N年發放現金股利` | `text` | `YES` | `` |
| 6 | `現金股利排名` | `text` | `YES` | `` |
| 7 | `現金股利殖利率排名` | `text` | `YES` | `` |

### `raw.raw_07_industry_classification_mapping`

Estimated rows: `300`

Source CSV: `07_Industry_Classification_Mapping.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `股票代號` | `text` | `YES` | `` |
| 2 | `股票名稱` | `text` | `YES` | `` |
| 3 | `上市上櫃` | `text` | `YES` | `` |
| 4 | `主產業` | `text` | `YES` | `` |
| 5 | `全部產業標籤` | `text` | `YES` | `` |

### `raw.raw_09_wide_table_summary_one_row_per_stock_2025`

Estimated rows: `300`

Source CSV: `09_Wide_Table_Summary_One_Row_Per_Stock_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `股票代號` | `text` | `YES` | `` |
| 2 | `股票名稱` | `text` | `YES` | `` |
| 3 | `市場` | `text` | `YES` | `` |
| 4 | `產業` | `text` | `YES` | `` |
| 5 | `收盤價` | `text` | `YES` | `` |
| 6 | `總市值(億)` | `text` | `YES` | `` |
| 7 | `市值比重(%)` | `text` | `YES` | `` |
| 8 | `本益比(近四季)` | `text` | `YES` | `` |
| 9 | `股價淨值比` | `text` | `YES` | `` |
| 10 | `週轉率(%)` | `text` | `YES` | `` |
| 11 | `季報酬率(%)` | `text` | `YES` | `` |
| 12 | `年報酬率(%)` | `text` | `YES` | `` |
| 13 | `與大盤比年報酬(%)` | `text` | `YES` | `` |
| 14 | `殖利率(%)` | `text` | `YES` | `` |
| 15 | `近20日法人買賣超` | `text` | `YES` | `` |
| 16 | `外資持股率(%)` | `text` | `YES` | `` |
| 17 | `法人持股率(%)` | `text` | `YES` | `` |
| 18 | `連續配息年數` | `text` | `YES` | `` |
| 19 | `最新年度現金股利` | `text` | `YES` | `` |
| 20 | `股利發放率(%)` | `text` | `YES` | `` |
| 21 | `最近除息日` | `text` | `YES` | `` |
| 22 | `同學會瀏覽次數` | `text` | `YES` | `` |
| 23 | `同學會瀏覽人數` | `text` | `YES` | `` |
| 24 | `今年新高` | `text` | `YES` | `` |
| 25 | `今年新低` | `text` | `YES` | `` |
| 26 | `今年以來(%)` | `text` | `YES` | `` |
| 27 | `距年線乖離(%)` | `text` | `YES` | `` |
| 28 | `買點分位(%)` | `text` | `YES` | `` |
| 29 | `創歷史新高` | `text` | `YES` | `` |

### `raw.raw_10_forum_posts_replies_daily_stats_2025`

Estimated rows: `105798`

Source CSV: `10_Forum_Posts_Replies_Daily_Stats_2025.csv`

| # | Column | Type | Nullable | Default |
|---:|---|---|---|---|
| 1 | `日期` | `text` | `YES` | `` |
| 2 | `股票代號` | `text` | `YES` | `` |
| 3 | `股票名稱` | `text` | `YES` | `` |
| 4 | `發文則數` | `text` | `YES` | `` |
| 5 | `發文人數` | `text` | `YES` | `` |
| 6 | `看多發文` | `text` | `YES` | `` |
| 7 | `看空發文` | `text` | `YES` | `` |
| 8 | `中性發文` | `text` | `YES` | `` |
| 9 | `回文則數` | `text` | `YES` | `` |
| 10 | `回文人數` | `text` | `YES` | `` |
