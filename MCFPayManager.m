//
//  MCFPayManager.m
//  AiPark
//
//  Created by MCF on 15/11/10.
//  Copyright © 2015年 智慧停车. All rights reserved.
//
/**
 *  支付注意事项
 *  1.微信代理回调方法在AppDelegate里面，需要添加对应观察者获取微信客户端支付结果
 *  2.百度支付出现时会调用viewwilldisappear方法，如果在此方法销毁观察者，注意在代理方法里重新注册通知
 *  3.百度支付需要在相应的controller里添加代理回调方法
 *  4.注意controller服从微信和百度的协议
 *  5.注意iOS9的返回上一个应用，在客户端完成支付后，在本应用AppDelegate里激活方法里发送请求余额消息
 */
#import "MCFPayManager.h"
#import "YFAlertView.h"

@interface MCFPayManager ()
@property(nonatomic,strong)NSTimer *tenSecondsLimit;
@end
@implementation MCFPayManager

+ (instancetype)manager{
    static MCFPayManager *manager= nil;
    static dispatch_once_t onceMark;
    dispatch_once(&onceMark, ^{
        manager = [MCFPayManager new];
    });
    return manager;
}

- (void)HTTPRequestPost:(NSString *)URLStr
             parameters:(NSDictionary *)parameters
                success:(void (^)(NSHTTPURLResponse *task, id responseObject))success
                failure:(void (^)(NSHTTPURLResponse *task,NSError *error))failure{
    
    if (URLStr.length<=0) return;
    [self _startTimer];
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager POST:URLStr parameters:parameters success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [self _stopTimer];
        success(operation.response,responseObject);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [self _stopTimer];
        if (operation.response.statusCode == 910) {
            [self _tokenEror];
        }else{
            [self.netDelegate netError];
        }
        failure(operation.response,error);
    }];
}
- (void)_startTimer{
    _tenSecondsLimit = [NSTimer scheduledTimerWithTimeInterval:10.f target:self selector:@selector(_timeOutAction) userInfo:nil repeats:NO];
    [_tenSecondsLimit fire];
    [[UIApplication sharedApplication]setNetworkActivityIndicatorVisible:YES];
}
- (void)_stopTimer{
    [_tenSecondsLimit invalidate];
    [[UIApplication sharedApplication]setNetworkActivityIndicatorVisible:NO];
}
- (void)_tokenEror{
    YFAlertView *alertView = [[YFAlertView alloc] init];
    alertView.tag = kTagTokenError;
    [alertView showWithMessage:@"此账号已在另一台设备上登录" imgName:@"tishi" buttonTitle:@"重新登录"];
    [self.netDelegate tokenError];
}

- (void)_timeOutAction{
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager.operationQueue cancelAllOperations];
}
- (void)getUserScore:(void (^)(id responseObject))complete failure:(void (^)(NSHTTPURLResponse *response,NSError *error))failure{
    NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                                [MCFPayManager getCurrentUserToken],kToken,
                                @"",kData,
                                @"",kVersion,nil];
    NSDictionary* paramsDict = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:parameters], kParams, nil];
    NSString *scoreURL = [NSString stringWithFormat:@"%@%@",HOST,GET_USER_SCORE];
    [self HTTPRequestPost:scoreURL parameters:paramsDict success:^(NSHTTPURLResponse *task, id responseObject) {
        complete(responseObject);
    } failure:^(NSHTTPURLResponse *task, NSError *error) {
        failure(task,error);
    }];
}
#pragma mark - 支付宝支付（重构版）
- (void)preAliPayWithAmount:(CGFloat)amount
                    success:(void (^)(NSHTTPURLResponse *operation, id responseObject))success
                    failure:(void (^)(NSHTTPURLResponse *operation, NSError *error))failure
{
    NSString* url = [NSString stringWithFormat:@"%@%@", HOST,CHARGE_MONEY_ALIPAY];
    NSDictionary* parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                                [MCFPayManager _float2string:amount], kPayFetchMoney,
                                @"app", kPayFetchSrc,
                                nil];
    NSDictionary* dataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              [CommonTools revertJsonString:parameters], kData,
                              [MCFPayManager getCurrentUserToken], kToken,
                              @"", kVersion,
                              @"",kPageNum,
                              @"",kPageSize,
                              @"",kVersion,
                              nil];
    NSDictionary* paramsDict = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:dataDict], kParams, nil];
    [self HTTPRequestPost:url parameters:paramsDict success:^(NSHTTPURLResponse *task, id responseObject) {
        success(task,responseObject);
    } failure:^(NSHTTPURLResponse *task, NSError *error) {
        failure(task,error);
    }];
}

