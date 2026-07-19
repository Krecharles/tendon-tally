import Foundation

protocol EventTapping {
    func start()
    func stop()
    func snapshot() -> RawActivitySnapshot
    func resetCounters()
    var onPermissionOrTapFailure: ((String) -> Void)? { get set }
    var onPermissionGranted: (() -> Void)? { get set }
    var onActivity: (() -> Void)? { get set }
}

extension EventTapManager: EventTapping {}
