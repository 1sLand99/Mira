import Foundation
import UIKit
import VideoToolbox
import CoreVideo
import QuartzCore
import Darwin

private let miraVideoMagic = Data([0x4d, 0x48, 0x53, 0x31])
private let miraPacketHeaderBytes = 20
private let miraScreenFrameRate: Int32 = 10
private let miraScreenMaxWidth = 540
private let miraScreenBitrate = 220_000

@MainActor
final class MiraRemoteServices {
    static let shared = MiraRemoteServices()

    private let screenState = MiraRemoteScreenState()
    private let inputController: MiraRemoteInputController
    private let screenStreamer: MiraRemoteScreenStreamer
    private let metricsSampler: MiraDeviceMetricsSampler
    private var lastRelayURL = ""
    private var running = false

    private init() {
        inputController = MiraRemoteInputController(screenState: screenState)
        screenStreamer = MiraRemoteScreenStreamer(screenState: screenState)
        metricsSampler = MiraDeviceMetricsSampler()
    }

    func start(relayURL: String) {
        let normalized = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        lastRelayURL = normalized
        running = true
        inputController.start()
        screenStreamer.start(relayURL: normalized)
        metricsSampler.start()
    }

    func stop() {
        running = false
        screenStreamer.stop()
        metricsSampler.stop()
        inputController.stop()
    }

    func pauseForSceneStop() {
        guard running else { return }
        screenStreamer.stop()
        metricsSampler.stop()
        inputController.stop()
    }

    func resumeForSceneActive() {
        guard running, !lastRelayURL.isEmpty else { return }
        inputController.start()
        screenStreamer.start(relayURL: lastRelayURL)
        metricsSampler.start()
    }
}

final class MiraRemoteScreenState: @unchecked Sendable {
    private let lock = NSLock()
    private var sourceSize = CGSize(width: 1, height: 1)
    private var encodedSize = CGSize(width: 1, height: 1)

    func update(source: CGSize, encoded: CGSize) {
        lock.lock()
        sourceSize = CGSize(width: max(1, source.width), height: max(1, source.height))
        encodedSize = CGSize(width: max(1, encoded.width), height: max(1, encoded.height))
        lock.unlock()
    }

    func mapFramePoint(_ point: CGPoint) -> CGPoint {
        lock.lock()
        let source = sourceSize
        let encoded = encodedSize
        lock.unlock()
        return CGPoint(
            x: point.x * source.width / max(1, encoded.width),
            y: point.y * source.height / max(1, encoded.height)
        )
    }

}

