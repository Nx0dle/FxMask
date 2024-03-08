//
//  FxMaskPlugIn.m
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#import "FxMaskPlugIn.h"
#import <IOSurface/IOSurfaceObjC.h>
#import "ShaderTypes.h"
#import "MetalDeviceCache.h"

typedef struct Parameters {
    FxPoint2D   upperLeft;
    FxPoint2D   lowerRight;
    double radius;
} Parameters;

@implementation FxMaskPlugIn

//---------------------------------------------------------
// initWithAPIManager:
//
// This method is called when a plug-in is first loaded, and
// is a good point to conduct any checks for anti-piracy or
// system compatibility. Returning NULL means that a plug-in
// chooses not to be accessible for some reason.
//---------------------------------------------------------

- (nullable instancetype)initWithAPIManager:(id<PROAPIAccessing>)newApiManager;
{
    self = [super init];
    if (self != nil)
    {
        _apiManager = newApiManager;
    }
    return self;
}

//---------------------------------------------------------
// properties
//
// This method should return an NSDictionary defining the
// properties of the effect.
//---------------------------------------------------------

- (BOOL)properties:(NSDictionary * _Nonnull *)properties
             error:(NSError * _Nullable *)error
{
    *properties = @{
                    kFxPropertyKey_MayRemapTime : [NSNumber numberWithBool:NO],
                    kFxPropertyKey_PixelTransformSupport : [NSNumber numberWithInt:kFxPixelTransform_ScaleTranslate],
                    kFxPropertyKey_VariesWhenParamsAreStatic : [NSNumber numberWithBool:NO]
                    };
    
    return YES;
}

//---------------------------------------------------------
// addParametersWithError
//
// This method is where a plug-in defines its list of parameters.
//---------------------------------------------------------

- (BOOL)addParametersWithError:(NSError**)error
{
    id<FxParameterCreationAPI_v5>   parmsApi;
    
    parmsApi = [_apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if (parmsApi == nil)
    {
        if (error != nil)
        {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedFailureReasonErrorKey :
                                                     @"Unable to get the FxParameterCreationAPI_v5 in -addParametersWithError:" }];
        }
        
        return NO;
    }
    
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    
    [parmsApi addPointParameterWithName:[bundle localizedStringForKey:@"Upper Left"
                                                                value:nil
                                                                table:nil]
                            parameterID:kLowerLeftID
                               defaultX:0.5
                               defaultY:0.5
                         parameterFlags:kFxParameterFlag_DEFAULT];
    
    [parmsApi addPointParameterWithName:[bundle localizedStringForKey:@"Lower Right"
                                                                value:nil
                                                                table:nil]
                            parameterID:kUpperRightID
                               defaultX:0.5
                               defaultY:0.5
                         parameterFlags:kFxParameterFlag_DEFAULT];
    
    [parmsApi addFloatSliderWithName:@"Blur Ammount"
                         parameterID:3
                        defaultValue:5.0
                        parameterMin:1.0
                        parameterMax:100.0
                           sliderMin:1.0
                           sliderMax:25.0
                               delta:0.01
                      parameterFlags:kFxParameterFlag_DEFAULT];
    
    return YES;
}

//---------------------------------------------------------
// pluginState:atTime:quality:error
//
// Your plug-in should get its parameter values, do any calculations it needs to
// from those values, and package up the result to be used later with rendering.
// The host application will call this method before rendering. The
// FxParameterRetrievalAPI* is valid during this call. Use it to get the values of
// your plug-in's parameters, then put those values or the results of any calculations
// you need to do with those parameters to render into an NSData that you return
// to the host application. The host will pass it back to you during subsequent calls.
// Do not re-use the NSData; always create a new one as this method may be called
// on multiple threads at the same time.
//---------------------------------------------------------

