# SPDX-FileCopyrightText: 2016 - 2025 Rick Helmus <r.helmus@uva.nl>
#
# SPDX-License-Identifier: GPL-3.0-only

context("components")

# take a blank and standard to have two different replicate groups
# set localMZRange=0 to keep isotopes
fGroups <- getTestFGroups(getTestAnaInfoComponents(), localMZRange = 0)
# reduced set for CAMERA/RAMClustR/intensity; for the others we keep all to have sufficient data for good results
fGroupsSimple <- fGroups[, 1:50]


# fix seed for reproducible clustering, suppress warnings about <5 samples
withr::with_seed(20, suppressWarnings(compsRC <- doGenComponents(fGroupsSimple, "ramclustr")))
withr::with_seed(20, suppressWarnings(compsRCMR <- doGenComponents(fGroupsSimple, "ramclustr", relMinReplicates = 1)))
# UNDONE: getting unknown NaN warnings here...
suppressWarnings(compsCAM <- doGenComponents(fGroupsSimple, "camera"))
suppressWarnings(compsCAMMR <- doGenComponents(fGroupsSimple, "camera", relMinReplicates = 1))
suppressWarnings(compsCAMSize <- doGenComponents(fGroupsSimple, "camera", minSize = 3))
compsNT <- doGenComponents(fGroups, "nontarget")
compsInt <- doGenComponents(fGroupsSimple, "intclust", average = FALSE) # no averaging: only one rep group
plists <- generateMSPeakLists(fGroupsSimple, "mzr")
compsSpec <- doGenComponents(fGroupsSimple, "specclust", plists)
compsOpenMS <- doGenComponents(fGroups, "openms")
compsOpenMSMS <- doGenComponents(fGroups, "openms", minSize = 3)
suppressWarnings({
    withr::with_seed(20, compsClMS <- doGenComponents(fGroups, "cliquems", parallel = FALSE))
    withr::with_seed(20, compsClMSNoAB <- doGenComponents(fGroups, "cliquems", relMinAdductAbundance = 0,
                                                          adductConflictsUsePref = FALSE, parallel = FALSE))
})

fGroupsEmpty <- getEmptyTestFGroups()
compsEmpty <- do.call(if (testWithSets()) componentsSet else components, list(algorithm = "none", componentInfo = data.table()))
compsEmpty2 <- do.call(if (testWithSets()) componentsSet else components, list(algorithm = "none2", componentInfo = data.table()))

test_that("components generation works", {
    # For RC/CAM: don't store their internal objects as they contain irreproducible file names
    # For RC: don't check attributes as they seem irreproducible
    expect_known_value(list(componentTable(compsRC), componentInfo(compsRC)), testFile("components-rc"),
                       check.attributes = FALSE, tolerance = 0.00001)
    expect_known_value(list(componentTable(compsCAM), componentInfo(compsCAM)), testFile("components-cam"))
    expect_known_value(compsNT, testFile("components-nt"))
    expect_known_value(compsInt, testFile("components-int"))
    expect_known_value(compsSpec, testFile("components-spec"))
    expect_known_value(compsOpenMS, testFile("components-om"))

    expect_length(compsEmpty, 0)
    expect_length(doGenComponents(fGroupsEmpty, "ramclustr"), 0)
    expect_length(doGenComponents(fGroupsEmpty, "camera"), 0)
    expect_length(doGenComponents(fGroupsEmpty, "intclust"), 0)
    expect_length(doGenComponents(fGroupsEmpty, "nontarget"), 0)
    expect_length(doGenComponents(fGroupsEmpty, "openms"), 0)
    expect_length(doGenComponents(fGroupsEmpty, "cliquems"), 0)

    expect_lt(length(groupNames(compsRCMR)), length(groupNames(compsRC)))
    expect_lt(length(groupNames(compsCAMMR)), length(groupNames(compsCAM)))
    expect_gte(min(componentInfo(compsCAMSize)$size), 3)
    
    expect_equal(min(componentInfo(compsOpenMSMS)$size), 3)
    
    # NOTE: can't compare cliqueMS data as it has environments in them that change
    expect_known_value(list(componentTable(compsClMS), componentInfo(compsClMS)), testFile("components-cm"))

    expect_lt(min(as.data.table(compsClMSNoAB)$adduct_abundance, na.rm = TRUE),
              min(as.data.table(compsClMS)$adduct_abundance, na.rm = TRUE))
})

