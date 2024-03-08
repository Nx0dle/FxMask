//
//  TileableRemoteBrightnessShaderTypes.h
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#import <simd/simd.h>

enum {
    kLowerLeftID    = 1,
    kUpperRightID   = 2,
};

typedef enum BrightnessVertexInputIndex {
    BVI_Vertices        = 0,
    BVI_ViewportSize    = 1
} BrightnessVertexInputIndex;

typedef enum BrightnessTextureIndex {
    BTI_InputImage  = 0
} BrightnessTextureIndex;

typedef enum BrightnessFragmentIndex {
    BFI_Brightness  = 0
} BrightnessFragmentIndex;

typedef struct Vertex2D {
    vector_float2   position;
    vector_float2   textureCoordinate;
} Vertex2D;

typedef struct ShapeVertex {
    vector_float2 position;
    vector_float4 color;
} ShapeVertex;

#endif
