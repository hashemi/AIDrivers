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
    var c0, c1: Float
    
    private static var randomConfig: (Float, Float) {
        (
            1.0 * ldexpf(Float.random(in: 0..<Float(UInt32.max)), -32),
            0.1 * ldexpf(Float.random(in: 0..<Float(UInt32.max)), -32)
        )
    }
    
    init(x: Float, y: Float, a: Float) {
        self.x = x
        self.y = y
        self.a = a
        self.color = .random
        (self.c0, self.c1) = Vehicle.randomConfig
    }
    
    mutating func randomizeConfiguration() {
        (self.c0, self.c1) = Vehicle.randomConfig
    }
    
    mutating func drive(map: Map, cfg: SysConf) -> Bool {
        guard map.alive(vehicle: self) else { return false }
        
        let s = (
            map.sense(x: x, y: y, a: a + .pi / -4),
            map.sense(x: x, y: y, a: a),
            map.sense(x: x, y: y, a: a + .pi / 4)
        )
        
        let steering = (s.2 * c0) - s.0 * c0
        let throttle = max(cfg.speedMin, min(cfg.speedMax, s.1 * c1))
        
        a += abs(steering) > cfg.control ?
            copysignf(cfg.control, steering) : steering
        x += throttle * cosf(a)
        y += throttle * sinf(a)
        
        return true
    }
}

final class PPM {
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
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = .allocate(capacity: 3 * width * height)
    }
    
    convenience init?(input: UnsafeMutablePointer<FILE>) {
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
        
        self.init(width: w, height: h)
        
        guard data.count == fread(data.baseAddress, 1, data.count, input) else {
            return nil
        }
    }
    
    func copy() -> PPM {
        let copy = PPM(width: width, height: height)
        memcpy(copy.data.baseAddress, self.data.baseAddress, data.count)
        return copy
    }

    deinit {
        self.data.deallocate()
    }
    
    func write() {
        print("P6")
        print("\(width) \(height)")
        print("255")
        fwrite(data.baseAddress, data.count, 1, stdout)
    }
}

final class Map {
    let width, height: Int
    let sx, sy: Int
    let sa: Float
    let d: UnsafeMutableBufferPointer<UInt>
    
    static let b = 8

    init(ppm: PPM) {
        self.width = ppm.width
        self.height = ppm.height

        self.d = .allocate(capacity: (width * height + Map.b - 1) / Map.b)

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
let frameskip = 1
let drop = 0
let erase = false
let reset = true
let beams = false
let cfg = SysConf.default

guard let f = PPM(input: stdin) else {
    fatalError("Couldn't read input map from stdin.")
}

let m = Map(ppm: f)

let overlay = PPM(width: f.width * scale, height: f.height * scale)

m.draw(on: overlay)

var vehicles = (0..<nvehicle).map { _ in
    Vehicle(x: Float(m.sx), y: Float(m.sy), a: m.sa)
}

for t in 0... {
    if t >= drop && t % frameskip == 0 {
        let out = overlay.copy()
        if beams {
            m.drawBeams(vehicles: vehicles, on: out)
        }
        m.draw(vehicles: vehicles, on: out)
        out.write()
    }
    
    for i in (0..<vehicles.count).reversed() {
        _ = vehicles[i].drive(map: m, cfg: cfg)
        if !m.alive(vehicle: vehicles[i]) {
            if !erase {
                m.draw(vehicles: [vehicles[i]], on: overlay)
            }
            if reset {
                vehicles[i].randomizeConfiguration()
                vehicles[i].x = Float(m.sx)
                vehicles[i].y = Float(m.sy)
                vehicles[i].a = m.sa
            } else {
                vehicles.remove(at: i)
            }
        }
    }
    if vehicles.isEmpty { break }
}