final class MiraRemoteScreenStreamer: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let screenState: MiraRemoteScreenState
    private let queue = DispatchQueue(label: "MiraRemoteScreenStreamer")
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var compressionSession: VTCompressionSession?
    private var running = false
    private var relayURL = ""
    private var sequence: UInt32 = 0
    private var codecString = "avc1.42E01E"
    private var sentCodecString = ""
    private var timer: DispatchSourceTimer?
    private var encodedSize = CGSize(width: 1, height: 1)
    private var sourceSize = CGSize(width: 1, height: 1)

    init(screenState: MiraRemoteScreenState) {
        self.screenState = screenState
        super.init()
    }

    func start(relayURL: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.relayURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !self.relayURL.isEmpty else { return }
            if self.running { return }
            self.running = true
            self.sequence = 0
            self.connectAndStream()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        running = false
        timer?.cancel()
        timer = nil
        if let compressionSession {
            VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(compressionSession)
        }
        compressionSession = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func connectAndStream() {
        guard running else { return }
        guard let url = URL(string: screenDeviceWebSocketURL(relayURL)) else {
            scheduleReconnect()
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 0
        let nextSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let nextSocket = nextSession.webSocketTask(with: url)
        session = nextSession
        socket = nextSocket
        nextSocket.resume()
        receiveLoop(task: nextSocket)
        configureEncoderAndTimer()
        sendScreenInfo()
    }

    private func scheduleReconnect() {
        guard running else { return }
        timer?.cancel()
        timer = nil
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.running else { return }
            self.socket?.cancel(with: .goingAway, reason: nil)
            self.session?.invalidateAndCancel()
            self.socket = nil
            self.session = nil
            self.connectAndStream()
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            self.queue.async {
                guard self.running, self.socket === task else { return }
                if case .failure = result {
                    self.scheduleReconnect()
                    return
                }
                self.receiveLoop(task: task)
            }
        }
    }

    private func configureEncoderAndTimer() {
        guard running else { return }
        let sizes = captureSizes()
        sourceSize = sizes.source
        encodedSize = sizes.encoded
        screenState.update(source: sizes.source, encoded: sizes.encoded)
        guard Int(encodedSize.width) > 0, Int(encodedSize.height) > 0 else {
            scheduleReconnect()
            return
        }
        configureCompressionSession(width: Int32(encodedSize.width), height: Int32(encodedSize.height))
        startTimer()
    }

    private func startTimer() {
        timer?.cancel()
        let nextTimer = DispatchSource.makeTimerSource(queue: queue)
        nextTimer.schedule(deadline: .now(), repeating: .milliseconds(Int(1000 / miraScreenFrameRate)), leeway: .milliseconds(12))
        nextTimer.setEventHandler { [weak self] in
            self?.captureAndEncodeFrame()
        }
        timer = nextTimer
        nextTimer.resume()
    }

    private func configureCompressionSession(width: Int32, height: Int32) {
        if let compressionSession {
            VTCompressionSessionInvalidate(compressionSession)
        }
        compressionSession = nil
        var nextSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(width),
                kCVPixelBufferHeightKey: Int(height),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: miraCompressionOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &nextSession
        )
        guard status == noErr, let nextSession else { return }
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: miraScreenFrameRate))
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: miraScreenFrameRate))
        VTSessionSetProperty(nextSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: miraScreenBitrate))
        VTCompressionSessionPrepareToEncodeFrames(nextSession)
        compressionSession = nextSession
    }

    private func captureAndEncodeFrame() {
        guard running, let compressionSession else { return }
        let sizes = captureSizes()
        if abs(sizes.encoded.width - encodedSize.width) > 0.5 || abs(sizes.encoded.height - encodedSize.height) > 0.5 {
            sourceSize = sizes.source
            encodedSize = sizes.encoded
            screenState.update(source: sizes.source, encoded: sizes.encoded)
            configureCompressionSession(width: Int32(encodedSize.width), height: Int32(encodedSize.height))
            sendScreenInfo()
            return
        }
        sourceSize = sizes.source
        screenState.update(source: sizes.source, encoded: sizes.encoded)
        guard let pixelBuffer = makePixelBuffer(width: Int(encodedSize.width), height: Int(encodedSize.height)) else { return }
        guard renderWindow(into: pixelBuffer, source: sizes.source, encoded: sizes.encoded) else { return }
        flipPixelBufferVertically(pixelBuffer, height: Int(encodedSize.height))
        sequence &+= 1
        let timestamp = CMTime(value: CMTimeValue(sequence), timescale: miraScreenFrameRate)
        let duration = CMTime(value: 1, timescale: miraScreenFrameRate)
        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    fileprivate func handleEncodedSample(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            let keyFrame = sampleBuffer.isKeyFrame
            if keyFrame, let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let spsPps = h264ParameterSets(formatDescription: format)
                if let sps = spsPps.first, sps.count >= 4 {
                    self.codecString = String(format: "avc1.%02X%02X%02X", sps[1], sps[2], sps[3])
                }
                if self.sentCodecString != self.codecString {
                    self.sendScreenInfo()
                }
            }
            guard let payload = annexBData(sampleBuffer: sampleBuffer) else { return }
            let packet = videoPacket(payload: payload, keyFrame: keyFrame, seq: self.sequence)
            self.socket?.send(.data(packet)) { [weak self] error in
                guard error != nil else { return }
                self?.queue.async { self?.scheduleReconnect() }
            }
        }
    }

    private func sendScreenInfo() {
        guard running else { return }
        let installId = MiraNativeStatus.installId
        guard !installId.isEmpty else { return }
        let payload: [String: Any] = [
            "type": "screen.video.info",
            "protocol": 1,
            "installId": installId,
            "deviceName": UIDevice.current.name,
            "codec": codecString,
            "mime": "video/avc",
            "format": "annexb",
            "width": Int(encodedSize.width),
            "height": Int(encodedSize.height),
            "sourceWidth": Int(sourceSize.width),
            "sourceHeight": Int(sourceSize.height),
            "fps": Int(miraScreenFrameRate),
            "bitrate": miraScreenBitrate,
            "maxWidth": miraScreenMaxWidth,
        ]
        sentCodecString = codecString
        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            self?.queue.async { self?.scheduleReconnect() }
        }
    }

    private func captureSizes() -> (source: CGSize, encoded: CGSize) {
        let source = DispatchQueue.main.sync { () -> CGSize in
            guard let window = MiraRemoteInputController.keyWindow else { return CGSize(width: 390, height: 844) }
            let bounds = window.bounds
            return CGSize(width: max(1, bounds.width), height: max(1, bounds.height))
        }
        let scale = min(1, CGFloat(miraScreenMaxWidth) / max(1, source.width))
        let width = max(2, Int((source.width * scale).rounded()))
        let height = max(2, Int((source.height * scale).rounded()))
        return (source, CGSize(width: width - (width % 2), height: height - (height % 2)))
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }

    private func renderWindow(into pixelBuffer: CVPixelBuffer, source: CGSize, encoded: CGSize) -> Bool {
        var ok = false
        let pixelBufferBox = UnsafeSendableBox(pixelBuffer)
        DispatchQueue.main.sync {
            guard let window = MiraRemoteInputController.keyWindow else { return }
            let pixelBuffer = pixelBufferBox.value
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: base,
                width: Int(encoded.width),
                height: Int(encoded.height),
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return }
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: encoded))
            UIGraphicsPushContext(context)
            context.saveGState()
            context.scaleBy(x: encoded.width / max(1, source.width), y: encoded.height / max(1, source.height))
            let rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            if !rendered {
                window.layer.render(in: context)
            }
            context.restoreGState()
            UIGraphicsPopContext()
            ok = true
        }
        return ok
    }

    private func flipPixelBufferVertically(_ pixelBuffer: CVPixelBuffer, height: Int) {
        guard height > 1 else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: bytesPerRow, alignment: MemoryLayout<UInt64>.alignment)
        defer { scratch.deallocate() }

        var top = 0
        var bottom = height - 1
        while top < bottom {
            let topRow = base.advanced(by: top * bytesPerRow)
            let bottomRow = base.advanced(by: bottom * bytesPerRow)
            scratch.copyMemory(from: topRow, byteCount: bytesPerRow)
            topRow.copyMemory(from: bottomRow, byteCount: bytesPerRow)
            bottomRow.copyMemory(from: scratch, byteCount: bytesPerRow)
            top += 1
            bottom -= 1
        }
    }

    private func screenDeviceWebSocketURL(_ value: String) -> String {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return raw }
        if !raw.contains("://") { raw = "http://\(raw)" }
        guard var components = URLComponents(string: raw) else { return raw }
        if components.scheme == "http" { components.scheme = "ws" }
        else if components.scheme == "https" { components.scheme = "wss" }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/ws/screen/device"
        } else if !components.path.hasSuffix("/ws/screen/device") {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + components.path + "/ws/screen/device"
        }
        return components.string ?? raw
    }
}

