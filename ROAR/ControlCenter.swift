//
//  ControlCenter.swift
//  Michael Wu
//
//  Created by Michael Wu on 9/11/2021
//

import Foundation
import ARKit
import os
import Network

class ControlCenter {
    public var vehicleState: VehicleState = VehicleState()
    public var transform: CustomTransform = CustomTransform()
    public var vel_x: Float = 0; // m/sec
    public var vel_y: Float = 0; // m/sec
    public var vel_z: Float = 0; // m/sec
    public var control: CustomControl = CustomControl()
    
    public var backCamImage: CustomImage!
    public var udpbackCamClient: UDPImageClient!
    public var udpVehStateClient: UDPVehicleStateClient!
    public var udpControlServer: UDPControlServer!

    public var worldCamDepth: CustomDepthData!
    var udpDepthClient: UDPDepthClient!
    
    public var vc: UIViewController!
    
    private var prevTransformUpdateTime: TimeInterval?;
    
    
    init(vc: UIViewController) {
        self.vc = vc
        self.backCamImage = CustomImage(compressionQuality: 0.005, ratio: .no_cut)//AppInfo.imageRatio)
        self.worldCamDepth = CustomDepthData()
    }
    
    func start(shouldStartServer: Bool = true){
        if shouldStartServer {
            
            self.udpbackCamClient = UDPImageClient(address: AppInfo.pc_address, port: AppInfo.udp_world_cam_port)
            self.udpDepthClient = UDPDepthClient(address: AppInfo.pc_address, port: AppInfo.udp_depth_cam_port)
            self.udpVehStateClient = UDPVehicleStateClient(address: AppInfo.pc_address, port: AppInfo.udp_veh_state_port)
            self.udpControlServer = UDPControlServer(controlCenter: self , address: NWEndpoint.Host.init(AppInfo.pc_address), port: 8004)
        }
    }
    func stop(){
        self.udpControlServer.stop()
        self.udpVehStateClient.stop()
        self.udpbackCamClient.stop()
        self.udpDepthClient.stop()
    }
    
    
    func restartUDP() {
        self.udpbackCamClient.restart(address: AppInfo.pc_address, port: AppInfo.udp_world_cam_port)
        self.udpDepthClient.restart(address: AppInfo.pc_address, port: AppInfo.udp_depth_cam_port)
        self.udpVehStateClient.restart(address: AppInfo.pc_address, port: AppInfo.udp_veh_state_port)
    }
    public func updateBackCam(frame:ARFrame) {
        if self.backCamImage.updating == false {
            self.backCamImage.updateImage(cvPixelBuffer: frame.capturedImage)
            self.backCamImage.updateIntrinsics(intrinsics: frame.camera.intrinsics)
        }
    }
    public func updateBackCam(cvpixelbuffer:CVPixelBuffer, rotationDegree:Float=90) {
        if self.backCamImage.updating == false {
            self.backCamImage.updateImage(cvPixelBuffer: cvpixelbuffer)
        }
    }
    public func updateWorldCamDepth(frame: ARFrame) {
        if self.worldCamDepth.updating == false {
            self.worldCamDepth.update(frame: frame)
        }
    }
    public func sendWorldCamImage() -> Bool {
        return self.udpbackCamClient.sendImage(customImage: self.backCamImage)

    }
    public func sendDepthImage() -> Bool {
        return self.udpDepthClient.sendDepth(customDepth: self.worldCamDepth)
    }
    public func sendVehState() -> Bool {
        return self.udpVehStateClient.sendVehicleState(vs: self.vehicleState)
    }
    public func recvControl() -> Bool {
        self.udpControlServer.recvControl()
        return true
    }
    
    public func updateTransform(pointOfView: SCNNode) {
        let node = pointOfView
        let time = TimeInterval(NSDate().timeIntervalSince1970)
        if prevTransformUpdateTime == nil {
            prevTransformUpdateTime = time
        } else {
            
            let time_diff = Float((time-prevTransformUpdateTime!))
            vel_x = (node.position.x - self.transform.position.x) / time_diff // m/s
            vel_y = (node.position.y - self.transform.position.y) / time_diff
            vel_z = (node.position.z - self.transform.position.z) / time_diff
            
            self.transform.position = (node.position + self.transform.position) / 2
            
            // yaw, roll, pitch DO NOT CHANGE THIS!
            self.transform.eulerAngle = SCNVector3(node.eulerAngles.z, node.eulerAngles.y, node.eulerAngles.x)
            
            
            self.vehicleState.update(x: transform.position.x,
                                     y: transform.position.y,
                                     z: transform.position.z,
                                     roll: transform.eulerAngle.z,
                                     pitch: transform.eulerAngle.y,
                                     yaw: transform.eulerAngle.x,
                                     vx: vel_x,
                                     vy: vel_y,
                                     vz: vel_z)
//            print("vx: \(vel_x) | vy: \(vel_y) | vz: \(vel_z)")
            prevTransformUpdateTime = time
        }
    }
}
