# M1 Scalping FX — MT4 Indicator

A single non-repainting MT4 custom indicator rebuilt from the **M1 Scalping Course**
(Forex Indian Scalper / "bhuwan fx"). It draws the 6-EMA ribbon on the price chart
and prints **BUY / SELL arrows** only when every confluence rule of the course is met.

> Educational reconstruction of a published strategy. Not financial advice. M1
> scalping is high-risk — test on a demo account first.

## Files
- `M1_Scalping_FX.mq4` — the indicator source (compile in MetaEditor → `.ex4`).

## Install (desktop MT4)
1. MT4 → **File → Open Data Folder** → `MQL4/Indicators/`.
2. Copy `M1_Scalping_FX.mq4` there.
3. In MetaEditor press **Compile** (F7).
4. Back in MT4, refresh **Navigator → Indicators** and drag it onto an **M1** chart.

## Install (mobile MT4)
Mobile MT4 cannot compile custom indicators. Compile `M1_Scalping_FX.ex4` on desktop
first, or load the raw indicators below and read the arrows manually. The default
inputs reproduce the course exactly.

## The strategy encoded (from the PDF)

### Chart template
| Indicator | Setting | Role |
|-----------|---------|------|
| EMA 30 | red    | ribbon |
| EMA 40 | dark red | ribbon |
| EMA 50 | blue   | ribbon |
| EMA 60 | orange | ribbon |
| EMA 70 | pink   | ribbon |
| EMA 80 | black  | ribbon |
| RSI(10) + EMA 2/7/25 applied | levels 70 / 30 | top/bottom touch |
| CCI(20) | levels 200 / 170 / −200 / −230 | top/bottom touch |
| MACD(12,26,9) | — | must be at top (sell) / bottom (buy) |
| Stochastic(14,4,4) | levels 80 / 20 | top/bottom touch |

### SELL — down-trend only (lower lows)
- Whole EMA ribbon **above** price (≈30% up / 70% down).
- RSI, CCI, Stoch **and** MACD all at the **top**, touching resistance.
- Bearish confirmation candle.

### BUY — up-trend only (higher highs)
- Whole EMA ribbon **below** price (≈30% down / 70% up).
- RSI, CCI, Stoch all at the **bottom**, touching support.
- Bullish confirmation candle.

### Money management (course)
- Target **5–15 pips** (~$20–30 per standard lot), close manually.
- Exit a sell immediately if the candle **body breaks the previous high**
  (mirror for buys). *(Entry/exit is manual — this tool only flags setups.)*

## Inputs
All periods, the overbought/oversold levels, `RequireRibbonOrder` (strict
EMA30>…>EMA80 stacking), `RequireCandle`, `UseMacdFilter`, arrow spacing and
pop-up / push / e-mail alerts are exposed so you can tune the strictness.

## Non-repainting
Signals are evaluated on **closed bars only** (shift ≥ 1), so an arrow never
moves or disappears once a bar has closed.

## "Empty" base
If you want a blank scaffold instead of the full logic (e.g. to wire your own
entry rules), delete the body of the confluence block in `OnCalculate` and keep
the buffer/arrow setup — the ribbon and arrow plumbing is already in place.
