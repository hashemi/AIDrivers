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

struct Vehicle {
    var x, y, a: Float
    let color: Color
    var c0, c1: Float
    
    init(x: Float, y: Float, a: Float, color: Color? = nil) {
        self.x = x
        self.y = y
        self.a = a
        self.color = color ?? .random
        self.c0 = 1.0 * ldexpf(Float.random(in: 0..<Float(UInt32.max)), -32)
        self.c1 = 0.1 * ldexpf(Float.random(in: 0..<Float(UInt32.max)), -32)
    }
    
    mutating func drive(map: Map, cfg: SysConf) -> Bool {
        guard alive(map: map) else { return false }
        
        let s = (
            sense(map: map, direction: .pi / -4),
            sense(map: map, direction: 0),
            sense(map: map, direction: .pi / 4)
        )
        
        let steering = (s.2 * c0) - s.0 * c0
        let throttle = max(cfg.speedMin, min(cfg.speedMax, s.1 * c1))
        
        a += abs(steering) > cfg.control ?
            copysignf(cfg.control, steering) : steering
        x += throttle * cosf(a)
        y += throttle * sinf(a)
        
        return true
    }

    func sense(map: Map, direction: Float, step: (Int, Int) -> () = { _, _ in }) -> Float {
        let dx = cosf(a + direction)
        let dy = sinf(a + direction)
        var d = 1
        while true {
            let bx = x + dx * Float(d)
            let by = y + dy * Float(d)
            let ix = Int(bx)
            let iy = Int(by)
            if ix < 0 || ix >= map.width || iy < 0 || iy >= map.height {
                break
            }
            if map[ix, iy] {
                break
            }
            step(ix, iy)
            d += 1
        }
        
        let d_ = Float(d)
        return sqrtf(d_*dx*d_*dx + d_*dy*d_*dy)
    }

    func alive(map: Map) -> Bool {
        !map[Int(x), Int(y)]
    }
}

final class PPM {
    let width: Int
    let height: Int
    
    private let data: UnsafeMutableBufferPointer<UInt8>
    
    subscript(x: Int, y: Int, scale scale: Int = 1) -> Color {
        get {
            Color(
                r: data[3 * (y * scale * width + x * scale) + 0],
                g: data[3 * (y * scale * width + x * scale) + 1],
                b: data[3 * (y * scale * width + x * scale) + 2]
            )
        }
        set {
            for dx in 0..<scale {
                for dy in 0..<scale {
                    data[3 * ((y * scale + dy) * width + (x * scale + dx)) + 0] = newValue.r
                    data[3 * ((y * scale + dy) * width + (x * scale + dx)) + 1] = newValue.g
                    data[3 * ((y * scale + dy) * width + (x * scale + dx)) + 2] = newValue.b
                }
            }
        }
    }
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = .allocate(capacity: 3 * width * height)
    }
    
    convenience init?(input: UnsafeMutablePointer<FILE>) {
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

    func draw(map: Map) {
        for y in 0..<map.height {
            for x in 0..<map.width {
                self[x, y, scale: width / map.width] = map[x, y] ? .white : .black
            }
        }
    }

    func draw(vehicles: [Vehicle], map: Map) {
        let s = self.width / map.width
        for v in vehicles {
            for d in -s*2..<s*2 {
                for j in -s/2..<s/2 {
                    let x = Float(s) * v.x
                        + Float(j) * cosf(v.a - Float.pi / 2)
                        + Float(d) * cosf(v.a) / 2
                    let y = Float(s) * v.y
                        + Float(j) * sinf(v.a - Float.pi / 2)
                        + Float(d) * sinf(v.a) / 2
                    self[Int(x), Int(y)] = v.color
                }
            }
        }
    }
    
    func drawBeams(vehicles: [Vehicle], map: Map) {
        let scale = width / map.width
        for v in vehicles {
            _ = v.sense(map: map, direction: .pi / -4) { x, y in self[x, y, scale: scale] = .red }
            _ = v.sense(map: map, direction: 0) { x, y in self[x, y, scale: scale] = .red }
            _ = v.sense(map: map, direction: .pi / 4) { x, y in self[x, y, scale: scale] = .red }
        }
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

overlay.draw(map: m)

var vehicles = (0..<nvehicle).map { _ in
    Vehicle(x: Float(m.sx), y: Float(m.sy), a: m.sa)
}

for t in 0... {
    if t >= drop && t % frameskip == 0 {
        let out = overlay.copy()
        if beams {
            out.drawBeams(vehicles: vehicles, map: m)
        }
        out.draw(vehicles: vehicles, map: m)
        out.write()
    }
    
    for i in (0..<vehicles.count).reversed() {
        _ = vehicles[i].drive(map: m, cfg: cfg)
        if !vehicles[i].alive(map: m) {
            if !erase {
                overlay.draw(vehicles: [vehicles[i]], map: m)
            }
            if reset {
                vehicles[i] = Vehicle(x: Float(m.sx), y: Float(m.sy), a: m.sa, color: vehicles[i].color)
            } else {
                vehicles.remove(at: i)
            }
        }
    }
    if vehicles.isEmpty { break }
}