- (BOOL)pluginState:(NSData**)pluginState
             atTime:(CMTime)renderTime
            quality:(FxQuality)qualityLevel
              error:(NSError**)error
{
    id<FxParameterRetrievalAPI_v6>  paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    
    if (paramGetAPI == nil)
    {
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_ThirdPartyDeveloperStart + 20
                                     userInfo:@{
                    NSLocalizedDescriptionKey:
                                                    @"Unable to retrieve FxParameterRetrievalAPI_v6 in \
                                                    [-pluginStateAtTime:]" }];
        }
        return NO;
    }
    
    Parameters shapeState  = {
        { 1.0, 1.0 },
        { 1.0, 1.0 },
    };
    
    shapeState.radius = 1.0;
    
    [paramGetAPI getXValue:&shapeState.upperLeft.x
                 YValue:&shapeState.upperLeft.y
          fromParameter:kLowerLeftID
                 atTime:renderTime];
    
    [paramGetAPI getXValue:&shapeState.lowerRight.x
                 YValue:&shapeState.lowerRight.y
          fromParameter:kUpperRightID
                 atTime:renderTime];
    
    [paramGetAPI getFloatValue:&shapeState.radius
                 fromParameter:3
                        atTime:renderTime];
    
    *pluginState = [NSData dataWithBytes:&shapeState
                                  length:sizeof(shapeState)];
    
    return YES;
}

//---------------------------------------------------------
// destinationImageRect:sourceImages:destinationImage:pluginState:atTime:error
//
// This method will calculate the rectangular bounds of the output
// image given the various inputs and plug-in state
// at the given render time.
// It will pass in an array of images, the plug-in state
// returned from your plug-in's -pluginStateAtTime:error: method,
// and the render time.
//---------------------------------------------------------

- (BOOL)destinationImageRect:(FxRect *)destinationImageRect
                sourceImages:(NSArray<FxImageTile *> *)sourceImages
            destinationImage:(nonnull FxImageTile *)destinationImage
                 pluginState:(NSData *)pluginState
                      atTime:(CMTime)renderTime
                       error:(NSError * _Nullable *)outError
{
    if (pluginState == nil)
    {
        if (outError != nil)
        {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedFailureReasonErrorKey : @"pluginState is nil in -destinationImageRect:" }];
        }
        return NO;
    }
    
    Parameters shapeState;
    [pluginState getBytes:&shapeState
                   length:sizeof(shapeState)];
    
    // Convert the source into image space
    FxRect  srcRect = sourceImages [ 0 ].imagePixelBounds;
    FxMatrix44* srcInvPixTrans  = sourceImages [ 0 ].inversePixelTransform;
    FxPoint2D   srcLowerLeft    = { srcRect.left, srcRect.bottom };
    FxPoint2D   srcUpperRight   = { srcRect.right, srcRect.top };
    srcLowerLeft = [srcInvPixTrans transform2DPoint:srcLowerLeft];
    srcUpperRight = [srcInvPixTrans transform2DPoint:srcUpperRight];
    CGSize  srcImageSize    = CGSizeMake(srcUpperRight.x - srcLowerLeft.x, srcUpperRight.y - srcLowerLeft.y);
    
    // Union the various objects
    CGRect  imageBounds = CGRectMake(srcLowerLeft.x, srcLowerLeft.y, srcImageSize.width, srcImageSize.height);
    CGRect  rectBounds  = CGRectMake((shapeState.upperLeft.x) * srcImageSize.width,
                                     (shapeState.upperLeft.y) * srcImageSize.height,
                                     (shapeState.lowerRight.x - shapeState.upperLeft.x) * srcImageSize.width,
                                     (shapeState.lowerRight.y - shapeState.upperLeft.y) * srcImageSize.height);
    rectBounds = CGRectOffset(rectBounds, srcLowerLeft.x, srcLowerLeft.y);
    
    imageBounds = CGRectUnion(imageBounds, rectBounds);
    
    // Convert back into pixel space
    FxPoint2D   dstLowerLeft    = imageBounds.origin;
    FxPoint2D   dstUpperRight   = { imageBounds.origin.x + imageBounds.size.width, imageBounds.origin.y + imageBounds.size.height };
    
    FxMatrix44* dstPixelTrans   = destinationImage.pixelTransform;
    dstLowerLeft = [dstPixelTrans transform2DPoint:dstLowerLeft];
    dstUpperRight = [dstPixelTrans transform2DPoint:dstUpperRight];
    
    destinationImageRect->left = floor(dstLowerLeft.x);
    destinationImageRect->bottom = floor(dstLowerLeft.y);
    destinationImageRect->right = ceil(dstUpperRight.x);
    destinationImageRect->top = ceil(dstUpperRight.y);
    
    return YES;
}

