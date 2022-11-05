//
//  ContentView.swift
//  KeychainApp
//
//  Created by Alfie on 29/10/2022.
//

import SwiftUI
import Alamofire

struct InputView: View {
    @State private var hasEnteredParameters = false
    @State private var deviceIdentifier = ""
    @State private var deviceVersion = ""
    @State private var keys = [FirmwareKey]()
    var body: some View {
        if hasEnteredParameters {
            EmptyView()
        } else {
            VStack {
                TextField("Device identifier", text: $deviceIdentifier)
                TextField("Device version", text: $deviceVersion)
                Button("Submit") {
                    let Software = SoftwareVersion(version: deviceVersion, deviceIdentifier: deviceIdentifier)
                    
                    var keys = [FirmwareKey]()
                    Software.fetchFirmwareKeys(completion: { keys in
                        if keys.count <= 1 {
                            print("Error")
                        }
                    })
                    print(keys.count)
                    
                    guard !keys.isEmpty else {
                        print("Error")
                        return
                    }
                    hasEnteredParameters.toggle()
                }
            }
            .padding()
        }
    }
}

struct InputView_Previews: PreviewProvider {
    static var previews: some View {
        InputView()
    }
}