test_that("verify components show", {
    expect_known_show(compsRC, testFile("components-rc", text = TRUE))
    expect_known_show(compsCAM, testFile("components-cam", text = TRUE))
    expect_known_show(compsInt, testFile("components-int", text = TRUE))
    expect_known_show(compsSpec, testFile("components-spec", text = TRUE))
    expect_known_show(compsOpenMS, testFile("components-om", text = TRUE))
    
    expect_known_show(compsClMS, testFile("components-cm", text = TRUE))
})

test_that("basic subsetting", {
    expect_length(compsRC["nope"], 0)
    expect_equivalent(names(compsRC[1:2]), names(compsRC)[1:2])
    expect_equivalent(names(compsRC[names(compsRC)[1:2]]), names(compsRC)[1:2])
    expect_equivalent(names(compsRC[c(FALSE, TRUE)]), names(compsRC)[c(FALSE, TRUE)])
    expect_equivalent(groupNames(compsRC[, 1:2]), groupNames(compsRC)[1:2])
    expect_equivalent(groupNames(compsRC[, groupNames(compsRC)[2:3]]), groupNames(compsRC)[2:3])
    expect_equivalent(groupNames(compsRC[, c(FALSE, TRUE)]), groupNames(compsRC)[c(FALSE, TRUE)])
    expect_equal(length(compsRC[FALSE]), 0)
    expect_length(compsEmpty[1:5], 0)

    expect_equivalent(compsRC[[1, 1]], componentTable(compsRC)[[1]][group == groupNames(compsRC)[1]])
    expect_equivalent(compsRC[[names(compsRC)[1], groupNames(compsRC)[1]]], componentTable(compsRC)[[1]][group == groupNames(compsRC)[1]])
    expect_equivalent(compsRC[[2]], componentTable(compsRC)[[2]])
    expect_equivalent(callDollar(compsRC, names(compsRC)[3]), compsRC[[3]])
})

