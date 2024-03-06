//
//  FxMaskOSC.m
//  FxMask
//
//  Created by MotionVFX on 06/03/2024.
//

#import "FxMaskOSC.h"
#import <Foundation/Foundation.h>
#import "MetalDeviceCache.h"
#import "ShaderTypes.h"

@implementation FxMaskOSC
{
    NSLock* lastPositionLock;
}

- (instancetype)initWithAPIManager:(id<PROAPIAccessing>)newAPIManager
{
    self = [super init];
    
    if (self != nil)
    {
        apiManager = newAPIManager;
        lastPositionLock = [[NSLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [lastPositionLock release];
    [super dealloc];
}

@end