#pragma mark -
#pragma mark parameterChanged method example

//- (BOOL)parameterChanged:(UInt32)paramID atTime:(CMTime)time error:(NSError * _Nullable *)error
//{
//    id<FxParameterRetrievalAPI_v6>  paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
//    
//    id<FxParameterSettingAPI_v6>  paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v6)];
//
//    if (paramID == kLowerLeftID)
//    {
//        double tmpX, tmpY;
//        [paramGetAPI getXValue:&tmpX YValue:&tmpY fromParameter:kLowerLeftID atTime:time];
//        
//        [paramSetAPI setXValue:tmpY YValue:tmpX toParameter:kUpperRightID atTime:time];
//        
//        
//    }
//    
//    
//    
//    return YES;
//}

//---------------------------------------------------------
// sourceTileRect:sourceImageIndex:sourceImages:destinationTileRect:destinationImage:pluginState:atTime:error
//
// Calculate tile of the source image we need
// to render the given output tile.
//---------------------------------------------------------

#pragma mark -

- (BOOL)sourceTileRect:(FxRect *)sourceTileRect
      sourceImageIndex:(NSUInteger)sourceImageIndex
          sourceImages:(NSArray<FxImageTile *> *)sourceImages
   destinationTileRect:(FxRect)destinationTileRect
      destinationImage:(FxImageTile *)destinationImage
           pluginState:(NSData *)pluginState
                atTime:(CMTime)renderTime
                 error:(NSError * _Nullable *)outError
{
    if (pluginState == nil)
    {
        if (outError != nil)
        {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedFailureReasonErrorKey : @"pluginState is nil in -destinationImageRect:" }];
        }
        return NO;
    }
    
    *sourceTileRect = destinationTileRect;
    
    return YES;
}

#pragma mark -
#pragma mark Rendering

//---------------------------------------------------------
// renderDestinationImage:sourceImages:pluginState:atTime:error:
//
// The host will call this method when it wants your plug-in to render an image
// tile of the output image. It will pass in each of the input tiles needed as well
// as the plug-in state needed for the calculations. Your plug-in should do all its
// rendering in this method. It should not attempt to use the FxParameterRetrievalAPI*
// object as it is invalid at this time. Note that this method will be called on
// multiple threads at the same time.
//---------------------------------------------------------