test_that("delete and filter", {
    checkmate::expect_names(names(delete(compsRC, i = 1)), disjunct.from = names(compsRC)[1])
    checkmate::expect_names(names(delete(compsRC, i = names(compsRC)[1])), disjunct.from = names(compsRC)[1])
    expect_length(delete(compsRC, i = names(compsRC)), 0)
    expect_false(delete(compsRC, j = 1)[[1]]$group[1] == compsRC[[1]]$group[1])
    checkmate::expect_names(names(delete(compsRC, j = groupNames(compsRC)[1])), disjunct.from = groupNames(compsRC)[1])
    expect_false(delete(compsRC, j = function(...) 1)[[1]]$group[1] == compsRC[[1]]$group[1])
    expect_equal(sum(componentInfo(delete(compsRC, j = function(...) 1:2))$size),
                 sum(componentInfo(compsRC)$size) - (length(names(compsRC)) * 2))
    expect_length(delete(compsRC, j = function(...) TRUE), 0)
    # NOTE: use componentTable since delete() will reduce the object, thus not allowing direct comparison
    expect_equal(componentTable(delete(compsRC, i = character())), componentTable(compsRC))
    expect_equal(componentTable(delete(compsRC, j = integer())), componentTable(compsRC))
    expect_length(delete(compsRC), 0)
    expect_length(delete(compsEmpty), 0)
    
    expect_length(filter(compsRC, size = c(0, 100)), length(compsRC))
    expect_length(filter(compsRC, size = c(50, 100)), 0)
    expect_length(filter(compsRC, size = c(0, 100), negate = TRUE), 0)
    expect_length(filter(compsRC, size = c(50, 100), negate = TRUE), length(compsRC))

    expect_length(filter(compsEmpty, size = c(0, 100)), 0)
    expect_length(filter(compsEmpty, size = c(0, 100), negate = TRUE), 0)

    # shouldn't filter if related data is not there
    expect_equal(groupNames(filter(compsInt, adducts = TRUE)), groupNames(compsInt))
    expect_equal(groupNames(filter(compsInt, isotopes = TRUE)), groupNames(compsInt))
    expect_equal(groupNames(filter(compsInt, adducts = TRUE, negate = TRUE)), groupNames(compsInt))
    expect_equal(groupNames(filter(compsInt, isotopes = TRUE, negate = TRUE)), groupNames(compsInt))

    expect_lt(length(groupNames(filter(compsRC, adducts = TRUE))), length(groupNames(compsRC)))
    expect_lt(length(groupNames(filter(compsRC, adducts = FALSE))), length(groupNames(compsRC)))
    expect_lt(length(groupNames(filter(compsRC, adducts = "[M+H]+"))), length(groupNames(compsRC)))
    expect_true(all(sapply(componentTable(filter(compsRC, adducts = "[M+H]+")),
                           function(cmp) all(!is.na(cmp$adduct_ion) & cmp$adduct_ion == "[M+H]+"))))
    expect_equivalent(filter(compsRC, adducts = FALSE, negate = FALSE),
                      filter(compsRC, adducts = TRUE, negate = TRUE))
    expect_equivalent(filter(compsRC, adducts = TRUE, negate = TRUE),
                      filter(compsRC, adducts = FALSE, negate = FALSE))
    expect_setequal(groupNames(compsRC),
                    c(groupNames(filter(compsRC, adducts = "[M+H]+")),
                      groupNames(filter(compsRC, adducts = "[M+H]+", negate = TRUE))))
    expect_true(all(sapply(componentTable(filter(compsRC, adducts = "[M+H]+", negate = TRUE)),
                           function(cmp) all(is.na(cmp$adduct_ion) | cmp$adduct_ion != "[M+H]+"))))

    expect_lt(length(groupNames(filter(compsRC, isotopes = TRUE))), length(groupNames(compsRC)))
    expect_lt(length(groupNames(filter(compsRC, isotopes = FALSE))), length(groupNames(compsRC)))
    expect_lt(length(groupNames(filter(compsRC, isotopes = 0:1))), length(groupNames(compsRC)))
    expect_true(all(sapply(componentTable(filter(compsRC, isotopes = 0)),
                           function(cmp) all(!is.na(cmp$isonr) & cmp$isonr == 0))))
    expect_equivalent(filter(compsRC, isotopes = FALSE, negate = FALSE),
                      filter(compsRC, isotopes = TRUE, negate = TRUE))
    expect_equivalent(filter(compsRC, isotopes = TRUE, negate = TRUE),
                      filter(compsRC, isotopes = FALSE, negate = FALSE))
    expect_setequal(groupNames(compsRC),
                    c(groupNames(filter(compsRC, isotopes = 0)),
                      groupNames(filter(compsRC, isotopes = 0, negate = TRUE))))
    expect_true(all(sapply(componentTable(filter(compsRC, isotopes = 0, negate = TRUE)),
                           function(cmp) all(is.na(cmp$isonr) | cmp$isonr != 0))))

    expect_length(filter(compsNT, rtIncrement = c(-1000, 1000)), length(compsNT))
    expect_length(filter(compsNT, rtIncrement = c(100, 1000)), 0)
    expect_length(filter(compsNT, mzIncrement = c(0, 1000)), length(compsNT))
    expect_length(filter(compsNT, mzIncrement = c(1000, 10000)), 0)
    expect_length(filter(compsNT, rtIncrement = c(-1000, 1000), negate = TRUE), 0)
    expect_length(filter(compsNT, rtIncrement = c(100, 1000), negate = TRUE), length(compsNT))
    expect_length(filter(compsNT, mzIncrement = c(0, 1000), negate = TRUE), 0)
    expect_length(filter(compsNT, mzIncrement = c(1000, 10000), negate = TRUE), length(compsNT))
})

