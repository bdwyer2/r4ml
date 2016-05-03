#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#' @include zzz.R
NULL

requireNamespace("SparkR")
#' A Reference Class that represent systemML MatrixCharacteristics
#'
#' Create a meta info about the block and overall size of matrix
#' This class acts as the metadata for the systemML matrix and is used by other
#' classes in the systemML.
#'
#' @family MLContext functions
#'
#' @field nrow number of row of the block matrix
#' @field ncol number of col of the block matrix
#' @field bnrow number of row in one block
#' @field bncol number of col of one block
#' @field env environment which among other things contains the underlying
#'  java reference
#' @export
#' @examples \dontrun{
#' matrix_info = sysml.MatrixCharacteristics(1000, 1000, 1000, 1000)
#' }
#'

sysml.MatrixCharacteristics <- setRefClass("sysml.MatrixCharacteristics",
  fields = list(nrow="numeric", ncol="numeric", bnrow="numeric",
                bncol="numeric", env="environment"),
  methods = list (
    initialize = function(numrow, numcol, blknumrow, blknumcol) {
      nrow <<- as.integer(numrow)
      ncol <<- as.integer(numcol)
      bnrow <<- as.integer(blknumrow)
      bncol <<- as.integer(blknumcol)
      env <<- new.env()
      env$jref <<- SparkR:::newJObject("org.apache.sysml.runtime.matrix.MatrixCharacteristics",
                                   as.integer(nrow), as.integer(ncol),
                                   as.integer(bnrow), as.integer(bncol))
    },
    finalize = function() {
      SparkR:::cleanup.jobj(env$jref)
    }
  )

)


