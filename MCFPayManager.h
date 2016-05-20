//
//  MCFPayManager.h
//  AiPark
//
//  Created by MCF on 15/11/10.
//  Copyright © 2015年 智慧停车. All rights reserved.
//

/**
 *  in this file,intergrated WEIXINPay ZHIFUBAO & BAIDUWallet 
 *  get all parameters done at first, then you can start your pay job
 *  by this file
 */
#import <Foundation/Foundation.h>
#import "AFNetworking.h"
#import "WXApi.h"
#import <AlipaySDK/AlipaySDK.h>
#import "BDWalletSDKMainManager.h"
#import "YFUserTool.h"
typedef  NS_ENUM(NSInteger,payResult) {
    payfailed            = -1,
    paySuccess           = 0,
    payInProsess         = 1,
    payCanceled          = 2,
    serverFailed         = 3,
    tokenError           = 4,
    WXClientUninstalled  = 5,
    payWithBalance       = 6
};
@protocol netConditionProtocol <NSObject>

- (void)timeOut;

- (void)tokenError;

- (void)netError;
@end

@protocol payProtocol <NSObject>
@required
- (void)refreshUserBalanceWith:(NSString *)balance;
@end

@interface MCFPayManager : NSObject
@property(nonatomic,weak)id<netConditionProtocol>netDelegate;
@property(nonatomic,weak)id<payProtocol>payDelegate;

+ (instancetype)manager;

+ (void)doPayByAlipayWithAmount:(CGFloat)amount;

+ (void)doPayByWeiXinWithAmount:(CGFloat)amount;

+ (void)doPayByBaiFuBaoWithAmount:(CGFloat)amount controller:(id<BDWalletSDKMainManagerDelegate>)ctrler;

+ (void)rememberPaymethod:(int)method;

- (void)requestUserBalance;

- (void)getUserScore:(void (^)(id responseObject))complete failure:(void (^)(NSHTTPURLResponse *response,NSError *error))failure;

- (void)Alipay:(CGFloat)amount
    paySuccess:(void(^)(id responseObject))PaySuccess
    payFailure:(void(^)(id responseObject))payFailure
       failure:(void(^)(NSHTTPURLResponse *response,NSError *error))failure;

- (void)WeiXinPay:(CGFloat)amount
       paySuccess:(void (^)(void))PaySuccess
  notInstalledYet:(void (^)(void))notInstalledYet
          failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure;

- (void)BaiFuBaoWithAmount:(CGFloat)amount
                controller:(id<BDWalletSDKMainManagerDelegate>)ctrler
                   success:(void(^)(void))success
                   failure:(void(^)(void))failure;

@end