test_that("basic usage works", {
    expect_equal(length(unique(as.data.table(compsCAM)$name)), length(compsCAM))

    expect_equivalent(findFGroup(compsCAM, compsCAM[[3]]$group[3])[1], 3) # take element [1]: sets give 2 results
    expect_length(findFGroup(compsCAM, "none"), 0)
    expect_length(findFGroup(compsEmpty, "1"), 0)
})

test_that("consensus works", {
    expect_length(consensus(compsRC, compsCAM), length(compsRC) + length(compsCAM))
    expect_error(consensus(compsEmpty, compsEmpty2), NA)
    
    skip_if(testWithSets())
    expect_error(consensus(compsRC, compsEmpty), NA) # can't do with sets: all objects must have same sets
})

test_that("clustered components", {
    expect_equivalent(length(treeCut(compsInt, k = 5)), 5)
    expect_equivalent(treeCutDynamic(compsInt), compsInt)
    expect_setequal(groupNames(compsSpec), groupNames(filter(plists, withMSMS = TRUE)))
})

test_that("reporting works", {
    expect_file(reportCSV(fGroupsSimple, getWorkPath(), components = compsRC),
                getWorkPath("components.csv"))

    expect_file(reportPDF(fGroupsSimple, getWorkPath(), reportFGroups = FALSE, components = compsRC),
                getWorkPath("components.pdf"))

    expect_reportHTML(makeReportHTML(fGroupsSimple, components = compsRC))
})

test_that("reporting empty object works", {
    expect_error(reportCSV(fGroupsSimple, getWorkPath(), components = compsEmpty), NA)
    expect_error(reportPDF(fGroupsSimple, getWorkPath(), reportFGroups = FALSE, components = compsEmpty), NA)
    expect_reportHTML(makeReportHTML(fGroupsSimple, components = compsEmpty))
    expect_error(makeReportHTML(fGroupsEmpty, components = compsRC), NA)
})

test_that("plotting works", {
    # specs don't work because of legend ... :(
    # expect_doppel("compon-spec", function() plotSpectrum(compsNT, 1))
    # expect_doppel("compon-spec-mark", function() plotSpectrum(compsNT, 1, markFGroup = names(fGroups)[1]))
    expect_plot(plotSpectrum(compsRC, 1))
    expect_plot(plotSpectrum(compsRC, 1, markFGroup = names(fGroupsSimple)[1]))
    expect_doppel("eic-component", function() plotChroms(compsRC, 1, fGroupsSimple))

    expect_plot(plot(compsInt))
    expect_plot(plot(compsSpec))
    expect_doppel("component-ic-int", function() plotInt(compsInt, index = 1))
    expect_doppel("component-ic-sil", function() plotSilhouettes(compsInt, 2:6))
    expect_doppel("component-ic-heat", function() plotHeatMap(compsInt, interactive = FALSE))

    skip_if(testWithSets())
    expect_HTML(plotGraph(compsNT, onlyLinked = FALSE))
})

fGroupsSI <- if (testWithSets())
{
    selectIons(fGroups, compsRC, prefAdduct = c("[M+H]+", "[M-H]-"), onlyMonoIso = TRUE)
} else
    selectIons(fGroups, compsRC, prefAdduct = "[M+H]+", onlyMonoIso = TRUE)

