  import Testing
//       ^^^^^^^ reference scip-swift swift Testing 6.2.4 Testing/
  
  @testable import SchemeFixture
//                 ^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . SchemeFixture/
  @testable import SchemeFixtureExt
//                 ^^^^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixtureExt . SchemeFixtureExt/
  
  // Test-target category of the FBQ-02 corpus: exercising every fixture category from test
  // code compiles this target into the same index store (the gate builds with --build-tests),
  // so Tests/SchemeFixtureTests/SchemeFixtureTests.swift is an indexed document too.
  
  @Suite("SchemeFixture exercises every category end-to-end")
//^ reference scip-swift swift Testing 6.2.4 Testing/
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0049$s18SchemeFixtureTestsAA5SuitefMm_4__$fMu__GpHDGbO19__testContentRecords6UInt32V4kind_AG9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//  kind Getter
//  display_name static SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAA5SuitefMm_4__🟡$fMu_.__testContentRecord.getter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//  signature_documentation
//  > static func getter:__testContentRecord
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0049$s18SchemeFixtureTestsAA5SuitefMm_4__$fMu__GpHDGbO19__testContentRecords6UInt32V4kind_AG9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//  kind StaticProperty
//  display_name static SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAA5SuitefMm_4__🟡$fMu_.__testContentRecord : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//  signature_documentation
//  > static var __testContentRecord
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0049$s18SchemeFixtureTestsAA5SuitefMm_4__$fMu__GpHDGbO`.
//  kind Enum
//  display_name SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAA5SuitefMm_4__🟡$fMu_
//  signature_documentation
//  > enum $s18SchemeFixtureTestsAA5SuitefMm_4__🟡$fMu_
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC25AA5SuitefMm_8accessorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvgZ`.
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC25AA5SuitefMm_8accessorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvgZ`.
//  kind Getter
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).getter : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//  signature_documentation
//  > static func getter:$s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC25AA5SuitefMm_8accessorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvpZ`.
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC25AA5SuitefMm_8accessorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvpZ`.
//  kind StaticProperty
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61) : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//  signature_documentation
//  > static var $s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC25AA5SuitefMm_8accessorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvsZ`.
//  kind Setter
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).setter : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//  signature_documentation
//  > static func setter:$s18SchemeFixtureTestsAA5SuitefMm_8accessorfMu_
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC26AA5SuitefMm_9generatorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LL7Testing4TestVyYaYbFZ`.
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC26AA5SuitefMm_9generatorfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LL7Testing4TestVyYaYbFZ`.
//  kind StaticMethod
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_9generatorfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61)@Sendable () async -> Testing.Test
//  signature_documentation
//  > static func $s18SchemeFixtureTestsAA5SuitefMm_9generatorfMu_()
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC35AA5SuitefMm_17testContentRecordfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC35AA5SuitefMm_17testContentRecordfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//  kind Getter
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).getter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//  signature_documentation
//  > static func getter:$s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC35AA5SuitefMm_17testContentRecordfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC35AA5SuitefMm_17testContentRecordfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//  kind StaticProperty
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61) : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//  signature_documentation
//  > static var $s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_
//^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC35AA5SuitefMm_17testContentRecordfMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvsZ`.
//  kind Setter
//  display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).setter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//  signature_documentation
//  > static func setter:$s18SchemeFixtureTestsAA5SuitefMm_17testContentRecordfMu_
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV`.
//^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//^ reference scip-swift swiftpm Testing . SourceLocation#
//^ reference scip-swift swiftpm Testing . SourceLocation#init().
//^ reference scip-swift swiftpm Testing . Test#
//^ reference scip-swift swiftpm Testing . __TestContentRecordContainer#
// ^^^^^ reference scip-swift swiftpm Testing . Suite!
  struct SchemeFixtureTests {
//       ^^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAVABycfc`.
//                          kind Constructor
//                          display_name SchemeFixtureTests.SchemeFixtureTests.init() -> SchemeFixtureTests.SchemeFixtureTests
//                          signature_documentation
//                          > init init()
//       ^^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV`.
//                          kind Struct
//                          display_name SchemeFixtureTests.SchemeFixtureTests
//                          signature_documentation
//                          > struct SchemeFixtureTests
    @Test("overloads, operators, extensions, and Unicode identifiers behave")
