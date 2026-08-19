// Builds an Intl.DateTimeFormat that renders a time zone name, falling back
// across the representations browsers support inconsistently.
export function buildTimeZoneNameFormatter(locale, baseOptions = {}) {
  for (const timeZoneName of ["shortOffset", "short"]) {
    try {
      return new Intl.DateTimeFormat(locale, { ...baseOptions, timeZoneName })
    } catch (_error) {
      // Try the next supported timezone-name representation.
    }
  }

  return null
}
