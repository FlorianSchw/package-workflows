# The package statuses of the DataSHIELD package catalogue
# (FederatedMethods/packages), with "unknown" for packages without one.
# The settings' and the plan's package-status lists may only use these.
package_statuses <- function() {
  c("production", "development", "unknown", "retired")
}
