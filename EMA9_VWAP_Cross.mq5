//+------------------------------------------------------------------+
//|                                            EMA9_VWAP_Cross.mq5    |
//|   "EMA9 + VWAP Cross" scalping strategy (from video analysis)     |
//|                                                                   |
//|   Strategy decoded from the reference video:                      |
//|     * Indicators on chart: Session VWAP + EMA(9)                   |
//|     * BUY CALLS  (long)  : EMA9 crosses ABOVE VWAP while price is  |
//|                            above VWAP ("candles wicking on top of  |
//|                            VWAP" = VWAP acting as support).        |
//|     * BUY PUTS   (short) : EMA9 crosses BELOW VWAP while price is  |
//|                            below VWAP (VWAP acting as resistance). |
//|     * EXIT              : Use EMA9 as the guide — exit when a      |
//|                            candle CLOSES through the EMA9 against  |
//|                            your position.                         |
//|     * Recommended timeframe in the video: 3-minute (M3 / M5).      |
//+------------------------------------------------------------------+
#property copyright "Generated from video strategy analysis"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

//--- Plot 0: EMA9
#property indicator_label1  "EMA9"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumPurple
#property indicator_width1  2

//--- Plot 1: Session VWAP
#property indicator_label2  "VWAP"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  2

//--- Plot 2: Buy (Calls) signal
#property indicator_label3  "Buy CALLS"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  3

//--- Plot 3: Sell (Puts) signal
#property indicator_label4  "Buy PUTS"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  3

//--- Plot 4: Exit long
#property indicator_label5  "Exit Long"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrGray
#property indicator_width5  2

//--- Plot 5: Exit short
#property indicator_label6  "Exit Short"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrGray
#property indicator_width6  2

//--- Inputs
input int                InpEmaPeriod     = 9;             // EMA period
input ENUM_APPLIED_PRICE InpEmaPrice      = PRICE_CLOSE;   // EMA applied price
input bool               InpRequireAbove  = true;          // Require close beyond VWAP to confirm entry
input bool               InpUseWickFilter = true;          // Require candle "wicking" on the VWAP side (rejection)
input bool               InpShowExits     = true;          // Plot EMA9-cross exit markers
input bool               InpAlertsOn      = false;         // Popup/sound alerts on new signal
input bool               InpUseRealVolume = false;         // true = tick-volume off, use real volume if available

//--- Buffers
double EmaBuf[];
double VwapBuf[];
double BuyBuf[];
double SellBuf[];
double ExitLongBuf[];
double ExitShortBuf[];

int    emaHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, EmaBuf,       INDICATOR_DATA);
   SetIndexBuffer(1, VwapBuf,      INDICATOR_DATA);
   SetIndexBuffer(2, BuyBuf,       INDICATOR_DATA);
   SetIndexBuffer(3, SellBuf,      INDICATOR_DATA);
   SetIndexBuffer(4, ExitLongBuf,  INDICATOR_DATA);
   SetIndexBuffer(5, ExitShortBuf, INDICATOR_DATA);

   PlotIndexSetInteger(2, PLOT_ARROW, 233); // up arrow  (buy calls)
   PlotIndexSetInteger(3, PLOT_ARROW, 234); // down arrow(buy puts)
   PlotIndexSetInteger(4, PLOT_ARROW, 251); // x         (exit long)
   PlotIndexSetInteger(5, PLOT_ARROW, 251); // x         (exit short)

   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, 0.0);

   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, InpEmaPrice);
   if(emaHandle == INVALID_HANDLE)
     {
      Print("Failed to create EMA handle");
      return(INIT_FAILED);
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "EMA9+VWAP Cross");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
  }

