---
> [!CAUTION]
> **LEGACY DOCUMENTATION**
> This file is part of the project archive. Technical specifications (e.g., step counts, year ranges, or script names) may be outdated.
> - **Current Study Period**: 2013–2023
> - **Current Pipeline Scale**: 83 steps
> - **Active Reference**: See [MASTER_DOCUMENTATION_INDEX.md](../MASTER_DOCUMENTATION_INDEX.md)
---

# HERE API departureTime Parameter Implementation

**Date:** 2025-11-01 21:45 MST
**Status:** ✅ IMPLEMENTED AND RUNNING
**User Decision:** Include departureTime for historical traffic data

---

## Executive Summary

Per user request, we have implemented the `departureTime` parameter for HERE Maps API isochrone generation. All 2013 isochrones are now being generated with:

**Departure Time:** October 18, 2013 at 10:00 AM Mountain Daylight Time (MDT)
**ISO 8601 Format:** `2013-10-18T10:00:00-06:00`

This represents the **third Friday in October 2013** as specified by the user.

---

## Changes Made

### 1. Updated HERE API Function

**File:** `R/here_api_isochrone_functions.R`

**Added Parameter:**
```r
generate_here_isochrone_single_physician <- function(
  npi,
  latitude,
  longitude,
  time_range,
  rate_limit_ms = 200,
  departure_time = NULL  # NEW PARAMETER
)
```

**Updated API Call:**
```r
params <- list(
  transportMode = "car",
  origin = sprintf("%.6f,%.6f", latitude, longitude),
  "range[type]" = "time",
  "range[values]" = time_range * 60,
  apikey = api_key
)

# Add departure time if provided
if (!is.null(departure_time)) {
  params$departureTime <- departure_time
}
```

### 2. Updated 2013 Generation Script

**File:** `generate_2013_isochrones.R`

**Added Departure Time Declaration:**
```r
# Set departure time: October 18, 2013 at 10:00 AM MDT (third Friday in October)
departure_time_2013 <- "2013-10-18T10:00:00-06:00"
cat(sprintf("Departure time: %s (Oct 18, 2013 10:00 AM MDT)\n\n", departure_time_2013))
```

**Updated API Calls:**
```r
iso <- generate_here_isochrone_single_physician(
  npi = rep$npi,
  latitude = rep$lat,
  longitude = rep$long,
  time_range = dt,
  rate_limit_ms = 250,
  departure_time = departure_time_2013  # PASSES DATE TO API
)
```

---

## Current Generation Status

**Process ID:** 52937
**Log File:** `manuscript/logs/2013_generation_WITH_DATE.log`
**Started:** 2025-11-01 21:43 MST

**Progress:** Currently processing rep 4/347
**Output Files:**
- `manuscript/data/isochrones_2013.rds` - Real isochrones
- `manuscript/data/isochrone_failures_2013.csv` - Rejected buffers and failures
- `manuscript/logs/isochrone_generation_2013.log` - Detailed generation log

**Verification from Log:**
```
Departure time: 2013-10-18T10:00:00-06:00 (Oct 18, 2013 10:00 AM MDT)

Year: 2013
Representatives: 347
Expected attempts: 1388 (4 drive times per rep)
Expected success (~68.8%): ~955 real isochrones
```

**Sample Results:**
- NPI 1003002627: 30 min ✓ (1013 vertices) - REAL isochrone
- NPI 1003044553: All 4 drive times successful (440v, 367v, 397v, 574v)
- NPI 1003801135: Partial (2 buffers rejected with 121v, 1 real accepted)

---

## Traffic Data Methodology

### What departureTime Does

When you specify `departureTime` to HERE API, it:
1. **Considers traffic patterns** for that date and time
2. **Adjusts travel speeds** based on expected congestion
3. **Modifies isochrone shapes** to reflect real-world delays

### For October 18, 2013 at 10:00 AM

**Day:** Friday (workday)
**Time:** 10:00 AM (mid-morning, post rush hour)
**Implications:**
- Urban areas: Moderate traffic conditions
- Rural areas: Minimal traffic impact
- Highways: Normal flow speeds

This provides a **representative snapshot** of accessibility during typical working hours.

---

## Next Steps for Other Years

### For Each Year 2014-2022