//  ^ reference scip-swift swift Swift 6.2.4 Void#
//  ^ reference scip-swift swift Testing 6.2.4 Testing/
//  ^ reference scip-swift swift _Concurrency 6.2.4 _Concurrency/
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0086$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__$b98945a684f99f28fMu__izJCFfO19__testContentRecords6UInt32V4kind_AG9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//    kind Getter
//    display_name static SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__🟡$b98945a684f99f28fMu_.__testContentRecord.getter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//    signature_documentation
//    > static func getter:__testContentRecord
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0086$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__$b98945a684f99f28fMu__izJCFfO19__testContentRecords6UInt32V4kind_AG9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//    kind StaticProperty
//    display_name static SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__🟡$b98945a684f99f28fMu_.__testContentRecord : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//    signature_documentation
//    > static var __testContentRecord
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV0086$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__$b98945a684f99f28fMu__izJCFfO`.
//    kind Enum
//    display_name SchemeFixtureTests.SchemeFixtureTests.$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__🟡$b98945a684f99f28fMu_
//    signature_documentation
//    > enum $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_20__🟡$b98945a684f99f28fMu_
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC54AAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLyyYaYbKFZ0dabcefgH14_7__localfMu0_L_yyScA_pSgYiYaYbKF1_L_AFvp`.
//    kind Parameter
//    display_name _ #1 : Swift.Actor? in $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_7__localfMu0_ #1 @Sendable (isolated Swift.Actor?) async throws -> () in static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61)@Sendable () async throws -> ()
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC54AAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLyyYaYbKFZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC54AAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLyyYaYbKFZ`.
//    kind StaticMethod
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61)@Sendable () async throws -> ()
//    signature_documentation
//    > static func $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_16b98945a684f99f28fMu_()
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC62AAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvgZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC62AAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvgZ`.
//    kind Getter
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).getter : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//    signature_documentation
//    > static func getter:$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC62AAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvpZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC62AAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvpZ`.
//    kind StaticProperty
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61) : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//    signature_documentation
//    > static var $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC62AAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLySbSv_S2VSgSutXCvsZ`.
//    kind Setter
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).setter : @convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool
//    signature_documentation
//    > static func setter:$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_24accessorb98945a684f99f28fMu_
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC63AAV18exerciseCategories4TestfMp_25generatorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LL7Testing4TestVyYaYbFZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC63AAV18exerciseCategories4TestfMp_25generatorb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LL7Testing4TestVyYaYbFZ`.
//    kind StaticMethod
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_25generatorb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61)@Sendable () async -> Testing.Test
//    signature_documentation
//    > static func $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_25generatorb98945a684f99f28fMu_()
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC71AAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC71AAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvgZ`.
//    kind Getter
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).getter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//    signature_documentation
//    > static func getter:$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC71AAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC71AAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvpZ`.
//    kind StaticProperty
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61) : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//    signature_documentation
//    > static var $s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_
//  ^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV04$s18abC71AAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_33_CB367A20D500AA4CD95DF30D62A4EC61LLs6UInt32V4kind_AF9reserved1SbSv_S2VSgSutXCSg8accessorSu7contextSu9reserved2tvsZ`.
//    kind Setter
//    display_name static SchemeFixtureTests.SchemeFixtureTests.($s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_ in _CB367A20D500AA4CD95DF30D62A4EC61).setter : (kind: Swift.UInt32, reserved1: Swift.UInt32, accessor: (@convention(c) (Swift.UnsafeMutableRawPointer, Swift.UnsafeRawPointer, Swift.UnsafeRawPointer?, Swift.UInt) -> Swift.Bool)?, context: Swift.UInt, reserved2: Swift.UInt)
//    signature_documentation
//    > static func setter:$s18SchemeFixtureTestsAAV18exerciseCategories4TestfMp_33testContentRecordb98945a684f99f28fMu_
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV18exerciseCategoriesyyF`.
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAVABycfc`.
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV`.
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:ScA`.
//  ^ reference scip-swift swiftpm Testing . SourceLocation#
//  ^ reference scip-swift swiftpm Testing . SourceLocation#init().
//  ^ reference scip-swift swiftpm Testing . Test#
//  ^ reference scip-swift swiftpm Testing . __TestContentRecordContainer#
//   ^^^^ reference scip-swift swiftpm Testing . Test!
    func exerciseCategories() {
//       ^^^^^^^^^^^^^^^^^^ definition scip-swift swiftpm SchemeFixtureTests . `s:18SchemeFixtureTestsAAV18exerciseCategoriesyyF`.
//                          kind Method
//                          display_name SchemeFixtureTests.SchemeFixtureTests.exerciseCategories() -> ()
//                          signature_documentation
//                          > func exerciseCategories()
      let vector = Vec(x: 1, y: 2)
//                 ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                 ^^^ reference scip-swift swiftpm SchemeFixture . Vec#init().
      let scalar = Vec(scalar: 3)
//                 ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                 ^^^ reference scip-swift swiftpm SchemeFixture . Vec#init(+1).
  
      #expect(vector + scalar == Vec(x: 4, y: 5))
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#+().
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#`==`().
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#init().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                   ^ reference scip-swift swiftpm SchemeFixture . Vec#+().
//                            ^^ reference scip-swift swiftpm SchemeFixture . Vec#`==`().
//                               ^^^ reference scip-swift swiftpm SchemeFixture . Vec#
//                               ^^^ reference scip-swift swiftpm SchemeFixture . Vec#init().
      #expect(parse("7") == 7)
//    ^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . parse().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^ reference scip-swift swiftpm SchemeFixture . parse().
//                       ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
      #expect(parse(7) == "7")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . parse(+1).
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^ reference scip-swift swiftpm SchemeFixture . parse(+1).
//                     ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
      #expect(vector.length() > 0)
//    ^ reference scip-swift swift Swift 6.2.4 Comparable#`>`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#length().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                   ^^^^^^ reference scip-swift swiftpm SchemeFixture . Vec#length().
//                            ^ reference scip-swift swift Swift 6.2.4 Comparable#`>`().
      #expect(vector.manhattanLength == 3)
//    ^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#manhattanLength().
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#manhattanLength.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                   ^^^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Vec#manhattanLength().
//                   ^^^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Vec#manhattanLength.
//                                   ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
      #expect(Box(content: vector).describe() == "box")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Box#
//    ^ reference scip-swift swiftpm SchemeFixture . Box#describe().
//    ^ reference scip-swift swiftpm SchemeFixture . Box#init().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^ reference scip-swift swiftpm SchemeFixture . Box#
//            ^^^ reference scip-swift swiftpm SchemeFixture . Box#init().
//                                 ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#describe().
//                                            ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
      #expect(Box(content: vector).unwrap() == vector)
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Box#
//    ^ reference scip-swift swiftpm SchemeFixture . Box#init().
//    ^ reference scip-swift swiftpm SchemeFixture . Box#unwrap().
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#`==`().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^ reference scip-swift swiftpm SchemeFixture . Box#
//            ^^^ reference scip-swift swiftpm SchemeFixture . Box#init().
//                                 ^^^^^^ reference scip-swift swiftpm SchemeFixture . Box#unwrap().
//                                          ^^ reference scip-swift swiftpm SchemeFixture . Vec#`==`().
      #expect("hey".schemeShout() == "HEY!")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Swift 6.2.4 String#schemeShout().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                  ^^^^^^^^^^^ reference scip-swift swift Swift 6.2.4 String#schemeShout().
//                                ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
      #expect(vector[0] == 1)
//    ^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:13SchemeFixture3VecVyS2icig`.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:13SchemeFixture3VecVyS2icip`.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:13SchemeFixture3VecVyS2icig`.
//                  ^ reference scip-swift swiftpm SchemeFixtureTests . `s:13SchemeFixture3VecVyS2icip`.
//                      ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
      #expect(conditionallyCompiled())
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . conditionallyCompiled().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^^^^^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . conditionallyCompiled().
      #expect(Spectrum.red != Spectrum.blue)
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Spectrum#
//    ^ reference scip-swift swiftpm SchemeFixture . Spectrum#blue.
//    ^ reference scip-swift swiftpm SchemeFixture . Spectrum#red.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:SQsE2neoiySbx_xtFZ`.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Spectrum#
//                     ^^^ reference scip-swift swiftpm SchemeFixture . Spectrum#red.
//                         ^^ reference scip-swift swiftpm SchemeFixtureTests . `s:SQsE2neoiySbx_xtFZ`.
//                            ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Spectrum#
//                                     ^^^^ reference scip-swift swiftpm SchemeFixture . Spectrum#blue.
  
      let poster = Poster()
//                 ^^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#
//                 ^^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#init().
      poster.label = "demo"
//           ^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#`label=`().
//           ^^^^^ reference scip-swift swiftpm SchemeFixture . Poster#label.
      #expect(poster.draw() == "poster(demo)")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Poster#draw().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                   ^^^^ reference scip-swift swiftpm SchemeFixture . Poster#draw().
//                          ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
  
      let observed = Observed()
//                   ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#
//                   ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#init().
      observed.computed = 5
//             ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#`computed=`().
//             ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#computed.
      observed.watched = 6
//             ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#`watched=`().
//             ^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#watched.
      #expect(observed.computed == 5 && observed.prepared)
//    ^ reference scip-swift swift Swift 6.2.4 Bool#`&&`().
//    ^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Observed#computed().
//    ^ reference scip-swift swiftpm SchemeFixture . Observed#computed.
//    ^ reference scip-swift swiftpm SchemeFixture . Observed#prepared().
//    ^ reference scip-swift swiftpm SchemeFixture . Observed#prepared.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                     ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#computed().
//                     ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#computed.
//                              ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//                                   ^^ reference scip-swift swift Swift 6.2.4 Bool#`&&`().
//                                               ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#prepared().
//                                               ^^^^^^^^ reference scip-swift swiftpm SchemeFixture . Observed#prepared.
  
      #expect(🚀 == "rocket")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . `🚀`().
//    ^ reference scip-swift swiftpm SchemeFixture . `🚀`.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^ reference scip-swift swiftpm SchemeFixture . `🚀`().
//            ^^^^ reference scip-swift swiftpm SchemeFixture . `🚀`.
//                 ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
      #expect(名前を付ける() == "名前")
//    ^ reference scip-swift swift Swift 6.2.4 String#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . `名前を付ける`().
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^^^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . `名前を付ける`().
//                                 ^^ reference scip-swift swift Swift 6.2.4 String#`==`().
      #expect(flagSequence.contains("🇻🇳"))
//    ^ reference scip-swift swift Swift 6.2.4 StringProtocol#contains().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . flagSequence().
//    ^ reference scip-swift swiftpm SchemeFixture . flagSequence.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//            ^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . flagSequence().
//            ^^^^^^^^^^^^ reference scip-swift swiftpm SchemeFixture . flagSequence.
//                         ^^^^^^^^ reference scip-swift swift Swift 6.2.4 StringProtocol#contains().
  
      let point: Point = vector
//               ^^^^^ reference scip-swift swiftpm SchemeFixture . Point#
      #expect(point.x == 1)
//    ^ reference scip-swift swift Swift 6.2.4 Int#`==`().
//    ^ reference scip-swift swift Testing 6.2.4 Testing/
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//    ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//    ^ reference scip-swift swiftpm SchemeFixtureTests . `s:Sa12arrayLiteralSayxGxd_tcfc`.
//    ^ reference scip-swift swiftpm Testing . SourceLocation#
//     ^^^^^^ reference scip-swift swiftpm Testing . expect!
//                  ^ reference scip-swift swiftpm SchemeFixture . Vec#x().
//                  ^ reference scip-swift swiftpm SchemeFixture . Vec#x.
//                    ^^ reference scip-swift swift Swift 6.2.4 Int#`==`().
    }
  }
  
