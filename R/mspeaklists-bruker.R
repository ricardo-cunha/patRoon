# SPDX-FileCopyrightText: 2016 - 2025 Rick Helmus <r.helmus@uva.nl>
#
# SPDX-License-Identifier: GPL-3.0-only

#' @include main.R
#' @include mspeaklists.R
#' @include utils-bruker.R
NULL

# NOTE: No coverage calculation for Bruker tools as they cannot be run on CI
# nocov start

#' Generate peak lists with Bruker DataAnalysis
#'
#' Uses Bruker DataAnalysis to read the data needed to generate MS peak lists.
#'
#' @templateVar algo Bruker DataAnalysis
#' @templateVar do generate MS peak lists
#' @templateVar generic generateMSPeakLists
#' @templateVar algoParam bruker
#' @template algo_generator
#'
#' @details The MS data should be in the Bruker data format (\file{.d}). This function leverages DataAnalysis
#'   functionality to support averaging of spectra, background subtraction and identification of isotopes. In order to
#'   obtain mass spectra TICs will be added in DataAnalysis of the MS and relevant MS/MS signals.
#'
#' @param bgsubtr If \code{TRUE} background will be subtracted using the 'spectral' algorithm.
#' @param minMSIntensity,minMSMSIntensity Minimum intensity for peak lists obtained with DataAnalysis. Highly
#'   recommended to set \samp{>0} as DA tends to report many very low intensity peaks.
#' @param clear Remove any existing chromatogram traces/mass spectra prior to making new ones.
#' @param MSMSType The type of MS/MS experiment performed: \code{"MSMS"} for MRM/AutoMSMS or \code{"BBCID"} for
#'   broadband CID.
#'
#' @template mspl_algo-args
#' @template dasaveclose-args
#' @inheritParams generateMSPeakLists
#'
#' @inherit generateMSPeakLists return
#'
#' @note The \option{Component} column should be active (Method-->Parameters-->Layouts-->Mass List Layout) in order to
#'   add isotopologue information.
#'
#' @template DA-restart-note
#'
#' @templateVar what generateMSPeakListsDA
#' @template main-rd-method
#' @export
setMethod("generateMSPeakListsDA", "featureGroups", function(fGroups, bgsubtr = TRUE, maxMSRtWindow = 5, minMSIntensity = 500,
                                                             minMSMSIntensity = 500,  clear = TRUE, close = TRUE, save = close,
                                                             MSMSType = "MSMS", avgFGroupParams = getDefAvgPListParams())
{
    # UNDONE: implement topMost
    # UNDONE: better hashing

    ac <- checkmate::makeAssertCollection()
    checkmate::assertClass(fGroups, "featureGroups", add = ac)
    aapply(checkmate::assertFlag, . ~ bgsubtr + clear + save, fixed = list(add = ac))
    aapply(checkmate::assertNumber, . ~ maxMSRtWindow + minMSIntensity + minMSMSIntensity,
           lower = 0, finite = TRUE, null.ok = TRUE, fixed = list(add = ac))
    checkmate::assertChoice(MSMSType, c("MSMS", "BBCID"), add = ac)
    assertAvgPListParams(avgFGroupParams, add = ac)
    assertDACloseSaveArgs(close, save, add = ac)
    checkmate::reportAssertions(ac)

    cacheDB <- openCacheDBScope()
    baseHash <- makeHash(fGroups, bgsubtr, maxMSRtWindow, minMSIntensity, minMSMSIntensity, MSMSType)

    ftindex <- groupFeatIndex(fGroups)
    fTable <- featureTable(fGroups)
    anaInfo <- analysisInfo(fGroups)
    gCount <- length(fGroups)
    gNames <- names(fGroups)
    DA <- getDAApplication()

    hideDAInScope()

    # structure: [[analysis]][[fGroup]][[MSType]][[MSPeak]]
    peakLists <- lapply(seq_len(nrow(anaInfo)), function(anai)
    {
        ana <- anaInfo$analysis[anai]
        anaFTInds <- unlist(ftindex[anai])
        anaFTInds <- anaFTInds[anaFTInds != 0]

        if (length(anaFTInds) == 0)
            return(NULL)

        anaGNames <- names(anaFTInds)
        DAFind <- getDAFileIndex(DA, ana, anaInfo$path[anai])

        setHash <- makeHash(baseHash, ana) # UNDONE
        cachedSet <- loadCacheSet("MSPeakListsDA", setHash, cacheDB)
        resultHashes <- sapply(anaGNames, makeHash, setHash) # UNDONE
        cachedResults <- pruneList(sapply(resultHashes, function(h)
        {
            result <- NULL
            if (!is.null(cachedSet))
                result <- cachedSet[[h]]
            if (is.null(result))
                result <- loadCacheData("MSPeakListsDA", h, cacheDB)
            return(result)
        }, simplify = FALSE))

        uncachedGNames <- setdiff(anaGNames, names(cachedResults))
        if (length(uncachedGNames) > 0)
        {
            if (clear)
                clearDAChromsAndSpecs(DA, uncachedGNames, DAFind)

            uncachedFTInds <- anaFTInds[names(anaFTInds) %in% uncachedGNames]
            featInfo <- rbindlist(lapply(uncachedFTInds, function(fti) fTable[[ana]][fti]),
                                  idcol = "group")

            DAEICs <- generateDAEICsForPeakLists(DA, ana, anaInfo$path[anai], bgsubtr, MSMSType,
                                                 uncachedGNames, featInfo, DAFind)

            DASpecs <- generateDASpecsForPeakLists(DA, maxMSRtWindow, MSMSType, uncachedGNames, featInfo,
                                                   DAEICs, DAFind)

            printf("Loading all MS peak lists for %d feature groups in analysis '%s'...\n", length(uncachedGNames), ana)
            prog <- openProgBar(0, length(uncachedGNames))

            uncachedResults <- setNames(lapply(seq_along(uncachedGNames), function(grpi)
            {
                results <- list()
                grp <- uncachedGNames[grpi]

                if (!is.null(DASpecs$MSSpecs[[grp]]))
                    results$MS <- getDAPeakList(DAFind, DASpecs$MSSpecs[[grp]], FALSE, FALSE,
                                                minMSIntensity)

                if (!is.null(DASpecs$MSMSSpecs[[grp]]))
                    results$MSMS <- getDAPeakList(DAFind, DASpecs$MSMSSpecs[[grp]], FALSE, TRUE,
                                                  minMSMSIntensity)

                results <- pruneList(results) # MS or MSMS entry might be NULL
                results <- lapply(results, assignPrecursorToMSPeakList,
                                  precursorMZ = featInfo[group == uncachedGNames[grpi], mz])

                saveCacheData("MSPeakListsDA", results, resultHashes[[grp]], cacheDB)

                setTxtProgressBar(prog, grpi)
                return(results)
            }), uncachedGNames)

            setTxtProgressBar(prog, length(uncachedGNames))
            close(prog)

            cachedResults <- c(cachedResults, uncachedResults)
            cachedResults <- cachedResults[intersect(anaGNames, names(cachedResults))]
        }

        if (is.null(cachedSet))
            saveCacheSet("MSPeakListsDA", resultHashes, setHash, cacheDB)

        closeSaveDAFile(DA, DAFind, close, save)

        return(cachedResults)
    })

    peakLists <- pruneList(setNames(peakLists, anaInfo$analysis))

    return(MSPeakLists(peakLists = peakLists, metadata = list(), avgPeakListArgs = avgFGroupParams,
                       origFGNames = gNames, algorithm = "bruker"))
})