**Use the same approach:**
1. Identify third Friday in October for that year
2. Use 10:00 AM MDT as departure time
3. Convert to ISO 8601 format

**Example Dates:**
```r
departure_time_2014 <- "2014-10-17T10:00:00-06:00"  # Oct 17, 2014
departure_time_2015 <- "2015-10-16T10:00:00-06:00"  # Oct 16, 2015
departure_time_2016 <- "2016-10-21T10:00:00-06:00"  # Oct 21, 2016
# ... etc
```

**Consistency:**
- All years use third Friday in October
- All use 10:00 AM Mountain Time
- All use same traffic conditions (mid-morning Friday)

---

## Files Modified

1. **R/here_api_isochrone_functions.R**
   - Added `departure_time` parameter
   - Passes parameter to HERE API when provided

2. **generate_2013_isochrones.R**
   - Declares `departure_time_2013` variable
   - Passes to all API calls
   - Logs departure time in output

---

## Validation Criteria (Unchanged)

**Strict Quality Control:**
- ✅ ACCEPT: Vertex count ≥ 200 (real drive-time isochrone)
- ❌ REJECT: Vertex count < 200 (circular buffer)
- ❌ REJECT: NULL results
- ❌ REJECT: Geometry validation failures

**All rejections documented in failures CSV.**

---

## Expected Outcomes

Based on pilot testing:
- **~68.8% success rate** for real isochrones
- **~31.2% buffers/failures** (documented)
- **~955 real isochrones** expected from 347 representatives × 4 drive times

With `departureTime`:
- Isochrones may be **smaller** in congested urban areas
- Isochrones may be **same size** in rural areas with minimal traffic
- Drive-time accuracy should **improve** for urban locations

---

## Monitoring Progress

**Check current status:**
```bash
# View live progress
tail -f manuscript/logs/2013_generation_WITH_DATE.log

# Check file sizes
ls -lh manuscript/data/isochrones_2013.rds
wc -l manuscript/data/isochrone_failures_2013.csv

# View detailed log
tail -50 manuscript/logs/isochrone_generation_2013.log
```

**Checkpoints:** Every 25 representatives (reps 25, 50, 75, etc.)

---

## Manuscript Methods Text

**Recommended wording:**

```
Isochrone Generation with Historical Traffic Data:

We generated drive-time isochrones (30, 60, 120, and 180 minutes) using
the HERE Maps Isoline API v8 with departure times set to the third Friday
in October at 10:00 AM Mountain Time for each study year (2013-2022).
This approach incorporates historical traffic patterns for mid-morning
Friday conditions, providing a consistent temporal reference across all
years while reflecting real-world travel times including congestion.

To ensure data quality, we implemented strict validation criteria:
isochrones with fewer than 200 vertices (indicating circular buffer
fallbacks rather than road-network geometries) were rejected and
documented as missing data. Of 3,060 attempted isochrone generations
(765 representatives × 4 drive times), we expect approximately 68.8%
to pass validation based on pilot testing.
```

---

## Technical Notes

### ISO 8601 Format

**Required by HERE API v8:**
- Format: `YYYY-MM-DDTHH:MM:SS±HH:MM`
- Example: `2013-10-18T10:00:00-06:00`
- Components:
  - Date: 2013-10-18
  - Time: 10:00:00 (24-hour format)
  - Timezone: -06:00 (MDT)

### Mountain Time Zones

- **MDT (Mountain Daylight Time):** March-November, UTC-6
- **MST (Mountain Standard Time):** November-March, UTC-7
- October 18, 2013 is during MDT (-06:00)

---

## Comparison: With vs Without departureTime

### Without departureTime (Previous Run)
- Used free-flow traffic speeds
- Isochrones based on road capacity
- No congestion effects
- Larger coverage areas

### With departureTime (Current Run)
- Uses historical traffic patterns
- Isochrones reflect real travel times
- Includes congestion effects
- More realistic coverage areas

**Both approaches are scientifically valid,** but user preference is to include historical traffic data.

---

**Created:** 2025-11-01 21:45 MST
**Process ID:** 52937
**Status:** ✅ Running with departureTime
**Estimated Completion:** ~2 hours (348 reps × 4 drive times × 250ms rate limit)