-(void)Alipay:(CGFloat)amount
   paySuccess:(void (^)(id))PaySuccess
   payFailure:(void (^)(id))payFailure
      failure:(void (^)(NSHTTPURLResponse *, NSError *))failure
{
    NSString* appScheme = @"SmartParking";//应用注册scheme,在AlixPayDemo-Info.plist定义URL types   SmartParking
    [self preAliPayWithAmount:amount success:^(NSHTTPURLResponse *operation, id responseObject) {
        NSString* resultCode = [responseObject objectForKey:kCode];
        MyLog(@"跳转到支付页面:支付宝.结果码为%@",resultCode);
        if ([resultCode intValue] == kSucCode) {
            NSDictionary* resultDic = [responseObject objectForKey:kData];
            NSString* orderString = [NSString stringWithFormat:@"%@",[resultDic objectForKey:kPayOrder]];// 订单字符串
            MyLog(@"支付订单字符串请求成功: %@",orderString);
            // 调用支付接口 支付并通过回调返回结果
            [[AlipaySDK defaultService] payOrder:orderString fromScheme:appScheme callback:^(NSDictionary *resultDic) {
                MyLog(@"viewController pay result = %@",resultDic);
                //------------ 验证支付结果 ----------------
                NSString* resultStatus = [resultDic objectForKey:@"resultStatus"];
                if ([resultStatus isEqualToString:@"9000"] ) {   // 订单支付成功 没有验证 waitSing
                    PaySuccess(resultStatus);
                }else{
                    payFailure(resultStatus);
                }
            }];
        } else {
            NSString* errMsg = [responseObject objectForKey:kMsg];
            MyLog(@"支付订单字符串请求失败! err:%@",errMsg);
        }
    } failure:^(NSHTTPURLResponse *operation, NSError *error) {
        failure(operation,error);
    }];
}