private let miraCompressionOutputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard status == noErr, let refcon, let sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else { return }
    let streamer = Unmanaged<MiraRemoteScreenStreamer>.fromOpaque(refcon).takeUnretainedValue()
    streamer.handleEncodedSample(sampleBuffer)
}

final class MiraDeviceMetricsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MiraDeviceMetricsSampler")
    private var timer: DispatchSourceTimer?
    private var lastNetwork: (rx: UInt64, tx: UInt64, at: TimeInterval)?

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(80))
            timer.setEventHandler { [weak self] in self?.sendMetrics() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.lastNetwork = nil
        }
    }

    private func sendMetrics() {
        let installId = MiraNativeStatus.installId
        guard !installId.isEmpty else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let network = networkSnapshot()
        let payload: [String: Any] = [
            "type": "device.metrics",
            "protocol": 1,
            "installId": installId,
            "deviceName": UIDevice.current.name,
            "state": "idle",
            "metrics": [
                "sampledAt": nowMs,
                "cpuPercent": round1(processCpuPercent()),
                "memoryPercent": round1(memoryPercent()),
                "memoryUsedMb": round1(memoryUsedMb()),
                "memoryTotalMb": round1(Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0),
                "rxBps": round1(network.rxBps),
                "txBps": round1(network.txBps),
                "networkBps": round1(max(0, network.rxBps) + max(0, network.txBps)),
            ],
        ]
        guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) else { return }
        _ = MiraNativeStatus.sendControlJSON(text)
    }

    private func networkSnapshot() -> (rxBps: Double, txBps: Double) {
        let total = networkByteCounters()
        let now = Date().timeIntervalSince1970
        defer { lastNetwork = (total.rx, total.tx, now) }
        guard let last = lastNetwork, now > last.at else { return (-1, -1) }
        let seconds = now - last.at
        return (
            max(0, Double(total.rx >= last.rx ? total.rx - last.rx : 0) / seconds),
            max(0, Double(total.tx >= last.tx ? total.tx - last.tx : 0) / seconds)
        )
    }
}

