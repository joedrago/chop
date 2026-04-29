import Foundation
import Metal
import MetalKit

/// Process-wide Metal device + command queue, lazily created.
@MainActor
enum MetalContext {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let queue: MTLCommandQueue? = device?.makeCommandQueue()
    static let pipelineCache: PipelineCache = PipelineCache()
}

@MainActor
final class PipelineCache {
    private var quadPipeline: MTLRenderPipelineState?
    private var samplerNearest: MTLSamplerState?

    func quad(format: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let p = quadPipeline { return p }
        guard
            let device = MetalContext.device,
            let library = makeShaderLibrary(device: device)
        else {
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "quad_vertex")
        desc.fragmentFunction = library.makeFunction(name: "quad_fragment")
        desc.colorAttachments[0].pixelFormat = format
        let p = try? device.makeRenderPipelineState(descriptor: desc)
        quadPipeline = p
        return p
    }

    func nearestSampler() -> MTLSamplerState? {
        if let s = samplerNearest { return s }
        guard let device = MetalContext.device else { return nil }
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        d.mipFilter = .notMipmapped
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        let s = device.makeSamplerState(descriptor: d)
        samplerNearest = s
        return s
    }
}

/// Inline Metal shader source. Tiny enough that an in-tree .metal file plus a
/// build phase isn't worth the ceremony — we compile from string at startup.
private let kShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        // Image-space → clip-space transform expressed as scale + translate.
        // clip.xy = (pix.xy * scale + translate)
        float2 scale;
        float2 translate;
        // Image dimensions in pixels and zoom (backing pixels per image
        // pixel). Used by the fragment shader to draw a pixel-boundary grid
        // when the user is zoomed in far enough to see individual pixels.
        float2 imageSize;
        float zoom;
        float _pad;
    };

    vertex VOut quad_vertex(uint vid [[vertex_id]],
                             constant Uniforms& u [[buffer(0)]]) {
        // Quad in image-space: (0,0)-(1,1), expanded by uniform scale below.
        float2 corners[4] = { float2(0,0), float2(1,0), float2(0,1), float2(1,1) };
        float2 c = corners[vid];
        VOut o;
        float2 clip = c * u.scale + u.translate;
        o.position = float4(clip.x, clip.y, 0.0, 1.0);
        // Texture is loaded with top-left origin (MTKTextureLoader default
        // for CGImage). Geometry is already flipped via negative scale.y in
        // the swift caller, so UV passes through unchanged.
        o.uv = c;
        return o;
    }

    fragment float4 quad_fragment(VOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler s [[sampler(0)]]) {
        float4 base = tex.sample(s, in.uv);

        // Pixel-boundary grid. Only visible when zoomed in enough that each
        // image pixel is at least ~8 backing pixels on screen — otherwise
        // grid lines overwhelm the image. Fade in from zoom 8 to 16.
        float gridOpacity = clamp((u.zoom - 8.0) / 8.0, 0.0, 1.0);
        if (gridOpacity > 0.0) {
            // Position within image pixel space.
            float2 px = in.uv * u.imageSize;
            // Distance to nearest pixel boundary in image-pixel units.
            float2 d = abs(fract(px) - 0.5) * 2.0;  // d in [0, 1], 1 at edge
            float edge = max(d.x, d.y);
            // The line is `lineWidthBacking` backing pixels wide. Convert to
            // image-pixel-space using zoom (backing pixels per image pixel),
            // then to the d ∈ [0,1] coordinate (where 1 unit = 0.5 image px).
            float lineWidthBacking = 1.0;
            float lineThreshold = 1.0 - (lineWidthBacking / u.zoom) * 2.0;
            if (edge >= lineThreshold) {
                // Invert the underlying color so the grid is visible against
                // any image — pure black, pure white, or anything in between.
                // (Pure 50% gray is its own inverse and will still vanish; in
                // practice it doesn't matter for real image content.)
                float t = smoothstep(lineThreshold, 1.0, edge) * gridOpacity;
                float3 line = float3(1.0) - base.rgb;
                base.rgb = mix(base.rgb, line, t);
            }
        }
        return base;
    }
    """

private func makeShaderLibrary(device: MTLDevice) -> MTLLibrary? {
    let opts = MTLCompileOptions()
    return try? device.makeLibrary(source: kShaderSource, options: opts)
}
