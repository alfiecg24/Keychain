//
//  SoftwareVersion.swift
//  Keychain
//
//  Created by Alfie on 28/10/2022.
//

import Foundation
import SwiftSoup
import Darwin
import Alamofire

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

enum FetchStatus {
case success
case error
}

struct SoftwareVersion {
    var version: String
    var deviceIdentifier: String
    
    func fetchAPIResponse(completion: @escaping (_: IPSWAPIResponse?, _:  FetchStatus) -> ()) {
        let url = "https://api.ipsw.me/v4/device/" + self.deviceIdentifier + "?type=ipsw"
        AF.request(url).responseDecodable(of: IPSWAPIResponse.self, decoder: JSONDecoderWithDate()) { response in
            debugPrint(response)
            if let data = response.value {
                completion(data, .success)
            }
        }
        completion(nil, .error)
    }
    
    func checkIfVersionExists(completion: @escaping (Bool) -> ()) {
        fetchAPIResponse(completion: { data, status in
            if let data = data {
                for firmware in data.firmwares {
                    if firmware.version == self.version {
                        completion(true)
                    }
                }
            }
        })
        completion(false)
    }
    
    func fetchIPSWURL(completion: @escaping (String?) -> ()) {
        checkIfVersionExists(completion: { res in
            if !res {
                print("ERROR: it looks like this device/version combination doesn't exist.")
                completion(nil)
            }
        })
        
        fetchAPIResponse(completion: { response, status in
            if status != .success { completion(nil) }
            if let response = response {
                for firmware in response.firmwares {
                    if firmware.version == self.version {
                        completion(firmware.version)
                    }
                }
            }
            
        })
    }
    
    func fetchAndParseBuildManifest(completion: @escaping (_: [String : Any], _: FetchStatus) -> ()) {
        var ipswUrl = ""
        fetchIPSWURL(completion: { url in
            if url == nil { completion([String : Any](), .error) }
            ipswUrl = url!
        })
        if ipswUrl == "" {
            print("ERROR: could not fetch IPSW URL")
            completion([String : Any](), .error)
        }
        let buildManifestURL = ipswUrl.split(separator: "/")
        print(buildManifestURL)
        let path = getPZBPath()
        if path == "" {
            print("pzb not found. Please make sure binary is inside /usr/local/bin")
            completion([String : Any](), .error)
        }
        let buildManifestName = "BuildManifest.plist"
        do {
            try runShellCommand("\(path) -g \(buildManifestName) \(ipswUrl)")
        } catch {
            print("Error with pzb")
            completion([String : Any](), .error)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: buildManifestName))
            let buildManifest = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as! [String: Any]
            completion(buildManifest, .success)
        } catch {
            print("Error: could not read BuildManifest.plist")
            completion([String : Any](), .error)
        }
    }

    func fetchBuildTrain(completion: @escaping (String?) -> ()) {
        fetchAndParseBuildManifest(completion: { manifest, status in
            if manifest.count <= 1 {
                completion(nil)
            }
            let identity: [[String : Any]] = manifest["BuildIdentities"] as! [[String : Any]]
            let identityFirst = identity[0]
            let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
            completion((info["BuildTrain"] as! String))
        })
        
    }

    func fetchBuildNumber(completion: @escaping (String?) -> ()) {
        fetchAndParseBuildManifest(completion: { manifest, status in
            if manifest.count <= 1 {
                completion(nil)
            }
            let identity: [[String : Any]] = manifest["BuildIdentities"] as! [[String : Any]]
            let identityFirst = identity[0]
            let info: [String : Any] = identityFirst["Info"]! as! [String : Any]
            completion((info["BuildNumber"] as! String))
        })
    }
    
    func fetchFirmwareKeys(completion: @escaping ([FirmwareKey]) -> ()) {
        checkIfVersionExists(completion: { res in
            if !res {
                print("ERROR: it looks like this device/version combination doesn't exist.")
                completion([FirmwareKey]())
            }
        })
        
        // Create URL of correct webpage
        let baseURL = "https://www.theiphonewiki.com"
        var buildTrain = ""
        fetchBuildTrain(completion: { train in
            if train == nil && train == "" {
                completion([FirmwareKey]())
            }
            buildTrain = train!
        })
        var buildNumber = ""
        fetchBuildNumber(completion: { number in
            if number == nil && number == "" {
                completion([FirmwareKey]())
            }
            buildNumber = number!
        })
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
            completion(allKeys)
        } catch {
            print("Could not parse HTML")
            completion([FirmwareKey]())
        }
    }
}
