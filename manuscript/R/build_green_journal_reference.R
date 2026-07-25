# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Build the Obstetrics & Gynecology Word reference template
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Produces manuscript/templates/green_journal_reference.docx by restyling
# pandoc's own default reference.docx (so every pandoc paragraph/table style is
# preserved and simply reformatted). Applies the journal's manuscript-file
# requirements:
#   * Times New Roman 12 pt body font (document defaults)
#   * Double line spacing (document defaults)
#   * Continuous line numbering (section properties)
#   * Centered page numbers (footer)
#
# Re-run any time to regenerate; deterministic. Requires pandoc + xml2 + zip.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({library(here); library(xml2)})

.gj_out <- here::here("manuscript", "templates", "green_journal_reference.docx")
dir.create(dirname(.gj_out), showWarnings = FALSE, recursive = TRUE)

work <- file.path(tempdir(), paste0("gjref_", as.integer(runif(1, 1, 1e6))))
if (dir.exists(work)) unlink(work, recursive = TRUE)
dir.create(work, recursive = TRUE)

# 1. Pandoc's default reference docx (fully style-complete).
base_docx <- file.path(work, "reference.docx")
st <- system2("pandoc", c("--print-default-data-file", "reference.docx"),
              stdout = base_docx)
if (!file.exists(base_docx) || file.info(base_docx)$size == 0)
  stop("Could not obtain pandoc default reference.docx")

unpack <- file.path(work, "unpacked")
utils::unzip(base_docx, exdir = unpack)

W <- "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R <- "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

# 2. Document defaults: Times New Roman 12 pt + double spacing.
styles_path <- file.path(unpack, "word", "styles.xml")
styles <- read_xml(styles_path)
ns <- c(w = W)
rpr <- xml_find_first(styles, ".//w:docDefaults/w:rPrDefault/w:rPr", ns)
if (inherits(rpr, "xml_missing")) {
  rprd <- xml_find_first(styles, ".//w:docDefaults/w:rPrDefault", ns)
  rpr <- xml_add_child(rprd, "w:rPr")
}
for (n in c("w:rFonts", "w:sz", "w:szCs")) {
  ex <- xml_find_first(rpr, n, ns); if (!inherits(ex, "xml_missing")) xml_remove(ex)
}
fonts <- xml_add_child(rpr, "w:rFonts")
xml_set_attr(fonts, "w:ascii", "Times New Roman")
xml_set_attr(fonts, "w:hAnsi", "Times New Roman")
xml_set_attr(fonts, "w:cs", "Times New Roman")
xml_set_attr(xml_add_child(rpr, "w:sz"),   "w:val", "24")   # 12 pt = 24 half-pts
xml_set_attr(xml_add_child(rpr, "w:szCs"), "w:val", "24")

ppr <- xml_find_first(styles, ".//w:docDefaults/w:pPrDefault/w:pPr", ns)
if (inherits(ppr, "xml_missing")) {
  pprd <- xml_find_first(styles, ".//w:docDefaults/w:pPrDefault", ns)
  ppr <- xml_add_child(pprd, "w:pPr")
}
ex <- xml_find_first(ppr, "w:spacing", ns); if (!inherits(ex, "xml_missing")) xml_remove(ex)
sp <- xml_add_child(ppr, "w:spacing")
xml_set_attr(sp, "w:line", "480")          # double spacing
xml_set_attr(sp, "w:lineRule", "auto")
write_xml(styles, styles_path)

# 3. Footer with a centered page number.
footer_xml <- sprintf(
'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="%s" xmlns:r="%s"><w:p><w:pPr><w:jc w:val="center"/></w:pPr>
<w:r><w:fldChar w:fldCharType="begin"/></w:r>
<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:ftr>', W, R)
writeLines(footer_xml, file.path(unpack, "word", "footer1.xml"))

# 3a. Content types override for the footer part.
ct_path <- file.path(unpack, "[Content_Types].xml")
ct <- read_xml(ct_path)
ov <- xml_add_child(ct, "Override")
xml_set_attr(ov, "PartName", "/word/footer1.xml")
xml_set_attr(ov, "ContentType",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml")
write_xml(ct, ct_path)

# 3b. Relationship from document to footer.
rels_path <- file.path(unpack, "word", "_rels", "document.xml.rels")
rels <- read_xml(rels_path)
rel <- xml_add_child(rels, "Relationship")
xml_set_attr(rel, "Id", "rIdGJFooter")
xml_set_attr(rel, "Type",
  "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer")
xml_set_attr(rel, "Target", "footer1.xml")
write_xml(rels, rels_path)

# 4. Section properties: continuous line numbers + footer reference.
doc_path <- file.path(unpack, "word", "document.xml")
doc <- read_xml(doc_path)
sect <- xml_find_first(doc, ".//w:body/w:sectPr", ns)
if (inherits(sect, "xml_missing")) {
  body <- xml_find_first(doc, ".//w:body", ns)
  sect <- xml_add_child(body, "w:sectPr")
}
fref <- xml_add_child(sect, "w:footerReference", .where = 0)
xml_set_attr(fref, "w:type", "default")
xml_set_attr(fref, "r:id", "rIdGJFooter")
ln <- xml_add_child(sect, "w:lnNumType")
xml_set_attr(ln, "w:countBy", "1")
xml_set_attr(ln, "w:restart", "continuous")
write_xml(doc, doc_path)

# 5. Repackage as .docx, preserving the OOXML directory structure. Use system
#    zip so relative paths (word/document.xml, _rels/.rels, ...) are retained.
if (file.exists(.gj_out)) unlink(.gj_out)
files <- list.files(unpack, recursive = TRUE, all.files = TRUE, no.. = TRUE)
old <- setwd(unpack); on.exit(setwd(old), add = TRUE)
# [Content_Types].xml first (stored), then everything else.
system2("zip", c("-X", "-q", shQuote(.gj_out), "\\[Content_Types\\].xml"))
rest <- setdiff(files, "[Content_Types].xml")
system2("zip", c("-X", "-q", shQuote(.gj_out), shQuote(rest)))
setwd(old)
cat("Wrote", .gj_out, "\n")
