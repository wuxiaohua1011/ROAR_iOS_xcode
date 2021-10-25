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


class CustomUDPClient {
    /*
    This class implement a custom chunking protocol for streaming large data under UDP protocol
    */
    var client: UDPClient!
    var MAX_DGRAM: Int = 9000 // for some mac, default size is 9620, make some room for header
    init(address: String = "192.168.1.10", port:Int32=8001) {
        client = UDPClient(address: address, port: port)
    }
    func restart(address: String, port: Int32){
        self.stop()
        client = UDPClient(address: address, port: port)
    }
    
    func sendData(data: Data) -> Bool {
        if (data.count > MAX_DGRAM) {
            return self.chunkAndSendData(data: data)
        } else {
            let r = self.client.send(data: data)
            return r.isSuccess
        }
    }
    
    func chunkAndSendData(data: Data) -> Bool {
        data.withUnsafeBytes{(u8Ptr: UnsafePointer<UInt8>) in
            let mutRawPointer = UnsafeMutableRawPointer(mutating: u8Ptr)
            let uploadChunkSize = self.MAX_DGRAM
            let totalSize = data.count
            var offset = 0
            var counter = Int(Float(totalSize / uploadChunkSize).rounded(.up)) + 1
            
            var total_sent = 0
            while offset < totalSize {
                var data_to_send:Data = String(counter).leftPadding(toLength: 3, withPad: "0")
                    .data(using:.ascii)!
                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                data_to_send.append(chunk)
                self.client.send(data: data_to_send)
                total_sent += chunk.count
                offset += chunkSize
                counter -= 1
            }
            
        }
        return true
    }
    
    func stop() {
        self.client.close()
    }
    
}

class UDPDepthClient: CustomUDPClient {
    func sendDepth(customDepth: CustomDepthData) -> Bool {
        return sendData(data: customDepth.depth_data)
    }
}

class UDPImageClient: CustomUDPClient {
    func sendImage(uiImage: UIImage) -> Bool {
        return self.sendData(data: uiImage.jpegData(compressionQuality: 0.01)!)
    }
}

class Server {
    var ipAddr: String
    var port: Int
    var app: Application?
    var dispatchWorkItem: DispatchWorkItem?
    var controlCenter: ControlCenter!
    var controlCheckTimer: Timer?
    
    var worldCamTimer: Timer?
    var worldCamWS: WebSocketKit.WebSocket?
    
    var depthCamTimer: Timer?
    var depthCamWS: WebSocketKit.WebSocket?
    
    var controlTimer: Timer?
    var controlWS: WebSocketKit.WebSocket?
    
    var transformTimer: Timer?
    var vehStateWS: WebSocketKit.WebSocket?
    
