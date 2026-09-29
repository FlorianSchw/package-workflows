# Whether a function works on DataSHIELD connections: it takes the
# conventional `datasources` argument, calls a datashield.*() function
# (DSI) or a ds.*() client function (e.g. dsBaseClient, on the default
# connections). Decides per function in utility packages, which mix such
# functions with purely local ones, whether DSLite tests and the demo login
# example apply.
uses_ds_connections <- function(parsed) {
  "datasources" %in% parsed$params ||
    grepl("\\b(datashield|ds)\\.[A-Za-z0-9_.]+\\s*\\(", fn_source(parsed))
}
