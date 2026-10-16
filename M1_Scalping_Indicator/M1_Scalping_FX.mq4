//+------------------------------------------------------------------+
//|                                             M1_Scalping_FX.mq4    |
//|                        Based on the "M1 SCALPING COURSE" PDF      |
//|                                      (Forex Indian Scalper)       |
//|                                                                  |
//|  Rebuilt as a single non-repainting MT4 custom indicator.        |
//|  It plots the 6-EMA ribbon on the price chart and prints BUY /   |
//|  SELL arrows only when every rule of the course lines up:        |
//|                                                                  |
//|   SELL (down-trend / lower-lows only)                            |
//|     - whole EMA ribbon ABOVE price (ribbon bearish, ~70% down)   |
//|     - RSI(10), CCI(20), Stoch(14,4,4) and MACD at the TOP        |
//|       (touching resistance / overbought)                        |
//|     - bearish confirmation candle                               |
//|                                                                  |
//|   BUY (up-trend / higher-highs only)                            |
//|     - whole EMA ribbon BELOW price (ribbon bullish, ~70% up)     |
//|     - RSI(10), CCI(20), Stoch(14,4,4) at the BOTTOM             |
//|       (touching support / oversold)                            |
//|     - bullish confirmation candle                              |
//|                                                                  |
//|  Signals are evaluated on CLOSED bars only => non-repainting.    |
//|  Money management from the course: TP ~5-15 pips, close sell if  |
//|  price body breaks the previous high.                           |
//+------------------------------------------------------------------+
#property copyright "M1 Scalping Course - rebuilt indicator"
#property link      ""
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 8

//--- 6 EMA ribbon lines
#property indicator_color1  clrRed          // EMA 30
#property indicator_color2  clrDarkRed      // EMA 40
#property indicator_color3  clrBlue         // EMA 50
#property indicator_color4  clrOrange       // EMA 60
#property indicator_color5  clrMagenta      // EMA 70 (pink)
#property indicator_color6  clrBlack        // EMA 80
//--- signal arrows
#property indicator_color7  clrLime         // BUY arrow
#property indicator_color8  clrRed          // SELL arrow

#property indicator_width1  1
#property indicator_width2  1
#property indicator_width3  1
#property indicator_width4  1
#property indicator_width5  1
#property indicator_width6  1
#property indicator_width7  2
#property indicator_width8  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string  __EMA__       = "----- EMA ribbon -----";
input int     EMA1_Period   = 30;
input int     EMA2_Period   = 40;
input int     EMA3_Period   = 50;
input int     EMA4_Period   = 60;
input int     EMA5_Period   = 70;
input int     EMA6_Period   = 80;
input bool    ShowRibbon    = true;   // draw the EMA lines

input string  __RSI__       = "----- RSI (top/bottom touch) -----";
input int     RSI_Period    = 10;
input double  RSI_Overbought= 70.0;   // sell: RSI >= this
input double  RSI_Oversold  = 30.0;   // buy : RSI <= this

input string  __CCI__       = "----- CCI -----";
input int     CCI_Period    = 20;
input double  CCI_TopLevel  = 170.0;  // sell: CCI >= this
input double  CCI_BotLevel  = -200.0; // buy : CCI <= this

input string  __STOCH__     = "----- Stochastic (14,4,4) -----";
input int     Stoch_K       = 14;
input int     Stoch_D       = 4;
input int     Stoch_Slow    = 4;
input double  Stoch_Top     = 80.0;   // sell: %K >= this
input double  Stoch_Bottom  = 20.0;   // buy : %K <= this

input string  __MACD__      = "----- MACD (12,26,9) -----";
input int     MACD_Fast     = 12;
input int     MACD_Slow     = 26;
input int     MACD_Signal   = 9;
input bool    UseMacdFilter = true;   // require MACD main at top(sell)/bottom(buy)

input string  __SIGNAL__    = "----- Signal behaviour -----";
input bool    RequireRibbonOrder = true; // full EMA30>...>EMA80 stacking
input bool    RequireCandle      = true; // bull candle buy / bear candle sell
input double  ArrowGapPips        = 1.5;  // arrow distance from the candle
input bool    AlertPopup          = true;
input bool    AlertPush           = false;
input bool    AlertEmail          = false;

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double Ema1[], Ema2[], Ema3[], Ema4[], Ema5[], Ema6[];
double BuyArrow[], SellArrow[];

datetime g_lastBuyBar  = 0;
datetime g_lastSellBar = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, Ema1);  SetIndexLabel(0, "EMA "+IntegerToString(EMA1_Period));
   SetIndexBuffer(1, Ema2);  SetIndexLabel(1, "EMA "+IntegerToString(EMA2_Period));
   SetIndexBuffer(2, Ema3);  SetIndexLabel(2, "EMA "+IntegerToString(EMA3_Period));
   SetIndexBuffer(3, Ema4);  SetIndexLabel(3, "EMA "+IntegerToString(EMA4_Period));
   SetIndexBuffer(4, Ema5);  SetIndexLabel(4, "EMA "+IntegerToString(EMA5_Period));
   SetIndexBuffer(5, Ema6);  SetIndexLabel(5, "EMA "+IntegerToString(EMA6_Period));

   for(int b=0; b<6; b++)
      SetIndexStyle(b, ShowRibbon ? DRAW_LINE : DRAW_NONE);

   SetIndexBuffer(6, BuyArrow);
   SetIndexStyle(6, DRAW_ARROW);
   SetIndexArrow(6, 233);            // up arrow
   SetIndexLabel(6, "M1 BUY");

   SetIndexBuffer(7, SellArrow);
   SetIndexStyle(7, DRAW_ARROW);
   SetIndexArrow(7, 234);            // down arrow
   SetIndexLabel(7, "M1 SELL");

   IndicatorSetString(INDICATOR_SHORTNAME, "M1 Scalping FX");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| pip size (handles 3/5-digit quotes)                              |
