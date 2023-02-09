//
//  Logging.swift
//  Mima
//
//  Created by Paul Tsochantaris on 09/02/2023.
//

import Foundation

func log(_ message: String) {
#if DEBUG
    NSLog(message)
#endif
}
