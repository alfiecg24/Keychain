//
//  SoftwareVersion.swift
//  Keychain
//
//  Created by Alfie on 28/10/2022.
//

import Foundation
import SwiftSoup
import Darwin

enum KeyTypes {
    case iv
    case key
    case kbag
    case unknown
}

func getKeyType(id: String) -> KeyTypes {
    if id.hasSuffix("iv") {
        return .iv
    } else if id.hasSuffix("key") {
        return .key
    } else if id.hasSuffix("kbag") {
        return .kbag
    } else {
        return .unknown
    }
}

struct FirmwareKey {
    var imageName: String
    var value: String
    var type: KeyTypes
}

struct SoftwareImage {
    var name: String
    var id: String
}

@discardableResult // Add to suppress warnings when you don't want/need a result
func runShellCommand(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh") //<--updated
    task.standardInput = nil

    try task.run() //<--updated
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    
    return output
}

func getPZBPath() -> String {
    do {
        var path = try runShellCommand("export PATH=\"/usr/local/bin:$PATH\"; which pzb")
        if path.contains("not found") {
            print("pzb command not found. Please ensure the binary is in /usr/local/bin and try again")
        } else {
            path.removeLast()
            return path
        }
    } catch {
        print("Error getting pzb path")
    }
    return ""
}

struct SoftwareVersion {
    var version: String
    var deviceIdentifier: String
    
    func fetchIPSWURL() {
        let url = "https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw"
        var data: [String: Any]
        do {
            data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(string: url)!), options: .mutableContainers) as! [String: Any]
        } catch {
            print("Could not fetch data from API. Probably an internet issue. 1")
            exit(1)
        }
        var ipswUrl = ""
        for x in data["firmwares"] as! [[String: Any]] {
            if x["version"] as! String == self.version {
                ipswUrl = x["url"] as! String
            }
        }
        guard ipswUrl != "" else {
            print("ERROR: could not fetch IPSW URL")
            exit(1)
        }
        print(ipswUrl)
    }
    
    func fetchAndParseBuildManifest() -> [String: Any] {
        let url = "https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw"
        var data: [String: Any]
        do {
            data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(string: url)!), options: .mutableContainers) as! [String: Any]
        } catch {
            print("Could not fetch data from API. Probably an internet issue. 1")
            exit(1)
        }
        var ipswUrl = ""
        for x in data["firmwares"] as! [[String: Any]] {
            if x["version"] as! String == self.version {
                ipswUrl = x["url"] as! String
            }
        }
        let path = getPZBPath()
        if path == "" {
            print("pzb not found. Please make sure binary is inside /usr/local/bin")
            exit(1)
        }
        let buildManifestName = "BuildManifest.plist"
        do {
            try runShellCommand("\(path) -g \(buildManifestName) \(ipswUrl)")
        } catch {
            print("Error with pzb")
            exit(1)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: buildManifestName))
            let buildManifest = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
            return buildManifest
        } catch {
            print("Error: could not read BuildManifest.plist")
            exit(1)
        }
    }

    func fetchBuildTrain() -> String {
        let result: [String : Any] = fetchAndParseBuildManifest()
        let identity: [[String : Any]] = result["BuildIdentities"] as! [[String : Any]]
        let identityFirst = identity[0]
        let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
        return info["BuildTrain"] as! String
    }

    func fetchBuildNumber() -> String {
        let result: [String : Any] = fetchAndParseBuildManifest()
        let identity: [[String : Any]] = result["BuildIdentities"] as! [[String : Any]]
        let identityFirst = identity[0]
        let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
        return info["BuildNumber"] as! String
    }
    
    func checkIfVersionExists() -> Bool {
        let url = "https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw"
        var data: [String: Any]
        do {
            data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(string: url)!), options: .mutableContainers) as! [String: Any]
        } catch {
            return false
        }
        for x in data["firmwares"] as! [[String: Any]] {
            if x["version"] as! String == self.version {
                return true
            }
        }
        return false
    }
    
    
    
    func fetchFirmwareKeys() -> [FirmwareKey] {
        if !checkIfVersionExists() {
            print("ERROR: it looks like this device/version combination doesn't exist.")
            exit(1)
        }
        // Create URL of correct webpage
        let baseURL = "https://www.theiphonewiki.com"
        var keysURL = "/wiki/\(fetchBuildTrain())_\(fetchBuildNumber())_(\(self.deviceIdentifier))"
        keysURL = baseURL + keysURL
        var webPage = ""
        // Fetch HTML of webpage
        do {
            webPage = try String(contentsOf: URL(string: keysURL)!)
        } catch {
            print("Could not fetch API data. Probably an internet connection issue. 3")
            exit(1)
        }
        if webPage == "" {
            print("Error fetching firmware keys, request returned nothing!")
            exit(1)
        }
        do {
            let document: Document = try SwiftSoup.parse(webPage)
            let headers = try document.select("span")
            var allImages = [SoftwareImage]()
            var isDoingName = true
            var tempName = ""
            for header in headers {
                var value = header.id()
                if value != "" {
                    if isDoingName {
                        if !value.contains("keypage") {
                            tempName = value
                            isDoingName.toggle()
                        }
                    } else {
                        if value.contains("keypage") {
                            value = value.replacingOccurrences(of: "keypage-", with: "")
                            let nonImageItems = ["version", "build", "codename", "device", "baseband", "download"]
                            if !nonImageItems.contains(value) {
                                allImages.append(SoftwareImage(name: tempName, id: value))
                            }
                            isDoingName.toggle()
                        }
                    }
                    
                }
            }
            var allKeys = [FirmwareKey]()
            let codes = try document.select("code")
            for code in codes {
                let id = code.id()
                let text = try code.text()
                for image in allImages {
                    if id.contains(image.id) {
                        var imageName = ""
                        for firmwareImage in allImages {
                            if id.contains(firmwareImage.id) {
                                imageName = image.name
                            }
                        }
                        let key = FirmwareKey(imageName: imageName, value: text, type: getKeyType(id: id))
                        allKeys.append(key)
                    }
                }
            }
            return allKeys
        } catch {
            print("Could not parse HTML")
            exit(1)
        }
    }
}
