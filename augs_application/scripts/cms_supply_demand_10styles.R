#!/usr/bin/env Rscript
# 10 styles of the URPS supply-vs-demand figure for a CMS (policy/data) audience.
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(ggplot2); library(patchwork)
})
ft <- tryCatch({ f <- systemfonts::system_fonts()$family
  if ("Inter" %in% f) "Inter" else "sans" }, error = function(e) "sans")

OUT <- here::here("augs_application","figures","cms_styles")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

d <- read_csv(here::here("data","urps_supply_demand_national_2026-07-23.csv"), show_col_types = FALSE) %>%
  mutate(demand_equiv    = 1339 * w65_index/100,        # physicians to hold 2025 status quo
         demand_equiv_lo = 1339 * w65_lo_index/100,
         demand_equiv_hi = 1339 * w65_hi_index/100,
         margin   = supply - demand_equiv,              # capacity margin (physicians)
         adequacy = supply / demand_equiv)              # 1.0 = balance
yrs <- range(d$YEAR)
long_idx <- tibble(
  YEAR = rep(d$YEAR,3),
  what = factor(rep(c("Supply","Demand (Status Quo, women 65+)","Demand (PFD prevalence)"), each=nrow(d)),
               levels=c("Supply","Demand (Status Quo, women 65+)","Demand (PFD prevalence)")),
  idx = c(d$supply_index,d$w65_index,d$pfd_index),
  lo  = c(d$supply_lo_index,d$w65_lo_index,d$pfd_lo_index),
  hi  = c(d$supply_hi_index,d$w65_hi_index,d$pfd_hi_index))

# ---- palettes ----
CMS_DK<-"#112e51"; CMS_BL<-"#205493"; CMS_LT<-"#0071bc"; CMS_CY<-"#02bfe7"
TEAL<-"#1b7f79"; ORANGE<-"#c77d1a"; RED<-"#d1495b"; GREEN<-"#2e8b57"; GREY<-"#8a97a8"
save1 <- function(p, f, w=9, h=5.4) ggsave(file.path(OUT,f), p, width=w, height=h, dpi=200, bg="white")

## 1. CMS federal-blue clean line chart (USWDS style)
p1 <- ggplot(d, aes(YEAR)) +
  geom_ribbon(aes(ymin=supply_lo_index,ymax=supply_hi_index), fill=CMS_LT, alpha=.15) +
  geom_line(aes(y=supply_index), color=CMS_DK, linewidth=1.3) +
  geom_line(aes(y=w65_index), color=CMS_CY, linewidth=1.3) +
  geom_line(aes(y=pfd_index), color="#9bb4c4", linewidth=1.1, linetype="21") +
  annotate("text", x=2050, y=179, label="Supply 179", hjust=1, vjust=-.6, family=ft, fontface="bold", color=CMS_DK, size=4) +
  annotate("text", x=2050, y=129, label="Demand 129", hjust=1, vjust=-.6, family=ft, color=CMS_LT, size=3.6) +
  labs(title="Urogynecology Supply vs. Demand, 2025–2050",
       subtitle="Indexed to 2025 = 100 · Federal report style",
       x=NULL, y="Index (2025 = 100)") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",color=CMS_DK,size=rel(1.15)), plot.title.position="plot",
        plot.subtitle=element_text(color=CMS_BL), panel.grid.minor=element_blank(),
        panel.grid.major=element_line(color="#e6eef5"))
save1(p1,"01_cms_federal_blue.png")

## 2. Per-100,000 Medicare-age women (the rate CMS reasons in)
p2 <- ggplot(d, aes(YEAR)) +
  geom_ribbon(aes(ymin=per100k_lo,ymax=per100k_hi), fill=CMS_BL, alpha=.14) +
  geom_line(aes(y=urogyn_per_100k_w65), color=CMS_BL, linewidth=1.4) +
  geom_point(data=d %>% filter(YEAR %in% c(2025,2050)), aes(y=urogyn_per_100k_w65), color=CMS_DK, size=2.6) +
  geom_text(data=d %>% filter(YEAR %in% c(2025,2050)), aes(y=urogyn_per_100k_w65,label=sprintf("%.2f",urogyn_per_100k_w65)),
            vjust=-1, family=ft, fontface="bold", size=4, color=CMS_DK) +
  labs(title="Urogynecologist Density per 100,000 Medicare-Age Women",
       subtitle="Provider-to-beneficiary ratio, 2025–2050", x=NULL, y="Urogynecologists per 100,000 women 65+") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",color=CMS_DK,size=rel(1.12)), plot.title.position="plot",
        plot.subtitle=element_text(color=CMS_BL), panel.grid.minor=element_blank())
save1(p2,"02_per_100k_medicare.png")

