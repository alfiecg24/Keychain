//
//  Modules.swift
//  Keychain
//
//  Created by Alfie on 29/10/2022.
//

import Foundation

func input(_ prompt: String) -> String {
    print(prompt, terminator: "")
    return readLine()!
}

class URLModule: CommandLineModule {
    static var name = "url"
    
    static var description = "Fetch the IPSW URL for the specified device and version"
    
    static var requiredArguments = [
        CommandLineArgument(shortVersion: "-d", longVersion: "--device", description: "The device to fetch the URL for (e.g. iPhone12,1)", type: .String),
        CommandLineArgument(shortVersion: "-s", longVersion: "--software", description: "The version to fetch the URL for (e.g. 14.0)", type: .String)
    ]
    
    static var optionalArguments = [CommandLineArgument]()
    
    static func main(arguments: ParsedArguments) -> Never {
        var deviceVersion = ""
        var deviceIdentifier = ""
        for i in arguments.requiredArguments {
            if i.shortVersion == "-d" {
                deviceIdentifier = i.value as! String
            }
            if i.shortVersion == "-s" {
                deviceVersion = i.value as! String
            }
        }
        guard deviceVersion != "" && deviceIdentifier != "" else {
            print("ERROR: invalid command line arguments")
            exit(1)
        }
        let Software = SoftwareVersion(version: deviceVersion, deviceIdentifier: deviceIdentifier)
        Software.fetchIPSWURL()
        exit(0)
    }
    
    
}


class KeysModule: CommandLineModule {
    static var description = "Fetch the firmware keys for the specified device and version"
    
    static var requiredArguments = [
        CommandLineArgument(shortVersion: "-d", longVersion: "--device", description: "The device to fetch firmware keys for (e.g. iPhone12,1)", type: .String),
        CommandLineArgument(shortVersion: "-s", longVersion: "--software", description: "The version to fetch firmware keys for (e.g. 14.0)", type: .String)
    ]
    
    static var optionalArguments = [CommandLineArgument]()
    
    static func main(arguments: ParsedArguments) -> Never {
        var deviceVersion = ""
        var deviceIdentifier = ""
        for i in arguments.requiredArguments {
            if i.shortVersion == "-d" {
                deviceIdentifier = i.value as! String
            }
            if i.shortVersion == "-s" {
                deviceVersion = i.value as! String
            }
        }
        guard deviceVersion != "" && deviceIdentifier != "" else {
            print("ERROR: invalid command line arguments")
            exit(1)
        }
        let Software = SoftwareVersion(version: deviceVersion, deviceIdentifier: deviceIdentifier)
        let keys = Software.fetchFirmwareKeys()
        if keys.count == 0 {
            print("No keys were returned. This usually means that this device/version combination has no keys available.")
            exit(1)
        }
        print("\n")
        var num = 1
        var given = [String]()
        var options = [Int : String]()
        for key in keys {
            if !given.contains(key.imageName) {
                print("\(num). \(key.imageName)")
                given.append(key.imageName)
                options[num] = key.imageName
                num += 1
            }
        }
        let choice = input("\nEnter component number: ")
        let choiceNumber = Int(choice) ?? -1
        guard choiceNumber != -1 && choiceNumber <= keys.count && choiceNumber > 0 else {
            print("Invalid choice")
            exit(1)
        }

        for key in options.keys {
            if key == choiceNumber {
                let keysForComponent = keys.filter({ $0.imageName == options[choiceNumber]!})
                for item in keysForComponent {
                    switch item.type {
                    case .key:
                        print("Key: \(item.value)")
                    case .iv:
                        print("IV: \(item.value)")
                    case .kbag:
                        print("KBAG: \(item.value)")
                    case .unknown:
                        print("Unknown type: \(item.value)")
                    }
                }
            }
        }
        exit(0)
    }
    
    static var name = "keys"  
}