@MainActor
final class MiraRemoteInputController: @unchecked Sendable {
    private let screenState: MiraRemoteScreenState
    private var active = false

    init(screenState: MiraRemoteScreenState) {
        self.screenState = screenState
    }

    func start() {
        guard !active else { return }
        active = true
        mira_ios_relay_set_screen_input_callback(miraScreenInputCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    func stop() {
        guard active else { return }
        active = false
        mira_ios_relay_set_screen_input_callback(nil, nil)
    }

    fileprivate func handle(json: String) {
        guard active, let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        handleOnMain(object)
    }

    private func handleOnMain(_ request: [String: Any]) {
        let kind = request["kind"] as? String ?? ""
        let result: InputResult
        switch kind {
        case "tap":
            let framePoint = CGPoint(x: numeric(request["x"]), y: numeric(request["y"]))
            result = handleTap(framePoint: framePoint)
        case "text":
            result = insertText(request["text"] as? String ?? "")
        case "paste":
            let text = request["text"] as? String ?? ""
            UIPasteboard.general.string = text
            result = insertText(text)
        case "key":
            result = handleKey(request["key"] as? String ?? "")
        case "copy":
            result = copyFocusedText()
        case "selectall":
            result = selectAllFocusedText()
        case "clear":
            result = clearFocusedText()
        default:
            result = .error("unsupported screen input kind=\(kind)")
        }
        sendResult(request: request, kind: kind, result: result)
    }

    private func handleTap(framePoint: CGPoint) -> InputResult {
        guard let window = Self.keyWindow else { return .error("window unavailable") }
        let point = screenState.mapFramePoint(framePoint)
        let bounded = CGPoint(
            x: min(max(0, point.x), max(0, window.bounds.width - 1)),
            y: min(max(0, point.y), max(0, window.bounds.height - 1))
        )
        guard let hit = window.hitTest(bounded, with: nil) else { return .error("tap target unavailable") }
        if activate(view: hit) { return .ok("tap dispatched") }
        if hit.becomeFirstResponder() { return .ok("focused") }
        return .error("tap not handled")
    }

    private func activate(view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if let textField = candidate as? UITextField {
                textField.becomeFirstResponder()
                return true
            }
            if let textView = candidate as? UITextView {
                textView.becomeFirstResponder()
                return true
            }
            if let control = candidate as? UIControl {
                control.sendActions(for: .touchDown)
                control.sendActions(for: .touchUpInside)
                control.sendActions(for: .valueChanged)
                return true
            }
            if candidate.accessibilityActivate() {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    private func insertText(_ text: String) -> InputResult {
        if text.isEmpty { return .ok("empty text") }
        guard let responder = firstResponder() else { return .error("focused view unavailable") }
        if let input = responder as? UIKeyInput, input.hasText || responder is UITextField || responder is UITextView {
            input.insertText(text)
            sendEditingChangedIfNeeded(responder)
            return .ok("text inserted")
        }
        if UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: responder, from: nil, for: nil) {
            return .ok("paste dispatched")
        }
        return .error("focused view does not accept text")
    }

    private func handleKey(_ key: String) -> InputResult {
        guard let responder = firstResponder() else { return .error("focused view unavailable") }
        switch key {
        case "Backspace":
            if let input = responder as? UIKeyInput {
                input.deleteBackward()
                sendEditingChangedIfNeeded(responder)
                return .ok("deleted")
            }
        case "Delete":
            if deleteForward(responder) {
                sendEditingChangedIfNeeded(responder)
                return .ok("deleted")
            }
        case "Enter":
            return insertText("\n")
        case "Tab":
            return insertText("\t")
        default:
            return .error("unsupported key: \(key)")
        }
        return .error("key not handled: \(key)")
    }

    private func deleteForward(_ responder: UIResponder) -> Bool {
        guard let textInput = responder as? (UIResponder & UITextInput), let selected = textInput.selectedTextRange else { return false }
        if !selected.isEmpty {
            textInput.replace(selected, withText: "")
            return true
        }
        guard let end = textInput.position(from: selected.end, offset: 1), let range = textInput.textRange(from: selected.end, to: end) else { return false }
        textInput.replace(range, withText: "")
        return true
    }

    private func copyFocusedText() -> InputResult {
        guard let responder = firstResponder() else { return .error("focused view unavailable") }
        let text: String
        if let field = responder as? UITextField {
            text = selectedText(in: field) ?? field.text ?? ""
        } else if let view = responder as? UITextView {
            text = selectedText(in: view) ?? view.text ?? ""
        } else if UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: responder, from: nil, for: nil), let pasted = UIPasteboard.general.string {
            text = pasted
        } else {
            return .error("focused view is not text")
        }
        UIPasteboard.general.string = text
        return .text("copied", text)
    }

    private func selectAllFocusedText() -> InputResult {
        guard let responder = firstResponder() else { return .error("focused view unavailable") }
        if let field = responder as? UITextField {
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            return .ok("selected all")
        }
        if let view = responder as? UITextView {
            view.selectedTextRange = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)
            return .ok("selected all")
        }
        if UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: responder, from: nil, for: nil) {
            return .ok("selected all")
        }
        return .error("focused text is not selectable")
    }

