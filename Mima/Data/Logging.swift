import Foundation

func log(_ message: String) {
    #if DEBUG
        NSLog(message)
    #endif
}
