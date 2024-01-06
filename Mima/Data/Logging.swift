import Foundation
#if DEBUG
    import OSLog
#endif

func log(_ message: @autoclosure () -> String) {
    #if DEBUG
        os_log("%{public}@", message())
    #endif
}
