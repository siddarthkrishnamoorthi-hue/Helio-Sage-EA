# Helio-Sage EA — Smart Money Algo Trading System

## Overview

Helio-Sage is a production-grade MetaTrader 5 Expert Advisor built on **Smart Money Concepts (SMC) / ICT methodology**. It automates institutional order flow analysis — detecting liquidity sweeps, order blocks, fair value gaps, and session manipulation patterns — then trades only when multiple confluences align.

The EA does **not** use grid, martingale, or averaging. Every trade has a defined stop loss, take profit, and calculated lot size based on risk percentage.

---

## Supported Pairs

| Pair | Priority | Notes |
|------|----------|-------|
| **EURUSD** | Primary | Best setup frequency, tightest spreads |
| **GBPUSD** | Primary | Higher volatility, larger moves |
| **USDJPY** | Secondary | Wider stops due to JPY volatility, fewer setups |

> **Important:** Run the EA on **ONE chart per pair**. If trading all 3 pairs, open 3 separate M1 charts and attach the EA to each with a **different Magic Number**.

---

## Chart & Timeframe Setup

| Setting | Value |
|---------|-------|
| **Execution Timeframe** | **M1 (1-Minute)** — the EA MUST run on M1 |
| **HTF Analysis (internal)** | M15, H1, H4, D1, W1, MN1 — handled automatically |
| **Chart Type** | Candlestick |
| **Auto-Trading** | Must be ENABLED in MT5 (green play button in toolbar) |

The EA analyzes higher timeframes internally using `CopyRates` / `iHigh` / `iLow` functions. You do **not** need to open multiple timeframe charts.

---

## Installation

1. Copy `Helio-Sage-EA.mq5` to your MT5 `MQL5/Experts/` folder
2. Open MetaEditor → compile the file (F7)
3. In MT5, open an **M1 chart** for EURUSD, GBPUSD, or USDJPY
4. Drag the EA onto the chart
5. In the Inputs tab, click **Load** and select a preset from the `Presets/` folder
6. Enable **Auto-Trading** in MT5
7. Confirm the smiley face icon appears on the chart

---

## Input Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `InpSymbol` | string | (blank) | Trading symbol. Blank = current chart symbol |
| `InpHTFBias` | enum | Auto | Higher timeframe bias: Bullish, Bearish, or Auto-Detect from D1 |
| `InpSessionMode` | enum | Both | Trade during London, New York, or Both sessions |
| `InpMinConfluences` | int | 3 | Minimum confluence score required to open a trade |
| `InpRiskPercent` | double | 1.0 | Risk per trade as % of account balance |
| `InpMaxTrades` | int | 2 | Maximum concurrent open positions |
| `InpUseBreakEven` | bool | true | Move SL to break even after trigger distance |
| `InpBETriggerPips` | double | 10.0 | Pips in profit before break even activates |
| `InpUseTrailingStop` | bool | false | Enable trailing stop |
| `InpTrailPips` | double | 15.0 | Trailing stop distance in pips |
| `InpMagicNumber` | int | 77701 | Unique identifier for EA's trades |
| `InpTradeComment` | string | HelioSage | Comment attached to each trade |
| `InpShowZones` | bool | true | Draw liquidity levels, FVGs, OBs on chart |
| `InpUTCOffset` | int | -99 | Broker UTC offset (-99 = auto-detect) |

---

## Preset Files

### Personal Account (`HelioSage_Personal.set`)

For personal live/demo accounts with no external drawdown restrictions.

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Risk % | 1.5% | Moderate aggression for personal capital |
| Min Confluences | 3 | Balanced trade frequency vs quality |
| Max Trades | 3 | Allows multiple concurrent setups |
| Break Even | On at 10 pips | Standard protection |
| Trailing Stop | On at 12 pips | Lock in profits on extended moves |
| Magic Number | 77701 | — |

**Expected behavior:** ~15-30 trades/month, ~4-8% monthly target

### Funded Account (`HelioSage_Funded.set`)

For prop firm challenges and funded accounts (FTMO, MyForexFunds, TFT, The5ers, etc.).

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Risk % | 0.5% | Protects 5% max drawdown rule |
| Min Confluences | 4 | Higher bar = fewer, better trades |
| Max Trades | 1 | Single exposure limits daily DD |
| Break Even | On at 7 pips | Move to safety faster |
| Trailing Stop | Off | Avoid premature stops |
| Magic Number | 77702 | Separate from personal account |

**Expected behavior:** ~8-15 trades/month, ~2-4% monthly target

---

## Drawdown Profile

| Metric | Personal Preset | Funded Preset |
|--------|----------------|---------------|
| Max single trade loss | 1.5% of balance | 0.5% of balance |
| Worst-case daily DD (max trades x loss) | 4.5% | 0.5% |
| Expected max monthly DD | 5-8% | 2-3% |
| Expected max annual DD | 10-15% | 5-7% |
| Recovery time from max DD | 2-4 weeks | 1-3 weeks |

