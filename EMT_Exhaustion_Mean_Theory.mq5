//+------------------------------------------------------------------+
//|                                   EMT_Exhaustion_Mean_Theory.mq5  |
//|                     Exhaustion Mean Theory (EMT) by Street Trades |
//|                 Reproduces the strategy rules exactly as taught   |
//|                 in the source video + "5 Pillars of EMT" sheet    |
//+------------------------------------------------------------------+
//
//  ============================  STRATEGY  ============================
//  2 indicators only : VWAP  +  9 EMA   (together = the "MEAN")
//  Intended timeframe : 5-minute chart (M5)
//
//  THE 5 PILLARS OF EMT (entry checklist):
//   1) ACCELERATION  - sharp momentum move + rising volume that
//                      stretches price far away from the mean.
//   2) EXHAUSTION    - a large rejection wick / clear stall; the move
//                      runs out of fuel -> this is the EXHAUSTION CANDLE
//                      (no new highs on a top / no new lows on a bottom).
//   3) CONFIRMATION  - order-flow footprint: absorption / effort without
//                      result (high volume, little price progress).
//                      (True footprint data is not available in standard
//                       MQL5, so this pillar is approximated with a
//                       volume vs. body/progress proxy - see code.)
//   4) DISTANCE      - price stretched far enough from VWAP/9EMA with a
//                      clear target back to the mean and favourable R:R
//                      (risk ~0.5-1R, reward 3R+).
//   5) LIQUIDITY     - break of a recent key level (swing high/low) that
//        SWEEP         traps breakout traders, then IMMEDIATE rejection
//                      back inside (wick sweep that closes back in range).
//
//  EXECUTION (from the video):
//   * DO NOT enter on the exhaustion candle itself.
//   * ENTER ON THE BREAK of the exhaustion candle:
//        - SHORT when price breaks BELOW the exhaustion candle's LOW.
//        - LONG  when price breaks ABOVE the exhaustion candle's HIGH.
//   * Stop  : just beyond the exhaustion wick.
//   * Target: rotation back to the mean (VWAP / 9 EMA).
//
//  A trade is only armed when at least "InpMinPillars" of the 5 pillars
//  are satisfied on the exhaustion candle.
//  ===================================================================
//
#property copyright "EMT - Exhaustion Mean Theory (educational reproduction)"
#property version   "1.00"
#property description "Exhaustion Mean Theory: VWAP + 9 EMA mean-reversion. Plots the mean, flags exhaustion candles that pass the 5-pillar checklist, and signals entry on the BREAK of the exhaustion candle."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

//--- Plot 0 : VWAP (part of the mean)
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

//--- Plot 1 : 9 EMA (part of the mean)
#property indicator_label2  "EMA(9)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1
#property indicator_style2  STYLE_SOLID

//--- Plot 2 : Exhaustion candle at a TOP (potential short)
#property indicator_label3  "Exhaustion Top"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrGold
#property indicator_width3  2

//--- Plot 3 : Exhaustion candle at a BOTTOM (potential long)
#property indicator_label4  "Exhaustion Bottom"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrGold
#property indicator_width4  2

//--- Plot 4 : SELL entry (break of exhaustion low)
#property indicator_label5  "EMT Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  3

//--- Plot 5 : BUY entry (break of exhaustion high)
#property indicator_label6  "EMT Buy"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  3

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group                "=== General ==="
input bool    InpWarnTF        = true;        // Warn if chart is not M5
input int     InpMaxBars       = 2000;        // Max bars to compute (0 = all)
input int     InpMinPillars    = 4;           // Pillars required to arm a trade (1..5)

input group                "=== Mean (VWAP + 9 EMA) ==="
enum ENUM_MEAN_MODE
  {
   MEAN_VWAP = 0,   // VWAP only
   MEAN_EMA  = 1,   // 9 EMA only
   MEAN_BOTH = 2    // Average of VWAP & 9 EMA
  };
input ENUM_MEAN_MODE InpMeanMode = MEAN_VWAP; // Which mean to target
input int     InpEmaPeriod     = 9;           // EMA period
input bool    InpVwapDailyReset= true;        // Anchor VWAP to each new day

input group                "=== Pillar 1: Acceleration ==="
input int     InpAccelBars     = 6;           // Bars measured for the momentum run
input double  InpAccelATR      = 2.0;         // Min run size (in ATR) to count as acceleration
input bool    InpRequireVolRise= true;        // Require rising volume into the move