    private func clearFocusedText() -> InputResult {
        guard let responder = firstResponder() else { return .error("focused view unavailable") }
        if let field = responder as? UITextField {
            field.text = ""
            field.sendActions(for: .editingChanged)
            return .ok("cleared")
        }
        if let view = responder as? UITextView {
            view.text = ""
            NotificationCenter.default.post(name: UITextView.textDidChangeNotification, object: view)
            return .ok("cleared")
        }
        return .error("focused text is not editable")
    }

    private func sendResult(request: [String: Any], kind: String, result: InputResult) {
        var response: [String: Any] = [
            "type": "screen.input.result",
            "protocol": 1,
            "installId": MiraNativeStatus.installId,
            "requestId": request["requestId"] as? String ?? "",
            "clientId": request["clientId"] as? String ?? "",
            "kind": kind,
            "ok": result.ok,
            "message": result.message,
        ]
        if !result.ok { response["error"] = result.message }
        if !result.text.isEmpty || kind == "copy" { response["text"] = result.text }
        guard JSONSerialization.isValidJSONObject(response), let data = try? JSONSerialization.data(withJSONObject: response), let text = String(data: data, encoding: .utf8) else { return }
        _ = MiraNativeStatus.sendControlJSON(text)
    }

    private func firstResponder() -> UIResponder? {
        miraCurrentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.miraCaptureFirstResponder(_:)), to: nil, from: nil, for: nil)
        return miraCurrentFirstResponder
    }

    private func selectedText(in field: UITextField) -> String? {
        guard let range = field.selectedTextRange, !range.isEmpty else { return nil }
        return field.text(in: range)
    }

    private func selectedText(in view: UITextView) -> String? {
        guard let range = view.selectedTextRange, !range.isEmpty else { return nil }
        return view.text(in: range)
    }

    private func sendEditingChangedIfNeeded(_ responder: UIResponder) {
        if let field = responder as? UITextField {
            field.sendActions(for: .editingChanged)
        } else if let view = responder as? UITextView {
            NotificationCenter.default.post(name: UITextView.textDidChangeNotification, object: view)
        }
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.windows.first { $0.isKeyWindow }
    }

    private struct InputResult {
        let ok: Bool
        let message: String
        let text: String

        static func ok(_ message: String) -> InputResult { InputResult(ok: true, message: message, text: "") }
        static func text(_ message: String, _ text: String) -> InputResult { InputResult(ok: true, message: message, text: text) }
        static func error(_ message: String) -> InputResult { InputResult(ok: false, message: message, text: "") }
    }
}

private let miraScreenInputCallback: mira_ios_screen_input_callback_t = { json, context in
    guard let json, let context else { return }
    let controller = Unmanaged<MiraRemoteInputController>.fromOpaque(context).takeUnretainedValue()
    let message = String(cString: json)
    Task { @MainActor in
        controller.handle(json: message)
    }
}

nonisolated(unsafe) private weak var miraCurrentFirstResponder: UIResponder?

private extension UIResponder {
    @objc func miraCaptureFirstResponder(_ sender: Any) {
        miraCurrentFirstResponder = self
    }
}

private func numeric(_ value: Any?) -> CGFloat {
    if let value = value as? CGFloat { return value }
    if let value = value as? Double { return CGFloat(value) }
    if let value = value as? Float { return CGFloat(value) }
    if let value = value as? Int { return CGFloat(value) }
    if let value = value as? NSNumber { return CGFloat(truncating: value) }
    if let value = value as? String, let number = Double(value) { return CGFloat(number) }
    return 0
}

