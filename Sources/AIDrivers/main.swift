import Darwin

struct Color: Equatable {
    let r, g, b: UInt8
    
    static let black = Color(r: 0, g: 0, b: 0)
    static let white = Color(r: 255, g: 255, b: 255)
    static let green = Color(r: 0, g: 255, b: 0)
    static let blue = Color(r: 0, g: 0, b: 255)
    static let red = Color(r: 255, g: 0, b: 0)

    static var random: Color {
        Color(
            r: UInt8.random(in: UInt8.min..<UInt8.max) | 0x40,
            g: UInt8.random(in: UInt8.min..<UInt8.max) | 0x40,
            b: UInt8.random(in: UInt8.min..<UInt8.max) | 0x40
        )
    }
}

struct SysConf {
    let speedMin: Float
    let speedMax: Float
    let control: Float
    
    static let `default` = SysConf(
        speedMin: 0.1,
        speedMax: 0.5,
        control: .pi/128
    )
}

struct Config {
    var c: (Float, Float)
    
    init(_ c1: Float, _ c2: Float) {
        self.c = (c1, c2)
    }

func readLine2(input: UnsafeMutablePointer<FILE>, strippingNewline: Bool = true) -> String? {
    var linePtr: UnsafeMutablePointer<Int8>?
    var capacity: Int = 0
    while getline(&linePtr, &capacity, input) < 0 && errno == EINTR { }
    defer { free(linePtr) }
    guard let cString = linePtr else { return nil }
    var result = String(validatingUTF8: cString)
    if strippingNewline, result?.last == "\n" || result?.last == "\r\n" {
        _ = result?.removeLast()
    }
    return result
}

struct Vehicle {
    var x, y, a: Float
    let color: Color
    
    mutating func drive(c: Config, map: Map, cfg: SysConf) -> Bool {
        guard map.alive(vehicle: self) else { return false }
        
        let s = (
            map.sense(x: x, y: y, a: a + .pi / -4),
            map.sense(x: x, y: y, a: a),
            map.sense(x: x, y: y, a: a + .pi / 4)
        )
        
        let steering = (s.2 * c.c.0) - s.0 * c.c.0
        let throttle = max(cfg.speedMin, min(cfg.speedMax, s.1 * c.c.1))
        
        a += abs(steering) > cfg.control ?
            copysignf(cfg.control, steering) : steering
        x += throttle * cosf(a)
        y += throttle * sinf(a)
        
        return true
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
    
    init?(input: UnsafeMutablePointer<FILE>) {
        guard let line1 = readLine2(input: input), line1 == "P6" else {
            return nil
        }

        guard let line2 = readLine2(input: input) else {
            return nil
        }

        let segments = line2.split(separator: " ")

        guard segments.count == 2,
              let w = Int(segments[0]),
              let h = Int(segments[1]) else {
            return nil
        }
        
        guard readLine2(input: input) != nil else {
            return nil
        }
        
        self.width = w
        self.height = h
        
        let size = 3 * w * h

        self.data = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: size)
        let readBytes = fread(self.data.baseAddress, 1, size, input)
        
        guard size == readBytes else {
            return nil
        }
    }
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        
        let size = 3 * width * height
        
        self.data = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: size)
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
                let v: UInt = ppm[x, y].r > 0x7f ? 1 : 0
                let i = y * width + x
                self.d[i / Map.b] |= v << (i % Map.b)
            }
        }
    }
    
    subscript(_ x: Int, _ y: Int) -> Bool {
        let i = y * width + x
        return (d[i / Map.b] >> (i % Map.b) & 1) != 0
    }
    
    func draw(on ppm: PPM) {
        let s = ppm.width / width
        for y in 0..<ppm.height {
            for x in 0..<ppm.width {
                ppm[x, y] = self[x/s, y/s] ? .white : .black
            }
        }
    }
    
    func draw(vehicles: [Vehicle], on ppm: PPM) {
        let s = ppm.width / width
        for v in vehicles {
            for d in -s*2..<s*2 {
                for j in -s/2..<s/2 {
                    let x = Float(s) * v.x
                        + Float(j) * cosf(v.a - Float.pi / 2)
                        + Float(d) * cosf(v.a) / 2
                    let y = Float(s) * v.y
                        + Float(j) * sinf(v.a - Float.pi / 2)
                        + Float(d) * sinf(v.a) / 2
                    ppm[Int(x), Int(y)] = v.color
                }
            }
        }
    }
    
    func sense(x: Float, y: Float, a: Float, on ppm: PPM? = nil) -> Float {
        let dx = cosf(a)
        let dy = sinf(a)
        var d = 1
        while true {
            let bx = x + dx * Float(d)
            let by = y + dy * Float(d)
            let ix = Int(bx)
            let iy = Int(by)
            if ix < 0 || ix >= width || iy < 0 || iy >= height {
                break
            }
            if self[ix, iy] {
                break
            }
            if let ppm = ppm {
                let s = ppm.width / width
                for py in 0..<s {
                    for px in 0..<s {
                        ppm[ix * s + px, iy * s + py] = .red
                    }
                }
            }
            d += 1
        }
        
        let d_ = Float(d)
        return sqrtf(d_*dx*d_*dx + d_*dy*d_*dy)
    }

    func drawBeams(vehicles: [Vehicle], on ppm: PPM) {
        for v in vehicles {
            _ = sense(x: v.x, y: v.y, a: v.a - .pi / 4, on: ppm)
            _ = sense(x: v.x, y: v.y, a: v.a, on: ppm)
            _ = sense(x: v.x, y: v.y, a: v.a + .pi / 4, on: ppm)
        }
    }
    
    func alive(vehicle: Vehicle) -> Bool {
        !self[Int(vehicle.x), Int(vehicle.y)]
    }
    
    deinit {
        d.deallocate()
    }
}

// Main
let scale = 12
let nvehicle = 16

guard let f = PPM(input: stdin) else {
    fatalError("Couldn't read input map from stdin.")
}

let m = Map(ppm: f)

var out: PPM
let overlay = PPM(width: f.width * scale, height: f.height * scale)

m.draw(on: overlay)

var vehicles = (0..<16).map { _ in
    Vehicle(x: Float(m.sx),
            y: Float(m.sy),
            a: m.sa,
            color: .random
    )
}

m.draw(vehicles: vehicles, on: overlay)
m.drawBeams(vehicles: vehicles, on: overlay)

overlay.write()
