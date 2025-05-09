# HACK HACK HACK: recently bookdown started to ignore files starting with
# underscores. This mechanism is also used for pkgdown to ignore files, which we
# need as it shouldn't include the bookdown sub-Rmd files in the website. For
# now we temporarily re-name the files to start with underscores and rename back
# once finished building the website...
handbookSubRmdPath <- file.path("vignettes", "handbook")
origRmds <- list.files(handbookSubRmdPath, pattern = "\\.Rmd")
disabledRmds <- paste0("_", origRmds)
origRmds <- file.path(handbookSubRmdPath, origRmds)
disabledRmds <- file.path(handbookSubRmdPath, disabledRmds)
file.rename(origRmds, disabledRmds)

# get older pkgdown version for now, see https://github.com/r-lib/pkgdown/issues/2022
# remotes::install_github("r-lib/pkgdown@v1.6.1")
install.packages("pkgdown")

install.packages(c("bookdown", "DiagrammeR", "rsvg", "webshot", "devtools"))
remotes::install_github("rich-iannone/DiagrammeRsvg")

# get latest version of tinytex to fix issues with the tutorial PDF: https://github.com/rstudio/rmarkdown/issues/2556#issuecomment-2678609024
install.packages("tinytex", repos = c("https://rstudio.r-universe.dev", "https://cloud.r-project.org"))
tinytex::install_tinytex()
tinytex::tlmgr_install("pdfcrop")
webshot::install_phantomjs()
Sys.setenv(PATH = paste0(Sys.getenv("PATH"), ":", "/home/rstudio/bin"))

pkgdown::clean_site()
pkgdown::build_site(examples = FALSE)

# HACK HACK HACK: re-enable bookdown files again...
file.rename(disabledRmds, origRmds)

# make book after pkgdown, otherwise it complains
# NOTE: set clean_envir to FALSE so that 'out' variable below is recognized
out <- file.path(normalizePath("docs", mustWork = FALSE), "handbook_bd")
withr::with_dir("vignettes/handbook/", bookdown::render_book("index.Rmd", output_dir = out))

# PDF versions
# OPENSSL_CONF workaround for PhamtomJS --> see https://stackoverflow.com/a/73063745
withr::with_dir("vignettes/handbook/",
                withr::with_envvar(c(OPENSSL_CONF = "/dev/null"),
                                   bookdown::render_book("index.Rmd", "bookdown::pdf_book", output_dir = out)))
rmarkdown::render("vignettes/tutorial.Rmd", "rmarkdown::pdf_document", output_dir = file.path("docs", "articles"))

tinytex::tlmgr_install("makeindex")
refp <- file.path("docs/reference")
patRoon:::mkdirp(refp)
devtools::build_manual(path = refp)
file.rename(file.path(refp, paste0(desc::desc_get_field("Package"), "_", desc::desc_get_version(), ".pdf")),
            file.path(refp, "patRoon.pdf"))
