import Darwin

struct Pixel: Equatable {
    let r, g, b: UInt8
    
    static let black = Pixel(r: 0, g: 0, b: 0)
    static let white = Pixel(r: 255, g: 255, b: 255)
}

class PPM {
    let width: Int
    let height: Int
    
    private let data: UnsafeMutableBufferPointer<UInt8>
    
    subscript(_ x: Int, _ y: Int) -> Pixel {
        get {
            Pixel(
                r: data[3 * (y * width + x) + 0],
                g: data[3 * (y * width + x) + 1],
                b: data[3 * (y * width + x) + 2]
            )
        }
        set {
            data[3 * (y * width + x) + 0] = newValue.r
            data[3 * (y * width + x) + 1] = newValue.g
            data[3 * (y * width + x) + 2] = newValue.b
        }
    }
    
    init?() {
        guard let line1 = readLine(strippingNewline: true), line1 == "P6" else {
            return nil
        }

        guard let line2 = readLine(strippingNewline: true) else {
            return nil
        }

        let segments = line2.split(separator: " ")

        guard segments.count == 2,
              let w = Int(segments[0]),
              let h = Int(segments[1]) else {
            return nil
        }
        
        guard readLine(strippingNewline: true) != nil else {
            return nil
        }
        
        self.width = w
        self.height = h
        
        let size = 3 * w * h

        self.data = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: size)
        let readBytes = fread(self.data.baseAddress, 1, size, stdin)
        
        guard size == readBytes else {
            return nil
        }
    }
    
    deinit {
        self.data.deallocate()
    }
    
    func inverse() {
        for x in 0..<width {
            for y in 0..<height {
                if self[x, y] == .black {
                    self[x, y] = .white
                } else if self[x, y] == .white {
                    self[x, y] = .black
                }
            }
        }
    }
    
    func write() {
        print("P6")
        print("\(width) \(height)")
        print("255")
        fwrite(data.baseAddress, data.count, 1, stdout)
    }
}

if let ppm = PPM() {
    ppm.inverse()
    ppm.write()
}
