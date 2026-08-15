// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

// Static rather than the dynamic framework Tuist builds by default: the consumer is a
// command-line tool, and a bare executable has no bundle to embed a framework into. It
// would build and then fail to launch with a dyld error naming a path that never existed.
let packageSettings = PackageSettings(
    productTypes: [
        "MCP": .staticFramework,
        "Logging": .staticFramework,
        "SystemPackage": .staticFramework,
        "EventSource": .staticFramework,
    ]
)
#endif

let package = Package(
    name: "Pergamenum",
    dependencies: [
        // The only third-party dependency in the project (ADR-0007 §D2). Everything
        // else here is written by hand on purpose; a wire protocol with a published
        // schema is the one place where that would be copying, not building.
        //
        // 0.12.1, published 2026-05-07, implements spec revision 2025-11-25 while the
        // current revision is 2026-07-28. The gap is deliberate on the spec's side -
        // it keeps `server/discover` as a backward-compatibility probe over stdio - but
        // it is a 0.x dependency that lags, and that is a risk the ADR records rather
        // than hides.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ]
)
