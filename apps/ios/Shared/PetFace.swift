import ImageIO
import SwiftUI

/// One frame of a species sheet (8 columns of 192x208, 39 rows), pixel-crisp. Sheets come from apps/web/public/pets.
struct PetFace: View {
    let species: String
    var row = 5       // idle
    var frame = 0
    var body: some View {
        if let img = Self.frame(species, row: row, frame: frame) {
            Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(192.0 / 208.0, contentMode: .fit)
        } else {
            Circle().fill(.secondary)
        }
    }

    static var cache: [String: CGImage] = [:]
    static func frame(_ species: String, row: Int, frame: Int) -> CGImage? {
        let key = "\(species)/\(row)/\(frame)"
        if let c = cache[key] { return c }
        guard let url = Bundle.main.url(forResource: species, withExtension: "webp", subdirectory: "pets") ?? Bundle.main.url(forResource: species, withExtension: "webp"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil), let sheet = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let cell = sheet.cropping(to: CGRect(x: frame * 192, y: row * 208, width: 192, height: 208)) else { return nil }
        cache[key] = cell
        return cell
    }
}