//+------------------------------------------------------------------+
double PipSize()
{
   double p = _Point;
   if(_Digits == 3 || _Digits == 5) p *= 10.0;
   return(p);
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
   int longestEMA = MathMax(EMA6_Period, MathMax(EMA5_Period, EMA4_Period));
   int minBars    = longestEMA + MACD_Slow + MACD_Signal + 5;
   if(rates_total < minBars) return(0);

   //--- how far back to (re)compute
   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0) limit = rates_total - minBars;
   if(limit > rates_total - minBars) limit = rates_total - minBars;

   double gap = ArrowGapPips * PipSize();

   // series indexing: shift 0 = current forming bar, shift 1 = last closed bar
   for(int i = limit; i >= 1; i--)   // i>=1 : evaluate CLOSED bars only (non-repaint)
   {
      //--- EMA ribbon
      double e1 = iMA(NULL,0,EMA1_Period,0,MODE_EMA,PRICE_CLOSE,i);
      double e2 = iMA(NULL,0,EMA2_Period,0,MODE_EMA,PRICE_CLOSE,i);
      double e3 = iMA(NULL,0,EMA3_Period,0,MODE_EMA,PRICE_CLOSE,i);
      double e4 = iMA(NULL,0,EMA4_Period,0,MODE_EMA,PRICE_CLOSE,i);
      double e5 = iMA(NULL,0,EMA5_Period,0,MODE_EMA,PRICE_CLOSE,i);
      double e6 = iMA(NULL,0,EMA6_Period,0,MODE_EMA,PRICE_CLOSE,i);

      Ema1[i]=e1; Ema2[i]=e2; Ema3[i]=e3; Ema4[i]=e4; Ema5[i]=e5; Ema6[i]=e6;
      BuyArrow[i]  = EMPTY_VALUE;
      SellArrow[i] = EMPTY_VALUE;

      double emaTop = MathMax(e1,MathMax(e2,MathMax(e3,MathMax(e4,MathMax(e5,e6)))));
      double emaBot = MathMin(e1,MathMin(e2,MathMin(e3,MathMin(e4,MathMin(e5,e6)))));

      //--- ribbon position vs price
      bool ribbonBelowPrice = (close[i] > emaTop);  // ribbon fully below -> buy side
      bool ribbonAbovePrice = (close[i] < emaBot);  // ribbon fully above -> sell side

      //--- optional strict fast>...>slow stacking
      bool stackUp   = (e1>e2 && e2>e3 && e3>e4 && e4>e5 && e5>e6);
      bool stackDown = (e1<e2 && e2<e3 && e3<e4 && e4<e5 && e5<e6);
      if(RequireRibbonOrder)
      {
         ribbonBelowPrice = ribbonBelowPrice && stackUp;
         ribbonAbovePrice = ribbonAbovePrice && stackDown;
      }

      //--- oscillators on the same closed bar
      double rsi   = iRSI(NULL,0,RSI_Period,PRICE_CLOSE,i);
      double cci   = iCCI(NULL,0,CCI_Period,PRICE_TYPICAL,i);
      double stK   = iStochastic(NULL,0,Stoch_K,Stoch_D,Stoch_Slow,MODE_SMA,0,MODE_MAIN,i);
      double macd  = iMACD(NULL,0,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE,MODE_MAIN,i);

      //--- candle confirmation
      bool bullCandle = (close[i] > open[i]);
      bool bearCandle = (close[i] < open[i]);

      //--- confluence
      bool buyOsc  = (rsi <= RSI_Oversold)  && (cci <= CCI_BotLevel) && (stK <= Stoch_Bottom);
      bool sellOsc = (rsi >= RSI_Overbought)&& (cci >= CCI_TopLevel) && (stK >= Stoch_Top);

      if(UseMacdFilter)
      {
         buyOsc  = buyOsc  && (macd < 0.0);   // MACD at the bottom for buys
         sellOsc = sellOsc && (macd > 0.0);   // MACD at the top for sells
      }

      bool buySignal  = ribbonBelowPrice && buyOsc  && (!RequireCandle || bullCandle);
      bool sellSignal = ribbonAbovePrice && sellOsc && (!RequireCandle || bearCandle);

      if(buySignal)  BuyArrow[i]  = low[i]  - gap;
      if(sellSignal) SellArrow[i] = high[i] + gap;

      //--- fire alerts once, only for the most recent closed bar
      if(i == 1)
      {
         if(buySignal && g_lastBuyBar != time[1])
         {
            g_lastBuyBar = time[1];
            DoAlert("BUY");
         }
         if(sellSignal && g_lastSellBar != time[1])
         {
            g_lastSellBar = time[1];
            DoAlert("SELL");
         }
      }
   }
   return(rates_total);
}

//+------------------------------------------------------------------+
void DoAlert(string dir)
{
   string msg = StringFormat("M1 Scalping FX: %s signal  %s  %s",
                             dir, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("M1 Scalping FX signal", msg);
}
//+------------------------------------------------------------------+