## 3. Absolute physician counts: supply vs demand-equivalent
p3 <- ggplot(d, aes(YEAR)) +
  geom_ribbon(aes(ymin=supply_lo,ymax=supply_hi), fill=TEAL, alpha=.13) +
  geom_line(aes(y=supply), color=TEAL, linewidth=1.3) +
  geom_line(aes(y=demand_equiv), color=ORANGE, linewidth=1.3) +
  annotate("text", x=2049, y=max(d$supply), label="Supply (workforce)", color=TEAL, family=ft, fontface="bold", hjust=1, vjust=-.5, size=3.8) +
  annotate("text", x=2049, y=max(d$demand_equiv), label="Demand-equivalent FTE", color=ORANGE, family=ft, hjust=1, vjust=1.4, size=3.6) +
  labs(title="Projected Urogynecologist Workforce vs. Demand-Equivalent Need",
       subtitle="Absolute counts · demand-equivalent = physicians to hold 2025 utilization", x=NULL, y="Urogynecologists (count)") +
  scale_y_continuous(labels=scales::comma) +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", panel.grid.minor=element_blank())
save1(p3,"03_absolute_counts.png")

## 4. Capacity margin area (green above balance) — policy "ahead or behind"
p4 <- ggplot(d, aes(YEAR, margin)) +
  geom_hline(yintercept=0, color=GREY) +
  geom_area(fill=GREEN, alpha=.18) + geom_line(color=GREEN, linewidth=1.3) +
  annotate("text", x=2038, y=max(d$margin)*.55, label="Capacity margin\n(supply above 2025-balanced need)",
           color="#1e6b43", family=ft, fontface="bold", size=4, lineheight=.9) +
  labs(title="Projected Capacity Margin Above Balanced Demand",
       subtitle="Physicians above (green) / below (red) the 2025-normalized requirement", x=NULL, y="Capacity margin (physicians)") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", panel.grid.minor=element_blank())
save1(p4,"04_capacity_margin_area.png")

## 5. Adequacy ratio (AAMC/HRSA convention CMS knows), reference at 1.0
p5 <- ggplot(d, aes(YEAR, adequacy)) +
  geom_hline(yintercept=1, linetype="dashed", color=RED) +
  geom_line(color=CMS_BL, linewidth=1.4) +
  annotate("text", x=2026, y=1, label="Balance (1.00)", color=RED, family=ft, hjust=0, vjust=1.5, size=3.4) +
  annotate("text", x=2050, y=max(d$adequacy), label=sprintf("%.2f", max(d$adequacy)), color=CMS_DK, family=ft, fontface="bold", hjust=1, vjust=-.6, size=4.2) +
  labs(title="Workforce Adequacy Ratio (Supply ÷ Demand)",
       subtitle="Values above 1.0 indicate supply exceeds status-quo demand", x=NULL, y="Adequacy ratio") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", panel.grid.minor=element_blank())
save1(p5,"05_adequacy_ratio.png")

## 6. Grouped bars at milestone years
bar <- long_idx %>% filter(YEAR %in% c(2025,2035,2050), what!="Demand (PFD prevalence)")
p6 <- ggplot(bar, aes(factor(YEAR), idx, fill=what)) +
  geom_col(position=position_dodge(.7), width=.62) +
  geom_text(aes(label=sprintf("%.0f",idx)), position=position_dodge(.7), vjust=-.4, family=ft, fontface="bold", size=3.6) +
  scale_fill_manual(values=c("Supply"=CMS_DK,"Demand (Status Quo, women 65+)"=CMS_CY)) +
  labs(title="Supply vs. Demand at Milestone Years", subtitle="Indexed to 2025 = 100", x=NULL, y="Index", fill=NULL) +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", legend.position="top",
        panel.grid.major.x=element_blank(), panel.grid.minor=element_blank())
save1(p6,"06_milestone_bars.png")

## 7. 508 / colorblind-safe grayscale (accessibility)
p7 <- ggplot(long_idx, aes(YEAR, idx, linetype=what, shape=what)) +
  geom_line(linewidth=1, color="grey15") +
  geom_point(data=long_idx %>% filter(YEAR%%5==0), size=2, color="grey15") +
  scale_linetype_manual(values=c("solid","longdash","dotted")) +
  scale_shape_manual(values=c(16,17,15)) +
  labs(title="Supply vs. Demand — Accessible (508 / colorblind-safe)",
       subtitle="Distinguished by line pattern and marker, not color", x=NULL, y="Index (2025 = 100)", linetype=NULL, shape=NULL) +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", legend.position="top",
        panel.grid.minor=element_blank(), panel.grid.major=element_line(color="grey88"))
save1(p7,"07_accessible_508.png")

