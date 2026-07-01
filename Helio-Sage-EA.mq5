//+------------------------------------------------------------------+
//|                                           Helio-Sage-EA.mq5     |
//|                         Helio-Sage Algo Trading System            |
//|                    Smart Money Concepts / ICT Methodology EA      |
//|                                                                  |
//|  Architecture: Single-file modular design with 15 engines        |
//|  Target: EURUSD, GBPUSD, USDJPY on M1 chart                     |
//|  HTF Analysis: M15, H1, H4, D1, W1, MN1                         |
//+------------------------------------------------------------------+
#property copyright "Heisenburg"
#property link      ""
#property version   "1.00"
#property description "Helio-Sage - Institutional Smart Money Concepts EA"
#property description "Developed by Heisenburg"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| SECTION 0: CONSTANTS AND ENUMERATIONS                            |
//+------------------------------------------------------------------+

enum ENUM_HTF_BIAS
{
   BIAS_BULLISH = 0,   // Bullish
   BIAS_BEARISH = 1,   // Bearish
   BIAS_AUTO    = 2    // Auto-Detect from D1
};

enum ENUM_SESSION_MODE
{
   SESSION_LONDON   = 0,  // London Only
   SESSION_NEWYORK  = 1,  // New York Only
   SESSION_BOTH     = 2   // Both Sessions
};

enum ENUM_FVG_DIR
{
   FVG_BULLISH = 0,
   FVG_BEARISH = 1
};

enum ENUM_OB_DIR
{
   OB_BULLISH = 0,
   OB_BEARISH = 1
};

enum ENUM_AMD_STATE
{
   AMD_NONE          = 0,
   AMD_ACCUMULATION  = 1,
   AMD_MANIPULATION  = 2,
   AMD_DISTRIBUTION  = 3
};

enum ENUM_SESSION_ID
{
   SES_ASIA           = 0,
   SES_FRANKFURT      = 1,
   SES_LONDON_OPEN    = 2,
   SES_LONDON_MAIN    = 3,
   SES_NEWYORK_OPEN   = 4,
   SES_NEWYORK_MAIN   = 5,
   SES_LONDON_CLOSE   = 6
};

enum ENUM_TRADE_DIR
{
   TRADE_BUY  = 0,
   TRADE_SELL = 1,
   TRADE_NONE = 2
};

enum ENUM_WEEK_DAY_TYPE
{
   WDAY_MANIPULATION    = 0,  // Monday
   WDAY_CONTINUATION    = 1,  // Tuesday
   WDAY_REVERSAL        = 2,  // Wednesday
   WDAY_COMPLETION      = 3,  // Thursday
   WDAY_DISTRIBUTION    = 4   // Friday
};

//--- Array size limits
#define MAX_FVG_COUNT        50
#define MAX_OB_COUNT         50
#define MAX_SWING_COUNT      50
#define MAX_CYCLE_WINDOWS    16

//--- Session time boundaries (hours and minutes in NY time)
#define ASIA_START_H         0
#define ASIA_START_M         0
#define ASIA_END_H           7
#define ASIA_END_M           0
#define FRANK_START_H        2
#define FRANK_START_M        0
#define FRANK_END_H          3
#define FRANK_END_M          0
#define LDN_OPEN_START_H     3
#define LDN_OPEN_START_M     0
#define LDN_OPEN_END_H       5
#define LDN_OPEN_END_M       0
#define LDN_MAIN_START_H     3
#define LDN_MAIN_START_M     0
#define LDN_MAIN_END_H       12
#define LDN_MAIN_END_M       0
#define NY_OPEN_START_H      9
#define NY_OPEN_START_M      30
#define NY_OPEN_END_H        11
#define NY_OPEN_END_M        30
#define NY_MAIN_START_H      9
#define NY_MAIN_START_M      30
#define NY_MAIN_END_H        17
#define NY_MAIN_END_M        0
#define LDN_CLOSE_START_H    11
#define LDN_CLOSE_START_M    0
#define LDN_CLOSE_END_H      12
#define LDN_CLOSE_END_M      0

//--- Pip factor for 5/3 digit brokers
#define PIP_FACTOR           10.0

//+------------------------------------------------------------------+
//| SECTION 1: INPUT PARAMETERS                                      |
//+------------------------------------------------------------------+
input group "=== CORE SETTINGS ==="
input string            InpSymbol          = "";              // Symbol (blank = current chart)
input ENUM_HTF_BIAS     InpHTFBias         = BIAS_AUTO;       // HTF Directional Bias
input ENUM_SESSION_MODE InpSessionMode     = SESSION_BOTH;    // Session Mode
input int               InpMinConfluences  = 3;               // Minimum Confluences to Trade
input double            InpRiskPercent     = 1.0;             // Risk % per Trade
input int               InpMaxTrades       = 2;               // Maximum Concurrent Trades

input group "=== TRADE MANAGEMENT ==="
input bool              InpUseBreakEven    = true;            // Use Break Even
input double            InpBETriggerPips   = 10.0;            // Break Even Trigger (Pips)
input bool              InpUseTrailingStop = false;           // Use Trailing Stop
input double            InpTrailPips       = 15.0;            // Trailing Stop Distance (Pips)
input int               InpMagicNumber     = 77701;           // Magic Number
input string            InpTradeComment    = "HelioSage";    // Trade Comment

input group "=== VISUALIZATION ==="
input bool              InpShowZones       = true;            // Show Zones on Chart

input group "=== TIME SETTINGS ==="
input int               InpUTCOffset       = -99;             // UTC Offset (-99 = Auto-Detect)

//+------------------------------------------------------------------+
//| SECTION 2: DATA STRUCTURES                                       |
//+------------------------------------------------------------------+

struct SwingPoint
{
   double            price;
   datetime          time;
   int               bar_index;
   bool              is_high;
   bool              is_strong;
   bool              swept;
   ENUM_TIMEFRAMES   timeframe;
};

struct FVGZone
{
   double            top;
   double            bottom;
   ENUM_FVG_DIR      direction;
   ENUM_TIMEFRAMES   timeframe;
   datetime          time;
   bool              filled;
   bool              is_hvi;
   string            obj_name;
};

struct OrderBlock
{
   double            high;
   double            low;
   ENUM_OB_DIR       direction;
   ENUM_TIMEFRAMES   timeframe;
   datetime          time;
   bool              broken;
   bool              inducement_confirmed;
   string            obj_name;
};

struct AMDPattern
{
   ENUM_AMD_STATE    state;
   double            accum_high;
   double            accum_low;
   datetime          accum_start;
   double            manip_price;
   ENUM_TRADE_DIR    expected_dir;
   datetime          last_update;
};

//+------------------------------------------------------------------+
//| SECTION 3: GLOBAL VARIABLES                                      |
//+------------------------------------------------------------------+

CTrade            g_trade;
CPositionInfo     g_position;

string            g_symbol;
double            g_point;
double            g_pip_size;
int               g_digits;
double            g_tick_size;

//--- Session data
double            g_asia_high;
double            g_asia_low;
double            g_frank_high;
double            g_frank_low;
double            g_daily_open;
double            g_day_high;
double            g_day_low;
datetime          g_current_day;
bool              g_asia_high_swept;
bool              g_asia_low_swept;

//--- Major liquidity levels
double            g_pdh, g_pdl;
double            g_pwh, g_pwl;
double            g_pmh, g_pml;
double            g_52wk_high, g_52wk_low;

//--- Swing point arrays
SwingPoint        g_h1_swings[];
int               g_h1_swing_count;
SwingPoint        g_m15_swings[];
int               g_m15_swing_count;
SwingPoint        g_m1_swings[];
int               g_m1_swing_count;

//--- FVG arrays
FVGZone           g_fvg_m1[];
int               g_fvg_m1_count;
FVGZone           g_fvg_m15[];
int               g_fvg_m15_count;
FVGZone           g_fvg_h1[];
int               g_fvg_h1_count;
FVGZone           g_fvg_h4[];
int               g_fvg_h4_count;

//--- Order Blocks
OrderBlock        g_ob[];
int               g_ob_count;

//--- 90-minute cycle data
double            g_cycle_opens[MAX_CYCLE_WINDOWS];
datetime          g_cycle_times[MAX_CYCLE_WINDOWS];
int               g_current_cycle_index;

//--- AMD patterns
AMDPattern        g_amd_london;
AMDPattern        g_amd_ny;

//--- Indicator handles
int               g_handle_rsi;
int               g_handle_stoch;
int               g_handle_atr;

//--- TDI values
double            g_tdi_rsi_line;
double            g_tdi_signal_line;
double            g_tdi_trade_line;
double            g_tdi_upper_band;
double            g_tdi_lower_band;
double            g_tdi_mid_band;

//--- Market structure state
ENUM_TRADE_DIR    g_current_bias;
bool              g_bms_bullish;
bool              g_bms_bearish;
bool              g_momentum_shift;
bool              g_failure_swing_bull;
bool              g_failure_swing_bear;

//--- Weekly cycle
ENUM_WEEK_DAY_TYPE g_week_day_type;

//--- Time management
int               g_utc_offset_hours;
bool              g_is_dst;
datetime          g_last_bar_time;
datetime          g_last_m15_bar;
datetime          g_last_h1_bar;
datetime          g_last_h4_bar;
datetime          g_last_d1_bar;

//--- Confluence
int               g_last_confluence_score;
ENUM_TRADE_DIR    g_last_signal_dir;

//--- Chart objects
const string      OBJ_PREFIX = "HS_";

//--- CSV logging
string            g_csv_filename;

//--- Alert throttle
datetime          g_last_alert_time;

