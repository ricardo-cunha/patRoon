# SPDX-FileCopyrightText: 2016 - 2025 Rick Helmus <r.helmus@uva.nl>
#
# SPDX-License-Identifier: GPL-3.0-only

executeFutureCmd <- function(cmd, finishHandler, timeoutHandler, errorHandler,
                             prepareHandler, procTimeout, logSubDir)
{
    if (!is.null(prepareHandler))
        cmd <- prepareHandler(cmd)
    timeoutRetries <- errorRetries <- 0
    while (TRUE)
    {
        # NOTE: cmd$workDir might be NULL
        stat <- processx::run(cmd$command, cmd$args, wd = cmd[["workDir"]], error_on_status = FALSE,
                              timeout = procTimeout, cleanup_tree = TRUE)
        stopMsg <- NULL
        
        if (stat$timeout)
        {
            if (timeoutHandler(cmd = cmd, retries = timeoutRetries))
            {
                timeoutRetries <- timeoutRetries + 1
                next
            }
        }
        else if (stat$status != 0)
        {
            eh <- errorHandler(cmd = cmd, exitStatus = stat$status, retries = errorRetries) 
            if (isTRUE(eh))
            {
                errorRetries <- errorRetries + 1
                next
            }
            else if (is.character(eh))
                stopMsg <- eh
        }
        else # success
        {
            patRoon:::doProgress()
            res <- finishHandler(cmd)
            return(list(stdout = stat$stdout, stderr = stat$stderr, result = res))
        }
        
        # failure
        return(list(stdout = stat$stdout, stderr = stat$stderr, result = NULL, stopMsg = stopMsg))
    }
}

executeMultiProcessFuture <- function(commandQueue, finishHandler, timeoutHandler, errorHandler,
                                      prepareHandler, cacheName, procTimeout, printOutput, printError, logSubDir, ...)
{
    if (is.null(procTimeout))
        procTimeout <- Inf
    
    results <- withProg(length(commandQueue), TRUE,
                        future.apply::future_lapply(commandQueue, patRoon:::executeFutureCmd,
                                                    finishHandler = finishHandler, timeoutHandler = timeoutHandler,
                                                    errorHandler = errorHandler, prepareHandler = prepareHandler,
                                                    procTimeout = procTimeout, logSubDir = logSubDir,
                                                    future.scheduling = getOption("patRoon.MP.futureSched",  1.0),
                                                    future.seed = TRUE))
                        
    logPath <- getOption("patRoon.MP.logPath", FALSE)
    if (!is.null(logSubDir) && !isFALSE(logPath))
    {
        logPath <- file.path(logPath, logSubDir)
        mkdirp(logPath)
        
        for (i in seq_along(commandQueue))
        {
            if (!is.null(commandQueue[[i]]$logFile))
            {
                tryCatch({
                    fprintf(file.path(logPath, commandQueue[[i]]$logFile),
                            "command: %s\nargs: %s\n", commandQueue[[i]]$command,
                            paste0(commandQueue[[i]]$args, collapse = " "))
                    fprintf(file.path(logPath, commandQueue[[i]]$logFile),
                            "\n---\n\noutput:\n%s\n\nstandard error output:\n%s\n",
                            results[[i]]$stdout, results[[i]]$stderr, append = TRUE)
                }, error = function(e) "")
            }
        }
    }
    
    if (!is.null(cacheName))
    {
        cacheDB <- openCacheDBScope()
        for (i in seq_along(commandQueue))
        {
            if (!is.null(results[[i]][["result"]]))
                saveCacheData(cacheName, results[[i]]$result, commandQueue[[i]]$hash, cacheDB)
        }
    }
    
    for (r in results)
    {
        # check for any errors thrown by errorHandler
        if (!is.null(r[["stopMsg"]]))
            stop(r$stopMsg)
    }

    return(sapply(results, "[[", "result", simplify = FALSE))
}
