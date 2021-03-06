
#' Make an orderby node (not a relational operation).
#'
#' Order a table by a set of columns (not general expressions) and
#' limit number of rows in that order.
#'
#' Note: this is a relational operator in that it takes a table that
#' is a relation (has unique rows) to a table that is still a relation.
#' However, most relational systems do not preserve row order in storage or between
#' operations.  So without the limit set this is not a useful operator except
#' as a last step prior ot pulling data to an in-memory \code{data.frame} (
#' which does preserve row order).
#'
#'
#' @param source source to select from.
#' @param orderby order by column names.
#' @param ... force later arguments to be bound by name
#' @param desc logical if TRUE reverse order
#' @param limit number limit row count.
#' @return select columns node.
#'
#' @examples
#'
#' my_db <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#' d <- dbi_copy_to(my_db, 'd',
#'                 data.frame(AUC = 0.6, R2 = 0.2))
#' eqn <- orderby(d, "AUC", desc=TRUE, limit=4)
#' cat(format(eqn))
#' sql <- to_sql(eqn, my_db)
#' cat(sql)
#' DBI::dbGetQuery(my_db, sql)
#' DBI::dbDisconnect(my_db)
#'
#' @export
#'
orderby <- function(source,
                     orderby,
                     ...,
                     desc = FALSE,
                     limit = NULL) {
  if(length(list(...))>0) {
    stop("unexpected arguemnts")
  }
  if(is.data.frame(source)) {
    tmp_name <- cdata::makeTempNameGenerator("rquery_tmp")()
    dnode <- table_source(tmp_name, colnames(source))
    dnode$data <- source
    enode <- orderby(dnode,
                     orderby,
                     desc = desc,
                     limit = limit)
    return(enode)
  }
  have <- column_names(source)
  check_have_cols(have, orderby, "rquery::orderby orderby")
  r <- list(source = list(source),
            table_name = NULL,
            parsed = NULL,
            orderby = orderby,
            desc = desc,
            limit = limit)
  r <- relop_decorate("relop_orderby", r)
  r
}



#' @export
format.relop_orderby <- function(x, ...) {
  if(length(list(...))>0) {
    stop("unexpected arguemnts")
  }
  paste0(trimws(format(x$source[[1]]), which="right"),
         " %.>%\n ",
         "orderby(., ",
         ifelse(length(x$orderby)>0,
                paste(x$orderby, collapse = ", "),
                ""),
         ifelse(x$desc, ", DESC", ""),
         ifelse((length(x$limit)>0) && (length(x$orderby)>0),
                paste0(", LIMIT ", x$limit),
                ""),
         ")",
         "\n")
}



calc_used_relop_orderby <- function (x, ...,
                                      using = NULL,
                                      contract = FALSE) {
  if(length(using)<=0) {
    using <- column_names(x)
  }
  consuming <- x$orderby
  using <- unique(c(using, consuming))
  missing <- setdiff(using, column_names(x$source[[1]]))
  if(length(missing)>0) {
    stop(paste("rquery::calc_used_relop_orderby unknown columns",
               paste(missing, collapse = ", ")))
  }
  using
}

#' @export
columns_used.relop_orderby <- function (x, ...,
                                       using = NULL,
                                       contract = FALSE) {
  cols <- calc_used_relop_select_rows(x,
                                      using = using,
                                      contract = contract)
  return(columns_used(x$source[[1]],
                      using = cols,
                      contract = contract))
}


#' @export
to_sql.relop_orderby <- function (x,
                                   db,
                                   ...,
                                   source_limit = NULL,
                                   indent_level = 0,
                                   tnum = mkTempNameGenerator('tsql'),
                                   append_cr = TRUE,
                                   using = NULL) {
  if(length(list(...))>0) {
    stop("unexpected arguemnts")
  }
  cols1 <- column_names(x$source[[1]])
  cols <- vapply(cols1,
                 function(ci) {
                   quote_identifier(db, ci)
                 }, character(1))
  ot <- vapply(x$orderby,
               function(ci) {
                 quote_identifier(db, ci)
               }, character(1))
  subcols <- calc_used_relop_orderby(x, using=using)
  subsql <- to_sql(x$source[[1]],
                   db = db,
                   source_limit = source_limit,
                   indent_level = indent_level + 1,
                   tnum = tnum,
                   append_cr = FALSE,
                   using = subcols)
  tab <- tnum()
  prefix <- paste(rep(' ', indent_level), collapse = '')
  q <- paste0(prefix, "SELECT * FROM (\n",
         subsql, "\n",
         prefix, ") ",
         tab,
         ifelse(length(ot)>0,
                paste0(" ORDER BY ", paste(ot, collapse = ", ")),
                ""),
         ifelse((x$desc) && (length(ot)>0), " DESC", ""),
         ifelse(length(x$limit)>0,
                paste0(" LIMIT ", x$limit),
                ""))
  if(append_cr) {
    q <- paste0(q, "\n")
  }
  q
}