#'
#' A Reference Class that represent systemML MLContext
#'
#' MLContext is the gateway to the systemML world and this class provides
#' ability of the R code to connect and use the various systemML
#' high performant distributed linear algebra library and allow use
#' to run the dml script in the R code.
#'
#' @family MLContext functions
#'
#' @field env An R environment that stores bookkeeping states of the class
#'        along with java ref corresponding to jvm
#' @export
#' @examples \dontrun{
#'    sc # the default spark context
#'    mlCtx = sysml.MLContext$new(sc)
#' }
sysml.MLContext <- setRefClass("sysml.MLContext",
  fields = list(env="environment"),
  methods = list(
    initialize = function(sparkContext = sc) {
      env <<- new.env()
      if (missing(sparkContext)) {
        sparkContext = get("sc", .GlobalEnv)
      }
      env$jref <<- SparkR:::newJObject("org.apache.sysml.api.MLContext", sparkContext)
    },

    finalize = function() {
      SparkR:::cleanup.jobj(env$jref)
    },

    reset = function() {
      '\\tabular{ll}{
         Description:\\tab \\cr
           \\tab reset the MLContext \\cr
       }'
      SparkR:::callJMethod(env$jref, "reset")
    },

    registerInput = function(dmlname, rdd_or_df, mc) {
      '\\tabular{ll}{
         Description:\\tab \\cr
           \\tab bind the rdd or dataframe to the dml variable
       }
       \\tabular{lll}{
         Arguments:\\tab \\tab \\cr
           \\tab dmlname \\tab variable name in the dml script \\cr
           \\tab rdd_or_df \\tab SparkR:::RDD rdd class which need to be attached\\cr
           \\tab mc \\tab \\link{sysml.MatrixCharacteristics} info about block matrix
       }
      '
      #check the args
      stopifnot(class(dmlname) == "character",
                class(mc) == "sysml.MatrixCharacteristics")
      # check rdd_or_df arg
      cls <- as.vector(class(rdd_or_df))
      jrdd <- NULL
      if (cls == 'DataFrame') {
        jrdd <- SparkR:::toRDD(rdd_or_df)
      } else if  (cls == 'RDD' || cls == 'PipelinedRDD') {
        jrdd <- SparkR:::getJRDD(rdd_or_df)
      } else if (cls == 'jobj') {
        jrdd = rdd_or_df
      } else {
        stop("unsupported argument rdd_or_df only rdd or dataframe is supported")
      }

      SparkR:::callJMethod(env$jref, "registerInput", dmlname, jrdd, mc$env$jref)
    },

    registerOutput = function(dmlname) {
      '\\tabular{ll}{
         Description:\\tab \\cr
           \\tab bind the output dml var
       }
       \\tabular{lll}{
         Arguments:\\tab \\tab \\cr
           \\tab dmlname \\tab variable name in the dml script \\cr
         }
      '
      stopifnot(class(dmlname) == "character")
      SparkR:::callJMethod(env$jref, "registerOutput", dmlname)
    },

    executeScriptNoArgs = function(dml_script) {
      '\\tabular{ll}{
        Description:\\tab \\cr
        \\tab This is deprecated. execute the string containing the dml code
      }
      \\tabular{lll}{
      Arguments:\\tab \\tab \\cr
      \\tab dml_script \\tab string containing the dml script whose variables has been bound using registerInput and registerOut \\cr
      \\tab rdd_or_df \\tab SparkR:::RDD rdd class which need to be attached\\cr
      \\tab mc \\tab \\link{sysml.MatrixCharacteristics} info about block matrix

      }
      '
      stopifnot(class(dml_script) == "character")
      out_jref <- SparkR:::callJMethod(env$jref, "executeScript", dml_script)
      #@TODO. get sqlContext from the ctor
      outputs <- sysml.MLOutput$new(out_jref, sqlContext)
    },

    executeScriptBase = function(dml_script, arg_keys, arg_vals, is.file) {
      '\\tabular{ll}{
      Description:\\tab \\cr
      \\tab execute the string containing the dml code
      }
      \\tabular{lll}{
      Arguments:\\tab \\tab \\cr
      \\tab dml_script \\tab string containing the dml script whose variables has been bound using registerInput and registerOut \\cr
      }
      '
      #DEBUG browser()
      stopifnot(class(dml_script) == "character")

      is_namedargs = FALSE
      if (!missing(arg_keys) && !missing(arg_vals)) {
        stopifnot(length(arg_keys) == length(arg_vals))
        if (length(arg_keys) > 0) {
          is_namedargs = TRUE
        }
      }
      # create keys
      jarg_keys <- java.ArrayList$new()
      if (!missing(arg_keys)) {
        sapply(arg_keys, function (e) {
          jarg_keys$add(e)
        })
      }

      #create vals
      jarg_vals <- java.ArrayList$new()
      if (!missing(arg_vals)) {
        sapply(arg_vals, function (e) {
          jarg_vals$add(e)
        })
      }
      #DEBUG browser()
      out_jref <- NULL
      if (is.file) {
        if (is_namedargs) {
          out_jref <- SparkR:::callJMethod(
                        env$jref, "execute",
                        dml_script,
                        jarg_keys$env$jref,
                        jarg_vals$env$jref
                      )
        } else {
          out_jref <- SparkR:::callJMethod(
                        env$jref, "execute",
                        dml_script
                      )
        }
      } else {
        if (is_namedargs) {
          out_jref <- SparkR:::callJMethod(
                        env$jref, "executeScript",
                        dml_script,
                        jarg_keys$env$jref,
                        jarg_vals$env$jref
                       )
        } else {
          out_jref <- SparkR:::callJMethod(
                        env$jref, "executeScript",
                        dml_script
                      )
        }
      }
      #@TODO. get sqlContext from the ctor
      outputs <- sysml.MLOutput$new(out_jref, sqlContext)
    },

    executeScript = function(dml_script, arg_keys, arg_vals) {
      '\\tabular{ll}{
      Description:\\tab \\cr
      \\tab execute the string containing the dml code
      }
      \\tabular{lll}{
      Arguments:\\tab \\tab \\cr
      \\tab dml_script \\tab string containing the dml script whose variables has been bound using registerInput and registerOut \\cr
      \\tab arg_keys \\tab arguement name of the dml script\\cr
      \\tab arg_vals \\tab corresponding arguement value of the dml scripts.
      }
      '
      .self$executeScriptBase(dml_script, arg_keys, arg_vals, is.file=FALSE)
    },

    execute = function(dml_script, arg_keys, arg_vals) {
      '\\tabular{ll}{
      Description:\\tab \\cr
      \\tab execute the string containing the dml code
      }
      \\tabular{lll}{
      Arguments:\\tab \\tab \\cr
      \\tab dml_script \\tab string containing the dml script whose variables has been bound using registerInput and registerOut \\cr
      \\tab arg_keys \\tab arguement name of the dml script\\cr
      \\tab arg_vals \\tab corresponding arguement value of the dml scripts.
      }
      '
      .self$executeScriptBase(dml_script, arg_keys, arg_vals, is.file=TRUE)
    }
  )
)

