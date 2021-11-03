//
//  Server.swift
//  ROAR
//
//  Created by Michael Wu on 9/11/21.
//

import Foundation
import os
import Vapor
import Photos
import UIKit
import SwiftSocket
import Network

class CustomUDPClient {
    /*
    This class implement a custom chunking protocol for streaming large data under UDP protocol
    */
    var client: UDPClient!
    var MAX_DGRAM: Int = 9000 // for some mac, default size is 9620, make some room for header
    var num_buffer: Int = 2
    private var curr_buffer = 0
    init(address: String = "192.168.1.10", port:Int32=8001, num_buffer: Int = 2) {
        print("Starting broadcast to \(address) ")
        client = UDPClient(address: address, port: port)
        self.num_buffer = num_buffer
    }
    func restart(address: String, port: Int32){
        self.stop()
        client = UDPClient(address: address, port: port)
    }
    
    func sendData(data: Data) -> Bool {
        return self.chunkAndSendData(data: data)
    }
    
    func chunkAndSendData(data: Data) -> Bool {
        data.withUnsafeBytes{(u8Ptr: UnsafePointer<UInt8>) in
            let mutRawPointer = UnsafeMutableRawPointer(mutating: u8Ptr)
            let uploadChunkSize = self.MAX_DGRAM
            let totalSize = data.count
            var offset = 0
            var counter = 0 // Int(Float(totalSize / uploadChunkSize).rounded(.up)) + 1
            var total = Int(Float(totalSize / uploadChunkSize).rounded(.up))
//            print(totalSize, total)
            while offset < totalSize {
                var data_to_send:Data = String(counter).leftPadding(toLength: 3, withPad: "0")
                    .data(using:.ascii)!
                
                data_to_send.append(String(total).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                data_to_send.append(String(curr_buffer).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                
                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                data_to_send.append(chunk)
                self.client.send(data: data_to_send)

                offset += chunkSize
                counter += 1
            }
            curr_buffer = (curr_buffer + 1) % num_buffer
            
        }
        return true
    }
    
    func stop() {
        self.client.close()
    }
    
}

class UDPDepthClient: CustomUDPClient {
    func sendDepth(customDepth: CustomDepthData) -> Bool {
        do {
            
            var data = Data()
            withUnsafePointer(to: &customDepth.fxD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &customDepth.fyD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &customDepth.cxD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            withUnsafePointer(to: &customDepth.cyD) { data.append(UnsafeBufferPointer(start: $0, count: 1)) } // ok
            let image_data = try customDepth.circular.read()
            data.append(image_data)
            return sendData(data: data)
        } catch  {
            return false
        }
    }
}

class UDPImageClient: CustomUDPClient {
    func sendImage(customImage: CustomImage) -> Bool {
        do {
            var data = Data()
            var fx = customImage.intrinsics[0][0]
            var fy = customImage.intrinsics[1][1]
            var cx = customImage.intrinsics[2][0]
            var cy = customImage.intrinsics[2][1]

            withUnsafePointer(to: &fx) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &fy) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &cx) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            withUnsafePointer(to: &cy) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
            let image_data = try customImage.circular.read()
//            print(image_data.count)
            data.append(image_data)
            return self.sendData(data: data)
        } catch  {
            return false
        }
    }
}

class UDPVehicleStateClient: CustomUDPClient {
    func sendVehicleState(vs: VehicleState) -> Bool {
        var data = Data()
        
        withUnsafePointer(to: &vs.x) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.y) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.z) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.roll) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.pitch) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.yaw) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.vx) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.vy) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        withUnsafePointer(to: &vs.vz) { data.append(UnsafeBufferPointer(start: $0, count: 1)) }
        
        return self.sendData(data: data)
    }
}


class UDPControlServer {
    var connection: NWConnection!
    var hostUDP: NWEndpoint.Host = "192.168.1.29"
    var portUDP: NWEndpoint.Port = 8004
    var controlCenter: ControlCenter!

    
    init(controlCenter: ControlCenter, address: NWEndpoint.Host = "192.168.1.10", port:NWEndpoint.Port=8001, num_buffer: Int = 2) {
        self.controlCenter = controlCenter
        self.hostUDP = address
        self.portUDP = port
        print("starting connection on \(self.hostUDP), \(self.portUDP)")
        self.connection = NWConnection(host: hostUDP, port: portUDP, using: .udp)
        
        self.connection?.stateUpdateHandler = { (newState) in
            if newState == .ready {
                self.recvControl()
            }
        }

        self.connection?.start(queue: .global())
    }
    
