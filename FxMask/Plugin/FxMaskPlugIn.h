//
//  FxMaskPlugIn.h
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

@interface FxMaskPlugIn : NSObject <FxTileableEffect>
@property (assign) id<PROAPIAccessing> apiManager;
@end
