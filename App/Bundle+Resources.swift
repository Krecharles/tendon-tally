import Foundation

extension Bundle {
    /// Resource location for both the Xcode app target and Swift Package builds.
    static var appResources: Bundle {
#if SWIFT_PACKAGE
        .module
#else
        .main
#endif
    }
}