#' @rdname generateMSPeakListsDA
#' @export
setMethod("generateMSPeakListsDA", "featureGroupsSet", function(fGroups, ...)
{
    generateMSPeakListsSet(fGroups, generateMSPeakListsDA, ...)
})

#' Generate peak lists with Bruker DataAnalysis from bruker features
#'
#' Uses 'compounds' that were generated by the Find Molecular Features (FMF) algorithm of Bruker DataAnalysis to extract
#' MS peak lists.
#'
#' @templateVar algo Bruker DataAnalysis with FMF
#' @templateVar do generate MS peak lists
#' @templateVar generic generateMSPeakLists
#' @templateVar algoParam brukerfmf
#' @template algo_generator
#'
#' @details This function is similar to \code{\link{generateMSPeakListsDA}}, but uses 'compounds' that were generated by
#'   the Find Molecular Features (FMF) algorithm to extract MS peak lists. This is generally much faster , however, it
#'   only works when features were obtained with the \code{\link{findFeaturesBruker}} function. Since all MS spectra
#'   are generated in advance by Bruker DataAnalysis, only few parameters exist to customize its operation.
#'
#' @inheritParams generateMSPeakListsDA
#'
#' @inherit generateMSPeakLists return
#'
#' @template DA-restart-note
#' 
#' @templateVar what generateMSPeakListsDAFMF
#' @template main-rd-method
#' @export
setMethod("generateMSPeakListsDAFMF", "featureGroups", function(fGroups, minMSIntensity = 500, minMSMSIntensity = 500,
                                                                close = TRUE, save = close,
                                                                avgFGroupParams = getDefAvgPListParams())
{
    ac <- checkmate::makeAssertCollection()
    checkmate::assertClass(fGroups, "featureGroups", add = ac)
    aapply(checkmate::assertNumber, . ~ minMSIntensity + minMSMSIntensity,
           lower = 0, finite = TRUE, null.ok = TRUE, fixed = list(add = ac))
    assertDACloseSaveArgs(close, save, add = ac)
    assertAvgPListParams(avgFGroupParams, add = ac)
    checkmate::reportAssertions(ac)

    # UNDONE: implement topMost

    cacheDB <- openCacheDBScope()

    ftindex <- groupFeatIndex(fGroups)
    gcount <- ncol(ftindex)
    gNames <- names(fGroups)
    fTable <- featureTable(fGroups)
    anaInfo <- analysisInfo(fGroups)
    DA <- getDAApplication()

    hideDAInScope()

    # structure: [[analysis]][[fGroup]][[MSType]][[MSPeak]]
    ret <- list()

    for (anai in seq_len(nrow(anaInfo)))
    {
        ana <- anaInfo$analysis[anai]

        setHash <- makeHash(ana, anaInfo$path[anai])
        cachedSet <- loadCacheSet("MSPeakListsDAFMF", setHash, cacheDB)
        resultHashes <- vector("character", gcount)

        findDA <- getDAFileIndex(DA, ana, anaInfo$path[anai])
        checkDAFMFCompounds(DA, fTable[[ana]], findDA, TRUE)

        cmpds <- DA[["Analyses"]][[findDA]][["Compounds"]]

        if (is.null(cachedSet))
        {
            cat("Deconvoluting spectra ...")
            cmpds$Deconvolute()
            cat("Done!\n")
        }

        printf("Loading all MS peak lists for %d feature groups in analysis '%s'...\n", gcount, ana)
        prog <- openProgBar(0, gcount)

        for (grpi in seq_len(gcount))
        {
            fti <- ftindex[[grpi]][anai]
            if (fti == 0)
                next

            hash <- makeHash(setHash, gNames[grpi])
            resultHashes[grpi] <- hash

            results <- NULL
            if (!is.null(cachedSet))
                results <- cachedSet[[hash]]
            if (is.null(results))
                results <- loadCacheData("MSPeakListsDAFMF", hash, cacheDB)

            if (is.null(results))
            {
                results <- list()
                fID <- fTable[[ana]][[fti, "ID"]]

                results$MS <- getDAPeakList(findDA, fID, TRUE, FALSE, minMSIntensity)

                if (cmpds[[fID]]$Count() > 1)
                    results$MSMS <- getDAPeakList(findDA, fID, TRUE, TRUE, minMSMSIntensity)

                results <- pruneList(results)
                results <- lapply(results, assignPrecursorToMSPeakList,
                                  precursorMZ = fTable[[ana]][[fti, "mz"]])

                saveCacheData("MSPeakListsDAFMF", results, hash, cacheDB)
            }

            ret[[ana]][[gNames[grpi]]] <- results

            setTxtProgressBar(prog, grpi)
        }

        setTxtProgressBar(prog, gcount)
        close(prog)

        if (is.null(cachedSet))
            saveCacheSet("MSPeakListsDAFMF", resultHashes[nzchar(resultHashes)], setHash, cacheDB)

        closeSaveDAFile(DA, findDA, close, save)
    }

    return(MSPeakLists(peakLists = ret, metadata = list(), avgPeakListArgs = avgFGroupParams,
                       origFGNames = gNames, algorithm = "Bruker_DataAnalysis_FMF"))
})

#' @rdname generateMSPeakListsDAFMF
#' @export
setMethod("generateMSPeakListsDAFMF", "featureGroupsSet", function(fGroups, ...)
{
    generateMSPeakListsSet(fGroups, generateMSPeakListsDAFMF, ...)
})

# nocov end
