import Darwin

struct Color: Equatable {
    let r, g, b: UInt8
    
    static let black = Color(r: 0, g: 0, b: 0)
    static let white = Color(r: 255, g: 255, b: 255)
    static let green = Color(r: 0, g: 255, b: 0)
    static let blue = Color(r: 0, g: 0, b: 255)
    
    var value: Int {
        Int(r) << 16 | Int(g) << 8 | Int(b) << 0
    }
}

class PPM {
    let width: Int
    let height: Int
    
    private let data: UnsafeMutableBufferPointer<UInt8>
    
    subscript(_ x: Int, _ y: Int) -> Color {
        get {
            Color(
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

class Map {
    let width, height: Int
    let sx, sy: Int
    let sa: Float
    let d: UnsafeMutableBufferPointer<UInt>
    
    static let b = 8

    init(ppm: PPM) {
        self.width = ppm.width
        self.height = ppm.height

        self.d = .allocate(capacity: (width * height + Map.b - 1) / Map.b)
        self.d.initialize(repeating: 0)

        var sx = width / 2
        var sy = height / 2
        var sa: Float = 0
        
        for y in 0..<height {
            for x in 0..<width {
                if ppm[x, y] == .green {
                    sx = x
                    sy = y
                }
            }
        }
        self.sx = sx
        self.sy = sy
        
        for y in 0..<height {
            for x in 0..<width {
                if ppm[x, y] == .blue {
                    sa = atan2(Float(y - sy), Float(x - sx))
                }
            }
        }
        self.sa = sa
        
        for y in 0..<height {
            for x in 0..<width {
                let c = ppm[x, y].value
                let v: UInt = c >> 16 > 0x7f ? 0 : 1
                let i = y * width + x
                self.d[i / Map.b] |= v << (i % Map.b)
            }
        }
    }
    
    subscript(_ x: Int, _ y: Int) -> Int {
        let i = y * width + x
        return Int(d[i / Map.b] >> (i % Map.b) & 1)
    }
    
    func draw(on ppm: PPM) {
        let s = ppm.width / width
        for y in 0..<height {
            for x in 0..<width {
                ppm[x, y] = self[x/s, y/s] != 0 ? .white : .black
            }
        }
    }
    
    deinit {
        d.deallocate()
    }
}

if let ppm = PPM() {
    let m = Map(ppm: ppm)
    m.draw(on: ppm)
    ppm.write()
}