input group                "=== Pillar 2: Exhaustion candle ==="
input double  InpWickRatio     = 0.5;         // Rejection wick must be >= this fraction of range
input double  InpStallBodyMax  = 0.35;        // ...OR body <= this fraction of range (clear stall)

input group                "=== Pillar 3: Confirmation (order-flow proxy) ==="
input bool    InpUseConfirm    = true;        // Require the confirmation pillar
input double  InpConfVolMult   = 1.3;         // "Effort": volume >= mult * average volume
input double  InpConfBodyMax   = 0.45;        // "No result": body <= this fraction of range

input group                "=== Pillar 4: Distance from the mean ==="
input int     InpAtrPeriod     = 14;          // ATR period (stretch normaliser)
input double  InpStretchATR    = 2.0;         // Min distance price-to-mean (in ATR)
input double  InpMinRR         = 3.0;         // Min reward:risk (target to mean vs. stop)

input group                "=== Pillar 5: Liquidity sweep ==="
input bool    InpUseSweep      = true;        // Require the liquidity-sweep pillar
input int     InpSweepLookback = 10;          // Prior swing high/low lookback

input group                "=== Entry (break of exhaustion candle) ==="
input int     InpBreakExpiry   = 5;           // Bars allowed for the break to occur
input double  InpStopBufferPts = 0.0;         // Extra stop buffer beyond the wick (points)

input group                "=== Display & alerts ==="
input bool    InpShowLines     = true;        // Draw entry / stop / target lines per signal
input bool    InpAlerts        = true;        // Popup/sound alert on a new entry
input bool    InpPushAlerts    = false;       // Send push notification on a new entry

//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+
double BufVWAP[];
double BufEMA[];
double BufExhTop[];
double BufExhBot[];
double BufSell[];
double BufBuy[];

//--- helper arrays (recomputed each pass)
double ATR[];
double AVGVOL[];

//--- object prefix for drawn lines
const string OBJ_PREFIX = "EMT_";

//--- alert de-duplication
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufVWAP,   INDICATOR_DATA);
   SetIndexBuffer(1, BufEMA,    INDICATOR_DATA);
   SetIndexBuffer(2, BufExhTop, INDICATOR_DATA);
   SetIndexBuffer(3, BufExhBot, INDICATOR_DATA);
   SetIndexBuffer(4, BufSell,   INDICATOR_DATA);
   SetIndexBuffer(5, BufBuy,    INDICATOR_DATA);

   //--- arrow codes
   PlotIndexSetInteger(2, PLOT_ARROW, 159); // small dot - exhaustion top
   PlotIndexSetInteger(3, PLOT_ARROW, 159); // small dot - exhaustion bottom
   PlotIndexSetInteger(4, PLOT_ARROW, 234); // down arrow - sell
   PlotIndexSetInteger(5, PLOT_ARROW, 233); // up arrow   - buy

   //--- 0.0 means "no value / do not draw" for the marker & arrow plots
   for(int p=2; p<=5; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, 0.0);

   //--- vertical nudge so exhaustion dots sit just off the wick
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT,  10);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, -12);
   PlotIndexSetInteger(5, PLOT_ARROW_SHIFT,  12);

   IndicatorSetString(INDICATOR_SHORTNAME, "EMT - Exhaustion Mean Theory");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   if(InpWarnTF && _Period != PERIOD_M5)
      Print("EMT: This strategy is designed for the 5-minute (M5) chart. Current TF = ", EnumToString((ENUM_TIMEFRAMES)_Period));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit - clean drawn objects                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, OBJ_PREFIX);
  }

//+------------------------------------------------------------------+
//| Compute the "mean" value for bar i                               |
//+------------------------------------------------------------------+
double MeanValue(const int i)
  {
   switch(InpMeanMode)
     {
      case MEAN_EMA:  return(BufEMA[i]);
      case MEAN_BOTH: return(0.5*(BufVWAP[i]+BufEMA[i]));
      default:        return(BufVWAP[i]);
     }
  }

