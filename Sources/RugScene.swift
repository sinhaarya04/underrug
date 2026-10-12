import AppKit
import SceneKit

/// SceneKit scene: orthographic top-down camera mapping 1 scene unit to 1 screen point,
/// a key light that turns lumps into shading, and a shadow-only floor.
final class RugScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let rug = SCNNode()
    let material = SCNMaterial()
    private var element: SCNGeometryElement?
    private var uv: SCNGeometrySource?
    private var nx = 0, ny = 0

    init(size: CGSize) {
        scene.background.contents = NSColor.clear
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(size.height / 2)
        cam.zNear = 10
        cam.zFar = 6000
        camera.camera = cam
        camera.position = SCNVector3(size.width / 2, size.height / 2, 3000)
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 210
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        let l = SCNLight()
        l.type = .directional
        l.intensity = 1250
        l.castsShadow = true
        l.shadowMode = .forward
        l.shadowColor = NSColor(white: 0, alpha: 0.42)
        l.shadowRadius = 7
        l.shadowBias = 6
        l.shadowSampleCount = 12
        l.shadowMapSize = CGSize(width: 4096, height: 4096)
        l.automaticallyAdjustsShadowProjection = false
        l.orthographicScale = Double(max(size.width, size.height) * 0.75)
        l.zNear = 10
        l.zFar = 6000
        key.light = l
        key.position = SCNVector3(size.width / 2 - 1300, size.height / 2 + 1500, 1300)
        key.look(at: SCNVector3(size.width / 2, size.height / 2, 0))
        scene.rootNode.addChildNode(key)

        let floor = SCNNode(geometry: SCNPlane(width: size.width, height: size.height))
        let fm = SCNMaterial()
        fm.lightingModel = .shadowOnly
        floor.geometry!.materials = [fm]
        floor.position = SCNVector3(size.width / 2, size.height / 2, 0)
        scene.rootNode.addChildNode(floor)

        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.transparencyMode = .aOne
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.normal.contents = RugArt.weaveNormalMap()
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.intensity = 0.22
        rug.castsShadow = true
        scene.rootNode.addChildNode(rug)
    }

    func setTexture(_ image: CGImage?, rugSize: SIMD2<Float>) {
        if ProcessInfo.processInfo.environment["UNDERRUG_PLAIN"] != nil {
            material.diffuse.contents = NSColor(white: 0.8, alpha: 1)
            material.normal.contents = ProcessInfo.processInfo.environment["UNDERRUG_PLAIN"] == "weave" ? RugArt.weaveNormalMap() : nil
            return
        }
        material.diffuse.contents = image
        material.normal.contentsTransform = SCNMatrix4MakeScale(CGFloat(rugSize.x / 4), CGFloat(rugSize.y / 4), 1)
    }

    private func topology(_ c: Cloth) {
        nx = c.nx; ny = c.ny
        var idx = [UInt32]()
        idx.reserveCapacity((nx - 1) * (ny - 1) * 6)
        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let a = UInt32(j * nx + i), b = a + 1, d = a + UInt32(nx), e = d + 1
                idx += [a, b, e, a, e, d]
            }
        }
        element = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        var tc = [CGPoint]()
        for j in 0..<ny { for i in 0..<nx { tc.append(CGPoint(x: Double(i) / Double(nx - 1), y: 1 - Double(j) / Double(ny - 1))) } }
        uv = SCNGeometrySource(textureCoordinates: tc)
    }

    func update(_ c: Cloth) {
        if c.nx != nx || c.ny != ny || element == nil { topology(c) }
        let P = c.pos
        var verts = [SCNVector3](), norms = [SCNVector3]()
        var shade = [Float]()
        shade.reserveCapacity(P.count * 4)
        verts.reserveCapacity(P.count); norms.reserveCapacity(P.count)
        for j in 0..<ny {
            for i in 0..<nx {
                let p = P[j * nx + i]
                verts.append(SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z)))
                let l = P[j * nx + max(i - 1, 0)], r = P[j * nx + min(i + 1, nx - 1)]
                let d = P[max(j - 1, 0) * nx + i], u = P[min(j + 1, ny - 1) * nx + i]
                var n = simd_cross(r - l, u - d)
                let len = simd_length(n)
                n = len > 1e-6 ? n / len : SIMD3(0, 0, 1)
                if n.z < 0 { n = -n }
                norms.append(SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z)))
                // cheap occlusion: cloth pressed into the valleys between lumps reads darker
                let g = c.ground.sample(p.x, p.y)
                let lift = min(max(p.z - 0.5, 0) / 13, 1), valley = g < 2 && p.z < 2 ? 0.06 : 0
                let v = 0.74 + 0.26 * lift - Float(valley)
                shade += [v, v, v, 1]
            }
        }
        // two blur passes over the normals: cloth reads as soft fabric instead of faceted paper
        for _ in 0..<2 {
            let src = norms
            for j in 0..<ny {
                for i in 0..<nx {
                    var acc = SIMD3<Float>(0, 0, 0)
                    for (di, dj) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let q = src[min(max(j + dj, 0), ny - 1) * nx + min(max(i + di, 0), nx - 1)]
                        acc += SIMD3(Float(q.x), Float(q.y), Float(q.z)) * (di == 0 && dj == 0 ? 2 : 1)
                    }
                    let n = simd_normalize(acc)
                    norms[j * nx + i] = SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z))
                }
            }
        }
        guard let element, let uv else { return }
        let colors = SCNGeometrySource(data: shade.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: P.count,
                                       usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms), uv, colors], elements: [element])
        g.materials = [material]
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        rug.geometry = g
        SCNTransaction.commit()
    }
}
