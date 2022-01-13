//
//  ViewController+REST.swift
//  ROAR
//
//  Created by Michael Wu on 12/21/21.
//

import Foundation
import Vapor
import ARKit
 
extension ViewController {
    func startVaporServer() {
        self.dispatchWorkItem = DispatchWorkItem{
            do {
                self.app = try Application(.detect())
                
                self.app!.http.server.configuration.hostname = findIPAddr()
                self.app!.http.server.configuration.port = 40001
                self.app!.routes.defaultMaxBodySize = "1024mb"
                self.app?.logger.logLevel = .notice
                self.configureRESTPaths()
                try self.app!.run()
            } catch {
                print("error")
            }
        }
        DispatchQueue.global(qos: .utility).async(execute: self.dispatchWorkItem!)
        
    }
    func configureRESTPaths() {
        self.app.get("save_world") { req -> String in
            let r = self.saveWorld()
            return "world_saved"
        }
    }
    func stopVaporServer() {
        if self.app!.didShutdown == false {
            self.app!.server.shutdown()
            do {
                try self.app!.server.onShutdown.wait()
            } catch {
                print("Failed to shutdown gracefully")
            }
        }
    }
}