test_that("selectIons works", {
    expect_setequal(annotations(fGroupsSI)$group, names(fGroupsSI))
    
    # expect pref adduct is most abundant
    expect_gt(sum(annotations(fGroupsSI)$adduct == "[M+H]+"), 0.5 * length(fGroupsSI))
    expect_gt(sum(annotations(selectIons(fGroups, compsRC, prefAdduct = "[M+Na]+"))$adduct == "[M+Na]+"),
              sum(annotations(fGroupsSI)$adduct == "[M+Na]+"))
    
    expect_gt(length(selectIons(fGroups, compsRC, prefAdduct = "[M+H]+", onlyMonoIso = FALSE)), length(fGroupsSI))
    
    # ignore empty components
    expect_equal(selectIons(fGroups, compsEmpty, prefAdduct = "[M+H]+", onlyMonoIso = TRUE), fGroups)
    # ... and components without annotations in general
    expect_equal(selectIons(fGroups, compsNT, prefAdduct = "[M+H]+", onlyMonoIso = TRUE), fGroups)
    
    skip_if(testWithSets())
    
    checkmate::expect_subset(names(fGroupsSI), names(fGroups))
    expect_equal(nrow(annotations(fGroupsSI)), length(fGroupsSI))
    
    # verify neutral masses
    expect_true(all(sapply(seq_len(nrow(annotations(fGroupsSI))), function(i)
    {
        ann <- annotations(fGroupsSI)[i]
        return(isTRUE(all.equal(patRoon:::calculateMasses(ann$neutralMass, as.adduct(ann$adduct), "mz"),
                                groupInfo(fGroupsSI)[ann$group, "mzs"])))
    })))
    
    skip_if(testWithSets())
    
    expect_lt(length(fGroupsSI), length(fGroups))
})

if (testWithSets())
{
    fgOneEmptySet <- makeOneEmptySetFGroups(fGroupsSimple)
    compsRCOneEmptySet <- withr::with_seed(20, suppressWarnings(doGenComponents(fgOneEmptySet, "ramclustr")))
    
    getSetCompNames <- function(cmp, set)
    {
        pat <- paste0("\\-", set, "$")
        ret <- grep(pat, names(cmp), value = TRUE)
        return(sub(pat, "", ret))
    }
}

test_that("sets functionality", {
    skip_if_not(testWithSets())
    
    # components should be just a combination of the set specific components
    expect_setequal(getSetCompNames(compsRC, "positive"), names(unset(compsRC, "positive")))
    expect_setequal(getSetCompNames(compsRC, "negative"), names(unset(compsRC, "negative")))
    expect_equal(length(compsRC), length(unset(compsRC, "positive")) + length(unset(compsRC, "negative")))
    
    expect_equal(compsRC, compsRC[, sets = sets(compsRC)])
    expect_length(compsRC[, sets = character()], 0)
    expect_equal(sets(filter(compsRC, sets = "positive", negate = TRUE)), "negative")
    expect_setequal(groupNames(compsRC), unlist(unique(lapply(setObjects(compsRC), groupNames))))
    expect_setequal(groupNames(unset(compsRC, "positive")), groupNames(setObjects(compsRC)[[1]]))
    expect_setequal(groupNames(unset(compsRCOneEmptySet, "positive")), groupNames(setObjects(compsRCOneEmptySet)[[1]]))
    expect_length(unset(compsRCOneEmptySet, "negative"), 0)

    expect_HTML(plotGraph(compsNT, set = "positive", onlyLinked = FALSE))
    
    expect_false(length(fGroupsSI) == length(fGroups)) # may increase or decrease for sets
    expect_false(checkmate::testSubset(names(fGroupsSI), names(fGroups))) # should re-group --> new group names
    # annotations stored per set
    expect_equal(nrow(annotations(fGroupsSI)),
                 length(fGroupsSI[, sets = "positive"]) + length(fGroupsSI[, sets = "negative"]))
    
    # verify neutral masses
    expect_true(all(sapply(seq_len(nrow(annotations(fGroupsSI))), function(i)
    {
        ann <- annotations(fGroupsSI)[i]
        # neutral mass equals neutralized group mass
        return(isTRUE(all.equal(ann$neutralMass, groupInfo(fGroupsSI)[ann$group, "mzs"])))
    })))
})