//+------------------------------------------------------------------+
//| SECTION 4: MODULE 1 — SESSION TIME ENGINE                        |
//| Converts broker time to NY time with automatic DST handling.     |
//| Tracks session boundaries and records session highs/lows.        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Determine if a UTC date falls within US Eastern DST               |
//| Rule: Second Sunday in March to First Sunday in November          |
//+------------------------------------------------------------------+
bool IsNewYorkDST(datetime utc_time)
{
   MqlDateTime dt;
   TimeToStruct(utc_time, dt);
   int month = dt.mon;
   int day   = dt.day;
   int hour  = dt.hour;

   if(month < 3 || month > 11) return false;
   if(month > 3 && month < 11) return true;

   if(month == 3)
   {
      int second_sunday = FindNthSunday(dt.year, 3, 2);
      if(day > second_sunday) return true;
      if(day < second_sunday) return false;
      return (hour >= 7);
   }

   if(month == 11)
   {
      int first_sunday = FindNthSunday(dt.year, 11, 1);
      if(day < first_sunday) return true;
      if(day > first_sunday) return false;
      return (hour < 6);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Calculate the Nth Sunday of a given month/year                    |
//+------------------------------------------------------------------+
int FindNthSunday(int year, int month, int n)
{
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year;
   dt.mon  = month;
   dt.day  = 1;
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime first_of_month = StructToTime(dt);
   TimeToStruct(first_of_month, dt);

   int dow = dt.day_of_week;
   int days_to_first_sun = (dow == 0) ? 0 : (7 - dow);
   int nth_day = 1 + days_to_first_sun + (n - 1) * 7;

   return nth_day;
}

//+------------------------------------------------------------------+
//| Convert broker server time to New York local time                  |
//+------------------------------------------------------------------+
datetime BrokerToNYTime(datetime broker_time)
{
   datetime utc_time = broker_time - g_utc_offset_hours * 3600;
   int ny_offset = IsNewYorkDST(utc_time) ? -4 : -5;
   return (datetime)(utc_time + ny_offset * 3600);
}

//+------------------------------------------------------------------+
//| Get current New York time                                         |
//+------------------------------------------------------------------+
datetime GetCurrentNYTime(void)
{
   return BrokerToNYTime(TimeCurrent());
}

//+------------------------------------------------------------------+
//| Convert datetime to decimal hours for session comparison           |
//+------------------------------------------------------------------+
double TimeToDecimal(datetime dt_time)
{
   MqlDateTime dt;
   TimeToStruct(dt_time, dt);
   return (double)dt.hour + (double)dt.min / 60.0;
}

//+------------------------------------------------------------------+
//| Check if current NY time is within a defined session               |
//+------------------------------------------------------------------+
bool IsInSession(ENUM_SESSION_ID sid)
{
   double t = TimeToDecimal(GetCurrentNYTime());

   switch(sid)
   {
      case SES_ASIA:
         return (t >= (double)ASIA_START_H + (double)ASIA_START_M / 60.0 &&
                 t <  (double)ASIA_END_H + (double)ASIA_END_M / 60.0);
      case SES_FRANKFURT:
         return (t >= (double)FRANK_START_H + (double)FRANK_START_M / 60.0 &&
                 t <  (double)FRANK_END_H + (double)FRANK_END_M / 60.0);
      case SES_LONDON_OPEN:
         return (t >= (double)LDN_OPEN_START_H + (double)LDN_OPEN_START_M / 60.0 &&
                 t <  (double)LDN_OPEN_END_H + (double)LDN_OPEN_END_M / 60.0);
      case SES_LONDON_MAIN:
         return (t >= (double)LDN_MAIN_START_H + (double)LDN_MAIN_START_M / 60.0 &&
                 t <  (double)LDN_MAIN_END_H + (double)LDN_MAIN_END_M / 60.0);
      case SES_NEWYORK_OPEN:
         return (t >= (double)NY_OPEN_START_H + (double)NY_OPEN_START_M / 60.0 &&
                 t <  (double)NY_OPEN_END_H + (double)NY_OPEN_END_M / 60.0);
      case SES_NEWYORK_MAIN:
         return (t >= (double)NY_MAIN_START_H + (double)NY_MAIN_START_M / 60.0 &&
                 t <  (double)NY_MAIN_END_H + (double)NY_MAIN_END_M / 60.0);
      case SES_LONDON_CLOSE:
         return (t >= (double)LDN_CLOSE_START_H + (double)LDN_CLOSE_START_M / 60.0 &&
                 t <  (double)LDN_CLOSE_END_H + (double)LDN_CLOSE_END_M / 60.0);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if currently in a valid entry window per session mode        |
//+------------------------------------------------------------------+
bool IsInTradingWindow(void)
{
   switch(InpSessionMode)
   {
      case SESSION_LONDON:  return IsInSession(SES_LONDON_OPEN);
      case SESSION_NEWYORK: return IsInSession(SES_NEWYORK_OPEN);
      case SESSION_BOTH:    return (IsInSession(SES_LONDON_OPEN) || IsInSession(SES_NEWYORK_OPEN));
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for new NY day and trigger daily reset                      |
//+------------------------------------------------------------------+
bool IsNewDay(void)
{
   datetime ny_time = GetCurrentNYTime();
   MqlDateTime dt;
   TimeToStruct(ny_time, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   datetime day_start = StructToTime(dt);

   if(day_start != g_current_day)
   {
      g_current_day = day_start;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Reset all daily-scoped data at NY midnight                        |
//+------------------------------------------------------------------+
void ResetDailyData(void)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   g_asia_high       = bid;
   g_asia_low        = bid;
   g_frank_high      = bid;
   g_frank_low       = bid;
   g_daily_open      = bid;
   g_day_high        = bid;
   g_day_low         = bid;
   g_asia_high_swept = false;
   g_asia_low_swept  = false;
   g_current_cycle_index = -1;
   ArrayInitialize(g_cycle_opens, 0.0);
   g_amd_london.state = AMD_NONE;
   g_amd_ny.state     = AMD_NONE;
}

//+------------------------------------------------------------------+
//| Update session highs/lows on every tick                           |
//+------------------------------------------------------------------+
void UpdateSessionData(void)
{
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   if(ask > g_day_high) g_day_high = ask;
   if(bid < g_day_low)  g_day_low  = bid;

   if(IsInSession(SES_ASIA))
   {
      if(ask > g_asia_high) g_asia_high = ask;
      if(bid < g_asia_low)  g_asia_low  = bid;
   }

   if(IsInSession(SES_FRANKFURT))
   {
      if(ask > g_frank_high) g_frank_high = ask;
      if(bid < g_frank_low)  g_frank_low  = bid;
   }

   if(!g_asia_high_swept && ask > g_asia_high + g_pip_size)
      g_asia_high_swept = true;
   if(!g_asia_low_swept && bid < g_asia_low - g_pip_size)
      g_asia_low_swept = true;
}

//+------------------------------------------------------------------+
//| Auto-detect broker UTC offset                                     |
//+------------------------------------------------------------------+
int DetectUTCOffset(void)
{
   long diff = (long)(TimeCurrent() - TimeGMT());
   return (int)MathRound((double)diff / 3600.0);
}

//+------------------------------------------------------------------+
//| SECTION 5: MODULE 2 — LIQUIDITY LEVELS ENGINE                    |
//| Calculates PDH/PDL, PWH/PWL, PMH/PML, 52-week extremes,         |
//| H1/M15 swing points, premium/discount zones.                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Update major liquidity levels from D1, W1, MN1 data               |
//+------------------------------------------------------------------+
void UpdateMajorLiquidity(void)
{
   g_pdh = iHigh(g_symbol, PERIOD_D1, 1);
   g_pdl = iLow(g_symbol, PERIOD_D1, 1);
   g_pwh = iHigh(g_symbol, PERIOD_W1, 1);
   g_pwl = iLow(g_symbol, PERIOD_W1, 1);
   g_pmh = iHigh(g_symbol, PERIOD_MN1, 1);
   g_pml = iLow(g_symbol, PERIOD_MN1, 1);

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(CopyHigh(g_symbol, PERIOD_W1, 0, 52, highs) == 52)
      g_52wk_high = highs[ArrayMaximum(highs)];
   if(CopyLow(g_symbol, PERIOD_W1, 0, 52, lows) == 52)
      g_52wk_low = lows[ArrayMinimum(lows)];
}

//+------------------------------------------------------------------+
//| Detect swing highs and lows on a given timeframe                  |
//| bars_side = bars on each side required for confirmation           |
//+------------------------------------------------------------------+
void DetectSwings(ENUM_TIMEFRAMES tf, int bars_side, SwingPoint &swings[], int &count)
{
   int total_bars = bars_side * 2 + 30;
   double highs[], lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   if(CopyHigh(g_symbol, tf, 0, total_bars, highs) < total_bars) return;
   if(CopyLow(g_symbol, tf, 0, total_bars, lows) < total_bars) return;
   if(CopyTime(g_symbol, tf, 0, total_bars, times) < total_bars) return;

   count = 0;

   for(int i = bars_side; i < total_bars - bars_side && count < MAX_SWING_COUNT; i++)
   {
      bool is_sh = true;
      for(int j = 1; j <= bars_side; j++)
      {
         if(highs[i] <= highs[i - j] || highs[i] <= highs[i + j])
         {
            is_sh = false;
            break;
         }
      }
      if(is_sh)
      {
         swings[count].price     = highs[i];
         swings[count].time      = times[i];
         swings[count].bar_index = i;
         swings[count].is_high   = true;
         swings[count].is_strong = false;
         swings[count].swept     = false;
         swings[count].timeframe = tf;
         count++;
         if(count >= MAX_SWING_COUNT) break;
      }

      bool is_sl = true;
      for(int j = 1; j <= bars_side; j++)
      {
         if(lows[i] >= lows[i - j] || lows[i] >= lows[i + j])
         {
            is_sl = false;
            break;
         }
      }
      if(is_sl && count < MAX_SWING_COUNT)
      {
         swings[count].price     = lows[i];
         swings[count].time      = times[i];
         swings[count].bar_index = i;
         swings[count].is_high   = false;
         swings[count].is_strong = false;
         swings[count].swept     = false;
         swings[count].timeframe = tf;
         count++;
      }
   }
}

//+------------------------------------------------------------------+
//| Update H1 swings (medium liquidity, 5 bars each side)             |
//+------------------------------------------------------------------+
void UpdateMediumLiquidity(void)
{
   DetectSwings(PERIOD_H1, 5, g_h1_swings, g_h1_swing_count);
}

//+------------------------------------------------------------------+
//| Update M15 swings (minor liquidity, 3 bars each side)             |
//+------------------------------------------------------------------+
void UpdateMinorLiquidity(void)
{
   DetectSwings(PERIOD_M15, 3, g_m15_swings, g_m15_swing_count);
}

//+------------------------------------------------------------------+
//| Premium zone check (above Daily Open)                             |
//+------------------------------------------------------------------+
bool IsInPremiumZone(void)
{
   return (SymbolInfoDouble(g_symbol, SYMBOL_BID) > g_daily_open);
}

//+------------------------------------------------------------------+
//| Discount zone check (below Daily Open)                            |
//+------------------------------------------------------------------+
bool IsInDiscountZone(void)
{
   return (SymbolInfoDouble(g_symbol, SYMBOL_BID) < g_daily_open);
}

//+------------------------------------------------------------------+
//| Check proximity to any major liquidity level                      |
//+------------------------------------------------------------------+
bool IsNearMajorLiquidity(double price, double threshold_pips)
{
   double thr = threshold_pips * g_pip_size;
   if(MathAbs(price - g_pdh) <= thr) return true;
   if(MathAbs(price - g_pdl) <= thr) return true;
   if(MathAbs(price - g_pwh) <= thr) return true;
   if(MathAbs(price - g_pwl) <= thr) return true;
   if(MathAbs(price - g_pmh) <= thr) return true;
   if(MathAbs(price - g_pml) <= thr) return true;
   return false;
}

//+------------------------------------------------------------------+
//| SECTION 6: MODULE 3 — 90-MINUTE CYCLE ENGINE                     |
//| Divides the NY day into 90-min windows, tracks opening prices,   |
//| detects sweeps of window opens followed by reversals.            |
//+------------------------------------------------------------------+

const int CYCLE_MINUTES[MAX_CYCLE_WINDOWS] =
{
   0, 90, 180, 270, 360, 450, 540, 630,
   720, 810, 900, 990, 1080, 1170, 1260, 1350
};

//+------------------------------------------------------------------+
//| Get the current 90-minute cycle window index                      |
//+------------------------------------------------------------------+
int GetCurrentCycleIndex(void)
{
   MqlDateTime dt;
   TimeToStruct(GetCurrentNYTime(), dt);
   int mins = dt.hour * 60 + dt.min;

   for(int i = MAX_CYCLE_WINDOWS - 1; i >= 0; i--)
   {
      if(mins >= CYCLE_MINUTES[i])
         return i;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Record opening price of new 90-minute windows                     |
//+------------------------------------------------------------------+
void UpdateCycleEngine(void)
{
   int idx = GetCurrentCycleIndex();
   if(idx != g_current_cycle_index)
   {
      g_current_cycle_index = idx;
      g_cycle_opens[idx] = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      g_cycle_times[idx] = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Detect 90-min cycle sweep and reversal                            |
//+------------------------------------------------------------------+
ENUM_TRADE_DIR CheckCycleSweepReversal(void)
{
   if(g_current_cycle_index < 0) return TRADE_NONE;
   double cycle_open = g_cycle_opens[g_current_cycle_index];
   if(cycle_open <= 0.0) return TRADE_NONE;

   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyHigh(g_symbol, PERIOD_M1, 0, 6, highs) < 6) return TRADE_NONE;
   if(CopyLow(g_symbol, PERIOD_M1, 0, 6, lows) < 6) return TRADE_NONE;
   if(CopyClose(g_symbol, PERIOD_M1, 0, 6, closes) < 6) return TRADE_NONE;

   bool swept_above = false;
   bool swept_below = false;
   for(int i = 1; i <= 5; i++)
   {
      if(highs[i] > cycle_open + g_pip_size) swept_above = true;
      if(lows[i] < cycle_open - g_pip_size)  swept_below = true;
   }

   if(swept_above && closes[1] < cycle_open) return TRADE_SELL;
   if(swept_below && closes[1] > cycle_open) return TRADE_BUY;

   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| SECTION 7: MODULE 4 — MARKET STRUCTURE ENGINE                    |
//| Analyzes M1/M15 for Strong/Weak Highs/Lows, BMS, Fake BMS,      |
//| Momentum Shifts, and Failure Swings.                             |
//+------------------------------------------------------------------+

void UpdateM1Swings(void)
{
   DetectSwings(PERIOD_M1, 3, g_m1_swings, g_m1_swing_count);
}

//+------------------------------------------------------------------+
//| Get most recent swing high (lowest bar_index = most recent)       |
//+------------------------------------------------------------------+
bool GetRecentSwingHigh(const SwingPoint &swings[], int count, SwingPoint &result)
{
   for(int i = 0; i < count; i++)
   {
      if(swings[i].is_high)
      {
         result = swings[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get most recent swing low                                         |
//+------------------------------------------------------------------+
bool GetRecentSwingLow(const SwingPoint &swings[], int count, SwingPoint &result)
{
   for(int i = 0; i < count; i++)
   {
      if(!swings[i].is_high)
      {
         result = swings[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Break in Market Structure                                   |
//+------------------------------------------------------------------+
void DetectBMS(void)
{
   g_bms_bullish = false;
   g_bms_bearish = false;

   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(g_symbol, PERIOD_M1, 0, 3, closes) < 3) return;

   SwingPoint sh, sl;
   if(GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sh))
   {
      if(closes[1] > sh.price) g_bms_bullish = true;
   }
   if(GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sl))
   {
      if(closes[1] < sl.price) g_bms_bearish = true;
   }
}

//+------------------------------------------------------------------+
//| Detect Strong High: wick sweeps prior high + closes below low     |
//+------------------------------------------------------------------+
bool DetectStrongHigh(void)
{
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyHigh(g_symbol, PERIOD_M1, 0, 20, highs) < 20) return false;
   if(CopyLow(g_symbol, PERIOD_M1, 0, 20, lows) < 20) return false;
   if(CopyClose(g_symbol, PERIOD_M1, 0, 20, closes) < 20) return false;

   SwingPoint sh, sl;
   if(!GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sh)) return false;
   if(!GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sl)) return false;

   for(int i = 1; i <= 5; i++)
   {
      if(highs[i] > sh.price && closes[i] < sl.price)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Strong Low: wick sweeps prior low + closes above high      |
//+------------------------------------------------------------------+
bool DetectStrongLow(void)
{
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyHigh(g_symbol, PERIOD_M1, 0, 20, highs) < 20) return false;
   if(CopyLow(g_symbol, PERIOD_M1, 0, 20, lows) < 20) return false;
   if(CopyClose(g_symbol, PERIOD_M1, 0, 20, closes) < 20) return false;

   SwingPoint sh, sl;
   if(!GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sh)) return false;
   if(!GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sl)) return false;

   for(int i = 1; i <= 5; i++)
   {
      if(lows[i] < sl.price && closes[i] > sh.price)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Momentum Shift                                             |
//+------------------------------------------------------------------+
bool DetectMomentumShift(ENUM_TRADE_DIR &direction)
{
   g_momentum_shift = false;
   direction = TRADE_NONE;

   if(DetectStrongLow())
   {
      g_momentum_shift = true;
      direction = TRADE_BUY;
      return true;
   }
   if(DetectStrongHigh())
   {
      g_momentum_shift = true;
      direction = TRADE_SELL;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Detect Failure Swings                                             |
//+------------------------------------------------------------------+
void DetectFailureSwings(void)
{
   g_failure_swing_bull = false;
   g_failure_swing_bear = false;

   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(g_handle_atr, 0, 0, 1, atr_buf) < 1) return;
   double atr_quarter = atr_buf[0] / 4.0;

   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyHigh(g_symbol, PERIOD_M1, 0, 15, highs) < 15) return;
   if(CopyLow(g_symbol, PERIOD_M1, 0, 15, lows) < 15) return;
   if(CopyClose(g_symbol, PERIOD_M1, 0, 15, closes) < 15) return;

   SwingPoint sh, sl;
   if(!GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sh)) return;
   if(!GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sl)) return;

   //--- Find recent low for bullish failure swing
   double recent_low = lows[1];
   for(int i = 2; i <= 5; i++)
      if(lows[i] < recent_low) recent_low = lows[i];

   if(recent_low > sl.price && (recent_low - sl.price) >= atr_quarter)
   {
      if(closes[1] > sh.price)
         g_failure_swing_bull = true;
   }

   //--- Find recent high for bearish failure swing
   double recent_high = highs[1];
   for(int i = 2; i <= 5; i++)
      if(highs[i] > recent_high) recent_high = highs[i];

   if(recent_high < sh.price && (sh.price - recent_high) >= atr_quarter)
   {
      if(closes[1] < sl.price)
         g_failure_swing_bear = true;
   }
}

//+------------------------------------------------------------------+
//| Determine HTF bias from D1 structure                              |
//+------------------------------------------------------------------+
ENUM_TRADE_DIR DetermineHTFBias(void)
{
   if(InpHTFBias == BIAS_BULLISH) return TRADE_BUY;
   if(InpHTFBias == BIAS_BEARISH) return TRADE_SELL;

   double d1h[], d1l[];
   ArraySetAsSeries(d1h, true);
   ArraySetAsSeries(d1l, true);

   if(CopyHigh(g_symbol, PERIOD_D1, 0, 10, d1h) < 10) return TRADE_NONE;
   if(CopyLow(g_symbol, PERIOD_D1, 0, 10, d1l) < 10) return TRADE_NONE;

   bool hh = (d1h[1] > d1h[3] && d1h[3] > d1h[5]);
   bool hl = (d1l[1] > d1l[3] && d1l[3] > d1l[5]);
   bool ll = (d1l[1] < d1l[3] && d1l[3] < d1l[5]);
   bool lh = (d1h[1] < d1h[3] && d1h[3] < d1h[5]);

   if(hh && hl) return TRADE_BUY;
   if(ll && lh) return TRADE_SELL;
   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| SECTION 8: MODULE 5 — FVG DETECTION ENGINE                       |
//+------------------------------------------------------------------+

void DetectFVGs(ENUM_TIMEFRAMES tf, FVGZone &fvg_array[], int &fvg_count)
{
   int bars_needed = 30;
   double highs[], lows[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   if(CopyHigh(g_symbol, tf, 0, bars_needed, highs) < bars_needed) return;
   if(CopyLow(g_symbol, tf, 0, bars_needed, lows) < bars_needed) return;
   if(CopyTime(g_symbol, tf, 0, bars_needed, times) < bars_needed) return;

   double avg_size = 0.0;
   int avg_cnt = 0;

   //--- Series: index 0=current, 1=previous, 2=two ago, etc.
   //--- FVG: 3 bars (i=newest, i+1=middle, i+2=oldest)
   for(int i = 1; i < bars_needed - 2; i++)
   {
      //--- Bullish FVG: oldest bar high < newest bar low
      if(highs[i + 2] < lows[i])
      {
         double gap = lows[i] - highs[i + 2];
         avg_size += gap;
         avg_cnt++;

         if(!FVGAlreadyExists(fvg_array, fvg_count, times[i], FVG_BULLISH) &&
            fvg_count < MAX_FVG_COUNT)
         {
            fvg_array[fvg_count].top       = lows[i];
            fvg_array[fvg_count].bottom    = highs[i + 2];
            fvg_array[fvg_count].direction = FVG_BULLISH;
            fvg_array[fvg_count].timeframe = tf;
            fvg_array[fvg_count].time      = times[i];
            fvg_array[fvg_count].filled    = false;
            fvg_array[fvg_count].is_hvi    = false;
            fvg_array[fvg_count].obj_name  = "";
            fvg_count++;
         }
      }

      //--- Bearish FVG: oldest bar low > newest bar high
      if(lows[i + 2] > highs[i])
      {
         double gap = lows[i + 2] - highs[i];
         avg_size += gap;
         avg_cnt++;

         if(!FVGAlreadyExists(fvg_array, fvg_count, times[i], FVG_BEARISH) &&
            fvg_count < MAX_FVG_COUNT)
         {
            fvg_array[fvg_count].top       = lows[i + 2];
            fvg_array[fvg_count].bottom    = highs[i];
            fvg_array[fvg_count].direction = FVG_BEARISH;
            fvg_array[fvg_count].timeframe = tf;
            fvg_array[fvg_count].time      = times[i];
            fvg_array[fvg_count].filled    = false;
            fvg_array[fvg_count].is_hvi    = false;
            fvg_array[fvg_count].obj_name  = "";
            fvg_count++;
         }
      }
   }

   //--- HVI classification (> 2x average)
   if(avg_cnt > 0)
   {
      avg_size /= (double)avg_cnt;
      for(int i = 0; i < fvg_count; i++)
      {
         double sz = fvg_array[i].top - fvg_array[i].bottom;
         fvg_array[i].is_hvi = (sz > avg_size * 2.0);
      }
   }

   //--- Fill status update
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   for(int i = 0; i < fvg_count; i++)
   {
      if(fvg_array[i].filled) continue;
      if(fvg_array[i].direction == FVG_BULLISH && bid <= fvg_array[i].bottom)
         fvg_array[i].filled = true;
      if(fvg_array[i].direction == FVG_BEARISH && bid >= fvg_array[i].top)
         fvg_array[i].filled = true;
   }

   //--- Array trim
   if(fvg_count >= MAX_FVG_COUNT)
      TrimFVGs(fvg_array, fvg_count);
}

bool FVGAlreadyExists(const FVGZone &arr[], int count, datetime t, ENUM_FVG_DIR dir)
{
   for(int i = 0; i < count; i++)
      if(arr[i].time == t && arr[i].direction == dir) return true;
   return false;
}

void TrimFVGs(FVGZone &arr[], int &count)
{
   int w = 0;
   for(int i = 0; i < count; i++)
   {
      if(!arr[i].filled)
      {
         if(w != i) arr[w] = arr[i];
         w++;
      }
   }
   count = w;
}

bool IsPriceAtFilledFVG(double price, ENUM_TRADE_DIR dir)
{
   if(CheckFVGHit(g_fvg_m15, g_fvg_m15_count, price, dir, false)) return true;
   if(CheckFVGHit(g_fvg_h1, g_fvg_h1_count, price, dir, false)) return true;
   if(CheckFVGHit(g_fvg_h4, g_fvg_h4_count, price, dir, false)) return true;
   return false;
}

bool IsHVIAtPrice(double price, ENUM_TRADE_DIR dir)
{
   if(CheckFVGHit(g_fvg_m15, g_fvg_m15_count, price, dir, true)) return true;
   if(CheckFVGHit(g_fvg_h1, g_fvg_h1_count, price, dir, true)) return true;
   if(CheckFVGHit(g_fvg_h4, g_fvg_h4_count, price, dir, true)) return true;
   return false;
}

bool CheckFVGHit(const FVGZone &arr[], int count, double price, ENUM_TRADE_DIR dir, bool hvi_only)
{
   for(int i = 0; i < count; i++)
   {
      if(hvi_only && !arr[i].is_hvi) continue;
      if(!hvi_only && !arr[i].filled) continue;
      if(price < arr[i].bottom || price > arr[i].top) continue;
      if(dir == TRADE_BUY && arr[i].direction == FVG_BULLISH) return true;
      if(dir == TRADE_SELL && arr[i].direction == FVG_BEARISH) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SECTION 9: MODULE 6 — ALGO CANDLE ENGINE                         |
//+------------------------------------------------------------------+

int DetectAlgoCandle(ENUM_TRADE_DIR &ac_dir)
{
   ac_dir = TRADE_NONE;

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if(CopyHigh(g_symbol, PERIOD_M1, 0, 10, highs) < 10) return 0;
   if(CopyLow(g_symbol, PERIOD_M1, 0, 10, lows) < 10) return 0;

   SwingPoint sh, sl;
   bool has_sh = GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sh);
   bool has_sl = GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sl);

   if(has_sh && highs[1] > sh.price)
   {
      if(HasRecentFVG(FVG_BEARISH, 3))
      {
         ac_dir = TRADE_SELL;
         int score = 1;
         if(g_bms_bearish) score = 2;
         if(HasInducementNearOB(TRADE_SELL)) score = 3;
         return score;
      }
   }

   if(has_sl && lows[1] < sl.price)
   {
      if(HasRecentFVG(FVG_BULLISH, 3))
      {
         ac_dir = TRADE_BUY;
         int score = 1;
         if(g_bms_bullish) score = 2;
         if(HasInducementNearOB(TRADE_BUY)) score = 3;
         return score;
      }
   }

   return 0;
}

bool HasRecentFVG(ENUM_FVG_DIR dir, int bars_lookback)
{
   datetime threshold = TimeCurrent() - bars_lookback * 60;
   for(int i = 0; i < g_fvg_m1_count; i++)
   {
      if(g_fvg_m1[i].direction == dir && g_fvg_m1[i].time >= threshold)
         return true;
   }
   return false;
}

ENUM_TRADE_DIR DetectVectorCandle(void)
{
   double opens[], closes[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   if(CopyOpen(g_symbol, PERIOD_M1, 0, 3, opens) < 3) return TRADE_NONE;
   if(CopyClose(g_symbol, PERIOD_M1, 0, 3, closes) < 3) return TRADE_NONE;

   bool bull_engulf = (closes[1] > opens[2] && closes[1] > closes[2] &&
                       opens[1] < closes[2] && opens[1] < opens[2]);
   bool bear_engulf = (closes[1] < opens[2] && closes[1] < closes[2] &&
                       opens[1] > closes[2] && opens[1] > opens[2]);

   if(bear_engulf && IsInPremiumZone()) return TRADE_SELL;
   if(bull_engulf && IsInDiscountZone()) return TRADE_BUY;
   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| SECTION 10: MODULE 7 — ORDER BLOCK ENGINE                        |
//+------------------------------------------------------------------+

void DetectOrderBlocks(ENUM_TIMEFRAMES tf)
{
   int bars_needed = 30;
   double opens[], closes[], highs[], lows[];
   datetime times[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(times, true);

   if(CopyOpen(g_symbol, tf, 0, bars_needed, opens) < bars_needed) return;
   if(CopyClose(g_symbol, tf, 0, bars_needed, closes) < bars_needed) return;
   if(CopyHigh(g_symbol, tf, 0, bars_needed, highs) < bars_needed) return;
   if(CopyLow(g_symbol, tf, 0, bars_needed, lows) < bars_needed) return;
   if(CopyTime(g_symbol, tf, 0, bars_needed, times) < bars_needed) return;

   for(int i = 1; i < bars_needed - 4; i++)
   {
      //--- Bullish OB: bearish candle followed by bullish impulse (i-1, i-2, i-3)
      if(closes[i] < opens[i])
      {
         int bull_cnt = 0;
         for(int j = 1; j <= 3 && (i - j) >= 0; j++)
            if(closes[i - j] > opens[i - j]) bull_cnt++;

         if(bull_cnt >= 3 && (i - 1) >= 0 && closes[i - 1] > highs[i])
            AddOrderBlock(lows[i], highs[i], OB_BULLISH, tf, times[i]);
      }

      //--- Bearish OB: bullish candle followed by bearish impulse
      if(closes[i] > opens[i])
      {
         int bear_cnt = 0;
         for(int j = 1; j <= 3 && (i - j) >= 0; j++)
            if(closes[i - j] < opens[i - j]) bear_cnt++;

         if(bear_cnt >= 3 && (i - 1) >= 0 && closes[i - 1] < lows[i])
            AddOrderBlock(lows[i], highs[i], OB_BEARISH, tf, times[i]);
      }
   }

   UpdateBreakerBlocks();
}

void AddOrderBlock(double low_p, double high_p, ENUM_OB_DIR dir, ENUM_TIMEFRAMES tf, datetime t)
{
   for(int i = 0; i < g_ob_count; i++)
      if(g_ob[i].time == t && g_ob[i].direction == dir) return;

   if(g_ob_count >= MAX_OB_COUNT)
   {
      for(int i = 0; i < g_ob_count - 1; i++)
         g_ob[i] = g_ob[i + 1];
      g_ob_count--;
   }

   g_ob[g_ob_count].low       = low_p;
   g_ob[g_ob_count].high      = high_p;
   g_ob[g_ob_count].direction = dir;
   g_ob[g_ob_count].timeframe = tf;
   g_ob[g_ob_count].time      = t;
   g_ob[g_ob_count].broken    = false;
   g_ob[g_ob_count].inducement_confirmed = false;
   g_ob[g_ob_count].obj_name  = "";
   g_ob_count++;
}

void UpdateBreakerBlocks(void)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   for(int i = 0; i < g_ob_count; i++)
   {
      if(g_ob[i].broken) continue;
      if(g_ob[i].direction == OB_BULLISH && bid < g_ob[i].low)
      {
         g_ob[i].broken = true;
         g_ob[i].direction = OB_BEARISH;
      }
      else if(g_ob[i].direction == OB_BEARISH && bid > g_ob[i].high)
      {
         g_ob[i].broken = true;
         g_ob[i].direction = OB_BULLISH;
      }
   }
}

bool IsPriceInOB(double price, ENUM_TRADE_DIR dir)
{
   for(int i = 0; i < g_ob_count; i++)
   {
      if(g_ob[i].broken) continue;
      if(price < g_ob[i].low || price > g_ob[i].high) continue;
      if(dir == TRADE_BUY && g_ob[i].direction == OB_BULLISH) return true;
      if(dir == TRADE_SELL && g_ob[i].direction == OB_BEARISH) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SECTION 11: MODULE 8 — INDUCEMENT DETECTION                      |
//+------------------------------------------------------------------+

bool HasInducementNearOB(ENUM_TRADE_DIR dir)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   for(int ob_i = 0; ob_i < g_ob_count; ob_i++)
   {
      if(g_ob[ob_i].broken) continue;

      if(dir == TRADE_BUY && g_ob[ob_i].direction == OB_BULLISH && g_ob[ob_i].high < bid)
      {
         for(int s = 0; s < g_m1_swing_count; s++)
         {
            if(!g_m1_swings[s].is_high &&
               g_m1_swings[s].price > g_ob[ob_i].high &&
               g_m1_swings[s].price < bid &&
               g_m1_swings[s].swept)
            {
               g_ob[ob_i].inducement_confirmed = true;
               return true;
            }
         }
      }

      if(dir == TRADE_SELL && g_ob[ob_i].direction == OB_BEARISH && g_ob[ob_i].low > bid)
      {
         for(int s = 0; s < g_m1_swing_count; s++)
         {
            if(g_m1_swings[s].is_high &&
               g_m1_swings[s].price < g_ob[ob_i].low &&
               g_m1_swings[s].price > bid &&
               g_m1_swings[s].swept)
            {
               g_ob[ob_i].inducement_confirmed = true;
               return true;
            }
         }
      }
   }
   return false;
}

void UpdateSweptStatus(void)
{
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

   for(int i = 0; i < g_m1_swing_count; i++)
   {
      if(g_m1_swings[i].swept) continue;
      if(g_m1_swings[i].is_high && ask > g_m1_swings[i].price)
         g_m1_swings[i].swept = true;
      if(!g_m1_swings[i].is_high && bid < g_m1_swings[i].price)
         g_m1_swings[i].swept = true;
   }

   for(int i = 0; i < g_m15_swing_count; i++)
   {
      if(g_m15_swings[i].swept) continue;
      if(g_m15_swings[i].is_high && ask > g_m15_swings[i].price)
         g_m15_swings[i].swept = true;
      if(!g_m15_swings[i].is_high && bid < g_m15_swings[i].price)
         g_m15_swings[i].swept = true;
   }
}

//+------------------------------------------------------------------+
//| SECTION 12: MODULE 9 — AMD PATTERN ENGINE                        |
//+------------------------------------------------------------------+

void UpdateAMDPattern(AMDPattern &amd, bool in_session)
{
   if(!in_session)
   {
      if(amd.state != AMD_DISTRIBUTION)
         amd.state = AMD_NONE;
      return;
   }

   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(g_handle_atr, 0, 0, 1, atr_buf) < 1) return;
   double atr_val = atr_buf[0];

   switch(amd.state)
   {
      case AMD_NONE:
         amd.state       = AMD_ACCUMULATION;
         amd.accum_high  = bid;
         amd.accum_low   = bid;
         amd.accum_start = TimeCurrent();
         amd.last_update = TimeCurrent();
         break;

      case AMD_ACCUMULATION:
      {
         if(bid > amd.accum_high) amd.accum_high = bid;
         if(bid < amd.accum_low)  amd.accum_low  = bid;
         double range = amd.accum_high - amd.accum_low;

         if(range < atr_val * 1.5 && (TimeCurrent() - amd.accum_start) >= 1800)
         {
            if(bid > amd.accum_high + g_pip_size)
            {
               amd.state        = AMD_MANIPULATION;
               amd.manip_price  = bid;
               amd.expected_dir = TRADE_SELL;
               amd.last_update  = TimeCurrent();
            }
            else if(bid < amd.accum_low - g_pip_size)
            {
               amd.state        = AMD_MANIPULATION;
               amd.manip_price  = bid;
               amd.expected_dir = TRADE_BUY;
               amd.last_update  = TimeCurrent();
            }
         }
         else if(range >= atr_val * 1.5)
         {
            amd.accum_high  = bid;
            amd.accum_low   = bid;
            amd.accum_start = TimeCurrent();
         }
         break;
      }

      case AMD_MANIPULATION:
      {
         if(amd.expected_dir == TRADE_SELL && bid < amd.accum_high)
         {
            amd.state = AMD_DISTRIBUTION;
            amd.last_update = TimeCurrent();
         }
         else if(amd.expected_dir == TRADE_BUY && bid > amd.accum_low)
         {
            amd.state = AMD_DISTRIBUTION;
            amd.last_update = TimeCurrent();
         }
         if(TimeCurrent() - amd.last_update > 900)
            amd.state = AMD_NONE;
         break;
      }

      case AMD_DISTRIBUTION:
      {
         if(TimeCurrent() - amd.last_update > 5400)
            amd.state = AMD_NONE;
         break;
      }
   }
}

ENUM_TRADE_DIR GetAMDSignal(void)
{
   if(g_amd_london.state == AMD_DISTRIBUTION) return g_amd_london.expected_dir;
   if(g_amd_ny.state == AMD_DISTRIBUTION)     return g_amd_ny.expected_dir;
   if(g_amd_london.state == AMD_MANIPULATION) return g_amd_london.expected_dir;
   if(g_amd_ny.state == AMD_MANIPULATION)     return g_amd_ny.expected_dir;
   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| SECTION 13: MODULE 10 — WEEKLY CYCLE ENGINE                      |
//+------------------------------------------------------------------+

void UpdateWeeklyCycle(void)
{
   MqlDateTime dt;
   TimeToStruct(GetCurrentNYTime(), dt);
   switch(dt.day_of_week)
   {
      case 1: g_week_day_type = WDAY_MANIPULATION;  break;
      case 2: g_week_day_type = WDAY_CONTINUATION;  break;
      case 3: g_week_day_type = WDAY_REVERSAL;      break;
      case 4: g_week_day_type = WDAY_COMPLETION;    break;
      case 5: g_week_day_type = WDAY_DISTRIBUTION;  break;
      default: g_week_day_type = WDAY_DISTRIBUTION; break;
   }
}

bool IsMondayManipulationAligned(void)
{
   if(g_week_day_type != WDAY_MANIPULATION) return false;
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   return (ask > g_pwh || bid < g_pwl);
}

bool IsFridayLate(void)
{
   if(g_week_day_type != WDAY_DISTRIBUTION) return false;
   return (TimeToDecimal(GetCurrentNYTime()) >= 14.0);
}

//+------------------------------------------------------------------+
//| SECTION 14: MODULE 11 — TDI INDICATOR                            |
//+------------------------------------------------------------------+

void CalculateTDI(void)
{
   double rsi_buf[];
   ArraySetAsSeries(rsi_buf, true);
   if(CopyBuffer(g_handle_rsi, 0, 0, 40, rsi_buf) < 40) return;

   int bb_period = 34;
   double bb_dev = 1.6185;

   double sum = 0.0;
   for(int i = 0; i < bb_period; i++)
      sum += rsi_buf[i];
   g_tdi_mid_band = sum / (double)bb_period;

   double sq_sum = 0.0;
   for(int i = 0; i < bb_period; i++)
   {
      double d = rsi_buf[i] - g_tdi_mid_band;
      sq_sum += d * d;
   }
   double std_dev = MathSqrt(sq_sum / (double)bb_period);
   g_tdi_upper_band = g_tdi_mid_band + bb_dev * std_dev;
   g_tdi_lower_band = g_tdi_mid_band - bb_dev * std_dev;

   g_tdi_rsi_line    = rsi_buf[0];
   g_tdi_signal_line = (rsi_buf[0] + rsi_buf[1]) / 2.0;

   double ts = 0.0;
   for(int i = 0; i < 7; i++)
      ts += rsi_buf[i];
   g_tdi_trade_line = ts / 7.0;
}

ENUM_TRADE_DIR DetectTDIBreakout(void)
{
   double rsi_buf[];
   ArraySetAsSeries(rsi_buf, true);
   if(CopyBuffer(g_handle_rsi, 0, 0, 3, rsi_buf) < 3) return TRADE_NONE;

   if(rsi_buf[0] > g_tdi_mid_band && rsi_buf[1] <= g_tdi_mid_band)
   {
      if(g_tdi_signal_line > g_tdi_trade_line) return TRADE_BUY;
   }
   if(rsi_buf[0] < g_tdi_mid_band && rsi_buf[1] >= g_tdi_mid_band)
   {
      if(g_tdi_signal_line < g_tdi_trade_line) return TRADE_SELL;
   }
   return TRADE_NONE;
}

ENUM_TRADE_DIR DetectTDIDivergence(void)
{
   double rsi_buf[], price_h[], price_l[];
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(price_h, true);
   ArraySetAsSeries(price_l, true);

   int lb = 20;
   if(CopyBuffer(g_handle_rsi, 0, 0, lb, rsi_buf) < lb) return TRADE_NONE;
   if(CopyHigh(g_symbol, PERIOD_M1, 0, lb, price_h) < lb) return TRADE_NONE;
   if(CopyLow(g_symbol, PERIOD_M1, 0, lb, price_l) < lb) return TRADE_NONE;

   int ph_idx = ArrayMaximum(price_h, 0, 10);
   int rh_idx = ArrayMaximum(rsi_buf, 0, 10);
   if(price_h[1] >= price_h[ph_idx] && rsi_buf[1] < rsi_buf[rh_idx] && rh_idx > 3)
      return TRADE_SELL;

   int pl_idx = ArrayMinimum(price_l, 0, 10);
   int rl_idx = ArrayMinimum(rsi_buf, 0, 10);
   if(price_l[1] <= price_l[pl_idx] && rsi_buf[1] > rsi_buf[rl_idx] && rl_idx > 3)
      return TRADE_BUY;

   return TRADE_NONE;
}

ENUM_TRADE_DIR CheckStochRSI(void)
{
   double main_buf[], sig_buf[];
   ArraySetAsSeries(main_buf, true);
   ArraySetAsSeries(sig_buf, true);
   if(CopyBuffer(g_handle_stoch, 0, 0, 2, main_buf) < 2) return TRADE_NONE;
   if(CopyBuffer(g_handle_stoch, 1, 0, 2, sig_buf) < 2) return TRADE_NONE;

   if(main_buf[0] > 80.0 && sig_buf[0] > 80.0) return TRADE_SELL;
   if(main_buf[0] < 20.0 && sig_buf[0] < 20.0) return TRADE_BUY;
   return TRADE_NONE;
}

//+------------------------------------------------------------------+
//| SECTION 15: MODULE 12 — CONFLUENCE SCORING ENGINE                |
//+------------------------------------------------------------------+

int CalculateConfluenceScore(ENUM_TRADE_DIR direction, string &details)
{
   int score = 0;
   details = "";
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   if(g_current_bias == direction)
   { score++; StringAdd(details, "HTF|"); }

   if(direction == TRADE_SELL && IsInPremiumZone())
   { score++; StringAdd(details, "PREM|"); }
   if(direction == TRADE_BUY && IsInDiscountZone())
   { score++; StringAdd(details, "DISC|"); }

   if(IsInTradingWindow())
   { score++; StringAdd(details, "SES|"); }

   if(direction == TRADE_SELL && g_asia_high_swept)
   { score++; StringAdd(details, "AHS|"); }
   if(direction == TRADE_BUY && g_asia_low_swept)
   { score++; StringAdd(details, "ALS|"); }

   if(IsPriceAtFilledFVG(bid, direction))
   { score++; StringAdd(details, "FVG|"); }

   if(IsHVIAtPrice(bid, direction))
   { score += 2; StringAdd(details, "HVI|"); }

   ENUM_TRADE_DIR ac_dir = TRADE_NONE;
   int ac_sc = DetectAlgoCandle(ac_dir);
   if(ac_sc > 0 && ac_dir == direction)
   { score += ac_sc; StringAdd(details, "AC" + IntegerToString(ac_sc) + "|"); }

   if(IsPriceInOB(bid, direction))
   { score++; StringAdd(details, "OB|"); }

   if(HasInducementNearOB(direction))
   { score++; StringAdd(details, "IND|"); }

   if(GetAMDSignal() == direction)
   { score++; StringAdd(details, "AMD|"); }

   if(IsMondayManipulationAligned())
   { score++; StringAdd(details, "WK|"); }

   if(DetectTDIBreakout() == direction)
   { score++; StringAdd(details, "TDI|"); }

   if(DetectTDIDivergence() == direction)
   { score++; StringAdd(details, "DIV|"); }

   if(CheckCycleSweepReversal() == direction)
   { score++; StringAdd(details, "90M|"); }

   if(IsNearMajorLiquidity(bid, 20.0))
   { score++; StringAdd(details, "LIQ|"); }

   ENUM_TRADE_DIR ms_dir = TRADE_NONE;
   if(DetectMomentumShift(ms_dir) && ms_dir == direction)
   { score++; StringAdd(details, "MOM|"); }

   if(direction == TRADE_BUY && g_failure_swing_bull)
   { score++; StringAdd(details, "FS|"); }
   if(direction == TRADE_SELL && g_failure_swing_bear)
   { score++; StringAdd(details, "FS|"); }

   return score;
}

//+------------------------------------------------------------------+
//| SECTION 16: MODULE 13 — TRADE EXECUTION ENGINE                   |
//+------------------------------------------------------------------+

int CountOpenTrades(void)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Magic() == InpMagicNumber && g_position.Symbol() == g_symbol)
            cnt++;
      }
   }
   return cnt;
}

double CalculateLotSize(double sl_pips)
{
   if(sl_pips <= 0.0) return 0.0;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amt = balance * InpRiskPercent / 100.0;
   double tick_val = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val <= 0.0 || tick_sz <= 0.0) return 0.0;

   double pip_val = tick_val * (g_pip_size / tick_sz);
   if(pip_val <= 0.0) return 0.0;

   double lots     = risk_amt / (sl_pips * pip_val);
   double min_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(lot_step <= 0.0) lot_step = 0.01;

   lots = MathMax(lots, min_lot);
   lots = MathMin(lots, max_lot);
   lots = NormalizeDouble(MathFloor(lots / lot_step) * lot_step, 2);
   return lots;
}

double CalculateStopLoss(ENUM_TRADE_DIR direction)
{
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(g_handle_atr, 0, 0, 1, atr_buf) < 1) return 0.0;
   double atr_half = atr_buf[0] * 0.5;

   SwingPoint sp;
   if(direction == TRADE_BUY)
   {
      if(GetRecentSwingLow(g_m1_swings, g_m1_swing_count, sp))
         return NormalizeDouble(sp.price - atr_half, g_digits);
      return NormalizeDouble(SymbolInfoDouble(g_symbol, SYMBOL_BID) - atr_buf[0], g_digits);
   }
   else
   {
      if(GetRecentSwingHigh(g_m1_swings, g_m1_swing_count, sp))
         return NormalizeDouble(sp.price + atr_half, g_digits);
      return NormalizeDouble(SymbolInfoDouble(g_symbol, SYMBOL_ASK) + atr_buf[0], g_digits);
   }
}

void CalculateTakeProfits(ENUM_TRADE_DIR direction, double entry, double &tp1, double &tp2)
{
   if(direction == TRADE_BUY)
   {
      tp1 = (g_pdh > entry) ? g_pdh : g_pwh;
      tp2 = (g_pwh > entry) ? g_pwh : g_pmh;
      if(tp1 <= entry) tp1 = entry + (entry - CalculateStopLoss(direction)) * 2.0;
      if(tp2 <= entry) tp2 = tp1 + (tp1 - entry);
   }
   else
   {
      tp1 = (g_pdl < entry) ? g_pdl : g_pwl;
      tp2 = (g_pwl < entry) ? g_pwl : g_pml;
      if(tp1 >= entry) tp1 = entry - (CalculateStopLoss(direction) - entry) * 2.0;
      if(tp2 >= entry) tp2 = tp1 - (entry - tp1);
   }
   tp1 = NormalizeDouble(tp1, g_digits);
   tp2 = NormalizeDouble(tp2, g_digits);
}

bool ExecuteTrade(ENUM_TRADE_DIR direction, int score, const string &confluences)
{
   if(CountOpenTrades() >= InpMaxTrades) return false;
   if(IsFridayLate()) return false;

   double sl = CalculateStopLoss(direction);
   double entry = 0.0;
   double sl_pips = 0.0;

   if(direction == TRADE_BUY)
   {
      entry   = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      sl_pips = (entry - sl) / g_pip_size;
   }
   else
   {
      entry   = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      sl_pips = (sl - entry) / g_pip_size;
   }

   if(sl_pips <= 0.0 || sl_pips > 100.0) return false;

   double lots = CalculateLotSize(sl_pips);
   if(lots <= 0.0) return false;

   double tp1 = 0.0, tp2 = 0.0;
   CalculateTakeProfits(direction, entry, tp1, tp2);

   string comment = InpTradeComment + "|" + IntegerToString(score);

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);

   bool result = false;
   if(direction == TRADE_BUY)
      result = g_trade.Buy(lots, g_symbol, entry, sl, tp1, comment);
   else
      result = g_trade.Sell(lots, g_symbol, entry, sl, tp1, comment);

   if(result)
   {
      PrintFormat("[TRADE] %s %.5f SL:%.5f TP:%.5f Lots:%.2f Score:%d %s",
                 (direction == TRADE_BUY ? "BUY" : "SELL"),
                 entry, sl, tp1, lots, score, confluences);
      LogTradeToCSV(direction, entry, sl, tp1, lots, score, confluences);
      SendNotification(g_symbol + " " + (direction == TRADE_BUY ? "BUY" : "SELL") +
                       " S:" + IntegerToString(score));
      return true;
   }

   PrintFormat("[ERROR] %d: %s", (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return false;
}

void ManageOpenPositions(void)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_position.SelectByIndex(i)) continue;
      if(g_position.Magic() != InpMagicNumber || g_position.Symbol() != g_symbol) continue;

      double open_p = g_position.PriceOpen();
      double cur_sl = g_position.StopLoss();
      double cur_tp = g_position.TakeProfit();
      ulong  ticket = g_position.Ticket();
      double bid    = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(g_symbol, SYMBOL_ASK);

      //--- Break Even
      if(InpUseBreakEven)
      {
         double be_dist = InpBETriggerPips * g_pip_size;
         if(g_position.PositionType() == POSITION_TYPE_BUY)
         {
            if((bid - open_p) >= be_dist && cur_sl < open_p)
            {
               double new_sl = NormalizeDouble(open_p + g_pip_size, g_digits);
               if(new_sl != cur_sl)
                  g_trade.PositionModify(ticket, new_sl, cur_tp);
            }
         }
         else if(g_position.PositionType() == POSITION_TYPE_SELL)
         {
            if((open_p - ask) >= be_dist && (cur_sl > open_p || cur_sl == 0.0))
            {
               double new_sl = NormalizeDouble(open_p - g_pip_size, g_digits);
               if(new_sl != cur_sl)
                  g_trade.PositionModify(ticket, new_sl, cur_tp);
            }
         }
      }

      //--- Trailing Stop
      if(InpUseTrailingStop)
      {
         double trail = InpTrailPips * g_pip_size;
         if(g_position.PositionType() == POSITION_TYPE_BUY)
         {
            double new_sl = NormalizeDouble(bid - trail, g_digits);
            if(new_sl > cur_sl && new_sl > open_p)
               g_trade.PositionModify(ticket, new_sl, cur_tp);
         }
         else if(g_position.PositionType() == POSITION_TYPE_SELL)
         {
            double new_sl = NormalizeDouble(ask + trail, g_digits);
            if((new_sl < cur_sl || cur_sl == 0.0) && new_sl < open_p)
               g_trade.PositionModify(ticket, new_sl, cur_tp);
         }
      }
   }
}

void CloseAllTrades(const string &reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_position.SelectByIndex(i)) continue;
      if(g_position.Magic() != InpMagicNumber || g_position.Symbol() != g_symbol) continue;
      ulong ticket = g_position.Ticket();
      if(g_trade.PositionClose(ticket))
         PrintFormat("[CLOSE] #%I64u %s", ticket, reason);
   }
}

void CheckSessionEndRules(void)
{
   datetime ny = GetCurrentNYTime();
   double t = TimeToDecimal(ny);
   MqlDateTime dt;
   TimeToStruct(ny, dt);

   if(InpSessionMode == SESSION_LONDON && t >= 12.0 && t < 12.02)
      CloseAllTrades("London Close");

   if(dt.day_of_week == 5 && t >= 17.0)
      CloseAllTrades("Weekend Close");
}

//+------------------------------------------------------------------+
//| SECTION 17: MODULE 14 — CHART VISUALIZATION                      |
//+------------------------------------------------------------------+

void CleanupChartObjects(void)
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
}

void DrawHLine(const string &tag, double price, color clr, int width,
               ENUM_LINE_STYLE style, const string &label)
{
   if(price <= 0.0) return;
   string name = OBJ_PREFIX + tag;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   else
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void DrawZoneRect(const string &tag, datetime t1, double p1, datetime t2, double p2, color clr)
{
   if(p1 <= 0.0 || p2 <= 0.0) return;
   string name = OBJ_PREFIX + tag;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, (long)t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, (long)t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawDashboard(int score, ENUM_TRADE_DIR dir, const string &details)
{
   string name1 = OBJ_PREFIX + "DASH1";
   string name2 = OBJ_PREFIX + "DASH2";

   string dir_txt = "NEUTRAL";
   color  dir_clr = clrGray;
   if(dir == TRADE_BUY)  { dir_txt = "BULLISH"; dir_clr = clrLimeGreen; }
   if(dir == TRADE_SELL) { dir_txt = "BEARISH"; dir_clr = clrOrangeRed; }

   string line1 = "HELIO-SAGE | Score:" + IntegerToString(score) +
                  " | Bias:" + dir_txt + " | Min:" + IntegerToString(InpMinConfluences);

   if(ObjectFind(0, name1) < 0)
      ObjectCreate(0, name1, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name1, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name1, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name1, OBJPROP_YDISTANCE, 20);
   ObjectSetString(0, name1, OBJPROP_TEXT, line1);
   ObjectSetString(0, name1, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name1, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name1, OBJPROP_COLOR, dir_clr);
   ObjectSetInteger(0, name1, OBJPROP_SELECTABLE, false);

   string ses_txt = "OFF";
   if(IsInSession(SES_ASIA))          ses_txt = "ASIA";
   else if(IsInSession(SES_FRANKFURT)) ses_txt = "FRANK";
   else if(IsInSession(SES_LONDON_OPEN))  ses_txt = "LDN_OPEN";
   else if(IsInSession(SES_NEWYORK_OPEN)) ses_txt = "NY_OPEN";
   else if(IsInSession(SES_LONDON_MAIN))  ses_txt = "LONDON";
   else if(IsInSession(SES_NEWYORK_MAIN)) ses_txt = "NY";

   string line2 = "Ses:" + ses_txt + " | " + (StringLen(details) > 0 ? details : "Scanning...");

   if(ObjectFind(0, name2) < 0)
      ObjectCreate(0, name2, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name2, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name2, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name2, OBJPROP_YDISTANCE, 38);
   ObjectSetString(0, name2, OBJPROP_TEXT, line2);
   ObjectSetString(0, name2, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name2, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name2, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name2, OBJPROP_SELECTABLE, false);
}

void UpdateVisualization(void)
{
   if(!InpShowZones) return;

   DrawHLine("PDH", g_pdh, clrDodgerBlue, 1, STYLE_DASH, "PDH");
   DrawHLine("PDL", g_pdl, clrCrimson, 1, STYLE_DASH, "PDL");
   DrawHLine("PWH", g_pwh, clrDodgerBlue, 2, STYLE_DASHDOT, "PWH");
   DrawHLine("PWL", g_pwl, clrCrimson, 2, STYLE_DASHDOT, "PWL");
   DrawHLine("PMH", g_pmh, clrDodgerBlue, 2, STYLE_SOLID, "PMH");
   DrawHLine("PML", g_pml, clrCrimson, 2, STYLE_SOLID, "PML");
   DrawHLine("DO", g_daily_open, clrYellow, 1, STYLE_SOLID, "D.O.");
   DrawHLine("AH", g_asia_high, clrRed, 1, STYLE_DOT, "Asia High");
   DrawHLine("AL", g_asia_low, clrLime, 1, STYLE_DOT, "Asia Low");

   DrawFVGRects(g_fvg_m15, g_fvg_m15_count, "F15_");
   DrawFVGRects(g_fvg_h1, g_fvg_h1_count, "FH1_");
   DrawFVGRects(g_fvg_h4, g_fvg_h4_count, "FH4_");
   DrawOBRects();

   string buy_det = "", sell_det = "";
   int buy_sc  = CalculateConfluenceScore(TRADE_BUY, buy_det);
   int sell_sc = CalculateConfluenceScore(TRADE_SELL, sell_det);

   if(buy_sc >= sell_sc)
   {
      g_last_confluence_score = buy_sc;
      g_last_signal_dir = TRADE_BUY;
      DrawDashboard(buy_sc, TRADE_BUY, buy_det);
   }
   else
   {
      g_last_confluence_score = sell_sc;
      g_last_signal_dir = TRADE_SELL;
      DrawDashboard(sell_sc, TRADE_SELL, sell_det);
   }
}

void DrawFVGRects(FVGZone &arr[], int count, const string &prefix)
{
   datetime future = TimeCurrent() + 14400;
   for(int i = 0; i < count; i++)
   {
      if(arr[i].filled) continue;
      string tag = prefix + IntegerToString(i);
      color clr = (arr[i].direction == FVG_BULLISH) ? clrRoyalBlue : clrIndianRed;
      DrawZoneRect(tag, arr[i].time, arr[i].bottom, future, arr[i].top, clr);
   }
}

void DrawOBRects(void)
{
   datetime future = TimeCurrent() + 14400;
   for(int i = 0; i < g_ob_count; i++)
   {
      if(g_ob[i].broken) continue;
      string tag = "OB_" + IntegerToString(i);
      color clr = (g_ob[i].direction == OB_BULLISH) ? clrOrange : clrMediumPurple;
      DrawZoneRect(tag, g_ob[i].time, g_ob[i].low, future, g_ob[i].high, clr);
   }
}

//+------------------------------------------------------------------+
//| SECTION 18: MODULE 15 — LOGGING AND ALERTS                       |
//+------------------------------------------------------------------+

void InitCSVLog(void)
{
   MqlDateTime dt;
   TimeCurrent(dt);
   g_csv_filename = StringFormat("HelioSage_%s_%04d%02d%02d.csv",
                                 g_symbol, dt.year, dt.mon, dt.day);

   if(!FileIsExist(g_csv_filename, FILE_COMMON))
   {
      int fh = FileOpen(g_csv_filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
      if(fh != INVALID_HANDLE)
      {
         FileWrite(fh, "Time", "Symbol", "Dir", "Entry", "SL", "TP", "Lots", "Score", "Confluences");
         FileClose(fh);
      }
   }
}

void LogTradeToCSV(ENUM_TRADE_DIR dir, double entry, double sl,
                   double tp, double lots, int score, const string &confluences)
{
   int fh = FileOpen(g_csv_filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(fh != INVALID_HANDLE)
   {
      FileSeek(fh, 0, SEEK_END);
      FileWrite(fh,
                TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                g_symbol,
                (dir == TRADE_BUY ? "BUY" : "SELL"),
                DoubleToString(entry, g_digits),
                DoubleToString(sl, g_digits),
                DoubleToString(tp, g_digits),
                DoubleToString(lots, 2),
                IntegerToString(score),
                confluences);
      FileClose(fh);
   }
}

void CheckEarlyWarning(int score, ENUM_TRADE_DIR dir)
{
   if(score >= InpMinConfluences - 1 && score < InpMinConfluences)
   {
      if(TimeCurrent() - g_last_alert_time > 300)
      {
         Alert(StringFormat("[ALGO] %s %s near threshold: %d/%d",
               g_symbol, (dir == TRADE_BUY ? "BUY" : "SELL"), score, InpMinConfluences));
         g_last_alert_time = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| SECTION 19: MAIN EA LIFECYCLE                                    |
//+------------------------------------------------------------------+

int OnInit()
{
   g_symbol = (InpSymbol == "" || InpSymbol == NULL) ? _Symbol : InpSymbol;

   if(!SymbolSelect(g_symbol, true))
   {
      Print("[FATAL] Cannot select symbol: ", g_symbol);
      return INIT_FAILED;
   }

   g_digits    = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point     = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   g_pip_size  = (g_digits == 5 || g_digits == 3) ? g_point * PIP_FACTOR : g_point;

   if(InpUTCOffset == -99)
      g_utc_offset_hours = DetectUTCOffset();
   else
      g_utc_offset_hours = InpUTCOffset;
   g_is_dst = IsNewYorkDST(TimeGMT());

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);

   g_handle_rsi   = iRSI(g_symbol, PERIOD_M1, 13, PRICE_CLOSE);
   g_handle_stoch = iStochastic(g_symbol, PERIOD_M1, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_handle_atr   = iATR(g_symbol, PERIOD_M1, 14);

   if(g_handle_rsi == INVALID_HANDLE || g_handle_stoch == INVALID_HANDLE || g_handle_atr == INVALID_HANDLE)
   {
      Print("[FATAL] Indicator creation failed");
      return INIT_FAILED;
   }

   ArrayResize(g_h1_swings, MAX_SWING_COUNT);
   ArrayResize(g_m15_swings, MAX_SWING_COUNT);
   ArrayResize(g_m1_swings, MAX_SWING_COUNT);
   ArrayResize(g_fvg_m1, MAX_FVG_COUNT);
   ArrayResize(g_fvg_m15, MAX_FVG_COUNT);
   ArrayResize(g_fvg_h1, MAX_FVG_COUNT);
   ArrayResize(g_fvg_h4, MAX_FVG_COUNT);
   ArrayResize(g_ob, MAX_OB_COUNT);

   g_h1_swing_count = 0; g_m15_swing_count = 0; g_m1_swing_count = 0;
   g_fvg_m1_count = 0; g_fvg_m15_count = 0; g_fvg_h1_count = 0; g_fvg_h4_count = 0;
   g_ob_count = 0;

   g_current_day = 0;
   g_asia_high = 0; g_asia_low = 0;
   g_frank_high = 0; g_frank_low = 0;
   g_daily_open = 0; g_day_high = 0; g_day_low = 0;
   g_asia_high_swept = false; g_asia_low_swept = false;
   g_current_cycle_index = -1;
   ArrayInitialize(g_cycle_opens, 0.0);
   g_amd_london.state = AMD_NONE; g_amd_ny.state = AMD_NONE;
   g_last_bar_time = 0; g_last_m15_bar = 0;
   g_last_h1_bar = 0; g_last_h4_bar = 0; g_last_d1_bar = 0;
   g_last_alert_time = 0;
   g_bms_bullish = false; g_bms_bearish = false;
   g_momentum_shift = false;
   g_failure_swing_bull = false; g_failure_swing_bear = false;
   g_last_confluence_score = 0;
   g_last_signal_dir = TRADE_NONE;

   UpdateMajorLiquidity();
   g_current_bias = DetermineHTFBias();
   UpdateWeeklyCycle();
   InitCSVLog();

   PrintFormat("[INIT] %s Pip:%.5f UTC:%+d DST:%s Bias:%s Min:%d",
              g_symbol, g_pip_size, g_utc_offset_hours,
              (g_is_dst ? "Y" : "N"),
              (g_current_bias == TRADE_BUY ? "BULL" : (g_current_bias == TRADE_SELL ? "BEAR" : "NEU")),
              InpMinConfluences);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_handle_rsi != INVALID_HANDLE)   IndicatorRelease(g_handle_rsi);
   if(g_handle_stoch != INVALID_HANDLE) IndicatorRelease(g_handle_stoch);
   if(g_handle_atr != INVALID_HANDLE)   IndicatorRelease(g_handle_atr);
   CleanupChartObjects();
   PrintFormat("[DEINIT] Reason: %d", reason);
}

void OnTick()
{
   if(IsNewDay())
   {
      ResetDailyData();
      UpdateMajorLiquidity();
      g_current_bias = DetermineHTFBias();
      UpdateWeeklyCycle();
      InitCSVLog();
      PrintFormat("[DAY] Open:%.5f Bias:%s %s",
                 g_daily_open,
                 (g_current_bias == TRADE_BUY ? "BULL" : (g_current_bias == TRADE_SELL ? "BEAR" : "NEU")),
                 EnumToString(g_week_day_type));
   }

   UpdateSessionData();
   UpdateCycleEngine();

   datetime bar_time[];
   ArraySetAsSeries(bar_time, true);
   if(CopyTime(g_symbol, PERIOD_M1, 0, 1, bar_time) < 1) return;

   if(bar_time[0] == g_last_bar_time)
   {
      ManageOpenPositions();
      CheckSessionEndRules();
      return;
   }
   g_last_bar_time = bar_time[0];

   //--- New M1 bar processing
   UpdateM1Swings();
   DetectBMS();
   DetectFailureSwings();
   UpdateSweptStatus();
   DetectFVGs(PERIOD_M1, g_fvg_m1, g_fvg_m1_count);
   DetectOrderBlocks(PERIOD_M1);
   UpdateAMDPattern(g_amd_london, IsInSession(SES_LONDON_MAIN));
   UpdateAMDPattern(g_amd_ny, IsInSession(SES_NEWYORK_MAIN));
   CalculateTDI();

   //--- M15 bar
   datetime m15_t[];
   ArraySetAsSeries(m15_t, true);
   if(CopyTime(g_symbol, PERIOD_M15, 0, 1, m15_t) >= 1 && m15_t[0] != g_last_m15_bar)
   {
      g_last_m15_bar = m15_t[0];
      UpdateMinorLiquidity();
      DetectFVGs(PERIOD_M15, g_fvg_m15, g_fvg_m15_count);
      DetectOrderBlocks(PERIOD_M15);
   }

   //--- H1 bar
   datetime h1_t[];
   ArraySetAsSeries(h1_t, true);
   if(CopyTime(g_symbol, PERIOD_H1, 0, 1, h1_t) >= 1 && h1_t[0] != g_last_h1_bar)
   {
      g_last_h1_bar = h1_t[0];
      UpdateMediumLiquidity();
      DetectFVGs(PERIOD_H1, g_fvg_h1, g_fvg_h1_count);
   }

   //--- H4 bar
   datetime h4_t[];
   ArraySetAsSeries(h4_t, true);
   if(CopyTime(g_symbol, PERIOD_H4, 0, 1, h4_t) >= 1 && h4_t[0] != g_last_h4_bar)
   {
      g_last_h4_bar = h4_t[0];
      DetectFVGs(PERIOD_H4, g_fvg_h4, g_fvg_h4_count);
   }

   //--- D1 bar
   datetime d1_t[];
   ArraySetAsSeries(d1_t, true);
   if(CopyTime(g_symbol, PERIOD_D1, 0, 1, d1_t) >= 1 && d1_t[0] != g_last_d1_bar)
   {
      g_last_d1_bar = d1_t[0];
      UpdateMajorLiquidity();
      g_current_bias = DetermineHTFBias();
   }

   g_is_dst = IsNewYorkDST(TimeGMT());

   //--- Signal evaluation
   if(IsInTradingWindow())
   {
      string buy_det = "", sell_det = "";
      int buy_sc  = CalculateConfluenceScore(TRADE_BUY, buy_det);
      int sell_sc = CalculateConfluenceScore(TRADE_SELL, sell_det);

      CheckEarlyWarning(buy_sc, TRADE_BUY);
      CheckEarlyWarning(sell_sc, TRADE_SELL);

      if(buy_sc >= InpMinConfluences && buy_sc > sell_sc)
      {
         PrintFormat("[SIG] BUY %d: %s", buy_sc, buy_det);
         ExecuteTrade(TRADE_BUY, buy_sc, buy_det);
      }
      else if(sell_sc >= InpMinConfluences && sell_sc > buy_sc)
      {
         PrintFormat("[SIG] SELL %d: %s", sell_sc, sell_det);
         ExecuteTrade(TRADE_SELL, sell_sc, sell_det);
      }
   }

   ManageOpenPositions();
   CheckSessionEndRules();
   UpdateVisualization();
}
//+------------------------------------------------------------------+
