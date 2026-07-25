#!/usr/bin/env Rscript
# URPS-only alternatives of the four workforce-cliff figures: titles removed,
# simplified (single cohort -> no legend, no dodging, single colour). Writes to
# cliff/figures/urps_only/.
suppressPackageStartupMessages({library(readr); library(dplyr); library(tidyr)
  library(ggplot2); library(here); library(scales)})

URPS <- "#d1495b"
D <- here("data"); OUT <- here("cliff","figures","urps_only")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
rd <- function(f) read_csv(file.path(D,f), show_col_types=FALSE)
house <- function(base=13) theme_minimal(base_size=base) +
  theme(plot.title.position="plot", panel.grid.minor=element_blank(),
        legend.position="none", axis.title=element_text(size=rel(0.9)))

# -------- FIG 1: robustness (URPS only) --------
wf<-rd("workforce_projections_consolidated.csv"); mort<-rd("mortality_sensitivity.csv")
cons<-rd("consistent_definition_baseline_sensitivity.csv"); op<-rd("open_payments_sensitivity.csv")
win<-rd("departure_window_sensitivity.csv"); grid<-rd("sensitivity_grid_summary.csv")
g<-function(df,col) df[[col]][df$subspecialty_abbrev=="URPS"]
rob<-tibble(
  scenario=c("Primary","Anchored-definition baseline","Open Payments-inclusive",
             "+ half expected deaths","+ all expected deaths",
             "Full window (2016-2023)","3x departure rate","Worst-case combined"),
  ratio=c(g(wf,"replacement_ratio"), g(cons,"ratio_consistent"),
          op$replacement_ratio[op$rule=="op_inclusive" & op$subspecialty_abbrev=="URPS"],
          g(mort,"ratio_adj_half_missed"), g(mort,"ratio_adj_all_missed"),
          win$dynamic_ratio[win$label=="full" & win$subspecialty_abbrev=="URPS"],
          g(grid,"oneway_min"), g(grid,"worst_ratio"))) %>%
  mutate(scenario=factor(scenario, levels=rev(scenario)))
p1<-ggplot(rob, aes(ratio, scenario)) +
  annotate("rect", xmin=-Inf, xmax=1, ymin=-Inf, ymax=Inf, fill="grey90", alpha=.6) +
  geom_vline(xintercept=1, linetype="dashed", colour="grey40") +
  geom_segment(aes(x=1, xend=ratio, yend=scenario), colour=URPS, linewidth=.9, alpha=.5) +
  geom_point(colour=URPS, size=3.6) +
  geom_text(aes(label=sprintf("%.1f", ratio)), hjust=-0.4, size=10, size.unit="pt") +
  scale_x_continuous(limits=c(0, max(rob$ratio)*1.1), breaks=seq(0,6,2), expand=expansion(mult=c(0,.02))) +
  labs(x="Completion-to-departure ratio", y=NULL) + house()
ggsave(file.path(OUT,"urps_fig1_robustness.png"), p1, width=8, height=4.8, dpi=300, bg="white")

# -------- FIG 2: trajectory (URPS only) --------
traj<-rd("scenario_projection_trajectories.csv") %>% filter(subspecialty_abbrev=="URPS")
sq<-traj %>% filter(tolower(scenario) %in% c("status_quo","status-quo","status quo"))
if(nrow(sq)==0) sq<-traj %>% filter(scenario==unique(scenario)[1])
ramp<-rd("graduation_active_transition_projection.csv") %>% filter(subspecialty_abbrev=="URPS")
end<-max(sq$year)
p2<-ggplot(sq, aes(year, median)) +
  geom_ribbon(aes(ymin=lo, ymax=hi), fill=URPS, alpha=.15) +
  geom_line(colour=URPS, linewidth=1.2) + geom_point(colour=URPS, size=2.3) +
  geom_point(aes(x=end, y=ramp$projected_2029_ramped), shape=21, size=4, stroke=1.2, colour=URPS, fill="white") +
  geom_text(aes(x=end, y=ramp$projected_2029_ramped,
                label=sprintf("transition-\nadjusted: %s", comma(round(ramp$projected_2029_ramped)))),
            hjust=1.1, vjust=1.25, size=9, size.unit="pt", lineheight=.9, colour=URPS) +
  scale_x_continuous(breaks=unique(sq$year), guide=guide_axis(check.overlap=TRUE)) +
  scale_y_continuous(labels=comma) +
  labs(x=NULL, y="Active urogynecologists") + house()
ggsave(file.path(OUT,"urps_fig2_trajectory.png"), p2, width=8, height=4.6, dpi=300, bg="white")

# -------- FIG 3: entrants vs departures (URPS only) --------
imb<-wf %>% filter(subspecialty_abbrev=="URPS") %>%
  transmute(Entrants=annual_entrants, Departures=avg_annual_retirements) %>%
  pivot_longer(everything(), names_to="flow", values_to="n") %>%
  mutate(flow=factor(flow, levels=c("Departures","Entrants")))
p3<-ggplot(imb, aes(flow, n, fill=flow)) +
  geom_col(width=.6) +
  geom_text(aes(label=round(n)), vjust=-0.4, size=12, size.unit="pt") +
  scale_fill_manual(values=c(Entrants="#2a9d8f", Departures="#e76f51")) +
  scale_y_continuous(expand=expansion(mult=c(0,.14))) +
  labs(x=NULL, y="Physicians per year") + house() +
  theme(panel.grid.major.x=element_blank())
ggsave(file.path(OUT,"urps_fig3_entrants_vs_departures.png"), p3, width=6.4, height=4.6, dpi=300, bg="white")

# -------- FIG 4: age-band hazard (URPS only) --------
hz<-rd("hazard_by_band_pooled_vs_unpooled.csv") %>%
  transmute(band, hazard=urps_hazard_unpooled) %>%
  mutate(band=factor(band, levels=c("<45","45-49","50-54","55-59","60-64","65-69","70+")))
p4<-ggplot(hz, aes(band, 100*hazard, group=1)) +
  geom_line(colour=URPS, linewidth=1.1) + geom_point(colour=URPS, size=2.6) +
  scale_x_discrete(guide=guide_axis(check.overlap=TRUE)) +
  labs(x="Age band", y="Annual departure hazard (%)") + house()
ggsave(file.path(OUT,"urps_fig4_ageband_hazard.png"), p4, width=8, height=4.4, dpi=300, bg="white")

cat("Wrote 4 URPS-only figures to", OUT, "\n"); print(list.files(OUT))
