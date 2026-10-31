import AVFoundation
import SwiftUI
import UIKit
import CrateCore

struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var request: LookupRequest?
    @State private var showingManualEntry = false
    @State private var manualPrefill: LookupQuery?
    @State private var torchOn = false
    @State private var scanMessage: String?

    /// False on the Simulator and on devices without a usable camera.
    @State private var cameraAvailable = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            VStack(spacing: 12) {
                ShopField(shop: $settings.currentShop, recentShops: model.recentShops)

                if !model.isOnline { OfflineBanner() }
                if let warning = model.storageWarning {
                    Text(warning).font(.footnote).foregroundStyle(.red)
                }
                if !model.isConnected {
                    Label("Connect your Discogs account in Settings to look records up.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                camera
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let scanMessage {
                    Text(scanMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showingManualEntry = true
                } label: {
                    Label("Type a barcode, cat. no. or run-out", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Scan")
            .toolbar {
                if cameraStatus == .authorized && cameraAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            torchOn.toggle()
                        } label: {
                            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .accessibilityLabel(torchOn ? "Turn torch off" : "Turn torch on")
                    }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView(prefill: manualPrefill) { query in
                    showingManualEntry = false
                    request = LookupRequest(query: query)
                }
            }
            .navigationDestination(item: $request) { request in
                ResultView(query: request.query)
            }
            .navigationDestination(for: ReleaseRoute.self) { route in
                PressingDetailView(route: route)
            }
            .task(id: model.hasStarted) {
                guard model.hasStarted else { return }
                openStartScreen()
            }
            .task {
                // Without a camera (the Simulator, for one) there is nothing to
                // ask permission for, and the fallback below is shown instead.
                if cameraAvailable && cameraStatus == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                if phase != .active { torchOn = false }
            }
        }
    }

    @ViewBuilder
    private var camera: some View {
        if !cameraAvailable {
            placeholder(
                symbol: "camera",
                text: "No camera available. Type the barcode, catalogue number or run-out instead."
            )
        } else {
            switch cameraStatus {
            case .authorized:
                ZStack(alignment: .bottom) {
                    BarcodeScannerView(
                        isActive: request == nil && !showingManualEntry && scenePhase == .active,
                        torchOn: torchOn,
                        onDetect: handle
                    )
                    Text("Point at the barcode on the back of the sleeve")
                        .font(.footnote.weight(.medium))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .accessibilityHidden(true)
                }
            case .notDetermined:
                placeholder(symbol: "camera", text: "Crate needs the camera to read barcodes.")
            default:
                VStack(spacing: 12) {
                    placeholder(
                        symbol: "camera.fill.badge.ellipsis",
                        text: "Camera access is off. You can still type identifiers, or allow the camera in Settings."
                    )
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.1))
    }

    /// Demo mode can open straight onto a lookup or the manual entry sheet.
    private func openStartScreen() {
        #if DEBUG
        switch model.takeStartScreen([.manual, .result, .pressings]) {
        case .manual:
            manualPrefill = .catalogueNumber(DemoLibrary.sharedCatalogueNumber)
            showingManualEntry = true
        case .result:
            if let barcode = Barcode(DemoLibrary.wantedBarcode) {
                request = LookupRequest(query: .barcode(barcode))
            }
        case .pressings:
            request = LookupRequest(query: .catalogueNumber(DemoLibrary.sharedCatalogueNumber))
        default:
            break
        }
        #endif
    }

    private func handle(_ code: ScannedCode) {
        guard let barcode = code.barcode else {
            scanMessage = "That code (\(code.value)) is not a retail barcode."
            return
        }
        guard barcode.hasValidCheckDigit else {
            scanMessage = "Misread barcode, try again or type it in."
            return
        }
        scanMessage = nil
        request = LookupRequest(query: .barcode(barcode))
    }
}

/// "Digging at" field. The shop name is typed by the user and stored with
/// dig log entries; Crate never uses location.
struct ShopField: View {
    @Binding var shop: String
    let recentShops: [String]

    var body: some View {
        HStack {
            Image(systemName: "storefront")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Digging at (shop or fair)", text: $shop)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .accessibilityLabel("Shop or record fair name")
            if !recentShops.isEmpty {
                Menu {
                    ForEach(recentShops, id: \.self) { name in
                        Button(name) { shop = name }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Recent shops")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
