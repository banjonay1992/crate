import AVFoundation
import SwiftUI
import UIKit
import CrateCore

/// A barcode read by the camera.
struct ScannedCode: Equatable {
    let value: String
    let isUPCE: Bool

    /// Converts to a Barcode, using the UPC-E rules when the camera says so.
    var barcode: Barcode? {
        if isUPCE, let upcE = Barcode(upcE: value) { return upcE }
        return Barcode(value)
    }
}

/// Live camera preview that reports EAN-13, EAN-8 and UPC-E barcodes.
/// UPC-A codes are reported by iOS as EAN-13 with a leading zero, which
/// CrateCore treats as the same product.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var torchOn: Bool
    var onDetect: (ScannedCode) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onDetect = onDetect
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onDetect = onDetect
        controller.setActive(isActive)
        controller.setTorch(torchOn)
    }

    static func dismantleUIViewController(_ controller: ScannerViewController, coordinator: ()) {
        controller.setActive(false)
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((ScannedCode) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "uk.co.nayproductions.crate.scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var wantsActive = false
    private var lastValue: String?
    private var lastDetection = Date.distantPast
    private let feedback = UINotificationFeedbackGenerator()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Camera viewfinder. Point it at the barcode on the sleeve."
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera)
        else { return }

        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()

        // Barcodes are read close up, so bias focus towards the near range.
        if (try? camera.lockForConfiguration()) != nil {
            if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
            if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
            camera.unlockForConfiguration()
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        device = camera
        isConfigured = true
        if wantsActive { startSession() }
    }

    func setActive(_ active: Bool) {
        guard active != wantsActive else { return }
        wantsActive = active
        if active { startSession() } else { stopSession() }
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func startSession() {
        guard isConfigured else { return }
        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
        feedback.prepare()
    }

    private func stopSession() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // Delivered on the main queue (see setMetadataObjectsDelegate above).
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue
        else { return }
        let isUPCE = code.type == .upce
        MainActor.assumeIsolated {
            self.handle(ScannedCode(value: value, isUPCE: isUPCE))
        }
    }

    private func handle(_ code: ScannedCode) {
        guard wantsActive else { return }
        // The camera reports the same code many times a second; ignore repeats.
        let now = Date()
        if code.value == lastValue, now.timeIntervalSince(lastDetection) < 3 { return }
        lastValue = code.value
        lastDetection = now
        feedback.notificationOccurred(.success)
        onDetect?(code)
    }
}
