# ReversalAfter90 — MT5 Indicator

A MetaTrader 5 (MQL5) indicator that watches price in real time and flags a
possible reversal when an extreme (a top or a bottom) holds unbroken for a set
number of candles.

## Strategy

The indicator silently tracks the running **high** and **low** of the current
move. These tracked levels are **not drawn** on the chart — only the confirmed
signal is shown.

### Sell side (tops)
- A candle's **high** (wick included) becomes the marked top as soon as the
  **next candle fails to break above it**.
- From that top, the next `N` candles are counted. Every one of them must stay
  **below** the marked high.
- If any candle **breaks above** the high, the old top is invalidated and the
  new, higher candle becomes the top — the count restarts from there.
- When `N` candles close without breaking the high, the count completes and a
  **reversal-down (SELL)** arrow is printed on the completing candle.

### Buy side (bottoms)
The exact mirror using candle **lows**: a low holds, the next `N` candles must
all stay **above** it (any break below restarts the count at the new lower
low), and completion prints a **reversal-up (BUY)** arrow.

`N` defaults to **90** (`InpBarsToConfirm`).

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `InpBarsToConfirm` | `90` | Candles the extreme must hold before signalling |
| `InpEnableSell` | `true` | Watch tops (reversal-down signals) |
| `InpEnableBuy` | `true` | Watch bottoms (reversal-up signals) |
| `InpArrowOffsetPts` | `20` | Gap between the arrow and the candle (points) |
| `InpSellArrowCode` | `234` | Wingdings code for the sell arrow |
| `InpBuyArrowCode` | `233` | Wingdings code for the buy arrow |
| `InpShowLevelLine` | `false` | Draw a short dotted line at the confirmed extreme |
| `InpAlertPopup` | `true` | Popup + sound alert on a new signal |
| `InpAlertPush` | `false` | Push notification to the MT5 mobile app |
| `InpAlertEmail` | `false` | Email alert on a new signal |

## Install

1. In MetaTrader 5: **File → Open Data Folder**.
2. Copy `ReversalAfter90.mq5` into `MQL5/Indicators/`.
3. Open **MetaEditor**, open the file, and press **Compile** (F7). This
   produces `ReversalAfter90.ex5`.
4. Back in MT5, refresh the **Navigator**, then drag the indicator onto a chart.

## Notes

- Signals are evaluated on **closed candles**. The still-forming candle is not
  counted, so an arrow never repaints once its candle has closed.
- Alerts fire only for the newest closed candle during a live session (not
  while historical bars are being recalculated), and each signal alerts once.
- For push notifications, enable them and set your MetaQuotes ID in
  **Tools → Options → Notifications**. For email, configure
  **Tools → Options → Email**.
