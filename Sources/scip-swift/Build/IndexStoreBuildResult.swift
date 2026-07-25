/// The outcome of running a build backend: where the resulting IndexStore landed on disk.
struct IndexStoreBuildResult {
  let indexStorePath: String
}

/// Something that can drive a build tool to completion and locate the IndexStore it produced.
protocol BuildRunner {
  func produceIndexStore() throws -> IndexStoreBuildResult
}
