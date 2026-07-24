#!/usr/bin/env python3
"""Scrape the American Board of Urology (ABU) public physician-verification portal.

Source:  https://portal.abu.org/static/verification/index.html
API:     GET https://portal.abu.org/api/public_records?page=N
         (a Vue2/axios SPA; the page param drives ~120-record alphabetical pages;
          limit/offset/per_page are ignored. Empty name => full registry.)

Purpose: capture ABU-certified urologists AND their Subspecialty, so the
urology-pathway "Female Pelvic Medicine / Urogynecology" (FPMRS) physicians that
the OB/GYN (ABOG-only) cohort structurally excludes can be identified for a
workforce-access sensitivity analysis. See the ABOG-only FPMRS scope note.

Respectful by design: identifies itself + a research contact, one request per
page, 1.2s spacing, retry-with-backoff, stops at the first empty page.

Record fields: Name, City, State, CertificationType, CertificationYear,
Subspecialty, ExpirationDisplay, ExpirationDate, ParticipationInCUCOrLL.
"""
import json, time, sys, csv, os, datetime, urllib.parse, urllib.request

BASE = "https://portal.abu.org/api/public_records"
UA = "Mozilla/5.0 (academic OB-GYN workforce access study; contact tyler.muffly@dhha.org)"
OUTDIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "abu_urology")
DELAY = 1.2          # seconds between page requests
MAX_PAGES = 400      # hard safety bound (registry is ~110 pages)
UROGYN_MATCH = "urogyn"  # case-insensitive substring flag for the female-urology subspecialty

def fetch_page(page, retries=4):
    url = f"{BASE}?{urllib.parse.urlencode({'page': page})}"
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries:
                raise
            back = 2 ** attempt
            print(f"  page {page} attempt {attempt} failed ({e}); retry in {back}s", flush=True)
            time.sleep(back)

def key(rec):
    return (rec.get("Name"), rec.get("City"), rec.get("State"),
            rec.get("CertificationType"), rec.get("CertificationYear"))

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    seen, records = set(), []
    empty_streak = 0
    for page in range(1, MAX_PAGES + 1):
        data = fetch_page(page)
        if not isinstance(data, list) or len(data) == 0:
            empty_streak += 1
            print(f"  page {page}: empty ({empty_streak})", flush=True)
            if empty_streak >= 2:
                break
            time.sleep(DELAY); continue
        empty_streak = 0
        new = 0
        for rec in data:
            k = key(rec)
            if k not in seen:
                seen.add(k); records.append(rec); new += 1
        print(f"  page {page}: {len(data)} rows, +{new} new (total {len(records)})", flush=True)
        time.sleep(DELAY)

    stamp = datetime.date.today().isoformat()
    # ---- raw JSON (all unique records) ----
    raw_path = os.path.join(OUTDIR, f"abu_public_records_{stamp}.json")
    with open(raw_path, "w") as f:
        json.dump(records, f, indent=1, default=str)

    # ---- full CSV ----
    cols = ["Name", "City", "State", "CertificationType", "Subspecialty",
            "CertificationYear", "ExpirationDisplay", "ExpirationDate",
            "ParticipationInCUCOrLL"]
    def flat(rec):
        row = {c: rec.get(c) for c in cols}
        ed = rec.get("ExpirationDate")
        row["ExpirationDate"] = ed.get("date") if isinstance(ed, dict) else ed
        return row
    csv_path = os.path.join(OUTDIR, f"abu_public_records_{stamp}.csv")
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
        for rec in records: w.writerow(flat(rec))

    # ---- female-urology (urogynecology) subset ----
    urogyn = [r for r in records if UROGYN_MATCH in str(r.get("Subspecialty", "")).lower()]
    ug_path = os.path.join(OUTDIR, f"abu_urogynecology_{stamp}.csv")
    with open(ug_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
        for rec in urogyn: w.writerow(flat(rec))

    # ---- breakdowns + receipt ----
    from collections import Counter
    subspec = Counter(str(r.get("Subspecialty")) for r in records)
    certtype = Counter(str(r.get("CertificationType")) for r in records)
    receipt = {
        "source_url": "https://portal.abu.org/static/verification/index.html",
        "api": f"{BASE}?page=N",
        "scraped_utc": datetime.datetime.utcnow().isoformat() + "Z",
        "method": "paginate ?page=1..N (empty name = full registry), dedupe by (Name,City,State,CertificationType,CertificationYear), stop on empty page",
        "total_unique_records": len(records),
        "urogynecology_count": len(urogyn),
        "subspecialty_breakdown": dict(subspec),
        "certification_type_breakdown": dict(certtype),
        "outputs": {"raw_json": raw_path, "full_csv": csv_path, "urogyn_csv": ug_path},
    }
    with open(os.path.join(OUTDIR, f"abu_scrape_receipt_{stamp}.json"), "w") as f:
        json.dump(receipt, f, indent=2)

    print("\n=== DONE ===")
    print(f"  total unique records : {len(records)}")
    print(f"  urogynecology (FPMRS): {len(urogyn)}")
    print(f"  subspecialties       : {dict(subspec)}")
    print(f"  cert types           : {dict(certtype)}")
    print(f"  outputs in           : {OUTDIR}")

if __name__ == "__main__":
    main()