    func sendUDP(_ content: String) {
         let contentToSendUDP = content.data(using: String.Encoding.utf8)
        self.connection?.send(content: contentToSendUDP, completion: NWConnection.SendCompletion.contentProcessed(({ _ in
            
        })))
//         self.connection?.send(content: contentToSendUDP, completion: NWConnection.SendCompletion.contentProcessed(({ (NWError) in
//             if (NWError == nil) {
//                 print("Data was sent to UDP")
//             } else {
//                 print("ERROR! Error when data (Type: Data) sending. NWError: \n \(NWError!)")
//             }
//         })))
     }
    
    func recvControl() -> (Float, Float)? {
        self.sendUDP("ack")
        self.connection?.receiveMessage { (data, context, isComplete, error) in
            if (isComplete) {
                if (data != nil) {
                    let backToString = String(decoding: data!, as: UTF8.self)
                    let arr = backToString.components(separatedBy: ",")
                    self.controlCenter.control.throttle = Float(arr[0]) ?? 0
                    self.controlCenter.control.steering = Float(arr[1]) ?? 0
                } else {
                    print("Data == nil")
                }
            }
        }
        return nil
    }
    
    func stop() {
        self.connection.cancel()
    }
}



//class Server {
//    var ipAddr: String
//    var port: Int
//    var app: Application?
//    var dispatchWorkItem: DispatchWorkItem?
//    var controlCenter: ControlCenter!
//    var controlCheckTimer: Timer?
//        
//    var controlTimer: Timer?
//    var controlWS: WebSocketKit.WebSocket?
//    
//    init(ipAddr: String? = nil, port: Int = 8005, controlCenter: ControlCenter) {
//        self.ipAddr = ipAddr ?? findIPAddr()
//        self.port = port
//        self.controlCenter = controlCenter
//        self.controlTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(receiveControl(sender:)), userInfo: nil, repeats: true)
//
//    }
//
//
//    
//    func start() {
//        self.dispatchWorkItem = DispatchWorkItem{
//            self.start_helper()
//        }
//        DispatchQueue.global(qos: .utility).async(execute: self.dispatchWorkItem!)
//    }
//    
//
//    
//    private func start_helper() {
//        do {
//            self.app = try Application(.detect())
//            self.app!.http.server.configuration.hostname = self.ipAddr
//            self.app!.http.server.configuration.port = self.port
//            self.app!.routes.defaultMaxBodySize = "1024mb"
//            self.app?.logger.logLevel = .notice
//            self.configurePaths()
//            try self.app!.run()
//        } catch {
//            print("Unable to start server, find something legit to do here")
//        }
//    }
//    
//    func stop() {
//        if self.app!.didShutdown == false {
//            self.app!.server.shutdown()
//            do {
//                try self.app!.server.onShutdown.wait()
//            } catch {
//                print("Failed to shutdown gracefully")
//            }
//        }
//        if self.controlTimer != nil {
//            self.controlTimer?.invalidate()
//            self.controlWS = nil
//        }
//
//        self.dispatchWorkItem?.cancel()
//    }
//    
//    private func configurePaths() {
//        configureControl()
//
//    }
//    
//    private func configureControl() {
//        self.app!.webSocket("control_rx") { req, ws in
//            self.controlWS = ws
//        }
//    }
//    
//    
//    @objc private func receiveControl(sender: Timer) {
//        if self.controlWS != nil && (AppInfo.sessionData.shouldCaliberate == false && AppInfo.sessionData.isCaliberated)  {
//            if self.controlWS != nil && self.controlWS?.isClosed == false {
//                self.controlWS!.onText(
//                    {ws,s in
//                        let arr = s.components(separatedBy: ",")
//                        self.controlCenter.control.throttle = Float(arr[0]) ?? 0
//                        self.controlCenter.control.steering = Float(arr[1]) ?? 0
//                    }
//                )
//            }
//        }
//    }
//}


