#!/usr/bin/env bash
# Regenerates Sources/scip-swift/Generated/Scip.pb.swift from scip.proto.
#
# Requires `protoc` and `protoc-gen-swift` on PATH (brew install protobuf swift-protobuf).
# scip.proto is vendored from https://github.com/sourcegraph/scip (root-level scip.proto).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

protoc \
  --swift_out=Sources/scip-swift/Generated \
  --swift_opt=Visibility=Public \
  --proto_path=Protos \
  Protos/scip.proto

mv Sources/scip-swift/Generated/scip.pb.swift Sources/scip-swift/Generated/Scip.pb.swift