//+------------------------------------------------------------------+
//| Build / refresh an entry-stop-target line set for a signal       |
//+------------------------------------------------------------------+
void DrawTradeLines(const string tag, const datetime t1, const datetime t2,
                    const double entry, const double stop, const double target,
                    const color cEntry)
  {
   if(!InpShowLines)
      return;

   string nE = OBJ_PREFIX + tag + "_E";
   string nS = OBJ_PREFIX + tag + "_S";
   string nT = OBJ_PREFIX + tag + "_T";

   //--- entry
   if(ObjectFind(0,nE) < 0) ObjectCreate(0,nE,OBJ_TREND,0,t1,entry,t2,entry);
   ObjectSetDouble(0,nE,OBJPROP_PRICE,0,entry);
   ObjectSetDouble(0,nE,OBJPROP_PRICE,1,entry);
   ObjectSetInteger(0,nE,OBJPROP_TIME,0,t1);
   ObjectSetInteger(0,nE,OBJPROP_TIME,1,t2);
   ObjectSetInteger(0,nE,OBJPROP_COLOR,cEntry);
   ObjectSetInteger(0,nE,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,nE,OBJPROP_RAY_RIGHT,false);

   //--- stop
   if(ObjectFind(0,nS) < 0) ObjectCreate(0,nS,OBJ_TREND,0,t1,stop,t2,stop);
   ObjectSetDouble(0,nS,OBJPROP_PRICE,0,stop);
   ObjectSetDouble(0,nS,OBJPROP_PRICE,1,stop);
   ObjectSetInteger(0,nS,OBJPROP_TIME,0,t1);
   ObjectSetInteger(0,nS,OBJPROP_TIME,1,t2);
   ObjectSetInteger(0,nS,OBJPROP_COLOR,clrCrimson);
   ObjectSetInteger(0,nS,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,nS,OBJPROP_RAY_RIGHT,false);

   //--- target (back to the mean)
   if(ObjectFind(0,nT) < 0) ObjectCreate(0,nT,OBJ_TREND,0,t1,target,t2,target);
   ObjectSetDouble(0,nT,OBJPROP_PRICE,0,target);
   ObjectSetDouble(0,nT,OBJPROP_PRICE,1,target);
   ObjectSetInteger(0,nT,OBJPROP_TIME,0,t1);
   ObjectSetInteger(0,nT,OBJPROP_TIME,1,t2);
   ObjectSetInteger(0,nT,OBJPROP_COLOR,clrMediumSeaGreen);
   ObjectSetInteger(0,nT,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,nT,OBJPROP_RAY_RIGHT,false);
  }

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < InpAtrPeriod + InpAccelBars + InpSweepLookback + 5)
      return(0);

   //--- arrays are used in time order: index 0 = oldest, rates_total-1 = newest
   ArrayResize(ATR,    rates_total);
   ArrayResize(AVGVOL, rates_total);

   //--- window to compute
   int startBar = 1;                                   // need i-1 for TR/EMA
   if(InpMaxBars > 0 && rates_total - InpMaxBars > startBar)
      startBar = rates_total - InpMaxBars;

   //--- choose the volume series (real volume if present, else tick volume)
   bool useRealVol = false;
   for(int i=rates_total-1; i>=MathMax(0,rates_total-50); i--)
      if(volume[i] > 0) { useRealVol = true; break; }

   //=================================================================
   // 1) Mean lines: VWAP (daily anchored) and 9 EMA
   //=================================================================
   double k = 2.0 / (InpEmaPeriod + 1.0);
   double cumPV = 0.0, cumV = 0.0;
   MqlDateTime dtPrev; dtPrev.day = -1;

   for(int i=0; i<rates_total; i++)
     {
      //--- EMA(9) on close
      if(i == 0)
         BufEMA[i] = close[i];
      else
         BufEMA[i] = close[i]*k + BufEMA[i-1]*(1.0-k);

      //--- VWAP (session/daily anchored)
      MqlDateTime dt; TimeToStruct(time[i], dt);
      if(InpVwapDailyReset && dt.day != dtPrev.day)
        { cumPV = 0.0; cumV = 0.0; }        // new day -> re-anchor
      dtPrev = dt;

      double tp  = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (double)(useRealVol ? volume[i] : tick_volume[i]);
      if(vol <= 0.0) vol = 1.0;
      cumPV += tp * vol;
      cumV  += vol;
      BufVWAP[i] = (cumV > 0.0) ? cumPV / cumV : close[i];
     }

   //=================================================================
   // ATR (simple avg of True Range) and average volume
   //=================================================================
   for(int i=0; i<rates_total; i++)
     {
      //--- ATR
      int a0 = i - InpAtrPeriod + 1;
      if(a0 < 1) { ATR[i] = (i>0 ? high[i]-low[i] : 0.0); }
      else
        {
         double sum = 0.0;
         for(int j=a0; j<=i; j++)
           {
            double tr = MathMax(high[j]-low[j],
                        MathMax(MathAbs(high[j]-close[j-1]),
                                MathAbs(low[j]-close[j-1])));
            sum += tr;
           }
         ATR[i] = sum / InpAtrPeriod;
        }

      //--- average volume (same period) for the acceleration / confirmation pillars
      int v0 = i - InpAtrPeriod + 1;
      if(v0 < 0) v0 = 0;
      double vs = 0.0; int vc = 0;
      for(int j=v0; j<=i; j++)
        { vs += (double)(useRealVol ? volume[j] : tick_volume[j]); vc++; }
      AVGVOL[i] = (vc>0) ? vs/vc : 0.0;
     }

   //=================================================================
   // Clear marker/arrow buffers over the computed window
   //=================================================================
   for(int i=startBar; i<rates_total; i++)
     {
      BufExhTop[i] = 0.0;
      BufExhBot[i] = 0.0;
      BufSell[i]   = 0.0;
      BufBuy[i]    = 0.0;
     }
   //--- refresh object set each pass
   ObjectsDeleteAll(0, OBJ_PREFIX);

   //=================================================================
   // Scan for exhaustion candles + the break entry
   //=================================================================
   for(int i=startBar; i<rates_total; i++)
     {
      if(ATR[i] <= 0.0) continue;

      double rng  = high[i] - low[i];
      if(rng <= 0.0) continue;

      double body     = MathAbs(close[i]-open[i]);
      double upWick   = high[i] - MathMax(open[i],close[i]);
      double dnWick   = MathMin(open[i],close[i]) - low[i];
      double meanI    = MeanValue(i);
      double vol      = (double)(useRealVol ? volume[i] : tick_volume[i]);

      //--- side / distance from the mean
      double distAbove = high[i] - meanI;   // >0 if candle sits above the mean
      double distBelow = meanI - low[i];    // >0 if candle sits below the mean

      //=============== evaluate a TOP exhaustion (short setup) ==========
      bool topSide = (close[i] > meanI) || (open[i] > meanI);
      if(topSide)
        {
         int score = 0;

         // Pillar 1: Acceleration - strong up-run + rising volume into it
         bool p1 = false;
         if(i-InpAccelBars >= 0)
           {
            double run = close[i] - close[i-InpAccelBars];
            bool volRise = (!InpRequireVolRise) || (vol >= AVGVOL[i]);
            p1 = (run >= InpAccelATR*ATR[i]) && volRise;
           }
         if(p1) score++;

         // Pillar 2: Exhaustion - big upper rejection wick OR a clear stall,
         //           and it is the local high (no new highs continuing)
         bool localHigh = (i>0) ? (high[i] >= high[i-1]) : true;
         bool p2 = ((upWick >= InpWickRatio*rng) || (body <= InpStallBodyMax*rng)) && localHigh;
         if(p2) score++;

         // Pillar 3: Confirmation - effort without result (high vol, small body)
         bool p3 = (!InpUseConfirm) ||
                   ((vol >= InpConfVolMult*AVGVOL[i]) && (body <= InpConfBodyMax*rng));
         if(p3) score++;

         // Pillar 4: Distance from the mean - stretched far enough above it
         bool p4 = (distAbove >= InpStretchATR*ATR[i]);
         if(p4) score++;

         // Pillar 5: Liquidity sweep - took out prior swing high then rejected back in
         bool p5 = (!InpUseSweep);
         if(InpUseSweep && i-1 >= InpSweepLookback)
           {
            double priorHigh = high[i-1];
            for(int j=i-InpSweepLookback; j<=i-1; j++)
               if(high[j] > priorHigh) priorHigh = high[j];
            p5 = (high[i] > priorHigh) && (close[i] < priorHigh); // swept & closed back in
           }
         if(p5) score++;

         bool pillar3ok = (!InpUseConfirm) || p3;
         bool pillar5ok = (!InpUseSweep)   || p5;

         if(score >= InpMinPillars && p2 && p4 && pillar3ok && pillar5ok)
           {
            BufExhTop[i] = high[i];   // flag the exhaustion candle

            //--- ENTER ON THE BREAK of the candle's LOW (do NOT enter on the candle)
            double trigger = low[i];
            int    kmax    = MathMin(InpBreakExpiry, rates_total-1-i);
            for(int m=1; m<=kmax; m++)
              {
               int b = i+m;
               if(low[b] < trigger)   // break below exhaustion low
                 {
                  double entry  = trigger;
                  double stop   = high[i] + InpStopBufferPts*_Point;
                  double target = MeanValue(b);
                  double risk   = stop - entry;
                  double reward = entry - target;
                  if(risk > 0.0 && reward > 0.0 && (reward/risk) >= InpMinRR)
                    {
                     BufSell[b] = high[b];
                     datetime t2 = time[b] + (datetime)(PeriodSeconds()*InpBreakExpiry*2);
                     DrawTradeLines("S"+(string)time[i], time[i], t2, entry, stop, target, clrRed);
                     if(b == rates_total-1) MaybeAlert(time[b], false, entry, stop, target);
                    }
                  break; // first break only
                 }
              }
           }
        }

      //=============== evaluate a BOTTOM exhaustion (long setup) ========
      bool botSide = (close[i] < meanI) || (open[i] < meanI);
      if(botSide)
        {
         int score = 0;

         // Pillar 1: Acceleration - strong down-run + rising volume
         bool p1 = false;
         if(i-InpAccelBars >= 0)
           {
            double run = close[i-InpAccelBars] - close[i];
            bool volRise = (!InpRequireVolRise) || (vol >= AVGVOL[i]);
            p1 = (run >= InpAccelATR*ATR[i]) && volRise;
           }
         if(p1) score++;

         // Pillar 2: Exhaustion - big lower rejection wick OR clear stall, local low
         bool localLow = (i>0) ? (low[i] <= low[i-1]) : true;
         bool p2 = ((dnWick >= InpWickRatio*rng) || (body <= InpStallBodyMax*rng)) && localLow;
         if(p2) score++;

         // Pillar 3: Confirmation - effort without result
         bool p3 = (!InpUseConfirm) ||
                   ((vol >= InpConfVolMult*AVGVOL[i]) && (body <= InpConfBodyMax*rng));
         if(p3) score++;

         // Pillar 4: Distance - stretched far enough below the mean
         bool p4 = (distBelow >= InpStretchATR*ATR[i]);
         if(p4) score++;

         // Pillar 5: Liquidity sweep - took out prior swing low then rejected back in
         bool p5 = (!InpUseSweep);
         if(InpUseSweep && i-1 >= InpSweepLookback)
           {
            double priorLow = low[i-1];
            for(int j=i-InpSweepLookback; j<=i-1; j++)
               if(low[j] < priorLow) priorLow = low[j];
            p5 = (low[i] < priorLow) && (close[i] > priorLow);
           }
         if(p5) score++;

         bool pillar3ok = (!InpUseConfirm) || p3;
         bool pillar5ok = (!InpUseSweep)   || p5;

         if(score >= InpMinPillars && p2 && p4 && pillar3ok && pillar5ok)
           {
            BufExhBot[i] = low[i];    // flag the exhaustion candle

            //--- ENTER ON THE BREAK of the candle's HIGH
            double trigger = high[i];
            int    kmax    = MathMin(InpBreakExpiry, rates_total-1-i);
            for(int m=1; m<=kmax; m++)
              {
               int b = i+m;
               if(high[b] > trigger)  // break above exhaustion high
                 {
                  double entry  = trigger;
                  double stop   = low[i] - InpStopBufferPts*_Point;
                  double target = MeanValue(b);
                  double risk   = entry - stop;
                  double reward = target - entry;
                  if(risk > 0.0 && reward > 0.0 && (reward/risk) >= InpMinRR)
                    {
                     BufBuy[b] = low[b];
                     datetime t2 = time[b] + (datetime)(PeriodSeconds()*InpBreakExpiry*2);
                     DrawTradeLines("L"+(string)time[i], time[i], t2, entry, stop, target, clrLime);
                     if(b == rates_total-1) MaybeAlert(time[b], true, entry, stop, target);
                    }
                  break;
                 }
              }
           }
        }
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Fire an alert once per bar for a fresh entry                     |
//+------------------------------------------------------------------+
void MaybeAlert(const datetime bartime, const bool isBuy,
                const double entry, const double stop, const double target)
  {
   if(bartime == g_lastAlertBar)
      return;
   g_lastAlertBar = bartime;

   string dir = isBuy ? "BUY (break of exhaustion high)" : "SELL (break of exhaustion low)";
   string msg = StringFormat("EMT %s on %s %s | Entry %s  Stop %s  Target(mean) %s",
                             dir, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
                             DoubleToString(entry,_Digits),
                             DoubleToString(stop,_Digits),
                             DoubleToString(target,_Digits));
   if(InpAlerts)     Alert(msg);
   if(InpPushAlerts) SendNotification(msg);
  }
//+------------------------------------------------------------------+
