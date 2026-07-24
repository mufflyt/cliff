# URPS Effective-Adequacy Explorer -------------------------------------------
# Interactive Module A: vary retirement age, clinical FTE, the urology/OB-GYN
# entrant split, entrant volume, attrition, and demand growth, and watch the
# EFFECTIVE (age-productivity-weighted) adequacy of the urogynecology workforce
# vs the aging (women 65+) population, 2025-2050.
#
# Effective supply weights each projected physician by a within-physician
# age-productivity curve (Medicare urogynecologic work-dollars vs age, 2013-24)
# and by clinical FTE. Adequacy = supply growth / demand growth (2025 = 1.00);
# < 1.00 means capacity is falling behind the aging population.
# Exploratory capacity model, NOT the frozen headline projection.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(data.table); library(plotly)
})

# Canonical projection model — single source of truth (Guard 57). app.R and the
# guard test suite both source this exact file, so they exercise identical logic.
.find_model <- function(f) { for (r in c(".", "cliff/shiny_urps_adequacy")) if (file.exists(file.path(r, f))) return(file.path(r, f)); f }
source(.find_model("model.R"))

TEAL<-"#1b7f79"; GREY<-"#8a97a8"; ORANGE<-"#c77d1a"; RED<-"#d1495b"

DRAFT_CSS <- "
html,body{overflow-x:hidden;}
.draft-badge{background:#b3261e;color:#fff;font-size:11px;font-weight:700;letter-spacing:.09em;
  padding:3px 10px;border-radius:4px;margin-left:14px;vertical-align:middle;white-space:nowrap;}
.wm{position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:9998;
  background-image:url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='900' height='520'><text x='450' y='300' text-anchor='middle' transform='rotate(-24 450 260)' fill='%23b3261e' fill-opacity='0.028' font-family='Helvetica,Arial,sans-serif' font-size='58' font-weight='700'>DRAFT · CONFIDENTIAL</text></svg>\");
  background-repeat:no-repeat;background-position:center;}
