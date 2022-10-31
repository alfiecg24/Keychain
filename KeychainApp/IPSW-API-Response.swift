// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let iPSWAPIResponse = try? newJSONDecoder().decode(IPSWAPIResponse.self, from: jsonData)

//
// To read values from URLs:
//
//   let task = URLSession.shared.iPSWAPIResponseTask(with: url) { iPSWAPIResponse, response, error in
//     if let iPSWAPIResponse = iPSWAPIResponse {
//       ...
//     }
//   }
//   task.resume()

import Foundation

// MARK: - IPSWAPIResponse
struct IPSWAPIResponse: Codable {
    let name: String
    let identifier: String
    let firmwares: [Firmware]
    let boards: [Board]
    let boardconfig, platform: String
    let cpid, bdid: Int
}

// MARK: - Board
struct Board: Codable {
    let boardconfig, platform: String
    let cpid, bdid: Int
}

// MARK: - Firmware
struct Firmware: Codable {
    let identifier: String
    let version, buildid, sha1Sum, md5Sum: String
    let sha256Sum: String
    let filesize: Int
    let url: String
    let releasedate, uploaddate: Date
    let signed: Bool

    enum CodingKeys: String, CodingKey {
        case identifier, version, buildid
        case sha1Sum
        case md5Sum
        case sha256Sum
        case filesize, url, releasedate, uploaddate, signed
    }
}

func JSONDecoderWithDate() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}


// MARK: - URLSession response handlers

extension URLSession {
    fileprivate func codableTask<T: Codable>(with url: URL, completionHandler: @escaping (T?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return self.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completionHandler(nil, response, error)
                return
            }
            completionHandler(try? JSONDecoderWithDate().decode(T.self, from: data), response, nil)
        }
    }

    func iPSWAPIResponseTask(with url: URL, completionHandler: @escaping (IPSWAPIResponse?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return self.codableTask(with: url, completionHandler: completionHandler)
    }
}