## 8. Slope / dumbbell 2025 -> 2050
sl <- long_idx %>% filter(YEAR %in% c(2025,2050))
p8 <- ggplot(sl, aes(factor(YEAR), idx, group=what, color=what)) +
  geom_line(linewidth=1.4) + geom_point(size=3.4) +
  geom_text(data=sl%>%filter(YEAR==2050), aes(label=sprintf("%s: %.0f",what,idx)), hjust=-.05, family=ft, size=3.4) +
  scale_color_manual(values=c("Supply"=TEAL,"Demand (Status Quo, women 65+)"=ORANGE,"Demand (PFD prevalence)"=RED)) +
  scale_x_discrete(expand=expansion(mult=c(.25,1.15))) +
  labs(title="Where Supply and Demand Land: 2025 → 2050", subtitle="Slope of the indexed change", x=NULL, y="Index (2025 = 100)") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.title=element_text(face="bold",size=rel(1.1)), plot.title.position="plot", legend.position="none",
        panel.grid.minor=element_blank(), panel.grid.major.x=element_blank())
save1(p8,"08_slope_2025_2050.png")

## 9. Dark dashboard style
p9 <- ggplot(d, aes(YEAR)) +
  geom_ribbon(aes(ymin=supply_lo_index,ymax=supply_hi_index), fill=CMS_CY, alpha=.13) +
  geom_line(aes(y=supply_index), color=CMS_CY, linewidth=1.4) +
  geom_line(aes(y=w65_index), color="#f0a202", linewidth=1.3) +
  geom_line(aes(y=pfd_index), color="#ff6b6b", linewidth=1.1) +
  labs(title="Urogynecology Supply–Demand Monitor", subtitle="Indexed to 2025 = 100", x=NULL, y="Index") +
  theme_minimal(base_family=ft, base_size=13) +
  theme(plot.background=element_rect(fill="#0e1621",color=NA), panel.background=element_rect(fill="#0e1621",color=NA),
        plot.title=element_text(face="bold",color="#e8eef4",size=rel(1.12)), plot.title.position="plot",
        plot.subtitle=element_text(color="#9fb3c8"), axis.text=element_text(color="#9fb3c8"),
        axis.title=element_text(color="#9fb3c8"), panel.grid.major=element_line(color="#1e2c3a"),
        panel.grid.minor=element_blank())
save1(p9,"09_dark_dashboard.png")

## 10. Executive callout / briefing slide
p10 <- ggplot(d, aes(YEAR)) +
  geom_line(aes(y=supply_index), color=TEAL, linewidth=1.6) +
  geom_line(aes(y=w65_index), color=GREY, linewidth=1.1) +
  annotate("text", x=2031, y=165, label="Supply grows 79% by 2050", color=TEAL, family=ft, fontface="bold", size=6, hjust=0) +
  annotate("text", x=2031, y=124, label="Demand grows 29%", color="#6a7686", family=ft, size=4.6, hjust=0) +
  annotate("segment", x=2050,xend=2050,y=129,yend=179, color=GREY, linewidth=.4) +
  annotate("text", x=2049.4, y=154, label="50-pt\ncushion", family=ft, size=3.6, color="#4a5560", lineheight=.9, hjust=1) +
  labs(title="The National Urogynecology Workforce Keeps Pace — On Average",
       subtitle="Aggregate supply outgrows demographic demand; geographic distribution is the real gap", x=NULL, y=NULL) +
  theme_minimal(base_family=ft, base_size=14) +
  theme(plot.title=element_text(face="bold",size=rel(1.2)), plot.title.position="plot",
        plot.subtitle=element_text(color="#6a7686",size=rel(.9)), panel.grid.minor=element_blank(),
        axis.text.y=element_blank(), panel.grid.major.y=element_blank())
save1(p10,"10_executive_callout.png")

# ---- contact sheet ----
titles <- c("1 · CMS federal blue","2 · Per-100k Medicare women","3 · Absolute counts",
            "4 · Capacity margin area","5 · Adequacy ratio","6 · Milestone bars",
            "7 · Accessible / 508","8 · Slope 2025→2050","9 · Dark dashboard","10 · Executive callout")
plots <- list(p1,p2,p3,p4,p5,p6,p7,p8,p9,p10)
plots <- Map(function(p,t) p + labs(title=t, subtitle=NULL, caption=NULL) +
               theme(plot.title=element_text(size=rel(1.0)), legend.position="none",
                     axis.title=element_blank(), plot.margin=margin(6,8,6,8)), plots, titles)
sheet <- wrap_plots(plots, ncol=2) +
  plot_annotation(title="URPS supply vs. demand — 10 styles for CMS",
                  theme=theme(plot.title=element_text(family=ft,face="bold",size=20)))
ggsave(file.path(OUT,"00_contact_sheet.png"), sheet, width=15, height=20, dpi=140, bg="white")
cat("wrote 10 figures +contact sheet to", OUT, "\n")
cat("files:\n"); cat(paste0("  ",list.files(OUT)), sep="\n")
