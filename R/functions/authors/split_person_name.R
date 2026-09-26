# Splits a full name into given and family name for person(): the last
# word is the family name, together with name particles right before it
# ("Ludwig van Beethoven" -> "Ludwig" / "van Beethoven"). A one-word name
# can't be split and comes back as given name only (family NULL).
split_person_name <- function(name) {
  words <- strsplit(trimws(name), "\\s+")[[1]]
  if (length(words) < 2) return(list(given = trimws(name), family = NULL))

  particles <- c("van", "von", "de", "der", "den", "del", "della", "di", "da", "das", "dos", "du", "la", "le", "ten", "ter", "zu")
  start <- length(words)
  while (start > 2 && tolower(words[start - 1]) %in% particles) start <- start - 1

  list(
    given = paste(words[seq_len(start - 1)], collapse = " "),
    family = paste(words[start:length(words)], collapse = " ")
  )
}
