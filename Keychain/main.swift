//
//  main.swift
//  Keychain
//
//  Created by Alfie on 28/10/2022.
//

import Foundation
import Darwin

DispatchQueue.global().async {
    parseCommandLine(modules: [
        KeysModule.self,
        URLModule.self
    ])
}

CFRunLoopRun()