- (void)preWEIXINPayWithAmount:(CGFloat)amount
                       success:(void (^)(NSHTTPURLResponse *operation, id responseObject))success
                       failure:(void (^)(NSHTTPURLResponse *operation, NSError *error))failure{

    NSString *payRequestUrl = [NSString stringWithFormat:@"%@%@",HOST,CHARGE_MONEY_WEIXIN];
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [MCFPayManager getCurrentUserToken],kToken,
                             [MCFPayManager _float2string:amount],@"total_fee",
                             @"app",kPayFetchSrc,
                             nil];
    NSDictionary* paraDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [CommonTools revertJsonString:dataDic], kData,
                             [MCFPayManager getCurrentUserToken], kToken,
                             @"",kPageNum,
                             @"",kPageSize,
                             @"",kVersion,
                             nil];
    NSDictionary *allPara = [NSDictionary dictionaryWithObject:[CommonTools revertJsonString:paraDic] forKey:kParams];
    [self HTTPRequestPost:payRequestUrl parameters:allPara success:^(NSHTTPURLResponse *task, id responseObject) {
        success(task,responseObject);
    } failure:^(NSHTTPURLResponse *task, NSError *error) {
        failure(task,error);
    }];
}
- (void)WeiXinPay:(CGFloat)amount
       paySuccess:(void (^)(void))PaySuccess
    notInstalledYet:(void (^)(void))notInstalledYet
          failure:(void (^)(NSHTTPURLResponse *response, NSError *error))failure
{
    if ([WXApi isWXAppInstalled]) {
        [self preWEIXINPayWithAmount:amount success:^(NSHTTPURLResponse *operation, id responseObject){
            NSDictionary *feedBackDataDic = [responseObject objectForKey:@"data"];
            NSString *codeStr = [responseObject objectForKey:@"code"];
            if([codeStr isEqualToString:@"0000"]){
                //========微信请求参数拼接==========
                PayReq* request = [[PayReq alloc] init];
                request.partnerId = [feedBackDataDic objectForKey:@"partnerid"];
                request.prepayId = [feedBackDataDic objectForKey:@"prepayid"];
                request.package = [feedBackDataDic objectForKey:@"package"];
                request.nonceStr = [feedBackDataDic objectForKey:@"noncestr"];
                NSString *str = [NSString stringWithFormat:@"%@",[feedBackDataDic objectForKey:@"timestamp"]];
                MyLog(@"微信时间戳%@",str);
                request.timeStamp = str.longLongValue;
                request.sign = [feedBackDataDic objectForKey:@"sign"];
                //========微信请求参数拼接结束==========
                BOOL sendOK = [WXApi sendReq:request];//向微信客户端发送消息
                if(sendOK){
                    PaySuccess();
                }else{
                    MyLog(@"发送微信请求失败:%i",sendOK);
                }
            }
        } failure:^(NSHTTPURLResponse *operation, NSError *error) {
            failure(operation,error);
        }];
    }else{
        notInstalledYet();
    }
}
- (void)preBaifuBao:(CGFloat)amount
     success:(void (^)(NSHTTPURLResponse *operation, id responseObject))success
     failure:(void (^)(NSHTTPURLResponse *operation, NSError *error))failure{
    NSString *baiduURL = [NSString stringWithFormat:@"%@%@",HOST,CHARGE_MONEY_BAIDU];
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [MCFPayManager _float2string:amount],@"total_fee",
                             @"app",kPayFetchSrc,
                             nil];
    NSDictionary *paraDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [MCFPayManager getCurrentUserToken],kToken,
                             [CommonTools revertJsonString:dataDic],kData,
                             @"",kPageNum,
                             @"",kPageSize,
                             @"",kVersion,
                             nil];
    NSDictionary *paramsDic = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:paraDic],kParams, nil];
    [self HTTPRequestPost:baiduURL parameters:paramsDic success:^(NSHTTPURLResponse *task, id responseObject) {
        success(task,responseObject);
    } failure:^(NSHTTPURLResponse *task, NSError *error) {
        failure(task,error);
    }];
}
- (void)BaiFuBaoWithAmount:(CGFloat)amount
                controller:(id<BDWalletSDKMainManagerDelegate>)ctrler
                   success:(void (^)(void))success
                   failure:(void (^)(void))failure
{
    [self preBaifuBao:amount success:^(NSHTTPURLResponse *operation, id responseObject) {
        NSDictionary *BDDic = [responseObject objectForKey:kData];
        NSString *BDStr = [BDDic objectForKey:@"url"];
        MyLog(@"百度钱包支付%@====%@",responseObject,BDStr);
        BDWalletSDKMainManager *BDManager = [BDWalletSDKMainManager getInstance];
        BDManager.bdWalletNavTitleColor = [UIColor blackColor];
        [BDManager doPayWithOrderInfo:BDStr params:nil delegate:ctrler];
        success();
    } failure:^(NSHTTPURLResponse *operation, NSError *error) {
        failure();
    }];
}
#pragma mark - 支付宝支付
+ (void)doPayByAlipayWithAmount:(CGFloat)amount
                        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure{
    NSString* url = [NSString stringWithFormat:@"%@%@", HOST,PAY_PARK_ALIPAY];
    NSDictionary* parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                                [self _float2string:amount], kPayFetchMoney,
                                @"app", kPayFetchSrc,
                                nil];
    NSDictionary* dataDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              [CommonTools revertJsonString:parameters], kData,
                              [self getCurrentUserToken], kToken,
                              @"", kVersion,
                              @"",kPageNum,
                              @"",kPageSize,
                              @"",kVersion,
                              nil];
    NSDictionary* paramsDict = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:dataDict], kParams, nil];
    AFHTTPRequestOperationManager* manager = [AFHTTPRequestOperationManager manager];
    [manager POST:url parameters:paramsDict success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(operation,responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        failure(operation,error);
    }];
}

