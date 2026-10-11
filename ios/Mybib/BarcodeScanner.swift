import SwiftUI
import UIKit
import AVFoundation

/// Live camera preview that reports EAN-13 / EAN-8 / UPC-E codes (AVCaptureMetadataOutput).
struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onFail: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.onCode = onCode
        vc.onFail = onFail
        return vc
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {
        vc.onCode = onCode
        vc.onFail = onFail
    }

    static func dismantleUIViewController(_ vc: ScannerController, coordinator: Coordinator) {
        vc.stop()
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFail: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "mybib.scanner")
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                Task { @MainActor in
                    if ok { self?.configure() } else { self?.onFail?() }
                }
            }
        default:
            onFail?()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onFail?()
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onFail?()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        configured = true
        start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    func start() {
        guard configured else { return }
        let s = session
        queue.async {
            if !s.isRunning { s.startRunning() }
        }
    }

    func stop() {
        let s = session
        queue.async {
            if s.isRunning { s.stopRunning() }
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, var value = obj.stringValue else { return }
        // iOS reports UPC-A as EAN-13 with a leading 0; Android (and the lookups) use the 12 digits
        if obj.type == .ean13, value.count == 13, value.hasPrefix("0") { value.removeFirst() }
        let code = value
        // the delegate queue is the main queue
        MainActor.assumeIsolated {
            self.onCode?(code)
        }
    }
}