#'
#' A Reference Class that represent systemML MLContext
#'
#' MLContext is the gateway to the systemML world and this class provides
#' ability of the R code to connect and use the various systemML
#' high performant distributed linear algebra library and allow use
#' to run the dml script in the R code.
#'
#' @family MLContext functions
#'
#' @field env An R environment that stores bookkeeping states of the class
#'        along with java ref corresponding to jvm
#' @export
#' @examples \dontrun{
#'    sc # the default spark context
#'    mlCtx = sysml.MLOutput$new()
#' }
sysml.MLOutput <- setRefClass("sysml.MLOutput",
  fields = list(env="environment"),
  methods = list(
    initialize = function(jref, sqlContext) {
      if (missing(sqlContext)) {
        sqlContext = get("sqlContext", .GlobalEnv)
      }
      if (missing(jref)) {
        stop("Must have jref object in the ctor of MLOutput")
      }
      env <<- new.env()
      env$jref <<- jref
      env$sqlContext <<- sqlContext
    },

    finalize = function() {
      SparkR:::cleanup.jobj(env$jref)
    },

    getDF = function(colname, drop.id = TRUE) {
      '\\tabular{ll}{
      Description:\\tab \\cr
      \\tab get the sparkR dataframe from MLOutput \\cr
      \\tab drop.id (default = TRUE) whether to drop internal columns ID\\cr
      }'
      stopifnot(class(colname) == "character")
      df_jref <- SparkR:::callJMethod(env$jref, "getDF", env$sqlContext, colname)
      df <- new("DataFrame", sdf=df_jref, isCached=FALSE)
      # drop the id,
      # rename the remaining column to 'colname'
      oldnames <- SparkR:::colnames(df)
      no_ids <- oldnames[oldnames != "ID"]
      df_noid <- SparkR:::select(df, no_ids)
      newnames <- as.vector(sapply(no_ids, function(x) colname))
      SparkR:::colnames(df_noid) <- newnames
      df_noid

    }
  )
)

#'
#' A Reference Class that represent systemML RDDConverterUtils and RDDConverterUtilsExt
#'
#' RDDConvertUtils lets one transform various RDD related info into the systemML internals
#' BinaryBlockRDD
#'
#' @family MLContext functions
#'
#' @field env An R environment that stores bookkeeping states of the class
#'        along with java ref corresponding to jvm
#' @export
#' @examples
#' \dontrun{
#'    sc # the default spark context
#'    air_dist <- createDataFrame(sqlContext, airrtd)
#'    x_cnt <- SparkR:::count(air_dist)
#'    x_mc <- HydraR:::sysml.MatrixCharacteristics$new(x_cnt, 1, 10, 1)
#'    rdd_utils <- HydraR:::sysml.RDDConverterUtils$new(sc)
#'    x_rdd <- rdd_utils$dataFrameToBinaryBlock(air_dist, X_mc)
#' }
#'
sysml.RDDConverterUtils <- setRefClass("sysml.RDDConverterUtils",
  fields = list(env="environment"),
  methods = list(
    initialize = function(sparkContext) {
      if (missing(sparkContext)) {
        sparkContext = get("sc", .GlobalEnv)
      }
      env <<- new.env()
      env$sparkContext <<- sparkContext
      env$jclass <<- "org.apache.sysml.runtime.instructions.spark.utils.RDDConverterUtilsExt"
    },

    finalize = function() {
      rm(list = ls(envir = env), envir = env)
    },

    stringDataFrameToVectorDataFrame = function(df) {
      '\\tabular{ll}{
         Description:\\tab \\cr
         \\tab convert the string dataframe the mllib.Vector dataframe. The supported formats are for the following formats
             ((1.2,4.3, 3.4))  or (1.2, 3.4, 2.2) or (1.2 3.4)
             [[1.2,34.3, 1.2, 1.2]] or [1.2, 3.4] or [1.3 1.2]
\\cr
      }'
      stopifnot(class(df) == "DataFrame")
      fname <- "stringDataFrameToVectorDataFrame"
      vdf_jref<-SparkR:::callJStatic(env$jclass, fname, env$sparkContext, df@sdf)
      vdf <- new ("DataFrame", vdf_jref, FALSE)
      vdf
    },

    vectorDataFrameToBinaryBlock = function(df, mc, colname, id = FALSE) {
      '\\tabular{ll}{
      Description:\\tab \\cr
      \\tab convert the mllib.Vector dataframe to systemML binary block.\\cr
      }'
      stopifnot(class(df) == "DataFrame",
                class(mc) == "sysml.MatrixCharacteristics",
                class(colname) == "character")

      fname <- "vectorDataFrameToBinaryBlock"
      vdf_jref<-SparkR:::callJStatic(env$jclass, fname, env$sparkContext, df@sdf, mc$env$jref, id, colname)
      vdf <- SparkR:::RDD(vdf_jref)
      vdf
    },

    dataFrameToBinaryBlock = function(df, mc, id = FALSE) {
      '\\tabular{ll}{
        Description:\\tab \\cr
        \\tab convert the spark dataframe to systemML binary block.\\cr
      }'
      # args checking
      stopifnot(class(df) == "hydrar.matrix",
                class(mc) == "sysml.MatrixCharacteristics")
      fname <- "dataFrameToBinaryBlock"
      vdf_jref<-SparkR:::callJStatic(env$jclass, fname, env$sparkContext, df@sdf, mc$env$jref, id)
      vdf_jref
      # @NOTE causing issues so remove it and hack around
      # vdf <- SparkR:::RDD(vdf_jref)
      # vdf
    }
  )
)

