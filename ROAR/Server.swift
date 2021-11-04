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
    var MAX_DGRAM: Int = 9200 // for some mac, default size is 9620, make some room for header
    var num_buffer: Int = 2
    var controlCenter: ControlCenter!
    private var curr_buffer = 0
    var address: String!
    var port: Int32!
    private var counter = 0
    var receivedDataBuffer = CircularBuffer<[Byte]>(capacity: 3)
    init(controlCenter: ControlCenter, address: String = "192.168.1.10", port:Int32=8001, num_buffer: Int = 1) {
        self.address = address
        self.port = port
        client = UDPClient(address: address, port: port)
        self.num_buffer = num_buffer
        self.controlCenter = controlCenter
    }
    func restart(address: String, port: Int32){
        self.stop()
        client = UDPClient(address: address, port: port)
    }
    
    func sendData(data: Data) -> Bool {
//        if self.counter % 1000 == 0 {
//            self.restart(address: self.address, port: self.port)
//        }
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
            while offset < totalSize {
                var data_to_send:Data = String(counter).leftPadding(toLength: 3, withPad: "0")
                    .data(using:.ascii)!
                
                data_to_send.append(String(total).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                data_to_send.append(String(curr_buffer).leftPadding(toLength: 3, withPad: "0").data(using: .ascii)!)
                
                let chunkSize = offset + uploadChunkSize > totalSize ? totalSize - offset : uploadChunkSize
                let chunk = Data(bytesNoCopy: mutRawPointer+offset, count: chunkSize, deallocator: Data.Deallocator.none)
                data_to_send.append(chunk)
                self.client.send(data: data_to_send)
//                print("buf_id \(self.curr_buffer) | prefix_num = \(counter) | total_num = \(total)")
                offset += chunkSize
                counter += 1
            }
            curr_buffer = (curr_buffer + 1) % num_buffer
        }
        return true
    }
    
    func recvData() {
        self.counter += 1
        if self.counter % 50 == 0 {
            // reset the client every 50 counts s.t. if server side does not respond, i do not overload my recv buffer.
            self.client.close()
            self.client = UDPClient(address: self.address, port: self.port)
            self.counter = 0
        }
        
        DispatchQueue.global(qos: .background).async {
            _ = self.client.send(string: "ack")
            let content = self.client.recv(100)
            guard let data = content.0 else {
                return
            }
            self.receivedDataBuffer.overwrite(data)
        }
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


class UDPControlClient: CustomUDPClient {
    func recvControl() -> (throttle: Float, steering: Float)? {
        self.recvData()
        if self.receivedDataBuffer.buffer.count > 0 {
            do {
                let bytes = try self.receivedDataBuffer.read()
                if let string = String(bytes: bytes, encoding: .utf8) {
                    let splitted = string.components(separatedBy: ",")
                    let throttle = Float(splitted[0]) ?? 0
                    let steering = Float(splitted[1]) ?? 0
                    return (throttle, steering)
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        }
        return nil
    }
}

