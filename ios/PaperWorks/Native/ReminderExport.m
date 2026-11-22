#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ReminderExport, NSObject)
RCT_EXTERN_METHOD(export : (NSString *)listTitle items : (NSArray *)items resolver : (RCTPromiseResolveBlock)resolve rejecter : (RCTPromiseRejectBlock)reject)
@end
