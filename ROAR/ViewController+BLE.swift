//
//  ViewController+BLE.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
import CoreBluetooth
import UIKit
extension ViewController:CBCentralManagerDelegate, CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            self.logger.error("central.state is .unknown")
        case .resetting:
            self.logger.error("central.state is .resetting")
        case .unsupported:
            self.logger.error("central.state is .unsupported")
        case .unauthorized:
            self.logger.error("central.state is .unauthorized")
        case .poweredOff:
            self.logger.error("central.state is .poweredOff")
        case .poweredOn:
            self.logger.info("central.state is .poweredOn, Scanning for peripherals")
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        @unknown default:
            self.logger.error("unknown state encountered")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.identifier == AppInfo.bluetootConfigurations?.uuid{
            self.logger.info("Peripheral found \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
            self.bluetoothPeripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        self.logger.info("Connection event occured")
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        self.logger.info("Connected to \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
        self.onBLEConnected()
        AppInfo.sessionData.isBLEConnected = true
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.logger.info("failed to connect")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.logger.info("Disconnected : \(AppInfo.bluetootConfigurations?.name ?? "No Name")")
        self.onBLEDisconnected()
        AppInfo.sessionData.isBLEConnected = false
    }
    
    func startWritingToBLE() {
        DispatchQueue.global(qos: .background).async {
            self.bleTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
                    self.writeBLE()
                }
                let runLoop = RunLoop.current
                runLoop.add(self.bleTimer, forMode: .default)
                runLoop.run()
            }
    }
    func disconnectBluetooth() {
        self.bleTimer.invalidate()
        if self.bluetoothPeripheral != nil {
            self.centralManager.cancelPeripheralConnection(self.bluetoothPeripheral)
        }
    }
    
    func writeBLE() {
        if self.bluetoothPeripheral != nil && self.bluetoothPeripheral.state == .connected {
            self.writeToBluetoothDevice(throttle: CGFloat(controlCenter.control.throttle), steering: CGFloat(controlCenter.control.steering))
        }
    }
    func writeToBluetoothDevice(throttle: CGFloat, steering: CGFloat){
        let currThrottleRPM = throttle.map(from: self.iOSControllerRange, to: self.throttle_range)
        var currSteeringRPM = steering.map(from: self.iOSControllerRange, to: self.steer_range)
        
        currSteeringRPM = currSteeringRPM.clamped(to: 1000...2000)
        
        
        let message: String = "(" + String(Int(currThrottleRPM)) + "," + String(Int(currSteeringRPM)) + ")"
        print(self.bluetoothPeripheral)
        if self.bluetoothPeripheral != nil {
            sendMessage(peripheral: self.bluetoothPeripheral, message: message)
        }
    }
    
    func sendMessage(peripheral: CBPeripheral, message: String) {
        if bleControlCharacteristic != nil {
            print(message)
            peripheral.writeValue(message.data(using: .utf8)!, for: bleControlCharacteristic, type: .withoutResponse)
//            peripheral.writeValue(message.data(using: .utf8)!, for: bleControlCharacteristic, type: CBCharacteristicWriteType.withResponse)
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for char in characteristics {
                if char.uuid.uuidString == "19B10011-E8F2-537E-4F6C-D104768A1214" {
                    bleControlCharacteristic = char
                }
            }
        }
    }
    
}