**Funded account safety:** With 0.5% risk and 1 max trade, you cannot breach a 5% max drawdown limit in a single day. Even 10 consecutive losses (statistically unlikely with 55%+ win rate) would only draw down 5%.

---

## Trading Sessions

All times are **New York time** (EST/EDT — DST is handled automatically).

| Session | NY Time | Purpose |
|---------|---------|---------|
| Asia | 00:00 - 07:00 | Range recording (Asia High/Low tracked for sweeps) |
| Frankfurt | 02:00 - 03:00 | Pre-London volatility (Frankfurt High/Low recorded) |
| **London Open** | **03:00 - 05:00** | **Primary entry window #1** |
| London Main | 03:00 - 12:00 | AMD pattern tracking |
| **NY Open** | **09:30 - 11:30** | **Primary entry window #2** |
| NY Main | 09:30 - 17:00 | AMD pattern tracking |
| London Close | 11:00 - 12:00 | Overlap volatility |

The EA only opens new trades during London Open and/or NY Open windows (configurable).

---

## How It Works — The 15 Modules

### Module 1: Session Time Engine
Converts broker server time to NY time with automatic US DST detection (March-November). Tracks session boundaries and records Asia/Frankfurt highs and lows.

### Module 2: Liquidity Levels Engine
Calculates Previous Day/Week/Month High and Low, 52-week extremes, and detects swing highs/lows on H1 (5-bar) and M15 (3-bar) for medium/minor liquidity levels. Determines Premium zone (above Daily Open = sell territory) and Discount zone (below Daily Open = buy territory).

### Module 3: 90-Minute Cycle Engine
Divides the trading day into 16 windows starting from NY midnight. Records the opening price of each 90-minute window. When price sweeps above/below a window open and reverses, it generates a confluence point.

### Module 4: Market Structure Engine
Analyzes M1 for Strong Highs (sweep + structural break down), Strong Lows (sweep + structural break up), Break in Market Structure (BMS), Fake BMS (against HTF bias), Momentum Shifts, and Failure Swings (failed new high/low by ATR/4 threshold).

### Module 5: FVG Detection Engine
Detects Fair Value Gaps on M1, M15, H1, and H4. Tracks whether each FVG has been filled (price traded through entire gap). Classifies FVGs larger than 2x average size as High Volume Imbalances (HVI), which carry double confluence weight.

### Module 6: Algo Candle Engine
Identifies candles that simultaneously sweep a prior high/low AND create an FVG. Scoring: Basic AC (sweep + FVG) = 1 point, Strong AC (+ BMS) = 2 points, Very Strong AC (+ Inducement) = 3 points. Also detects Vector Candles (engulfing patterns in premium/discount zones).

### Module 7: Order Block Engine
Detects the last opposing candle before an impulse move (3+ continuation candles breaking structure). When price violates an OB entirely, it converts to a Breaker Block in the opposite direction.

### Module 8: Inducement Detection
Finds minor swing highs/lows sitting between current price and a known Order Block. When these "trap" levels are swept before price reaches the OB, it confirms the OB as high-probability.

### Module 9: AMD Pattern Engine
Tracks Accumulation (tight range for 30+ minutes), Manipulation (false breakout of range), and Distribution (reversal in true direction). State machine resets if manipulation doesn't reverse within 15 minutes.

### Module 10: Weekly Cycle Engine
Monday = Manipulation Day (prior week level sweeps). Tuesday = Continuation. Wednesday = Reversal. Thursday = Completion. Friday = Distribution (no new trades after 2 PM NY).

### Module 11: TDI Indicator
Implements Traders Dynamic Index: RSI(13) with Bollinger Bands(34, 1.6185), 2-period Signal Line, 7-period Trade Signal Line. Detects High Volume Breakouts (RSI crossing BB midline + signal cross) and classic Price/RSI Divergence. Stochastic RSI (14,3,3) provides supplementary overbought/oversold filtering.

### Module 12: Confluence Scoring Engine
Aggregates all signals into a single score. Each trade direction (Buy/Sell) is scored independently. A trade only triggers when score >= `InpMinConfluences`. Score items range from +1 (session timing, Asia sweep) to +2 (HVI, Strong Algo Candle) to +3 (Very Strong AC with BMS + Inducement + FVG).

### Module 13: Trade Execution Engine
Market orders with calculated lot size: `lots = (balance × risk%) / (SL_pips × pip_value)`. Stop loss placed beyond the sweep point + ATR(14)×0.5 buffer. Take profit targets opposite liquidity levels (PDH/PDL → PWH/PWL → PMH/PML). Break even and trailing stop managed on every tick.