#' @title An interface to execute dml via the Hydra.matrix and SystemML
#' @description execute the dml code or script via the systemML library
#' @name sysml.execute
#' @param dml a string containing dml code or the file containing dml code
#' @return a named list containing hydrar.matrix for each output
#' @export
#' @examples \dontrun{
#'
#'}
#'
sysml.execute <- function(dml, ...) {
  log_source <- "sysml.execute"
  if (missing(dml)) {
    hydrar.err(log_source, "Must have the dml file or script")
  }
  # extract the DML code to be run
  # note dml can be file or string.
  # we check if it ends with .dml and doesn't contains new line then it must be
  # a dml script else it is a string
  is.file <- FALSE
  dml_code <- dml
  if (regexpr('\\.dml$', dml) > 0 && regexpr('\\n', dml)) {
    if (file.exists(dml)) {
      is.file <- TRUE
    } else {
      dml = file.path(hydrar.env$SYSML_ALGO_ROOT(), dml)
      if (file.exists(dml)) {
        is.file <- TRUE
      } else {
        hydrar.err(log_source, dml %++% " file doesn't exists")
      }
    }
  }

  # extract the arguement which are non hydrar.frame
  ml_ctx = sysml.MLContext$new()
  ml_ctx$reset()
  dml_arg_keys <- c()
  dml_arg_vals <- c()
  out_args <- c()
  if (!missing(...)) {
    args <- list(...)
    rdd_utils<- HydraR:::sysml.RDDConverterUtils$new()
    arg_names <- names(args)
    i = 1
    for (arg_val in args) {
      arg_name <- arg_names[i]
      i <- i + 1
      if (class(arg_val) == "hydrar.matrix") {
        hm = arg_val
        # now v is the numeric dataframe
        #find the characteristics of the dataframe
        hm_nrows <- length(SparkR:::count(hm))
        hm_ncols <- length(SparkR:::colnames(hm))
        bm_nrows <- min(hm_nrows, hydrar.env$SYSML_BLOCK_MATRIX_SIZE$nrows)
        bm_ncols <- min(hm_ncols,  hydrar.env$SYSML_BLOCK_MATRIX_SIZE$ncols)
        mc = sysml.MatrixCharacteristics(hm_nrows, hm_ncols, bm_nrows, bm_ncols)
        hm_jrdd <- rdd_utils$dataFrameToBinaryBlock(hm, mc)
        ml_ctx$registerInput(arg_name, hm_jrdd, mc)
      } else if (is.null(arg_name) || arg_name == "") {
        ml_ctx$registerOutput(arg_val)
        out_args <- c(out_args, arg_val)
      } else {
        # it is the normal argument and pass in as the parameter to the dml
        dml_arg_keys <- c(dml_arg_keys, as.character(arg_name))
        dml_arg_vals <- c(dml_arg_vals, as.character(arg_val))
      }
    }
  }
  #execute the scripts
  sysml_outs <- if (is.file) {
    ml_ctx$execute(dml_code, dml_arg_keys, dml_arg_vals)
  } else {
    ml_ctx$executeScript(dml_code, dml_arg_keys, dml_arg_vals)
  }
  # get the output and returns
  outputs <- list()
  for (out_arg in out_args) {
    out_df <- sysml_outs$getDF(out_arg)
    out_hm <- as.hydrar.matrix(as.hydrar.frame(out_df))
    outputs[out_arg] <- out_hm
  }
  outputs
}