- (BOOL)renderDestinationImage:(FxImageTile *)destinationImage
                  sourceImages:(NSArray<FxImageTile *> *)sourceImages
                   pluginState:(NSData *)pluginState
                        atTime:(CMTime)renderTime
                         error:(NSError * _Nullable *)outError
{
    if ((pluginState == nil) || (sourceImages [ 0 ].ioSurface == nil) || (destinationImage.ioSurface == nil))
    {
        NSDictionary*   userInfo    = @{
                                        NSLocalizedDescriptionKey : @"Invalid plugin state received from host"
                                        };
        if (outError != NULL)
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:userInfo];
        return NO;
    }
    
    // This is where you would access parameter values and other info about the source tile
    // from the pluginState.
    Parameters shapeState;
    [pluginState getBytes:&shapeState
                   length:sizeof(shapeState)];
    
    // Set up the renderer, in this case we are using Metal.
    MetalDeviceCache*  deviceCache     = [MetalDeviceCache deviceCache];
    MTLPixelFormat     pixelFormat     = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
    id<MTLCommandQueue> commandQueue   = [deviceCache commandQueueWithRegistryID:sourceImages[0].deviceRegistryID
                                                                     pixelFormat:pixelFormat];
    if (commandQueue == nil)
    {
        return NO;
    }
    
    id<MTLCommandBuffer>    commandBuffer   = [commandQueue commandBuffer];
    commandBuffer.label = @"DynamicRegXPC Command Buffer";
    [commandBuffer enqueue];
    
    id<MTLTexture>  inputTexture    = [sourceImages[0] metalTextureForDevice:[deviceCache deviceWithRegistryID:sourceImages[0].deviceRegistryID]];
    
    id<MTLTexture>  outputTexture   = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];

    // Set texture descriptor for textures between in and out
    MTLTextureDescriptor *additionalTexDescriptor = [MTLTextureDescriptor new];
    additionalTexDescriptor.textureType = MTLTextureType2D;
    additionalTexDescriptor.width = inputTexture.width;
    additionalTexDescriptor.height = inputTexture.height;
    additionalTexDescriptor.pixelFormat = MTLPixelFormatRGBA16Float;
    additionalTexDescriptor.usage = MTLTextureUsageRenderTarget |
                            MTLTextureUsageShaderRead;
    
    id<MTLTexture> secondPassTexture = [commandBuffer.device newTextureWithDescriptor:additionalTexDescriptor];
    
    // Middle texture pixel format
    MTLPixelFormat secondPassPixFormat = secondPassTexture.pixelFormat;
    
    float   outputWidth     = (float)(destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left);
    
    float   outputHeight    = (float)(destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom);
    
    // Viewport vertices
    Vertex2D viewportVertices[]  = {
        { {  outputWidth / 2.0, -outputHeight / 2.0 }, { 1.0, 1.0 } },
        { { -outputWidth / 2.0, -outputHeight / 2.0 }, { 0.0, 1.0 } },
        { {  outputWidth / 2.0,  outputHeight / 2.0 }, { 1.0, 0.0 } },
        { { -outputWidth / 2.0,  outputHeight / 2.0 }, { 0.0, 0.0 } }
    };
    
    MTLViewport viewport    = {
        0, 0, outputWidth, outputHeight, -1.0, 1.0
    };
    
    // First pass rendering input image to output texture
    {
        @autoreleasepool {
            
            MTLRenderPassDescriptor* renderPassDescriptorCopyTextureToFinalPass = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDescriptorCopyTextureToFinalPass.colorAttachments[0].texture = outputTexture;
            renderPassDescriptorCopyTextureToFinalPass.colorAttachments[0].loadAction = MTLLoadActionClear;
            renderPassDescriptorCopyTextureToFinalPass.colorAttachments[0].storeAction = MTLStoreActionStore;
            
            id<MTLRenderCommandEncoder> commandEncoderCopyInputToOutput = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptorCopyTextureToFinalPass];
            
            id<MTLRenderPipelineState>  pipelineState  = [deviceCache pipelineStateWithRegistryID:sourceImages[0].deviceRegistryID pixelFormat:secondPassPixFormat];
            
            [commandEncoderCopyInputToOutput setViewport:viewport];
            
            [commandEncoderCopyInputToOutput setRenderPipelineState:pipelineState];
            
            [commandEncoderCopyInputToOutput setVertexBytes:viewportVertices
                                    length:sizeof(viewportVertices)
                                   atIndex:BVI_Vertices];
            
            simd_uint2  viewportSize = {
                (unsigned int)(outputWidth),
                (unsigned int)(outputHeight)
            };
            [commandEncoderCopyInputToOutput setVertexBytes:&viewportSize
                                    length:sizeof(viewportSize)
                                   atIndex:BVI_ViewportSize];
            
            [commandEncoderCopyInputToOutput setFragmentTexture:inputTexture
                                       atIndex:BTI_InputImage];
            
            [commandEncoderCopyInputToOutput drawPrimitives:MTLPrimitiveTypeTriangleStrip
                               vertexStart:0
                               vertexCount:4];
            
            [commandEncoderCopyInputToOutput endEncoding];
            
        }
    }
    
    // Second pass drawing rectangle with expanded Y axix borders and applying gaussian blur on X axis, rendering from input image to second pass texture
    {
        @autoreleasepool {
            
            // Expanded rectangle borders on Y axis to fill Y axis blur gap
            Vertex2D quadVerticesOffset[] = {
                {{(shapeState.upperLeft.x),   (shapeState.upperLeft.y + shapeState.radius)},  {0.0, 1.0}},
                {{(shapeState.upperLeft.x),   (shapeState.lowerRight.y - shapeState.radius)}, {0.0, 0.0}},
                {{(shapeState.lowerRight.x),  (shapeState.upperLeft.y + shapeState.radius)},  {1.0, 1.0}},
                {{(shapeState.lowerRight.x),  (shapeState.lowerRight.y - shapeState.radius)}, {1.0, 0.0}}
            };
            
            MTLRenderPassDescriptor* renderPassDescriptorSecondPass = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDescriptorSecondPass.colorAttachments[0].texture = secondPassTexture;
            renderPassDescriptorSecondPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
            renderPassDescriptorSecondPass.colorAttachments[0].storeAction = MTLStoreActionStore;
            
            id<MTLRenderCommandEncoder>  commandEncoderSecondPass  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptorSecondPass];
            
            id<MTLRenderPipelineState>  pipelineStateShape  = [deviceCache maskPipelineStateWithRegistryID:sourceImages[0].deviceRegistryID pixelFormat:secondPassPixFormat];
            
            [commandEncoderSecondPass setViewport:viewport];
            
            [commandEncoderSecondPass setRenderPipelineState:pipelineStateShape];
            
            [commandEncoderSecondPass setVertexBytes:quadVerticesOffset
                                    length:sizeof(quadVerticesOffset)
                                   atIndex:2];
            
            float fragmentRadius = (float)shapeState.radius;
            [commandEncoderSecondPass setFragmentBytes:&fragmentRadius
                                    length:sizeof(fragmentRadius)
                                   atIndex:3];
            
            [commandEncoderSecondPass setFragmentTexture:inputTexture
                                       atIndex:0];
            
            [commandEncoderSecondPass drawPrimitives:MTLPrimitiveTypeTriangleStrip
                               vertexStart:0
                               vertexCount:4];
            
            [commandEncoderSecondPass endEncoding];
            
        }
    }
    
    // Final pass drawing in the main size rectangle gaussian blur on Y axis
    {
        @autoreleasepool {
            
            // Main size rectangle on final pass
            Vertex2D quadVertices[] = {
                {{  (shapeState.upperLeft.x),   (shapeState.upperLeft.y)},  {0.0, 1.0}},
                {{  (shapeState.upperLeft.x),   (shapeState.lowerRight.y)}, {0.0, 0.0}},
                {{  (shapeState.lowerRight.x),  (shapeState.upperLeft.y)},  {1.0, 1.0}},
                {{  (shapeState.lowerRight.x),  (shapeState.lowerRight.y)}, {1.0, 0.0}}
            };
            
            MTLRenderPassDescriptor* renderPassDescriptorFinalPass = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDescriptorFinalPass.colorAttachments[0].texture = outputTexture;
            renderPassDescriptorFinalPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
            renderPassDescriptorFinalPass.colorAttachments[0].storeAction = MTLStoreActionStore;
            
            id<MTLRenderCommandEncoder>   commandEncoderFinalPass  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptorFinalPass];
            
            id<MTLRenderPipelineState>  pipelineStateShapeSecondPass  = [deviceCache maskSecondPassPipelineStateWithRegistryID:sourceImages[0].deviceRegistryID pixelFormat:secondPassPixFormat];
            
            [commandEncoderFinalPass setViewport:viewport];
            
            [commandEncoderFinalPass setRenderPipelineState:pipelineStateShapeSecondPass];
            
            [commandEncoderFinalPass setVertexBytes:quadVertices
                                    length:sizeof(quadVertices)
                                   atIndex:2];
            
            float fragmentRadius = (float)shapeState.radius;
            [commandEncoderFinalPass setFragmentBytes:&fragmentRadius
                                    length:sizeof(fragmentRadius)
                                   atIndex:4];
            
            [commandEncoderFinalPass setFragmentTexture:secondPassTexture
                                       atIndex:1];
            
            [commandEncoderFinalPass drawPrimitives:MTLPrimitiveTypeTriangleStrip
                               vertexStart:0
                               vertexCount:4];
            
            [commandEncoderFinalPass endEncoding];
            
        }
    }
    
    [commandBuffer commit];
    
    [commandBuffer waitUntilCompleted];
    
    [deviceCache returnCommandQueueToCache:commandQueue];
    
    return YES;
    
}

@end
