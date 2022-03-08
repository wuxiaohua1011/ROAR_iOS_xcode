//
//  Agent.swift
//  IntelRacing
//
//  Created by Michael Wu on 8/2/21.
//
import Foundation

class Agent {
    
    var cc: ControlCenter!
    var vc: ViewController!
    var run_step_rate:Double = 0.025
    var timer: Timer?
    var has_started:Bool = false
    init(controlCenter: ControlCenter, vc: ViewController, run_step_rate:Double=0.025) {
        self.cc = controlCenter
        self.vc = vc
        self.run_step_rate = run_step_rate
    }
    
    func step() {
        // make one step
    }
    
    func stop() {
        // stop the agent in-spot
        self.vc.logger.info("Stopping Agent")
        if self.timer != nil {
            self.timer?.invalidate()
            self.timer = nil
        }
        self.has_started = false
        self.cc.control.throttle = 0
        self.cc.control.steering = 0
    }
    
    func start() {
        self.vc.logger.info("Starting Agent")
        self.timer = Timer(timeInterval: self.run_step_rate, repeats: true, block: {
            timer in
            self.step()
        })
        RunLoop.current.add(self.timer!, forMode: .common)
        self.has_started = true
    }
}