    init(ipAddr: String? = nil, port: Int = 8005, controlCenter: ControlCenter) {
        self.ipAddr = ipAddr ?? findIPAddr()
        self.port = port
        self.controlCenter = controlCenter
        self.worldCamTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(sendWorldCam(sender:)), userInfo: nil, repeats: true)
        self.controlTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(receiveControl(sender:)), userInfo: nil, repeats: true)
        self.transformTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(sendVehState(sender:)), userInfo: nil, repeats: true)
        self.depthCamTimer = Timer.scheduledTimer(timeInterval: 0.04, target: self, selector: #selector(sendDepth(sender:)), userInfo: nil, repeats: true)
    }


    
    func start() {
        self.dispatchWorkItem = DispatchWorkItem{
            self.start_helper()
        }
        DispatchQueue.global(qos: .utility).async(execute: self.dispatchWorkItem!)
    }
    

    
    private func start_helper() {
        do {
            self.app = try Application(.detect())
            self.app!.http.server.configuration.hostname = self.ipAddr
            self.app!.http.server.configuration.port = self.port
            self.app!.routes.defaultMaxBodySize = "1024mb"
            self.app?.logger.logLevel = .notice
            self.configurePaths()
            try self.app!.run()
        } catch {
            print("Unable to start server, find something legit to do here")
        }
    }
    
    func stop() {
        if self.app!.didShutdown == false {
            self.app!.server.shutdown()
            do {
                try self.app!.server.onShutdown.wait()
            } catch {
                print("Failed to shutdown gracefully")
            }
        }
        if self.worldCamTimer != nil {
            self.worldCamTimer?.invalidate()
            self.worldCamWS = nil
        }
        
        if self.depthCamTimer != nil {
            self.depthCamTimer?.invalidate()
            self.depthCamWS = nil
        }
        if self.transformTimer != nil {
            self.transformTimer?.invalidate()
            self.vehStateWS = nil
        }
        if self.controlTimer != nil {
            self.controlTimer?.invalidate()
            self.controlWS = nil
        }

        self.dispatchWorkItem?.cancel()
    }
    
    private func configurePaths() {
        
        configureRearCam()
        configureVehState()
        configureControl()
        configureRearDepthCam()

    }
    private func configureRearDepthCam() {
        self.app!.webSocket("world_cam_depth") { req, ws in
            self.depthCamWS = ws
        }
    }
    
    @objc private func sendDepth(sender:Timer) {
        if (self.controlCenter.worldCamDepth.depth_data != nil && (AppInfo.sessionData.shouldCaliberate == false && AppInfo.sessionData.isCaliberated)) {
            if self.depthCamWS != nil && self.depthCamWS?.isClosed == false {
                let ws = self.depthCamWS!
//                ws.send(raw: self.controlCenter.worldCamDepth.depth_data, opcode: .binary)
                let d = self.controlCenter.worldCamDepth
                
                let data = "\(String(describing: d?.fxD ?? -1)),\(String(describing: d?.fyD ?? -1)),\(String(describing: d?.cxD ?? -1)),\(String(describing: d?.cyD ?? -1))"
                ws.send(data)
            }
        }
    }
    private func configureRearCam() {
        self.app!.webSocket("world_cam") { req, ws in
            self.worldCamWS = ws
        }
    }
    
    @objc private func sendWorldCam(sender:Timer) {
        if self.controlCenter.backCamImage.outputData != nil && (AppInfo.sessionData.shouldCaliberate == false && AppInfo.sessionData.isCaliberated) {
            if self.worldCamWS != nil && self.worldCamWS?.isClosed == false {
//                self.worldCamWS!.send(raw: self.controlCenter.backCamImage.outputData ?? Data.init(count: 0), opcode: .binary)
                let k = self.controlCenter.backCamImage.intrinsics
                if k == nil {
                    let data = "\(-1),\(-1),\(-1),\(-1)"
                    self.worldCamWS!.send(data)

                } else {
                    let data = "\(String(describing: k?[0][0] ?? -1)),\(String(describing: k?[1][1] ?? -1)),\(String(describing: k?[2][0] ?? -1)),\(String(describing: k?[2][1] ?? -1))"
                    self.worldCamWS!.send(data)

                }
            }
        }
    }
    
    private func configureVehState() {
        self.app!.webSocket("veh_state") { req, ws in
            self.vehStateWS = ws
        }
    }
    
    @objc private func sendVehState(sender: Timer) {
        if (AppInfo.sessionData.shouldCaliberate == false && (AppInfo.sessionData.shouldCaliberate == false && AppInfo.sessionData.isCaliberated)){
            if self.vehStateWS != nil && self.vehStateWS?.isClosed == false {
                let ws = self.vehStateWS!
                let data = self.controlCenter.vehicleState.toData()
                ws.send(raw: data, opcode: .binary)
            }

        }
    }
    
    private func configureControl() {
        self.app!.webSocket("control_rx") { req, ws in
            self.controlWS = ws
        }
    }
    
    
    @objc private func receiveControl(sender: Timer) {
        if self.controlWS != nil && (AppInfo.sessionData.shouldCaliberate == false && AppInfo.sessionData.isCaliberated)  {
            if self.controlWS != nil && self.controlWS?.isClosed == false {
                self.controlWS!.onText(
                    {ws,s in
                        let arr = s.components(separatedBy: ",")
                        self.controlCenter.control.throttle = Float(arr[0]) ?? 0
                        self.controlCenter.control.steering = Float(arr[1]) ?? 0
                    }
                )
            }
        }
    }
}