//+------------------------------------------------------------------+
//| Returns true if bar at index i starts a new trading day          |
//+------------------------------------------------------------------+
bool IsNewSession(const datetime &time[], int i)
  {
   if(i == 0) return(true);
   MqlDateTime t0, t1;
   TimeToStruct(time[i],   t1);
   TimeToStruct(time[i-1], t0);
   return(t1.day != t0.day || t1.mon != t0.mon || t1.year != t0.year);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpEmaPeriod + 2) return(0);

   //--- pull EMA values
   if(CopyBuffer(emaHandle, 0, 0, rates_total, EmaBuf) <= 0)
      return(prev_calculated);

   //--- recompute VWAP from the first changed bar backward to session start.
   //    VWAP is cumulative within a session, so we always rebuild from the
   //    session that contains the first uncomputed bar.
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   // walk back to the start of the session that holds 'start'
   int sessStart = start;
   while(sessStart > 0 && !IsNewSession(time, sessStart))
      sessStart--;

   double cumPV = 0.0;   // sum(typical_price * volume)
   double cumV  = 0.0;   // sum(volume)

   for(int i = sessStart; i < rates_total; i++)
     {
      if(IsNewSession(time, i))
        {
         cumPV = 0.0;
         cumV  = 0.0;
        }

      double typical = (high[i] + low[i] + close[i]) / 3.0;   // hlc3 (TradingView default)
      double v = (double)(InpUseRealVolume ? volume[i] : tick_volume[i]);
      if(v <= 0.0) v = 1.0;                                    // guard flat-volume bars

      cumPV += typical * v;
      cumV  += v;

      VwapBuf[i]  = (cumV > 0.0) ? cumPV / cumV : typical;

      // reset signal buffers for this bar
      BuyBuf[i]       = 0.0;
      SellBuf[i]      = 0.0;
      ExitLongBuf[i]  = 0.0;
      ExitShortBuf[i] = 0.0;

      if(i < 1) continue;
      if(EmaBuf[i] == 0.0 || EmaBuf[i-1] == 0.0) continue;

      double emaNow = EmaBuf[i],  emaPrev = EmaBuf[i-1];
      double vwNow  = VwapBuf[i],  vwPrev  = VwapBuf[i-1];

      bool crossUp   = (emaPrev <= vwPrev && emaNow > vwNow);  // EMA9 crosses above VWAP
      bool crossDown = (emaPrev >= vwPrev && emaNow < vwNow);  // EMA9 crosses below VWAP

      bool priceAbove = (!InpRequireAbove) || (close[i] > vwNow);
      bool priceBelow = (!InpRequireAbove) || (close[i] < vwNow);

      // "Candles wicking on top of VWAP" -> candle body above VWAP but lower
      // wick reaching down to / rejecting VWAP (support). Mirror for shorts.
      bool wickOkLong  = (!InpUseWickFilter) ||
                         (low[i]  <= vwNow && close[i] > vwNow && close[i] >= open[i]);
      bool wickOkShort = (!InpUseWickFilter) ||
                         (high[i] >= vwNow && close[i] < vwNow && close[i] <= open[i]);

      //--- ENTRIES
      if(crossUp && priceAbove && wickOkLong)
        {
         BuyBuf[i] = low[i] - (high[i]-low[i])*0.5;
         DoAlert(i, time, "BUY CALLS: EMA9 crossed above VWAP");
        }
      if(crossDown && priceBelow && wickOkShort)
        {
         SellBuf[i] = high[i] + (high[i]-low[i])*0.5;
         DoAlert(i, time, "BUY PUTS: EMA9 crossed below VWAP");
        }

      //--- EXITS: candle closes through EMA9 against the position
      if(InpShowExits)
        {
         // exit long: prior close above EMA9, this candle closes below EMA9
         if(close[i-1] >= EmaBuf[i-1] && close[i] < emaNow)
            ExitLongBuf[i] = high[i] + (high[i]-low[i])*0.3;
         // exit short: prior close below EMA9, this candle closes above EMA9
         if(close[i-1] <= EmaBuf[i-1] && close[i] > emaNow)
            ExitShortBuf[i] = low[i] - (high[i]-low[i])*0.3;
        }
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
datetime g_lastAlert = 0;
void DoAlert(int i, const datetime &time[], string msg)
  {
   if(!InpAlertsOn) return;
   // only alert on the most recent completed bar, once per bar
   if(i != ArraySize(time)-1) return;
   if(time[i] == g_lastAlert) return;
   g_lastAlert = time[i];
   Alert(_Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period), " | ", msg);
  }
//+------------------------------------------------------------------+
