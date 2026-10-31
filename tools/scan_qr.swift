import Vision
import AppKit
for path in CommandLine.arguments.dropFirst().sorted() {
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print(path, "LOAD FAIL"); continue }
    let req = VNDetectBarcodesRequest(); req.symbologies = [.qr]
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    let found = (req.results ?? []).compactMap { $0.payloadStringValue }
    print((path as NSString).lastPathComponent, found.isEmpty ? "UNREADABLE" : found.joined(separator: " | "))
}
