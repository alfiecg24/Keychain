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

enum Errors: Error {
case couldNotFetchData
case couldNotDecodeData
case couldNotGetPath
case combinationDoesNotExist
case couldNotParseData
case invalidURL
case genericError
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
    
    func fetchAPIResponse(completion: @escaping (IPSWAPIResponse)->()) throws {
        guard let url = URL(string: ("https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw")) else {
            print("Invalid URL")
            throw Errors.invalidURL
        }
        
        let task = URLSession.shared.iPSWAPIResponseTask(with: url) { decodedResponse, response, error in
            if let decodedResponse = decodedResponse {
                completion(decodedResponse)
            }
        }
        task.resume()
    }
    func checkIfVersionExists() -> Bool {
        guard let url = URL(string: ("https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw")) else {
            print("Invalid URL")
            return false
        }
        print("URL: \(url)")
        
        var exists = false
        
        do {
            let response = try self.fetchAPIResponse() { APIResponse in
                for firmware in APIResponse.firmwares {
                    if firmware.version == self.version {
                        exists = true
                    }
                }
            }
        } catch { }
        return exists
    }
    
    func fetchIPSWURL() throws -> String {
        guard checkIfVersionExists() else {
            print("ERROR: device/version combination doesn't exist")
            throw Errors.combinationDoesNotExist
        }
        
        guard let url = URL(string: ("https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw")) else {
            print("Invalid URL")
            return ""
        }
        
        var ipswUrl = ""
        
        let task = URLSession.shared.iPSWAPIResponseTask(with: url) { decodedResponse, response, error in
            if let decodedResponse = decodedResponse {
                for firmware in decodedResponse.firmwares {
                    if firmware.version == self.version {
                        ipswUrl = firmware.url
                    }
                }
            }
        }
        task.resume()
        
        guard ipswUrl != "" else {
            print("ERROR: could not fetch IPSW URL")
            throw Errors.couldNotDecodeData
        }
        
        return ipswUrl
    }
    
    func fetchAndParseBuildManifest() throws -> [String: Any] {
        var ipswUrl = ""
        do {
            ipswUrl = try fetchIPSWURL()
        } catch {
            throw Errors.couldNotFetchData
        }
        guard ipswUrl != "" else {
            print("ERROR: could not fetch IPSW URL")
            throw Errors.couldNotFetchData
        }
        let path = getPZBPath()
        if path == "" {
            print("pzb not found. Please make sure binary is inside /usr/local/bin")
            throw Errors.couldNotGetPath
        }
        let buildManifestName = "BuildManifest.plist"
        do {
            try runShellCommand("\(path) -g \(buildManifestName) \(ipswUrl)")
        } catch {
            print("Error with pzb")
            throw Errors.genericError
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: buildManifestName))
            let buildManifest = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
            return buildManifest
        } catch {
            print("Error: could not read BuildManifest.plist")
            throw Errors.couldNotParseData
        }
    }

    func fetchBuildTrain() -> String {
        var result = [String : Any]()
        do {
            result = try fetchAndParseBuildManifest()
        } catch {
            return ""
        }
        let identity: [[String : Any]] = result["BuildIdentities"] as! [[String : Any]]
        let identityFirst = identity[0]
        let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
        return info["BuildTrain"] as! String
    }

    func fetchBuildNumber() -> String {
        var result = [String : Any]()
        do {
            result = try fetchAndParseBuildManifest()
        } catch {
            return ""
        }
        let identity: [[String : Any]] = result["BuildIdentities"] as! [[String : Any]]
        let identityFirst = identity[0]
        let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
        return info["BuildNumber"] as! String
    }
    
    
    
    
    func fetchFirmwareKeys() throws -> [FirmwareKey] {
        if !checkIfVersionExists() {
            print("ERROR: it looks like this device/version combination doesn't exist.")
            exit(1)
        }
        // Create URL of correct webpage
        let baseURL = "https://www.theiphonewiki.com"
        let buildTrain = fetchBuildTrain()
        let buildNumber = fetchBuildNumber()
        guard buildTrain != "" && buildNumber != "" else {
            throw Errors.couldNotFetchData
        }
        var keysURL = "/wiki/\(buildTrain)_\(buildNumber)_(\(self.deviceIdentifier))"
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
            throw Errors.couldNotParseData
        }
    }
}