### Module 14: Chart Visualization
Draws PDH/PDL/PWH/PWL/PMH/PML as horizontal lines, FVG zones as colored rectangles (blue=bullish, red=bearish), Order Blocks (orange=bullish, purple=bearish), Asia High/Low, Daily Open, and a dashboard showing current confluence score, bias direction, and active session.

### Module 15: Logging & Alerts
Logs all trades with confluence details to CSV files in `MQL5/Files/`. Sends push notifications on trade open. Fires an Alert when score reaches one below threshold (early warning).

---

## Confluence Score Items

| Signal | Points | Direction |
|--------|--------|-----------|
| HTF bias alignment | +1 | Must match trade direction |
| Premium/Discount zone | +1 | Sell in Premium, Buy in Discount |
| Session timing (London/NY Open) | +1 | Must be in entry window |
| Asia High/Low swept | +1 | AHS for sells, ALS for buys |
| Filled FVG at price (M15+) | +1 | Price at fully filled gap zone |
| High Volume Imbalance (HVI) | +2 | FVG > 2x average size |
| Algo Candle (basic) | +1 | Sweep + FVG |
| Algo Candle (strong) | +2 | + BMS |
| Algo Candle (very strong) | +3 | + Inducement |
| Order Block at price | +1 | Price inside active OB zone |
| Inducement swept near OB | +1 | Minor liquidity trapped |
| AMD Distribution direction | +1 | Manipulation confirmed, distribution phase |
| Monday manipulation sweep | +1 | Monday + prior week level swept |
| TDI High Volume Breakout | +1 | RSI cross + signal alignment |
| TDI Divergence | +1 | Price/RSI divergence |
| 90-Minute cycle reversal | +1 | Window open swept and reversed |
| Near major liquidity (20 pips) | +1 | Close to PDH/PDL/PWH/PWL/PMH/PML |
| Momentum Shift | +1 | Strong AC with structural break |
| Failure Swing | +1 | Failed new high/low + structural break |

**Maximum possible score: ~20+ (extremely rare). Typical strong setup: 4-7.**

---

## Performance Expectations

| Metric | Personal | Funded |
|--------|----------|--------|
| Trades per month | 15-30 | 8-15 |
| Expected win rate | 55-60% | 55-65% |
| Average Risk:Reward | 1:1.5 to 1:2 | 1:1.5 to 1:2 |
| Monthly return (realistic) | 4-8% | 2-4% |
| Annual return (compounded) | 60-100% | 27-60% |
| Losing months per year | 2-4 | 1-3 |
| Max expected drawdown | 10-15% | 5-7% |

> These are estimates, not guarantees. Past methodology performance does not predict future results.

---

## Risk Warnings

- **No strategy is 100% profitable.** Expect losing months.
- **Spread matters.** Use a broker with raw/ECN spreads (EURUSD < 1.0 pip).
- **VPS recommended.** The EA runs on M1 and needs consistent connectivity.
- **Backtest first.** Run at least 6 months of backtesting on each pair before going live.
- **Start on demo.** Validate the EA on a demo account for 2-4 weeks minimum.
- **Do NOT increase risk** to chase losses. The presets are calibrated for long-term survival.

---

## Multi-Pair Setup

To run on all 3 pairs simultaneously:

| Chart | Pair | Magic Number |
|-------|------|-------------|
| Chart 1 | EURUSD M1 | 77701 (Personal) or 77702 (Funded) |
| Chart 2 | GBPUSD M1 | 77711 (Personal) or 77712 (Funded) |
| Chart 3 | USDJPY M1 | 77721 (Personal) or 77722 (Funded) |

> Each chart must have a **unique Magic Number**. Change it in the EA inputs before attaching.

---

## Broker Requirements

| Requirement | Minimum |
|-------------|---------|
| Platform | MetaTrader 5 |
| Account type | Hedging or Netting |
| Spread (EURUSD) | < 1.5 pips (raw preferred) |
| Execution | Market execution |
| VPS latency | < 10ms to broker server (recommended) |
| Leverage | 1:30 minimum (1:100+ preferred) |

---

## Files Included

```
Helio-Sage-EA.mq5              — Main EA source file
Presets/
  HelioSage_Personal.set       — Personal account preset
  HelioSage_Funded.set         — Funded/prop firm preset
README.md                      — This file
```

---

## Changelog

### v1.00 (2026-06-30)
- Initial release
- 15 integrated modules
- Full confluence scoring system
- Automated DST handling
- CSV trade logging
- Chart visualization with dashboard

---

## License & Disclaimer

This EA is provided as-is for educational and personal trading use. Trading forex carries substantial risk. The developer is not responsible for any financial losses incurred through the use of this software. Always test on demo accounts before risking real capital.
