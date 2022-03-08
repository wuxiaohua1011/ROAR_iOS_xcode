//
//  LineFollowingAgent.swift
//  IntelRacing
//
//  Created by Michael Wu on 9/3/21.
//
import Foundation
import UIKit
import Collections

class LineFollowingAgent: Agent {
    var rMin:Int = 180
     var gMin:Int = 180
     var bMin:Int = 0
     var rMax:Int = 255
     var gMax:Int = 255
     var bMax:Int = 140
    var heightOffset: Int = 10
    var target_speed: Float = 1
    var lat_kp:Float = 0.005  // this is how much you want to steer
    var lat_kd:Float = 0.075  // this is how much you want to resist change
    var lat_ki:Float = 0  // this is the correction on past errors
    
    var flat_ground_throttle: Float = 0.25
    var up_ramp_throttle: Float = 0.3
    var down_ramp_throttle: Float = -0.01
    
    var max_lat_deque_count: Int = 10
    
    var errorScaling: [[Float]] = [
        [20,0.1],
        [40,0.75],
        [60,1],
        [80,1.5],
        [100,1.75],
        [200, 3]
    ]
    
    private var lat_deque: Deque<Float> = []
    private var lon_deque: Deque<Float> = []
    
    override func step() {
        if self.cc.backCamImage.uiImage != nil {
            // get the current frame
            let depth_width = self.cc.worldCamDepth.width
            let uiImage = self.resizeImage(image: self.cc.backCamImage.uiImage!, newWidth: CGFloat(depth_width))!
            
            // based on the current frame, find middle line
            let color_xs = findColorInUiImage(in: uiImage, heightOffset: self.heightOffset,
                                              rMin: self.rMin, rMax: self.rMax,
                                              gMin: self.gMin, gMax: self.gMax,
                                              bMin: self.bMin, bMax: self.bMax)
            if color_xs.count < 3 {
                print("Cannot find line")
                // execute prev command
                let past_steering_avg = self.lat_deque.reduce(0, +)
                if self.cc.control.steering < 0 {
                    self.cc.control.steering = -1
                } else {
                    self.cc.control.steering = 1
                }
//                self.cc.control.throttle = self.cc.control.throttle
            } else {
                // find the avg of the points
                let avg = Int(color_xs.reduce(0, +) / color_xs.count)
                let middle = Int(uiImage.size.height / 2)
                
                // find and scale error
                var error = middle - avg
                for item in self.errorScaling {
                    let e: Float = item[0]
                    let scale: Float = item[1]
                    if abs(error) < Int(e) {
                        error = error * Int(scale)
                        break
                    }
                }
                let lat_error = error
                let long_error = self.target_speed - self.getCurrentSpeed()
                
                // execute PID control
                let steering = self.run_lat_pid(error: Float(lat_error))
                let throttle = self.run_lon_pid(error: Float(long_error))
                print(throttle, steering)
                self.cc.control.steering = steering
                self.cc.control.throttle = throttle
            }
        } else {
            print("back image not ready")
        }
//        print(self.cc.control.description)
    }
    
    func run_lat_pid(error: Float) -> Float {
        if self.lat_deque.count >= self.max_lat_deque_count {
            self.lat_deque.removeFirst()
        }
        self.lat_deque.append(error)
        
        var error_dt:Float = 0
        if self.lat_deque.count > 0 {
            error_dt = error - self.lat_deque.last!
        }
        
        let error_it = self.lat_deque.reduce(0, +)
        
        let e_p = self.lat_kp * error
        let e_d = self.lat_kd * error_dt
        let e_i = self.lat_ki * error_it
        
        let lat_control = (e_p + e_d + e_i).clamped(to: -1...1)
        return lat_control
    }
    