.readout-body{overflow-wrap:break-word;word-break:normal;}
.scen-badge{font-size:11px;font-weight:700;letter-spacing:.04em;padding:3px 10px;border-radius:4px;color:#fff;}
"

## ── plausibility envelope (reference / outside-observed / extreme) per lever ──
## Reference band = empirically supported; between ref and ext = outside observed;
## beyond ext = extreme stress test. A scenario's badge = worst active lever.
ENV <- list(
  retire     = list(ref=c(63,70),   ext=c(60,73),   min=55,  max=75),
  entrants   = list(ref=c(52,76),   ext=c(40,95),   min=20,  max=120),
  fte_new    = list(ref=c(80,95),   ext=c(65,100),  min=50,  max=100),
  ob_share   = list(ref=c(68,86),   ext=c(50,95),   min=0,   max=100),
  uro_fte    = list(ref=c(55,85),   ext=c(40,95),   min=0,   max=100),
  haz_mult   = list(ref=c(0.8,1.3), ext=c(0.5,1.6), min=0.5, max=2.0),
  demand_mult= list(ref=c(0.9,1.2), ext=c(0.7,1.5), min=0.5, max=2.0))
classify1 <- function(v, e) if (v>=e$ref[1] && v<=e$ref[2]) 0L else if (v>=e$ext[1] && v<=e$ext[2]) 1L else 2L
band_css <- function() paste(vapply(names(ENV), function(k){ e<-ENV[[k]]
  x1<-(e$ref[1]-e$min)/(e$max-e$min)*100; x2<-(e$ref[2]-e$min)/(e$max-e$min)*100
  sprintf(".band-%s .irs-line{background:linear-gradient(90deg,#e3e3e3 0 %.1f%%,rgba(46,139,87,.30) %.1f%% %.1f%%,#e3e3e3 %.1f%% 100%%)!important;}",
          k, x1, x1, x2, x2) }, character(1)), collapse="\n")
bslider <- function(id, ...) div(class=paste0("band-", id), sliderInput(id, ...))   # green ref band on track

## ── scenario presets (each applies on top of Reference) ──────────────────────
PRESETS <- list(
  Reference         = list(retire=65, entrants=64, fte_new=90, ob_share=round(100*OB_BASE_SHARE), uro_fte=70, haz_mult=1.0, demand_mult=1.0),
  `Retire early`    = list(retire=63),
  `Retire late`     = list(retire=67),
  `Lower entrants`  = list(entrants=48),
  `Higher entrants` = list(entrants=80),
  `Stress test`     = list(retire=63, entrants=48, fte_new=80, haz_mult=1.3, demand_mult=1.2))

## ── data sources & references (variable, source/derivation, url, code file) ──
## Derived quantities cite the producing code rather than an external URL.
REFS <- list(
  list("Urogynecologists, OB/GYN pathway",
       "American Board of Obstetrics &amp; Gynecology (ABOG) board certification.",
       "https://www.abog.org", ""),
  list("Urogynecologists, urology pathway",
       "American Board of Urology (ABU) public verification portal; de-duplicated against the ABOG side.",
       "https://www.abu.org", ""),
  list("Baseline active workforce (1,339)",
       "This study: active ABOG + ABU urogynecologists (in_model_baseline == TRUE), restricted to physicians active in Medicare / clinical practice. The individual ages are assembled into the model's starting workforce vector (URPS_AGES).",
       "", "R/workforce_cliff_engine.R → data/urps_model_data.R (URPS_AGES)"),
  list("Age-productivity curve (work by age)",
       "Fixed-effects model of Medicare urogynecologic work-dollars vs physician age (2013-2024; peak ~44) fit to CMS Medicare Physician &amp; Other Practitioners, by Provider and Service.",
       "https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners-by-provider-and-service",
       "scripts/urps_module_a_age_productivity_2026-07-23.R → data/urps_module_a_age_productivity_2026-07-23.csv"),
  list("Departure / retirement hazard by age band",
       "This study: age-band departure hazard = events ÷ person-years from a URPS-specific hierarchical partial-pooled survival model. A departure is any exit from clinical practice — Medicare billing/prescribing stop, NPPES removal, board-certification lapse, or death.",
       "", "scripts/hierarchical_hazard_partial_pooling.R → R/workforce_cliff_engine.R → data/urps_model_data.R (BAND_EV / BAND_PY / HAZ_WINDOWS)"),
  list("Aging-women demand driver (this app): women 65+, 2025-2050",
       "U.S. Census Bureau, 2023 National Population Projections, main series (np2023_d1_mid; low/hi drive the uncertainty band). Supersedes the 2017-vintage projections in P25-1144 (46.9M women 65+ in 2050); the 2023 revision is lower (44.8M) for COVID mortality and reduced immigration/fertility.",
       "https://www.census.gov/programs-surveys/popproj.html",
       "scripts/urps_supply_demand_national_2026-07-23.R → data/urps_supply_demand_national_2026-07-23.csv (women_65plus, w65_lo/hi)"),
  list("Geographic denominator (Module D map): women 65+ by county",
       "U.S. Census Bureau, ACS 5-year, Table B01001 (Sex by Age) — cross-sectional county counts for the access map, not the temporal driver above.",
       "https://data.census.gov/table/ACSDT5Y2023.B01001", ""),
  list("Pelvic floor disorder prevalence (context)",
       "Nygaard et al., JAMA 2008;300(11):1311-16; Wu et al., Obstet Gynecol 2009.",
       "https://jamanetwork.com/journals/jama/fullarticle/182579", ""),
  list("Procedure-based demand (Modules B/C)",
       "CMS Physician/Supplier Procedure Summary (PSPS) &amp; Medicare Part B, decomposed by modifier and calibrated for suppression.",
       "https://www.cms.gov/data-research/statistics-trends-reports/medicare-provider-utilization-payment-data",
       "scripts/urps_module_bc_FROZEN_2026-07-23.R"),
  list("Procedure codes (HCPCS/CPT)",
       "57288 sling; 57282 apical suspension (colpopexy); 51728 complex cystometrogram; 52287 bladder chemodenervation.",
       "https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system", ""),
  list("FTE definition, retirement age, scenario names",
       "AAMC / GlobalData 2024, &ldquo;The Complexities of Physician Supply and Demand: Projections From 2021 to 2036.&rdquo;",
       "https://www.aamc.org/media/75236/download",
       "cliff/URPS_SUPPLY_DEMAND_METHODS_REFERENCES.md")
)
refs_table <- function() {
  cell <- function(r) {
    parts <- character(0)
    if (nzchar(r[[3]])) parts <- c(parts, sprintf("<a href='%s' target='_blank' rel='noopener'>%s</a>", r[[3]], r[[3]]))
    if (nzchar(r[[4]])) parts <- c(parts, sprintf("<span style='color:#555'>Code: <code style='font-size:11px'>%s</code></span>", r[[4]]))
    if (!length(parts)) parts <- "<span style='color:#999'>derived (this study)</span>"
    paste(parts, collapse="<br>")
  }
  rows <- vapply(REFS, function(r) sprintf(
    "<tr><td style='padding:6px 10px;font-weight:600;vertical-align:top'>%s</td><td style='padding:6px 10px;vertical-align:top'>%s</td><td style='padding:6px 10px;vertical-align:top;font-size:12px;word-break:break-word'>%s</td></tr>",
    r[[1]], r[[2]], cell(r)), character(1))
  HTML(paste0("<table style='width:100%;border-collapse:collapse;font-size:13px;table-layout:fixed'>",
    "<colgroup><col style='width:26%'><col style='width:44%'><col style='width:30%'></colgroup>",
    "<thead><tr style='border-bottom:2px solid #ddd'><th style='text-align:left;padding:6px 10px'>Variable</th><th style='text-align:left;padding:6px 10px'>Source &amp; derivation</th><th style='text-align:left;padding:6px 10px'>Link / code file</th></tr></thead><tbody>",
    paste(rows, collapse=""), "</tbody></table>"))
}

## ── UI ───────────────────────────────────────────────────────────────────────
slab  <- function(...) tags$span(style="font-size:13px", ...)
shelp <- function(txt) tags$small(class="text-muted d-block", style="margin-top:-6px;margin-bottom:8px;line-height:1.3", txt)
ui <- function(request) page_sidebar(
  title = tagList("Urogynecology Effective-Adequacy Explorer",
                  tags$span("DRAFT · CONFIDENTIAL", class="draft-badge")),
  theme = bs_theme(version=5, primary=TEAL, base_font=font_google("Inter", local=FALSE)),
  tags$head(tags$style(HTML(paste0(DRAFT_CSS, "\n", band_css())))),
  tags$div(class="wm"),
  sidebar = sidebar(width=360, title="Scenario levers",
    tags$small(class="text-muted d-block", "Presets"),
    div(class="d-flex flex-wrap gap-1 mb-1",
        actionButton("p_ref","Reference",class="btn-outline-primary btn-sm"),
        actionButton("p_re","Retire early",class="btn-outline-secondary btn-sm"),
        actionButton("p_rl","Retire late",class="btn-outline-secondary btn-sm"),
        actionButton("p_le","Lower entrants",class="btn-outline-secondary btn-sm"),
        actionButton("p_he","Higher entrants",class="btn-outline-secondary btn-sm"),
        actionButton("p_st","Stress test",class="btn-outline-danger btn-sm")),
    div(class="d-flex gap-1 mb-2",
        actionButton("reset", "Reset", class="btn-outline-secondary btn-sm"),
        downloadButton("dl", "CSV", class="btn-outline-secondary btn-sm"),
        bookmarkButton(label="Copy link", class="btn-outline-secondary btn-sm")),
    tags$small(class="text-muted d-block mb-2", style="line-height:1.3",
      "Green band on each slider = empirically supported (reference) range."),
    accordion(multiple=TRUE, open=c("Reference assumptions"),
      accordion_panel("Reference assumptions",
        bslider("retire", slab("Retirement age, years (physicians exit at this age)"), 55, 75, 65, step=1),
        bslider("entrants", slab("New urogynecologists entering per year"), 20, 120, 64, step=2),
        shelp("The TOTAL yearly inflow. The pathway split below only divides this total between training routes — it does not change how many enter."),
        bslider("fte_new", slab("New-physician clinical time, full-time equivalent (FTE) %"),
                    50, 100, 90, step=5, post="%"),
        shelp("100% = full-time clinical practice; lower reflects part-time / non-clinical time among NEW urogynecologists. Age-related decline in output is captured separately, by the age-productivity curve, so this slider is the entry-cohort baseline only."),
        bslider("ob_share", slab("New urogynecologist training pathway"),
                    0, 100, round(100*OB_BASE_SHARE), step=5, post="% OB/GYN"),
        shelp("0% = all urology-trained · 100% = all OB/GYN-trained. Urology-trained physicians are then counted at the urogyn-time fraction under Practice allocation.")
      ),
      accordion_panel("Practice allocation",
        bslider("uro_fte", slab("Urologists: clinical time in urogynecology (rest is general urology) %"),
                    0, 100, 70, step=5, post="%"),
        shelp("Applies only to urology-trained urogynecologists. 70% = 70% of clinical time in urogynecology, 30% general urology. OB/GYN-trained are counted at 100%."),
        checkboxInput("weight_on", slab("Adjust for age-productivity (age-adjusted effective FTE)"), TRUE),
        shelp("On: capacity is weighted by an empirical age-productivity curve (older physicians produce less). Off: unweighted clinical FTE. Physician age is always headcount-weighted, regardless of this toggle.")
      ),
      accordion_panel("Advanced assumptions",
        bslider("haz_mult", slab("Pre-retirement departure rate (× observed)"), 0.5, 2.0, 1.0, step=0.1),
        shelp("Even before the retirement age, a steady fraction of physicians leaves each year (career change, disability, relocation, death). This multiplies that observed early-departure rate: 1.0 = as observed, 1.5 = 50% faster, 0.5 = half as fast. The retirement age is the single age everyone still practicing stops; this slider is the ongoing trickle of exits at every earlier age."),
        bslider("demand_mult", slab("Demand growth (× women-65+ population trend)"), 0.5, 2.0, 1.0, step=0.1),
        sliderInput("entry_age", slab("Physician entry age (years)"), 30, 45, 34, step=1),
        sliderInput("end_year", slab("Projection horizon (year)"), 2035, 2050, 2050, step=5, sep=""),
        selectInput("band_var", slab("Uncertainty band on the capacity-gap chart varies"),
          choices=c("Retirement timing (±2 yr)"="retire", "Annual entrants (±20)"="entrants",
                    "New-physician FTE (±10 pts)"="fte", "Demand growth (±20%)"="demand",
                    "Urology urogyn-time (±15 pts)"="uro"), selected="retire")
      )
    )
  ),
  div(class="mb-1", uiOutput("badge", inline=TRUE)),
  card(class="mb-2", fill=FALSE, card_body(htmlOutput("readout"), class="readout-body", fillable=FALSE)),
  layout_columns(fill=FALSE, col_widths=c(3,3,3,3),
    value_box(title=tagList("Effective supply in ", textOutput("yr1", inline=TRUE)),
              value=htmlOutput("kpi_eff"), theme="primary"),
    value_box(title=tagList("Capacity met in ", textOutput("yr2", inline=TRUE)), value=htmlOutput("kpi_adeq")),
    value_box("Tightest year", value=htmlOutput("kpi_trough")),
    value_box(title=tagList("Workforce age in ", textOutput("yr3", inline=TRUE)), value=htmlOutput("kpi_age"))
  ),
  card(fill=FALSE,
    card_header(tagList("Projected urogynecology capacity margin ",
      tags$small(class="text-muted", htmlOutput("gap_sub", inline=TRUE)))),
    plotlyOutput("p_shortfall", height="360px"),
    card_footer(class="text-muted", style="font-size:12px",
      "Capacity margin = effective supply FTEs − demand-equivalent effective FTEs. Above zero (green) = projected capacity above the 2025-normalized requirement; below zero (red) = short of it, the additional effective FTEs needed to hold 2025 realized utilization. Up = ahead, matching the adequacy chart. This measures capacity to maintain 2025 realized utilization, not prevalence-based clinical need or current unmet demand; no validated national urogynecology shortfall estimate exists.")),
  layout_columns(fill=FALSE, col_widths=c(6,6),
    card(fill=FALSE, card_header("Indexed growth in full-time-equivalent physicians (2025 = 100)"),
         plotlyOutput("p_growth", height="360px")),
    card(fill=FALSE, card_header("Adequacy ratio (supply growth ÷ demand growth)"),
         plotlyOutput("p_adeq", height="360px"))
  ),
  accordion(open=FALSE, multiple=TRUE,
    accordion_panel("About this model", icon=NULL, HTML(
      "<div style='font-size:13px;line-height:1.6'>An exploratory capacity model, <b>not</b> the frozen headline projection.
       Terminology follows the AAMC / GlobalData 2024 convention (&ldquo;The Complexities of Physician Supply and Demand&rdquo;):
       <i>Demand (Status Quo)</i> holds 2024/2025 realized utilization rates constant and applies projected demographic
       change; <i>Supply</i> is reported as full-time equivalents (FTE), the average weekly patient-care hours for the
       specialty, here weighted by an empirical age-productivity curve. The capacity-gap chart assumes effective supply
       and realized-utilization demand are <b>balanced in 2025</b> (a normalization, not a finding of current adequacy);
       positive values are the additional effective FTEs needed to hold 2025 utilization, not prevalence-based clinical
       need or an estimate of current unmet demand.</div>")),
    accordion_panel("Data sources & references", icon=NULL, htmlOutput("refs"))),
  tags$div(style="text-align:right;color:#aaa;font-size:11px;margin-top:6px",
           sprintf("Model version %s · Data through %s · Exploratory, not the frozen headline projection",
                   MODEL_VERSION, DATA_THROUGH),
           tags$div(style="font-family:monospace;font-size:10px;color:#c4c4c4", textOutput("fp", inline=TRUE)))
)

## ── server ───────────────────────────────────────────────────────────────────
server <- function(input, output, session) {
  cm  <- function(x) formatC(round(x), big.mark=",", format="d")           # 1462 -> "1,462"
  cms <- function(x) { s<-cm(abs(x)); if (x >= 0) paste0("+",s) else paste0("−",s) }  # signed
  GREEN <- "#2e8b57"

  observeEvent(input$reset, {
    updateSliderInput(session,"retire",value=65); updateSliderInput(session,"fte_new",value=90)
    updateSliderInput(session,"ob_share",value=round(100*OB_BASE_SHARE)); updateSliderInput(session,"uro_fte",value=70)
    updateSliderInput(session,"entrants",value=64); updateSliderInput(session,"haz_mult",value=1.0)
    updateSliderInput(session,"demand_mult",value=1.0); updateSliderInput(session,"entry_age",value=34)
    updateCheckboxInput(session,"weight_on",value=TRUE); updateSliderInput(session,"end_year",value=2050)
    updateSelectInput(session,"band_var",selected="retire")
  })

  # scenario presets (each applied on top of Reference)
  apply_preset <- function(p) { v <- modifyList(PRESETS$Reference, p)
    updateSliderInput(session,"retire",value=v$retire);   updateSliderInput(session,"entrants",value=v$entrants)
    updateSliderInput(session,"fte_new",value=v$fte_new); updateSliderInput(session,"ob_share",value=v$ob_share)
    updateSliderInput(session,"uro_fte",value=v$uro_fte); updateSliderInput(session,"haz_mult",value=v$haz_mult)
    updateSliderInput(session,"demand_mult",value=v$demand_mult) }
  observeEvent(input$p_ref, apply_preset(PRESETS$Reference))
  observeEvent(input$p_re,  apply_preset(PRESETS[["Retire early"]]))
  observeEvent(input$p_rl,  apply_preset(PRESETS[["Retire late"]]))
  observeEvent(input$p_le,  apply_preset(PRESETS[["Lower entrants"]]))
  observeEvent(input$p_he,  apply_preset(PRESETS[["Higher entrants"]]))
  observeEvent(input$p_st,  apply_preset(PRESETS[["Stress test"]]))
  setBookmarkExclude(c("p_ref","p_re","p_rl","p_le","p_he","p_st","reset","dl"))

  # plausibility badge = worst category among the active levers; names the offenders
  LEVER_NAME <- c(retire="retirement age", entrants="entrants/yr", fte_new="new-physician FTE",
                  ob_share="% OB/GYN pathway", uro_fte="urology urogyn-time",
                  haz_mult="departure rate", demand_mult="demand growth")
  LEVER_UNIT <- c(retire="", entrants="/yr", fte_new="%", ob_share="%", uro_fte="%",
                  haz_mult="×", demand_mult="×")
  output$badge <- renderUI({
    vals <- list(retire=input$retire, entrants=input$entrants, fte_new=input$fte_new,
                 ob_share=input$ob_share, uro_fte=input$uro_fte, haz_mult=input$haz_mult,
                 demand_mult=input$demand_mult)
    cats <- vapply(names(vals), function(k) classify1(vals[[k]], ENV[[k]]), integer(1))
    lvl  <- max(cats)
    spec <- switch(lvl+1L,
      list(t="Reference-range scenario", bg="#2e8b57"),
      list(t="Outside observed range",  bg="#c77d1a"),
      list(t="Extreme stress test",     bg="#b3261e"))
    detail <- ""
    if (lvl > 0) {
      off <- names(vals)[cats == lvl]
      parts <- vapply(off, function(k){ e<-ENV[[k]]
        sprintf("%s %s%s (reference %s–%s)", LEVER_NAME[[k]], vals[[k]], LEVER_UNIT[[k]], e$ref[1], e$ref[2]) },
        character(1))
      detail <- sprintf(" <span style='font-size:12px;color:#555'>— %s</span>", paste(parts, collapse="; "))
    }
    HTML(sprintf("<span class='scen-badge' style='background:%s'>%s</span>%s", spec$bg, spec$t, detail))
  })

  cur_params <- reactive(list(retire=input$retire, entrants=input$entrants, entry_age=input$entry_age,
    fte_new=input$fte_new/100, obgyn_share=input$ob_share/100, uro_fte=input$uro_fte/100,
    haz_mult=input$haz_mult, demand_mult=input$demand_mult, weight_on=isTRUE(input$weight_on),
    end_year=input$end_year))
  proj    <- reactive(project_from(cur_params()))
  troughv <- reactive({ d<-proj(); i<-which.min(d$adeq_eff); list(v=d$adeq_eff[i], yr=d$YEAR[i]) })
  # ONE canonical summary object; every narrative/KPI reads from it, and the
  # contract validator hard-fails if it ever disagrees with the projection.
  summ <- reactive({ p<-cur_params(); s<-scenario_summary(proj(), p, DEFAULTS)
    validate_scenario_contract(proj(), p, s, DEFAULTS); s })
  output$fp <- renderText(paste("scenario", summ()$fingerprint))

  band_lab <- reactive(switch(input$band_var,
    retire="retirement timing by ±2 years", entrants="annual entrants by ±20",
    fte="new-physician FTE by ±10 points",  demand="demand growth by ±20%",
    uro="urology urogyn-time by ±15 points"))
  # Uncertainty band varies ANY chosen lever (Guard: user-selectable band).
  projRange <- reactive({
    p <- cur_params()
    lohi <- switch(input$band_var,
      retire   = list(modifyList(p, list(retire=max(55, p$retire-2))),  modifyList(p, list(retire=min(75, p$retire+2)))),
      entrants = list(modifyList(p, list(entrants=max(20, p$entrants-20))), modifyList(p, list(entrants=min(120, p$entrants+20)))),
      fte      = list(modifyList(p, list(fte_new=max(0.5, p$fte_new-0.10))), modifyList(p, list(fte_new=min(1.0, p$fte_new+0.10)))),
      demand   = list(modifyList(p, list(demand_mult=max(0.5, p$demand_mult-0.20))), modifyList(p, list(demand_mult=min(2.0, p$demand_mult+0.20)))),
      uro      = list(modifyList(p, list(uro_fte=max(0, p$uro_fte-0.15))), modifyList(p, list(uro_fte=min(1, p$uro_fte+0.15)))))
    list(central=project_from(p), a=project_from(lohi[[1]]), b=project_from(lohi[[2]]))
  })

  output$refs <- renderUI(refs_table())
  output$yr1  <- renderText(input$end_year)
  output$yr2  <- renderText(input$end_year)
  output$yr3  <- renderText(input$end_year)
  sub <- function(txt) sprintf("<div style='font-size:13px;font-weight:400;color:#6a7686;margin-top:2px'>%s</div>", txt)

  # all four KPIs read from the single canonical summary object (no recompute)
  output$kpi_eff <- renderUI({ s<-summ()
    HTML(paste0(cm(s$effective_end), " FTEs", sub(sprintf("%+.0f%% from 2025", s$eff_growth_pct)))) })
  output$kpi_adeq <- renderUI({ s<-summ()
    HTML(paste0(sprintf("%d%%", s$met_pct), sub("of status-quo demand"))) })
  output$kpi_trough <- renderUI({ s<-summ()
    HTML(paste0(s$trough_year, sub(sprintf("%d%% of demand met", s$trough_pct)))) })
  output$kpi_age <- renderUI({ s<-summ()
    HTML(paste0(sprintf("%.1f years", s$mean_age_end), sub(sprintf("mean age · SD %.1f", s$sd_age_end)))) })
  output$gap_sub <- renderUI(HTML(sprintf(
    "(effective FTEs; 2025 normalized to balance; shaded range varies %s)", band_lab())))

  L_DEM <- "Demand (Status Quo)"; L_EFF <- "Supply, effective FTE"; L_HC <- "Supply, headcount"
  plotly_cfg <- function(p) config(p, displaylogo=FALSE,
    modeBarButtonsToRemove=list("select2d","lasso2d","autoScale2d","hoverClosestCartesian","hoverCompareCartesian"))
  scen_note <- function(r, extra="") list(text=paste0(sprintf("Supply scenario: retire at %d yr", r), extra),
    showarrow=FALSE, x=0, xref="paper", y=-0.16, yref="paper", xanchor="left", yanchor="top",
    font=list(size=11, color="#666"))

  output$p_growth <- renderPlotly({
    d <- proj(); r <- input$retire
    plot_ly(d, x=~YEAR) |>
      add_trace(y=~dem_index, name=L_DEM, type="scatter", mode="lines+markers",
                line=list(color=ORANGE,width=3), marker=list(color=ORANGE,size=5),
                hovertemplate=paste0(L_DEM,": %{y:.0f}<extra></extra>")) |>
      add_trace(y=~eff_index, name=L_EFF, type="scatter", mode="lines+markers",
                line=list(color=TEAL,width=3), marker=list(color=TEAL,size=5),
                hovertemplate=paste0(L_EFF,": %{y:.0f}<extra></extra>")) |>
      add_trace(y=~hc_index, name=L_HC, type="scatter", mode="lines+markers",
                line=list(color=GREY,width=3), marker=list(color=GREY,size=5),
                hovertemplate=paste0(L_HC,": %{y:.0f}<extra></extra>")) |>
      layout(hovermode="x unified", legend=list(orientation="h", y=1.16, x=0, font=list(size=11)),
             xaxis=list(title="", dtick=5, showgrid=FALSE),
             yaxis=list(title="Index (2025 = 100)", hoverformat=".0f"),
             margin=list(t=54,r=14,b=48,l=52), annotations=list(scen_note(r))) |>
      plotly_cfg()
  })

  output$p_adeq <- renderPlotly({
    d <- proj(); r <- input$retire
    ymin <- min(0.90, min(d$adeq_eff)*0.99); ymax <- max(1.02, max(d$adeq_hc, d$adeq_eff)*1.01)
    plot_ly(d, x=~YEAR) |>
      add_trace(y=~adeq_eff, name="Age-adjusted effective FTE", type="scatter", mode="lines+markers",
                line=list(color=TEAL,width=3), marker=list(color=TEAL,size=5),
                hovertemplate="Effective FTE: %{y:.2f}<extra></extra>") |>
      add_trace(y=~adeq_hc, name="Headcount", type="scatter", mode="lines+markers",
                line=list(color=GREY,width=3), marker=list(color=GREY,size=5),
                hovertemplate="Headcount: %{y:.2f}<extra></extra>") |>
      layout(hovermode="x unified", legend=list(orientation="h", y=1.16, x=0, font=list(size=11)),
             xaxis=list(title="", dtick=5, showgrid=FALSE),
             yaxis=list(title="Capacity met (2025 = 1.00)", hoverformat=".2f", range=c(ymin,ymax)),
             # consistent with the capacity-gap chart: RED = short of the 2025 requirement, GREEN = above it
             shapes=list(
               list(type="rect", xref="paper", x0=0, x1=1, yref="y", y0=ymin, y1=1,
                    fillcolor=RED,   opacity=0.06, line=list(width=0), layer="below"),
               list(type="rect", xref="paper", x0=0, x1=1, yref="y", y0=1, y1=ymax,
                    fillcolor=GREEN, opacity=0.06, line=list(width=0), layer="below"),
               list(type="line", xref="paper", x0=0, x1=1, yref="y", y0=1, y1=1,
                    line=list(color="#888", dash="dash", width=1))),
             margin=list(t=54,r=14,b=48,l=52),
             annotations=list(scen_note(r),
               list(xref="paper",x=0.01, yref="paper",y=0.98, text="Above the 2025 requirement", showarrow=FALSE,
                    xanchor="left", font=list(color=GREEN, size=10)),
               list(xref="paper",x=0.01, yref="paper",y=0.02, text="Below the 2025 requirement", showarrow=FALSE,
                    xanchor="left", font=list(color=RED, size=10)))) |>
      plotly_cfg()
  })

  output$p_shortfall <- renderPlotly({
    pr <- projRange(); ey <- input$end_year
    # capacity MARGIN = effective supply − requirement = −gap, so "ahead" points UP,
    # matching the adequacy chart (up/green = above requirement, down/red = below).
    b <- data.table(YEAR=pr$central$YEAR, mid=-pr$central$shortfall,
                    loB=pmin(-pr$a$shortfall, -pr$b$shortfall),
                    hiB=pmax(-pr$a$shortfall, -pr$b$shortfall))
    b[, `:=`(pos=ifelse(mid>=0, mid, NA_real_), neg=ifelse(mid<=0, mid, NA_real_))]
    e <- b[YEAR==ey]
    rg <- range(c(b$loB, b$hiB, 0)); pad <- max(diff(rg)*0.10, 5)
    plot_ly(b, x=~YEAR) |>
      add_trace(y=~loB, type="scatter", mode="lines", line=list(width=0), showlegend=FALSE, hoverinfo="skip") |>
      add_trace(y=~hiB, type="scatter", mode="lines", fill="tonexty", fillcolor="rgba(130,130,130,0.13)",
                line=list(width=0), showlegend=FALSE, hoverinfo="skip") |>
      add_trace(y=~pos, type="scatter", mode="lines+markers", line=list(color=GREEN,width=3), connectgaps=FALSE,
                marker=list(color=GREEN,size=5), showlegend=FALSE,
                hovertemplate="Capacity margin: %{y:+.0f} FTE (above requirement)<extra></extra>") |>
      add_trace(y=~neg, type="scatter", mode="lines+markers", line=list(color=RED,width=3), connectgaps=FALSE,
                marker=list(color=RED,size=5), showlegend=FALSE,
                hovertemplate="Capacity margin: %{y:+.0f} FTE (below requirement)<extra></extra>") |>
      layout(hovermode="x unified",
             xaxis=list(title="", dtick=5, showgrid=FALSE, range=c(2025, ey+3)),
             yaxis=list(title="Capacity margin (effective FTE)", zeroline=FALSE,
                        range=c(rg[1]-pad, rg[2]+pad), hoverformat=".0f"),
             shapes=list(
               list(type="rect", xref="paper",x0=0,x1=1, yref="y",y0=0,y1=rg[2]+pad, fillcolor=GREEN, opacity=0.05, line=list(width=0), layer="below"),
               list(type="rect", xref="paper",x0=0,x1=1, yref="y",y0=rg[1]-pad,y1=0, fillcolor=RED,   opacity=0.05, line=list(width=0), layer="below"),
               list(type="line", xref="paper",x0=0,x1=1, yref="y",y0=0,y1=0, line=list(color="#888",dash="dash",width=1))),
             margin=list(t=20,r=20,b=28,l=58),
             annotations=list(
               list(x=ey, y=e$mid, text=sprintf("<b>%s FTEs</b>", cms(e$mid)), showarrow=FALSE,
                    xanchor="left", xshift=8, font=list(color=if (e$mid>=0) GREEN else RED, size=14)),
               list(x=ey, y=e$mid, text=sprintf("range %s to %s", cm(min(e$loB,e$hiB)), cm(max(e$loB,e$hiB))),
                    showarrow=FALSE, xanchor="left", xshift=8, yshift=-15, font=list(color="#777", size=10)),
               list(xref="paper",x=0.01, yref="paper",y=0.98, text="Above the 2025 requirement", showarrow=FALSE,
                    xanchor="left", font=list(color=GREEN, size=10)),
               list(xref="paper",x=0.01, yref="paper",y=0.02, text="Below the 2025 requirement", showarrow=FALSE,
                    xanchor="left", font=list(color=RED, size=10)),
               list(x=2025, y=0, text="balance (2025)", showarrow=FALSE, xanchor="left",
                    yshift=11, font=list(color="#888", size=11)))) |>
      plotly_cfg()
  })

  output$readout <- renderUI({
    s <- summ()
    finding <- sprintf(
      "By <b>%d</b>, effective supply grows <b>%+.0f%%</b> while status-quo demand grows <b>%+.0f%%</b>, so the model supplies <b>%d%%</b> of the capacity needed to maintain 2025 utilization, with the tightest point in <b>%d</b> (%d%%).",
      s$horizon, s$eff_growth_pct, s$dem_growth_pct, s$met_pct, s$trough_year, s$trough_pct)
    # patient-level translation (literature: report the patient consequence, not just an FTE gap)
    patient <- if (s$load_increase_pct >= 0)
        sprintf("In patient terms: each effective urogynecologist would cover <b>%+.0f%%</b> more women 65+ than in 2025 (from ~%s to ~%s women per FTE); density is <b>%.2f</b> per 100,000 women 65+.",
                s$load_increase_pct, cm(s$women_per_efte_2025), cm(s$women_per_efte_end), s$per100k_end)
      else
        sprintf("In patient terms: each effective urogynecologist would cover <b>%.0f%%</b> fewer women 65+ than in 2025 (from ~%s to ~%s women per FTE); density is <b>%.2f</b> per 100,000 women 65+.",
                -s$load_increase_pct, cm(s$women_per_efte_2025), cm(s$women_per_efte_end), s$per100k_end)
    lbl <- if (s$is_reference) "Reference scenario" else "Current scenario"
    ref <- sprintf(
      "%s: retirement at %d, %s entrants annually, %d%% new-physician clinical FTE. See <i>About this model</i> below for terminology and the 2025-balance assumption.",
      lbl, input$retire, cm(input$entrants), input$fte_new)
    HTML(sprintf("<div style='font-size:15px;line-height:1.55'><p style='margin:0 0 6px'>%s</p><p style='margin:0 0 6px;color:#444;font-size:13px'>%s</p><p style='margin:0;color:#666;font-size:12.5px'>%s</p></div>", finding, patient, ref))
  })

  output$dl <- downloadHandler(
    filename=function() sprintf("urps_capacity_scenario_retire%d_ent%d_fte%d.csv",
                                input$retire, input$entrants, input$fte_new),
    content=function(file) {
      con <- file(file, "w")
      writeLines(c("# URPS Effective-Adequacy Explorer — scenario assumptions (reproduces this run)",
        paste0("# retirement_age: ", input$retire),
        paste0("# entrants_per_year: ", input$entrants),
        paste0("# obgyn_pathway_pct: ", input$ob_share),
        paste0("# urology_urogyn_time_pct: ", input$uro_fte),
        paste0("# new_physician_fte_pct: ", input$fte_new),
        paste0("# pre_retirement_departure_multiplier: ", input$haz_mult),
        paste0("# demand_multiplier: ", input$demand_mult),
        paste0("# entry_age: ", input$entry_age),
        paste0("# age_productivity_adjust: ", isTRUE(input$weight_on)),
        paste0("# projection_horizon: ", input$end_year),
        paste0("# uncertainty_band_variable: ", input$band_var),
        paste0("# model_version: ", MODEL_VERSION),
        paste0("# data_through: ", DATA_THROUGH),
        paste0("# generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
        paste0("# scenario_fingerprint: ", attr(proj(), "scenario_fp")),
        "#"), con)
      close(con)
      fwrite(proj(), file, append=TRUE, col.names=TRUE)
    })
}

shinyApp(ui, server, enableBookmarking = "url")
