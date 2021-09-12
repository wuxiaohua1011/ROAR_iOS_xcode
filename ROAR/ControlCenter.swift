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
    public var transform: CustomTransform = CustomTransform()
    public var vel_x: Float = 0; // m/sec
    public var vel_y: Float = 0; // m/sec
    public var vel_z: Float = 0; // m/sec
    public var control: CustomControl = CustomControl()
    
    public var backCamImage: CustomImage!
    
    public var worldCamDepth: CustomDepthData!
    
    public var vc: UIViewController!
    
    private var prevTransformUpdateTime: TimeInterval?;
    private var gameTimeReductionTimer: Timer!
    
    public var server:Server!
    
    init(vc: UIViewController) {
        self.vc = vc
        self.backCamImage = CustomImage(compressionQuality: 0.005, ratio: .no_cut)//AppInfo.imageRatio)
        self.worldCamDepth = CustomDepthData()
        self.server = Server(controlCenter: self)
    }
    
    func start(shouldStartServer: Bool = true){
        if shouldStartServer {
            self.server.start()
        }
    }
    func stop(){
        self.server.stop()
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
//            self.backCamImage.updateIntrinsics(intrinsics: frame.camera.intrinsics)
        }
    }
    public func updateWorldCamDepth(frame: ARFrame) {
        if self.worldCamDepth.updating == false {
            self.worldCamDepth.update(frame: frame)
        }
    }
    
    
    public func updateTransform(pointOfView: SCNNode) {
        let node = pointOfView
        let time = TimeInterval(NSDate().timeIntervalSince1970)
        if prevTransformUpdateTime == nil {
            prevTransformUpdateTime = time
        } else {
            
            let time_diff = Float((time-prevTransformUpdateTime!))
            vel_x = (node.position.x - self.transform.position.x) / time_diff
            vel_y = (node.position.y - self.transform.position.y) / time_diff
            vel_z = (node.position.z - self.transform.position.z) / time_diff
            
            self.transform.position = (node.position + self.transform.position) / 2
            
            // yaw, roll, pitch DO NOT CHANGE THIS!
            self.transform.eulerAngle = SCNVector3(node.eulerAngles.z, node.eulerAngles.y, node.eulerAngles.x)
        }
    }
}
