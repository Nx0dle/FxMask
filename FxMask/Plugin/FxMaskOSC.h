//
//  FxMaskOSC.h
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>
#import <Metal/Metal.h>

@interface FxMaskOSC : NSObject <FxOnScreenControl_v4>
{
    id<PROAPIAccessing> apiManager;
    
    CGPoint lastObjectPosition;
}

@end