    func run_lon_pid(error: Float) -> Float {
        let angle = 90 + rad2deg(Double(self.cc.vehicleState.roll))
        
        if angle < -5 {
            // down ramp
            print("Current Angle: \(angle) Going Down Ramp")
            return down_ramp_throttle
        } else if angle > 5 {
            // up ramp
            print("Current Angle: \(angle) Going Up Ramp")
            return up_ramp_throttle
        } else {
            return flat_ground_throttle
        }
    }
    
    func getCurrentSpeed() -> Float {
        return sqrt( self.cc.vel_x * self.cc.vel_x + self.cc.vel_y * self.cc.vel_y + self.cc.vel_z * self.cc.vel_z )
    }
    
    func resizeImage(image: UIImage, newWidth: CGFloat) -> UIImage? {
        let scale = newWidth / image.size.width
        let newHeight = image.size.height * scale
        UIGraphicsBeginImageContext(CGSize(width: newWidth, height: newHeight))
        image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

}
//On the top of your swift
func findColorInUiImage(in image: UIImage, heightOffset: Int = 10, rMin:Int=200,rMax:Int=255, gMin:Int=170, gMax:Int=240, bMin:Int=0, bMax:Int=150) -> [Int] {
    var result: [Int] = []
    guard let inputCGImage = image.cgImage else { print("unable to get cgImage"); return result }
    let colorSpace       = CGColorSpaceCreateDeviceRGB()
    let width            = inputCGImage.width
    let height           = inputCGImage.height
    let bytesPerPixel    = 4
    let bitsPerComponent = 8
    let bytesPerRow      = bytesPerPixel * width
    let bitmapInfo       = RGBA32.bitmapInfo

    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
        print("Cannot create context!"); return result
    }
    context.draw(inputCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let buffer = context.data else { print("Cannot get context data!"); return result }

    let pixelBuffer = buffer.bindMemory(to: RGBA32.self, capacity: width * height)
    let column = width - heightOffset

    for row in 0 ..< Int(height) {
            let offset = row * width + column

            if pixelBuffer[offset].redComponent >=  rMin && pixelBuffer[offset].redComponent <=  rMax &&
                pixelBuffer[offset].greenComponent >=  gMin && pixelBuffer[offset].greenComponent <=  gMax &&
                pixelBuffer[offset].blueComponent >= bMin && pixelBuffer[offset].blueComponent <= bMax &&
                pixelBuffer[offset].alphaComponent <= 255 {
                result.append(row)
            }
    }

    return result
}
struct RGBA32: Equatable {
    private var color: UInt32

    var redComponent: UInt8 {
        return UInt8((color >> 24) & 255)
    }

    var greenComponent: UInt8 {
        return UInt8((color >> 16) & 255)
    }

    var blueComponent: UInt8 {
        return UInt8((color >> 8) & 255)
    }

    var alphaComponent: UInt8 {
        return UInt8((color >> 0) & 255)
    }

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let red   = UInt32(red)
        let green = UInt32(green)
        let blue  = UInt32(blue)
        let alpha = UInt32(alpha)
        color = (red << 24) | (green << 16) | (blue << 8) | (alpha << 0)
    }

    static let red     = RGBA32(red: 255, green: 0,   blue: 0,   alpha: 255)
    static let green   = RGBA32(red: 0,   green: 255, blue: 0,   alpha: 255)
    static let blue    = RGBA32(red: 0,   green: 0,   blue: 255, alpha: 255)
    static let white   = RGBA32(red: 255, green: 255, blue: 255, alpha: 255)
    static let black   = RGBA32(red: 0,   green: 0,   blue: 0,   alpha: 255)
    static let magenta = RGBA32(red: 255, green: 0,   blue: 255, alpha: 255)
    static let yellow  = RGBA32(red: 255, green: 255, blue: 0,   alpha: 255)
    static let cyan    = RGBA32(red: 0,   green: 255, blue: 255, alpha: 255)

    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    static func ==(lhs: RGBA32, rhs: RGBA32) -> Bool {
        return lhs.color == rhs.color
    }
}
