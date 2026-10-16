# ProfitableStrategy_EA (MT4)

An Expert Advisor that trades the signals of your **ProfitableStrategy_11**
ZigZag-style indicator.

- **Lime / bottom marker (buffer 0)** → opens a **BUY** at 0.01 lot
- **Red / top marker (buffer 1)** → opens a **SELL** at 0.01 lot
- **Take-Profit** = 10 price units by default
  - BUY at 4000 → TP 4010
  - SELL at 4000 → TP 3990

---

## 1. Install

1. In MT4: **File → Open Data Folder**.
2. Copy `ProfitableStrategy_EA.mq4` into `MQL4\Experts\`.
3. Make sure your indicator `ProfitableStrategy_11.ex4` is in `MQL4\Indicators\`.
4. In MT4 open **Navigator**, right-click **Expert Advisors → Refresh**
   (or restart MT4). The EA appears in the list.
5. Drag it onto a **gold (XAUUSD)** chart on the timeframe you used in the
   screenshots. Tick **"Allow live trading"** and enable **AutoTrading**.

> You do **not** need the indicator's source code. The EA reads it with
> `iCustom`, which only needs the compiled `.ex4`.

---

## 1b. Confirmed from your Data Window

Your screenshots confirmed the setup:

- **Buffer 0** (`ZigZag(156,5,2)` line) = **bottom = BUY** (value = candle Low)
- **Buffer 1** (`Value 2`) = **top = SELL** (value = candle High)
- Empty slots read as `0.0000` → treated as "no signal"
- Parameters `156, 5, 2` match

### Why it may show no trades even when correct
ZigZag plots a pivot **back at the extreme candle**. By the time the pivot
is *confirmed*, that candle is already several bars in the past. So checking
only the last closed bar misses it. **v1.10 scans a window** (`ScanBars`) of
recent bars for a newly-appeared marker, which fixes this.

### Debug mode
`DebugMode = true` prints to the **Experts** tab (bottom of MT4) every new
bar, e.g. `Scan: newestBUY=... newestSELL=...`. If those times are blank,
`iCustom` isn't reading the indicator (parameter/name problem). If they show
real times and advance, signals are being read correctly.

---

## 2. ⚠️ If it still never trades — check parameters

The tooltip shows `ZigZag(156,5,2)`. The EA passes those three numbers to
the indicator in this order: **Depth = 156, Deviation = 5, Backstep = 2**
(inputs `InpDepth`, `InpDeviation`, `InpBackstep`).

Because I don't have the indicator's source, I can't see its exact input
list. **If the EA opens no trades, 95% of the time it's because these
parameters (count or order) don't match the indicator.** To verify the
buffers and parameters:

1. Attach the **indicator** to the chart.
2. Open the **Data Window** (Ctrl+D) and hover over a candle that has a
   red or green marker.
3. Confirm which buffer value (`Value1`, `Value2`, …) becomes a real number
   at the top vs the bottom markers.
   - `Value1` = buffer index 0, `Value2` = buffer index 1, etc.
4. Set `BuyBufferIndex` / `SellBufferIndex` in the EA to match.

If your indicator has **more or fewer than 3 inputs**, tell me and I'll
adjust the `iCustom` call — this is the only part I had to guess.

---

## 3. Is it repainting? (your question)

**Short answer: almost certainly yes, on the last leg.** ZigZag-type
indicators find the highest high / lowest low over a window. Until price
confirms a pivot, the most recent top/bottom can **move or disappear** as
new candles arrive. That is classic repainting — not a bug, it's how
ZigZag works. The historical markers (older pivots) stay fixed; only the
newest, still-forming one repaints.

**What this means for trading:** if you enter the instant a marker first
appears on the live candle, it may vanish and you're left in a bad trade.

**How this EA protects you:**

- It evaluates signals only when a **new bar opens**, reading the marker on
  a **closed bar** (`SignalShift = 1`), not the live candle.
- `ConfirmBars` lets you require the pivot to survive extra closed bars
  before trading (e.g. `ConfirmBars = 2` = wait 2 more bars). Higher =
  fewer repaint fakeouts but later entries.

This greatly reduces repaint damage but **cannot fully eliminate it** —
no EA can, because the indicator itself redraws. Backtest first.

---

## 4. Inputs

| Input | Default | Meaning |
|---|---|---|
| `LotSize` | 0.01 | Fixed lot per trade |
| `TP_Distance` | 10.0 | Take-Profit in price units ($10 on gold) |
| `SL_Distance` | 0.0 | Stop-Loss in price units (0 = none) |
| `Slippage` | 30 | Max slippage in points |
| `MagicNumber` | 77811 | EA's order id |
| `MaxOpenPositions` | 1 | Max trades open at once (0 = unlimited) |
| `IndicatorName` | ProfitableStrategy_11 | Indicator file name (no `.ex4`) |
| `InpDepth / InpDeviation / InpBackstep` | 156 / 5 / 2 | Indicator params (from tooltip) |
| `BuyBufferIndex` | 0 | Buffer with bottom/BUY markers (Lime) |
| `SellBufferIndex` | 1 | Buffer with top/SELL markers (Red) |
| `ScanBars` | 60 | Recent bars scanned for a new marker |
| `ConfirmBars` | 2 | Bars the pivot must survive before trading (anti-repaint) |
| `TradeOnlyNewSignals` | true | Ignore markers already present at attach time |
| `CloseOppositeFirst` | false | Close opposite EA trades on a new signal |
| `DebugMode` | true | Log buffer reads to the Experts tab |

---

## 5. Notes & safety

- **Test on a demo account first.** This places real market orders.
- The TP is a flat distance (entry ± `TP_Distance`), so it works on any
  gold quote, not just 4000.
- `TP_Distance` is in *price* units. On XAUUSD, 10.0 = a $10 move.
- Minimum TP/SL distance is auto-adjusted to the broker's stop level.
- There is no money management beyond the fixed lot — add a stop-loss
  (`SL_Distance`) if you want downside protection, since TP-only trades can
  run against you indefinitely without one.
