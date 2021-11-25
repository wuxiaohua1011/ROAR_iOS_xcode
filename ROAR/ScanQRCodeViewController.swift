import AVFoundation
import UIKit
import Loaf
import CocoaAsyncSocket
import JGProgressHUD

import Network

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, GCDAsyncUdpSocketDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var delegate: ScanQRCodeProtocol? = nil
    var is_connected: Bool = false
    var connection: NWConnection?
    var pc_ip_addr: String? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }

    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if (captureSession?.isRunning == false) {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            find(ip_addr: stringValue)
        }
    }
    
    func find(ip_addr:String) {
        
        if validateIpAddress(ipToValidate: ip_addr) {
            perform_handshake(code: ip_addr)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                if self.is_connected == false {
                    Loaf.init("No Response from \(ip_addr)", state: .error, location: .bottom, presentingDirection: .vertical, dismissingDirection: .vertical, sender: self).show(.average, completionHandler: {
                        _ in
                        self.captureSession.startRunning()
                    })
                    if self.connection != nil {
                        self.connection?.cancel()
                    }
                    self.pc_ip_addr = nil
                } else {
                    AppInfo.pc_address = self.pc_ip_addr!
                    AppInfo.save()
                    self.dismiss(animated: true, completion: {
                        self.delegate?.onQRCodeScanFinished()
                        self.connection?.cancel()
                    }
                    )
                }
            })
        }
    }


    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    
    func perform_handshake(code:String){
        self.pc_ip_addr = code
        let hostUDP: NWEndpoint.Host = NWEndpoint.Host.init(code)
        self.connection = NWConnection(host: hostUDP, port: 8890, using: .udp)
        
        self.connection?.stateUpdateHandler = { (newState) in
                    switch (newState) {
                        case .ready:
                            for _ in 0...9 {
                                print("sending handshake...")
                                self.sendUDP("hi")
                            }
                            self.receiveUDP()
                        case .setup:
                            print("State: Setup\n")
                        case .cancelled:
                            print("State: Cancelled\n")
                        case .preparing:
                            print("State: Preparing\n")
                        default:
                            print("ERROR! State not defined!\n")
                    }
                }

        self.connection?.start(queue: .main)
        
    }
    
    func sendUDP(_ content: String) {
        let contentToSendUDP = content.data(using: String.Encoding.utf8)
        self.connection?.send(content: contentToSendUDP, completion: NWConnection.SendCompletion.contentProcessed(({ (NWError) in
            if (NWError != nil) {
                print("ERROR! Error when data (Type: Data) sending. NWError: \n \(NWError!)")
            }
        })))
    }

    func receiveUDP() {
        self.connection?.receiveMessage { (data, context, isComplete, error) in
            if (isComplete) {
                self.is_connected = true
                
            }
        }
    }
}

