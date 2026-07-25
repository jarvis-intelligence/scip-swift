import ArgumentParser

/// Debug vs. release build configuration, forwarded to the underlying build tool.
enum BuildConfiguration: String, CaseIterable, ExpressibleByArgument {
  case debug
  case release
}