private func videoPacket(payload: Data, keyFrame: Bool, seq: UInt32) -> Data {
    var packet = Data(capacity: miraPacketHeaderBytes + payload.count)
    packet.append(miraVideoMagic)
    packet.append(keyFrame ? 1 : 0)
    packet.append(0)
    packet.append(contentsOf: [0, 0])
    appendBigEndian(UInt32(seq), to: &packet)
    appendBigEndian(UInt64(seq) * UInt64(1_000_000 / miraScreenFrameRate), to: &packet)
    packet.append(payload)
    return packet
}

private func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

private func appendBigEndian(_ value: UInt64, to data: inout Data) {
    var big = value.bigEndian
    withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
}

private func annexBData(sampleBuffer: CMSampleBuffer) -> Data? {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer), let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    var lengthAtOffset = 0
    var totalLength = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr, let dataPointer else { return nil }

    let parameterSets = sampleBuffer.isKeyFrame ? h264ParameterSets(formatDescription: format) : []
    var out = Data()
    for set in parameterSets {
        out.append(contentsOf: [0, 0, 0, 1])
        out.append(set)
    }

    let nalLengthSize = h264NalLengthSize(formatDescription: format)
    var offset = 0
    while offset + nalLengthSize <= totalLength {
        var nalLength = 0
        for index in 0..<nalLengthSize {
            nalLength = (nalLength << 8) | Int(UInt8(bitPattern: dataPointer[offset + index]))
        }
        offset += nalLengthSize
        guard nalLength > 0, offset + nalLength <= totalLength else { break }
        out.append(contentsOf: [0, 0, 0, 1])
        out.append(UnsafeBufferPointer(start: UnsafeRawPointer(dataPointer + offset).assumingMemoryBound(to: UInt8.self), count: nalLength))
        offset += nalLength
    }
    return out.isEmpty ? nil : out
}

private func h264ParameterSets(formatDescription: CMFormatDescription) -> [Data] {
    var count = 0
    var lengthSize = Int32(0)
    guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        parameterSetIndex: 0,
        parameterSetPointerOut: nil,
        parameterSetSizeOut: nil,
        parameterSetCountOut: &count,
        nalUnitHeaderLengthOut: &lengthSize
    ) == noErr else { return [] }
    var result: [Data] = []
    for index in 0..<count {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: index,
            parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        ) == noErr, let pointer, size > 0 {
            result.append(Data(bytes: pointer, count: size))
        }
    }
    return result
}

private func h264NalLengthSize(formatDescription: CMFormatDescription) -> Int {
    var lengthSize = Int32(4)
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        formatDescription,
        parameterSetIndex: 0,
        parameterSetPointerOut: nil,
        parameterSetSizeOut: nil,
        parameterSetCountOut: nil,
        nalUnitHeaderLengthOut: &lengthSize
    )
    return max(1, Int(lengthSize))
}

private extension CMSampleBuffer {
    var isKeyFrame: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]], let first = attachments.first else {
            return false
        }
        return first[kCMSampleAttachmentKey_NotSync] == nil
    }
}

private func processCpuPercent() -> Double {
    var threadList: thread_act_array_t?
    var threadCount = mach_msg_type_number_t(0)
    guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threadList else { return -1 }
    defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)) }
    var total: Double = 0
    for index in 0..<Int(threadCount) {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(THREAD_INFO_MAX)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS, (info.flags & TH_FLAGS_IDLE) == 0 {
            total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
    }
    return total
}

private func memoryUsedMb() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1024.0 / 1024.0
}

private func memoryPercent() -> Double {
    let total = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
    let used = memoryUsedMb()
    guard total > 0, used >= 0 else { return -1 }
    return min(100, max(0, used / total * 100.0))
}

private func networkByteCounters() -> (rx: UInt64, tx: UInt64) {
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let start = addresses else { return (0, 0) }
    defer { freeifaddrs(start) }
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var cursor: UnsafeMutablePointer<ifaddrs>? = start
    while let current = cursor {
        defer { cursor = current.pointee.ifa_next }
        let flags = Int32(current.pointee.ifa_flags)
        guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = current.pointee.ifa_data else { continue }
        let stats = data.assumingMemoryBound(to: if_data.self).pointee
        rx += UInt64(stats.ifi_ibytes)
        tx += UInt64(stats.ifi_obytes)
    }
    return (rx, tx)
}

private func round1(_ value: Double) -> Double {
    guard value >= 0, value.isFinite else { return -1 }
    return (value * 10).rounded() / 10
}

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
