//
//  TileableRemoteBrightness.metal
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#include "ShaderTypes.h"

typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
    
} RasterizerData;

#pragma mark -
#pragma mark Viewport shaders

vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]],
             constant Vertex2D *vertexArray [[buffer(BVI_Vertices)]],
             constant vector_uint2 *viewportSizePointer [[buffer(BVI_ViewportSize)]])
{
    RasterizerData out;
    
    // Index into our array of positions to get the current vertex
    //   Our positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
    //   the origin)
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    
    // Get the size of the drawable so that we can convert to normalized device coordinates,
    float2 viewportSize = float2(*viewportSizePointer);
    
    // The output position of every vertex shader is in clip space (also known as normalized device
    //   coordinate space, or NDC). A value of (-1.0, -1.0) in clip-space represents the
    //   lower-left corner of the viewport whereas (1.0, 1.0) represents the upper-right corner of
    //   the viewport.
    
    // In order to convert from positions in pixel space to positions in clip space we divide the
    //   pixel coordinates by half the size of the viewport.
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize / 2.0);
    
    // Set the z component of our clip space position 0 (since we're only rendering in
    //   2-Dimensions for this sample)
    out.clipSpacePosition.z = 0.0;
    
    // Set the w component to 1.0 since we don't need a perspective divide, which is also not
    //   necessary when rendering in 2-Dimensions
    out.clipSpacePosition.w = 1.0;
    
    // Pass our input textureCoordinate straight to our output RasterizerData. This value will be
    //   interpolated with the other textureCoordinate values in the vertices that make up the
    //   triangle.
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    
    return out;
}

// Fragment function
fragment float4 fragmentShader(RasterizerData in [[stage_in]],
                               texture2d<half> colorTexture [[ texture(BTI_InputImage) ]],
                               constant float &sigma [[buffer(3)]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    // Sample the texture to obtain a color
    const half4 sample = colorTexture.sample(textureSampler, in.textureCoordinate);
    float4 result = float4(sample);

    return result;
}

#pragma mark -
#pragma mark Mask shaders

// Vertex shader for maping rectangle texture from viewport texture
vertex RasterizerData
maskVertexShader(uint vertexID [[vertex_id]],
             constant Vertex2D *vertexArray [[buffer(2)]],
             constant vector_uint2 *viewportSizePointer [[buffer(BVI_ViewportSize)]])
{
    RasterizerData out;
    
    // Set texture coordinates as vertex positions
    out.textureCoordinate = vertexArray[vertexID].position.xy;
    
    // Convert vertex positions from (0,1) to (-1,1)
    out.clipSpacePosition = float4(vertexArray[vertexID].position * 2 - 1, 0.0, 1.0);
    
    // Reverse Y axis
    out.clipSpacePosition.y *= -1;
    
    return out;
}

// Fragment shader for first gaussian blur pass (X axis)
fragment float4 maskFragmentShader(RasterizerData in [[stage_in]],
                                      texture2d<float> texture [[texture(0)]],
                                   constant float &sigma [[buffer(3)]])
{
    sampler simpleSampler(mip_filter::linear,
                          mag_filter::linear,
                          min_filter::linear,
                          address::mirrored_repeat);

    // Sample data from the texture.
    float4 colorSample;

    float4 color = float4(0.0);
    float radius = 3.0 * sigma, weightSum = 0.0, x = 0.0;

    for (int y = -radius; y <= radius; y++) {
        float2 offset = float2(y, x) / float2(texture.get_height(), texture.get_width());
        float weight = exp(-(y * y) / (2.0 * sigma * sigma));
        color += texture.sample(simpleSampler, in.textureCoordinate.xy + offset) * weight;
        weightSum += weight;
    }

    colorSample = color / weightSum;

    return colorSample;
}

// Fragment shader for second gaussian blur pass (Y axis)
fragment float4 maskSecondFragmentShader(RasterizerData in [[stage_in]],
                                      texture2d<float> texture [[texture(1)]],
                                         constant float &sigma [[buffer(4)]])
{
    sampler simpleSampler(mip_filter::linear,
                          mag_filter::linear,
                          min_filter::linear,
                          address::mirrored_repeat);

    // Sample data from the texture.
    float4 colorSample;

    float4 color = float4(0.0);
    float radius = 3.0 * sigma, weightSum = 0.0, y = 0.0;

    for (int x = -radius; x <= radius; x++) {
        float2 offset = float2(y, x) / float2(texture.get_height(), texture.get_width());
        float weight = exp(-(x * x) / (2.0 * sigma * sigma));
        color += texture.sample(simpleSampler, in.textureCoordinate.xy + offset) * weight;
        weightSum += weight;
    }

    colorSample = color / weightSum;

    return colorSample;
}
