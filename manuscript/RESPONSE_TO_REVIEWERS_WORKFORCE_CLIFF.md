# Response to Reviewers — Gynecologic Subspecialist Workforce

**Manuscript:** "National Headcount Balance Between Fellowship Completions and Clinical-Practice Departures in Gynecologic Oncology and Urogynecology, 2025-2029"

We thank the reviewer for a careful and constructive major-revision assessment. The estimand handling, the both-pathway urogynecology construction, and the stock-flow framing were all strengthened in direct response. Below we address each numbered point. Status tags: **[Done]** change made in this revision; **[In progress]** analysis underway; **[Pending — external]** blocked on a resource outside our control. Quoted figures are regenerated from the pinned single source of truth (`workforce_projections_consolidated.csv`); the primary completion-to-departure ratios are now reported to one decimal place (Gynecologic Oncology 7.1, urogynecology 5.6), with minimally invasive gynecologic surgery treated as an exploratory cohort throughout.

---

### 1. The primary outcome is not yet individually validated  [In progress + Pending — external]
We agree that physician-level validation is the central requirement. In this revision we (a) report the independent state-licensure concordance check (negative predictive value 0.98; 11% vs 3% flagged; kappa 0.06) as an external, non-corroborating benchmark, and (b) state explicitly that automated corroboration cannot validate an anchor-defined endpoint (a tautology). The prespecified two-reviewer chart adjudication sample and instrument are complete, but the human review is not; we therefore continue to frame the endpoint as a **provisional administrative model**, not a validated departure measurement. We are building the probabilistic misclassification-correction machinery so hazards, tables, figures, and intervals can be re-derived immediately when the adjudicated labels are available. **This item requires two clinician reviewers and cannot be closed by analysis alone.**

### 2. Death ascertainment  [Done (sensitivity) + Pending — external (confirmed deaths)]
The phrase "removes zero deceased physicians" has been removed. We added a prespecified **age- and sex-specific expected-mortality sensitivity** (SSA Period Life Table, 2020; Appendix Table S25): expected annual deaths are layered onto the departure numerator. Because general-population mortality overstates mortality among practicing physicians, attributing every expected death to a missed departure is a conservative upper bound; even so, both cohorts remain above one-for-one (Gynecologic Oncology 4.3, urogynecology 3.3 under the all-missed bound; 5.3 and 4.2 if half are missed). Board-confirmed death removal is blocked because our obituary-confirmation pipeline is stalled at a Google Custom Search API authorization error; the age-specific mortality sensitivity is the reviewer's stated "at minimum" analysis.

### 3. Inconsistent active-stock vs departure-event definitions  [Done]
We completed the prespecified **consistent-definition baseline sensitivity** (Appendix Table S26): the 2025 active stock is regenerated under the SAME non-Open-Payments anchored rule used for departures. The anchored stock is modestly larger (Gynecologic Oncology 1,052 to 1,099; urogynecology 1,295 to 1,328, because the stricter anchor classifies fewer physicians as departed) and the ratios remain well above one-for-one (6.7 and 5.4). Pairing a broad cohorting baseline with an anchored departure definition therefore does not materially bias the stock-flow balance.

### 4. Pooled hazard may conceal specialty differences  [Done]
We added a **hierarchical partial-pooling discrete-time hazard** (a shared age-band shape with a specialty deviation, fit by penalized maximum likelihood with a weakly-informative prior on the between-specialty variance; the frequentist analog of Bayesian partial pooling, used because the Stan toolchain was unavailable) as a primary sensitivity (Appendix Table S28). The partial-pooled completion-to-departure ratio lies between the unpooled and pooled estimates for each cohort (Gynecologic Oncology 7.6, between 7.8 unpooled and 7.1 pooled; urogynecology 5.1, between 4.8 and 5.6), and all three methods — with their intervals — remain above one-for-one replacement (partial-pooled 95% lower bounds 4.5 and 3.6). ABU-hazard uncertainty (0.5x-2x) folded into the urogynecology envelope leaves it above replacement (4.3 to 5.7). Age-band event and person-year counts are reported alongside.

### 5. The 2025 baseline is estimated, not observed  [Done]
The baseline is labeled "estimated 2025 active baseline" throughout, and we added a decomposition by administrative-support recency (Appendix Table S30): about 89% (Gynecologic Oncology) and 88% (ABOG-pathway urogynecology) of the Part B-observable stock had Medicare Part B activity in the latest administrative year (2023), and only 20 and 19 physicians respectively rest on a three-year-or-longer carry-forward. The baseline-lag sensitivity (removing those long-lag physicians as the most adverse baseline-classification error) does not weaken the conclusion — the ratio is unchanged to slightly higher (7.3 and 5.7).

### 6. Uncertainty intervals too narrow  [Done]
The Monte Carlo interval has been removed from the abstract and is labeled a **conditional, partial parameter-uncertainty interval** in the body (it omits baseline, roster, model-form, death, conversion, and classification uncertainty). Scenario ranges are now the principal uncertainty presentation. Ratios are rounded to one decimal (7.1, 5.6).

