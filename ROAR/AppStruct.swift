//
//  AppStruct.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
struct AppInfo : Codable {
    static var sessionData: SessionData = SessionData()
    static var curr_world_name: String = "berkeley"
    static var bluetootConfigurations: BluetoothConfigurations? = nil

    static func get_ar_experience_name(name: String=AppInfo.curr_world_name) -> String{
        return "\(name)_ar_experience_data"
    }
    
    static func save() {
        UserDefaults.standard.setValue([
                                        "bluetooth_name": AppInfo.bluetootConfigurations?.name ?? "",
                                        "bluetooth_uuid": AppInfo.bluetootConfigurations?.uuid?.uuidString ?? ""],
                                       forKey: "bluetooth_data")
    }
    static func load() {
        if UserDefaults.standard.value(forKey: "bluetooth_data") != nil {
            let data =  UserDefaults.standard.value(forKey: "bluetooth_data") as! Dictionary<String, String>
            AppInfo.bluetootConfigurations = BluetoothConfigurations(name: data["bluetooth_name"], uuid: UUID(uuidString: data["bluetooth_uuid"]!))            
        }
    }
}
struct SessionData: Codable {
    /*
     Instance data. Do NOT cache or save this data. When user start the app again, this data will start from default.
     */
    var shouldCaliberate: Bool = true
    var isTracking:Bool = false
    var isCaliberated:Bool = false
    var isBLEConnected:Bool = false
    var shouldAutoDrive: Bool = false
}


struct BluetoothConfigurations: Codable {
    var name: String?;
    var uuid: UUID?;
    
    
    func describe() -> String {
        return """
                name: \(String(describing: AppInfo.bluetootConfigurations?.name))
                uuid: \(String(describing: AppInfo.bluetootConfigurations?.uuid))
                """
    }
    
}