+ (void)doPayByAlipayWithAmount:(CGFloat)amount{
    NSString* appScheme = @"SmartParking";//应用注册scheme,在AlixPayDemo-Info.plist定义URL types   SmartParking
    __block NSString *_outTradeNumber;
    __block payResult _result;
    [self doPayByAlipayWithAmount:amount success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSString* resultCode = [responseObject objectForKey:kCode];
        MyLog(@"跳转到支付页面:支付宝.结果码为%@",resultCode);
        if ([resultCode intValue] == kSucCode) {
            NSDictionary* resultDic = [responseObject objectForKey:kData];
            NSString* orderString = [NSString stringWithFormat:@"%@",[resultDic objectForKey:kPayOrder]];// 订单字符串
            MyLog(@"支付订单字符串请求成功: %@",orderString);
            _outTradeNumber = [NSString stringWithFormat:@"%@",@""];// 订单号
            BOOL isLogined = [[AlipaySDK defaultService] isLogined];// 检测本地是否曾经登录使用过
            if (isLogined) {
                MyLog(@"曾经登录过");
            }
            // 调用支付接口 支付并通过回调返回结果
            [[AlipaySDK defaultService] payOrder:orderString fromScheme:appScheme callback:^(NSDictionary *resultDic) {
                //MyLog(@"viewControlffl fde r  pay result = %@",resultDic);
                //------------ 验证支付结果 ----------------
                NSDictionary* payInfoDic = [CommonTools getOutPayResultInfoWithResultStr:[resultDic objectForKey:@"result"]];
                NSString* tradeNo = [NSString stringWithFormat:@"%@",[payInfoDic objectForKey:kTradeNumber]];
                NSString* success = [NSString stringWithFormat:@"%@",[payInfoDic objectForKey:kSuccess]];
                MyLog(@"resultStatus = %@ success = %@",[resultDic objectForKey:@"resultStatus"], success);
                NSString* resultStatus = [resultDic objectForKey:@"resultStatus"];
                _outTradeNumber = tradeNo;
                if ([resultStatus isEqualToString:@"9000"] ) {   // 订单支付成功 没有验证 waitSing
                    _result = paySuccess;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"zhifubaoclientOut" object:nil];
                }else{
                    _result = payfailed;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZFBPayFailedOut" object:nil];
                }
            }];
        } else {
            NSString* errMsg = [responseObject objectForKey:kMsg];
            MyLog(@"支付订单字符串请求失败! err:%@",errMsg);
            _result = payfailed;
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        MyLog(@"网络请求失败: error: %@",error);
        if (operation.response.statusCode == 910) {
            _result = tokenError;
        }else {
            _result = serverFailed;
        }
    }];
}
#pragma mark - 微信支付  反馈结果在appdelegate里
+ (void)doPayByWeiXinWithAmount:(CGFloat)amount
                        success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                        failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure{
    NSString *payRequestUrl = [NSString stringWithFormat:@"%@%@",HOST,PAY_PARK_WEIXIN];
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [self getCurrentUserToken],kToken,
                             [self _float2string:amount],@"total_fee",
                             @"app",kPayFetchSrc,
                             nil];
    NSDictionary* paraDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [CommonTools revertJsonString:dataDic], kData,
                             [self getCurrentUserToken], kToken,
                             @"",kPageNum,
                             @"",kPageSize,
                             @"",kVersion,
                             nil];
    NSDictionary *allPara = [NSDictionary dictionaryWithObject:[CommonTools revertJsonString:paraDic] forKey:kParams];
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager POST:payRequestUrl parameters:allPara success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(operation,responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        failure(operation,error);
    }];
}
+ (void)doPayByWeiXinWithAmount:(CGFloat)amount{
    __block payResult _result;
    if ([WXApi isWXAppInstalled]) {
        [self doPayByWeiXinWithAmount:amount success:^(AFHTTPRequestOperation *operation, id responseObject) {
            MyLog(@"微信支付请求结果为%@===%i===%@",responseObject,[NSThread isMainThread],[responseObject objectForKey:@"msg"]);
            NSDictionary *feedBackDataDic = [responseObject objectForKey:@"data"];
            NSString *codeStr = [responseObject objectForKey:@"code"];
            if([codeStr isEqualToString:@"0000"]){
                //========微信请求参数拼接==========
                PayReq* request = [[PayReq alloc] init];
                request.partnerId = [feedBackDataDic objectForKey:@"partnerid"];
                request.prepayId = [feedBackDataDic objectForKey:@"prepayid"];
                request.package = [feedBackDataDic objectForKey:@"package"];
                request.nonceStr = [feedBackDataDic objectForKey:@"noncestr"];
                NSString *str = [NSString stringWithFormat:@"%@",[feedBackDataDic objectForKey:@"timestamp"]];
                MyLog(@"微信时间戳%@",str);
                request.timeStamp = str.longLongValue;
                request.sign = [feedBackDataDic objectForKey:@"sign"];
                //========微信请求参数拼接结束==========
                BOOL sendOK = [WXApi sendReq:request];//向微信客户端发送消息
                if(sendOK){
                    MyLog(@"微信请求发送成功");
                }else{
                    MyLog(@"发送微信请求失败:%i",sendOK);
                }
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            MyLog(@"微信支付失败%@",error);
            if (operation.response.statusCode == 910) {
                _result = tokenError;
            }else {
                _result = serverFailed;
            }
        }];
    }else{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WXClientUninstalled" object:nil];

        _result = WXClientUninstalled;
    }
}
#pragma mark - 百度钱包支付
+ (void)doPayByBaiFuBaoWithAmount:(CGFloat)amount
                               success:(void (^)(AFHTTPRequestOperation *operation, id responseObject))success
                               failure:(void (^)(AFHTTPRequestOperation *operation, NSError *error))failure{
    NSString *baiduURL = [NSString stringWithFormat:@"%@%@",HOST,PAY_PARK_BAIDU];
    NSDictionary *dataDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [self _float2string:amount],@"total_fee",
                             @"app",kPayFetchSrc,
                             nil];
    NSDictionary *paraDic = [NSDictionary dictionaryWithObjectsAndKeys:
                             [self getCurrentUserToken],kToken,
                             [CommonTools revertJsonString:dataDic],kData,
                             @"",kPageNum,
                             @"",kPageSize,
                             @"",kVersion,
                             nil];
    NSDictionary *paramsDic = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:paraDic],kParams, nil];
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager POST:baiduURL parameters:paramsDic success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(operation,responseObject);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        failure(operation,error);
    }];
}
+ (void)doPayByBaiFuBaoWithAmount:(CGFloat)amount controller:(id<BDWalletSDKMainManagerDelegate>)ctrler{
    __block payResult _result;
    [self doPayByBaiFuBaoWithAmount:amount success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSDictionary *BDDic = [responseObject objectForKey:kData];
        NSString *BDStr = [BDDic objectForKey:@"url"];
        MyLog(@"百度钱包支付%@====%@",responseObject,BDStr);
        BDWalletSDKMainManager *BDManager = [BDWalletSDKMainManager getInstance];
        BDManager.bdWalletNavTitleColor = [UIColor blackColor];
        [BDManager doPayWithOrderInfo:BDStr params:nil delegate:ctrler];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        MyLog(@"百度钱包支付失败%@",error);
        if (operation.response.statusCode == 910) {
            _result = tokenError;
        }else {
            _result = serverFailed;
        }
    }];
}
#pragma mark - 获取用户余额
- (void)requestUserBalance{
    NSString *url = [NSString stringWithFormat:@"%@%@",HOST,GET_USER_BALANCE];
    MyLog(@"用户余额：%@",url);
    NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                                [MCFPayManager getCurrentUserToken],kToken,
                                @"",kData,
                                @"",kVersion,nil];
    NSDictionary *paramsDict = [NSDictionary dictionaryWithObjectsAndKeys:[CommonTools revertJsonString:parameters],kParams, nil];
    //=========拼接结束============
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    [manager POST:url parameters:paramsDict success:^(AFHTTPRequestOperation *operation, NSDictionary *responseObject) {
        
        MyLog(@"用户余额请求返回结果为：%@",responseObject);
        NSDictionary *dataDic = [responseObject objectForKey:kData];
        NSString *moneyStr = [NSString stringWithFormat:@"%@",[dataDic objectForKey:@"money"]];
        MyLog(@"moneyStr == class:%@", [[dataDic objectForKey:@"money"] class]);
        double serverMpney = moneyStr.doubleValue;
        NSString *transMoneyStr = nil;
        if([[dataDic objectForKey:@"money"] isKindOfClass:[NSNull class]]|| [moneyStr isEqualToString:@"<null>"]||[dataDic objectForKey:@"money"]==NULL ){
            transMoneyStr = @"0.00";
        }else{
            transMoneyStr = [NSString stringWithFormat:@"%.2f",serverMpney];
            [self.payDelegate refreshUserBalanceWith:transMoneyStr];
        }
        if( [[[YFUserTool currentUser] balance] doubleValue]!=[transMoneyStr doubleValue]){//比较当前user余额，
            [YFUserTool currentUser].balance = [NSString stringWithFormat:@"%@",transMoneyStr];
            [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_USER_BALANCE_CHANGED object:[NSString stringWithFormat:@"%@",transMoneyStr]];
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        MyLog(@"用户余额请求数据失败%@",error);
        [self.netDelegate netError];

    }];
}
+ (NSString *)getCurrentUserToken{
    SPUser *currentUser = [YFUserTool currentUser];
    return currentUser.token;
}
+ (NSString *)_float2string:(CGFloat) num{
    CGFloat temp;
    if (num<=0) {
        temp = 0.0;
    }else{
        temp = num;
    }
    return [NSString stringWithFormat:@"%2f",temp];
}
/*记忆支付方法*/
+ (void)rememberPaymethod:(int)method{
    
    NSUserDefaults *userData= [NSUserDefaults standardUserDefaults];
    NSString *orderStr = [NSString stringWithFormat:@"%i",method];
    [userData setObject:orderStr forKey:@"payMethod"];
    
}
@end