### 7. Transition-adjusted projection should be primary  [Done]
Figure 1 now shows the status-quo trajectory with the **immediate-entry projection as the structural upper line (with a 95% partial parameter band) and the transition-adjusted 2029 counts as the paired lower endpoints** (1,259 and 1,428). The immediate-entry assumption is labeled a structural upper estimate.

### 8. Four-year graduate average ignores program growth  [Done]
We added distinct graduate-supply scenarios (Appendix Table S29): flat recent mean, cohort accounting (the most recent completing class), contraction (the recent annual low), and a cautious extrapolated trend, alongside the conservative-70% and optimistic-NRMP references. Each is passed through the same dynamic model. Both cohorts remain above replacement under every scenario (Gynecologic Oncology 6.6 under contraction to 7.5 under cohort accounting; urogynecology 5.4 to 5.8).

### 9. Inactivity-threshold sensitivity  [Done]
We added a dedicated sensitivity varying the **required inactivity duration (2 vs 3 vs 4 years)** — distinct from the calendar-window sensitivity — by re-deriving departure events directly from Medicare Part B activity at each threshold (Appendix Table S27). Both cohorts remain above replacement at every threshold; because this pure Part B definition is more aggressive than the multi-source primary, its ratios are lower than the primary (Gynecologic Oncology 4.4 at a 2-3 year threshold rising to 7.6 at 4 years; urogynecology 3.7 rising to 5.7). The 2- and 3-year thresholds are indistinguishable within the fully-observable 2016-2021 window, and a stricter 4-year requirement raises the ratio.

### 10. Holdout / specialty-specific temporal calibration  [Done]
The temporal back-test reports an out-of-sample mode split by cohort and base/target year (within ~1%). We added an **age-band axis** (Appendix Table S31): stratifying the 2016-cohort survival to 2021 by age band, the model calibrates to within about 3% in every well-populated band; larger percentage errors are confined to the sparse oldest bands (four to nine physicians per cohort). We note explicitly that the historical back-test cohort is the ABOG-pathway population; ABU net-new urogynecologists have no pre-2024 roster and are not in it.

### 11. Policy conclusion too forward  [Done]
The conclusion now reads: "Under the modeled assumptions, we found no evidence of a near-term national aggregate headcount replacement gap that would, by itself, require expanding fellowship positions over 2025-2029; this does not imply the workforce meets population demand." Prescriptive expansion language has been removed.

### 12. Qualify "replacement" throughout  [Done]
"Replacement" is defined once as **headcount flow balance** and used only in that sense. Bare sufficiency phrasings were revised ("headcount sufficiency" to "adequate headcount"; "keeps pace" to "balances"; "replacement fails" to "the headcount balance would fall below one-for-one"). Where "above/below replacement" appears in sensitivity descriptions it is shorthand for the defined one-for-one headcount flow balance.

### 13. Tipping-point language is not validation  [Done]
The tipping point is now framed as **one axis of a broader uncertainty analysis, not a substitute for validating the endpoint**, with an explicit statement that several moderate biases (missed deaths, missed non-Medicare departures, lower conversion, reduced entrant effort, baseline over-counting, specialty hazard differences) act in the same direction and could compound, and should be read alongside the structural sensitivity envelope.

### 14. Length and scope  [In progress + clarification]
**Clarification:** two items the review lists to trim — the detailed **operative-workforce validity analysis** and **ABU-hazard scaling** — are the subject of a *separate* accessibility/E2SFCA manuscript, not this paper; the density the reviewer perceived may reflect reading across both. In this paper the operative-capacity discussion is retained as a single brief paragraph explaining why headcount cannot be equated with surgical capacity. We are trimming the main text toward the requested ~one-third reduction (consolidating the repeated caveats into one limitations block) and keeping minimally invasive gynecologic surgery material supplemental except for the one sentence explaining its exclusion.

---

### Editorial corrections
- **Table cross-reference:** the full-window sensitivity now cites Appendix S12 (previously mis-cited Table 3, the age table). [Done]
- **Cessation definitions:** the two-year Open Payments threshold (detection-only, supporting signal) and the uniform three-year qualifying-signal rule (which defines the primary endpoint) are now explicitly reconciled. [Done]
- **R version / software citation:** analyses used R 4.4.2, matching the citation. [Done]
- **Terminology / title:** the title now leads with "National Headcount Balance ... Clinical-Practice Departures" so it cannot be read as a demand or operative-capacity study. [Done]
- **Figure 1:** now plots the transition-adjusted primary trajectory with immediate-entry as the upper structural line. [Done]
- **ACGME citation:** the ACGME Data Resource Book (Table D.5, AY2020-21 through 2023-24) used for the graduate counts is now formally cited. [Done]

We believe the completed items substantially strengthen the manuscript and that the in-progress analyses will close the remaining prespecified gaps. We welcome further guidance on prioritization.
