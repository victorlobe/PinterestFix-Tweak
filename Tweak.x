#import <Foundation/Foundation.h>
#import <sys/sysctl.h>

static NSString * const PinterestFixPreferencesPath = @"/var/mobile/Library/Preferences/com.victorlobe.pinterestfix.plist";
static NSString * const PinterestFixDefaultAppVersion = @"14.42";
static NSString * const PinterestFixLoginVersion = @"3.8.1";
static NSString * const PinterestFixUserAgentPrefix = @"Pinterest for iOS/";

static NSString * const PinterestFixImageHost = @"https://i.pinimg.com/";
static NSString * const PinterestFixImageHostReplacement = @"https://i-h1.pinimg.com/";

static NSString * const PinterestFixReactionFields = @"pin.reaction_by_me,pin.total_reaction_count,pin.aggregated_pin_data(),aggregatedpindata.id,aggregatedpindata.comment_count";
static NSString * const PinterestFixReactionUserFields = @"userreaction.user(),user.id,user.username,user.full_name,user.first_name,user.image_medium_url,user.image_small_url";
static NSString * const PinterestFixCommentUserFields = @"aggregatedcomment.user(),user.id,user.username,user.full_name,user.first_name,user.image_medium_url,user.image_small_url";

static NSString * const PinterestFixInstallIdKey = @"PinterestFixInstallId";
static NSString * const PinterestFixHandledRequestKey = @"PinterestFixHandled";

static NSString *pinterestFixAppVersion;
static BOOL pinterestFixHidePromotedPins;
static BOOL pinterestFixBlockTracking;
static BOOL pinterestFixImageHostFix;

static NSMutableDictionary *pinterestFixAggregatedPinIds;


static void pinterestFixLoadPreferences(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:PinterestFixPreferencesPath];

    pinterestFixHidePromotedPins = [[preferences objectForKey:@"HidePromotedPins"] boolValue];
    pinterestFixBlockTracking = [[preferences objectForKey:@"BlockTracking"] boolValue];
    pinterestFixImageHostFix = [[preferences objectForKey:@"ImageHostFix"] boolValue];

    NSString *version = [[preferences objectForKey:@"SpoofedVersion"] description];
    version = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSRegularExpression *format = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,3}\\.[0-9]{1,2}$" options:0 error:nil];
    BOOL valid = version && [format numberOfMatchesInString:version options:0 range:NSMakeRange(0, [version length])] == 1;

    pinterestFixAppVersion = valid ? version : PinterestFixDefaultAppVersion;
}

static NSString *pinterestFixBundleVersion(NSString *version) {
    NSArray *parts = [version componentsSeparatedByString:@"."];
    long major = (long)[[parts objectAtIndex:0] integerValue];
    long minor = (long)[[parts lastObject] integerValue];

    return [NSString stringWithFormat:@"%ld%02ld000", major, minor];
}

static NSDictionary *pinterestFixInfoValues(void) {
    return @{
        @"BuildMachineOSBuild": @"22G120",
        @"CFBundleShortVersionString": pinterestFixAppVersion,
        @"CFBundleVersion": pinterestFixBundleVersion(pinterestFixAppVersion),
        @"DTPlatformBuild": @"14B18",
        @"DTPlatformVersion": @"14.4",
        @"DTSDKName": @"iphoneos18.0",
        @"DTXcode": @"0511",
        @"DTXcodeBuild": @"15A240d",
    };
}

static void pinterestFixSpoofInfoDictionary(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];

    @try {
        [(NSMutableDictionary *)info addEntriesFromDictionary:pinterestFixInfoValues()];
    } @catch (NSException *exception) {
        NSLog(@"[PinterestFix] Info.plist spoofing failed: %@", exception);
    }
}


static NSString *pinterestFixInstallId(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *installId = [defaults stringForKey:PinterestFixInstallIdKey];

    if ([installId length] == 0) {
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        NSString *uuidString = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);

        installId = [[uuidString stringByReplacingOccurrencesOfString:@"-" withString:@""] lowercaseString];
        [defaults setObject:installId forKey:PinterestFixInstallIdKey];
        [defaults synchronize];
    }

    return installId;
}

static NSString *pinterestFixDeviceModel(void) {
    char model[64] = {0};
    size_t size = sizeof(model) - 1;

    if (sysctlbyname("hw.machine", model, &size, NULL, 0) != 0) {
        return nil;
    }
    return [NSString stringWithUTF8String:model];
}

static void pinterestFixAddMissingClientHeaders(NSMutableURLRequest *request) {
    if (![request valueForHTTPHeaderField:@"X-Pinterest-InstallId"]) {
        [request setValue:pinterestFixInstallId() forHTTPHeaderField:@"X-Pinterest-InstallId"];
    }

    NSString *model = pinterestFixDeviceModel();
    if (model && ![request valueForHTTPHeaderField:@"X-Pinterest-Device"]) {
        [request setValue:model forHTTPHeaderField:@"X-Pinterest-Device"];
    }

    if (![request valueForHTTPHeaderField:@"X-Pinterest-AppState"]) {
        [request setValue:@"active" forHTTPHeaderField:@"X-Pinterest-AppState"];
    }
}

static BOOL pinterestFixIsLoginPath(NSString *path) {
    return [path hasPrefix:@"login"] && ![path hasPrefix:@"login/email/"];
}

static NSString *pinterestFixLoginUserAgent(NSString *userAgent) {
    NSString *spoofed = [PinterestFixUserAgentPrefix stringByAppendingString:pinterestFixAppVersion];
    NSString *login = [PinterestFixUserAgentPrefix stringByAppendingString:PinterestFixLoginVersion];

    return [userAgent stringByReplacingOccurrencesOfString:spoofed withString:login];
}


static NSString *pinterestFixReactPathForLikePath(NSString *path) {
    if (![path hasPrefix:@"pins/"] || ![path hasSuffix:@"/like/"]) {
        return nil;
    }
    return [[path substringToIndex:[path length] - [@"like/" length]] stringByAppendingString:@"react/"];
}

static NSString *pinterestFixReactionsPathForLikesPath(NSString *path) {
    if (![path hasPrefix:@"pins/"] || ![path hasSuffix:@"/likes/"]) {
        return nil;
    }
    return [[path substringToIndex:[path length] - [@"likes/" length]] stringByAppendingString:@"reactions/"];
}

static NSString *pinterestFixRelatedModulesPathForRelatedPinsPath(NSString *path) {
    if (![path hasPrefix:@"pins/"] || ![path hasSuffix:@"/related/pin/"]) {
        return nil;
    }
    return [[path substringToIndex:[path length] - [@"pin/" length]] stringByAppendingString:@"modules/"];
}

static BOOL pinterestFixIsPinCommentsPath(NSString *path) {
    return [path hasPrefix:@"pins/"] && [path hasSuffix:@"/comments/"] && [[path componentsSeparatedByString:@"/"] count] == 4;
}

static NSDictionary *pinterestFixParametersWithReactionFields(NSString *path, NSDictionary *parameters) {
    if ([path hasPrefix:@"login"] || [path hasPrefix:@"register"] || [path rangeOfString:@"add_fields="].location != NSNotFound) {
        return parameters;
    }

    NSMutableDictionary *newParameters = parameters ? [parameters mutableCopy] : [NSMutableDictionary dictionary];
    NSString *addFields = [newParameters objectForKey:@"add_fields"];

    if ([addFields isKindOfClass:[NSString class]] && [addFields length] > 0) {
        if ([addFields rangeOfString:@"pin.reaction_by_me"].location != NSNotFound) {
            return parameters;
        }
        addFields = [NSString stringWithFormat:@"%@,%@", addFields, PinterestFixReactionFields];
    } else {
        addFields = PinterestFixReactionFields;
    }

    [newParameters setObject:addFields forKey:@"add_fields"];
    return newParameters;
}


static void pinterestFixRememberAggregatedPinIdForPinId(NSString *pinId, NSString *aggregatedId) {
    if (!pinId || !aggregatedId) {
        return;
    }

    @synchronized ([NSMutableDictionary class]) {
        if (!pinterestFixAggregatedPinIds) {
            pinterestFixAggregatedPinIds = [NSMutableDictionary dictionary];
        }
        [pinterestFixAggregatedPinIds setObject:aggregatedId forKey:pinId];
    }
}

static void pinterestFixRememberAggregatedPinId(NSDictionary *pin) {
    NSDictionary *aggregated = [pin objectForKey:@"aggregated_pin_data"];
    id pinId = [pin objectForKey:@"id"];
    id aggregatedId = [aggregated isKindOfClass:[NSDictionary class]] ? [aggregated objectForKey:@"id"] : nil;

    pinterestFixRememberAggregatedPinIdForPinId([pinId description], [aggregatedId description]);
}

static NSString *pinterestFixAggregatedPinIdForPinId(NSString *pinId) {
    @synchronized ([NSMutableDictionary class]) {
        return [pinterestFixAggregatedPinIds objectForKey:pinId];
    }
}


static BOOL pinterestFixIsTypedItem(id item, NSString *type) {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    id itemType = [item objectForKey:@"type"];
    return [itemType isKindOfClass:[NSString class]] && (!type || [itemType isEqualToString:type]);
}

static BOOL pinterestFixIsPromotedPin(id item) {
    if (!pinterestFixIsTypedItem(item, @"pin")) {
        return NO;
    }
    return [[item objectForKey:@"is_promoted"] boolValue] || [[item objectForKey:@"promoter"] isKindOfClass:[NSDictionary class]];
}

static NSArray *pinterestFixPinsOnly(NSArray *items) {
    BOOL hasPins = NO;
    BOOL hasRemovableItems = NO;

    for (id item in items) {
        if (pinterestFixIsTypedItem(item, @"pin")) {
            hasPins = YES;
            hasRemovableItems = hasRemovableItems || (pinterestFixHidePromotedPins && pinterestFixIsPromotedPin(item));
        } else if (pinterestFixIsTypedItem(item, nil)) {
            hasRemovableItems = YES;
        }
    }

    if (!hasPins || !hasRemovableItems) {
        return items;
    }

    NSMutableArray *pins = [NSMutableArray arrayWithCapacity:[items count]];
    for (id item in items) {
        BOOL keep = !pinterestFixIsTypedItem(item, nil) || pinterestFixIsTypedItem(item, @"pin");
        if (keep && !(pinterestFixHidePromotedPins && pinterestFixIsPromotedPin(item))) {
            [pins addObject:item];
        }
    }
    return pins;
}

static NSString *pinterestFixMappedImageURL(NSString *url) {
    if (!pinterestFixImageHostFix || ![url hasPrefix:PinterestFixImageHost]) {
        return url;
    }
    return [PinterestFixImageHostReplacement stringByAppendingString:[url substringFromIndex:[PinterestFixImageHost length]]];
}

static id pinterestFixMapResponse(id object) {
    if ([object isKindOfClass:[NSString class]]) {
        return pinterestFixMappedImageURL(object);
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *mapped = nil;
        NSUInteger count = [object count];

        for (NSUInteger i = 0; i < count; i++) {
            id item = [object objectAtIndex:i];
            id mappedItem = pinterestFixMapResponse(item);

            if (mappedItem != item && !mapped) {
                mapped = [object mutableCopy];
            }
            if (mapped) {
                [mapped replaceObjectAtIndex:i withObject:mappedItem];
            }
        }
        return pinterestFixPinsOnly(mapped ?: object);
    }

    if (![object isKindOfClass:[NSDictionary class]]) {
        return object;
    }

    NSMutableDictionary *mapped = nil;
    for (id key in [object allKeys]) {
        id value = [object objectForKey:key];
        id mappedValue = pinterestFixMapResponse(value);

        if (mappedValue != value) {
            if (!mapped) {
                mapped = [object mutableCopy];
            }
            [mapped setObject:mappedValue forKey:key];
        }
    }

    if (pinterestFixIsTypedItem(object, @"pin")) {
        pinterestFixRememberAggregatedPinId(object);

        NSDictionary *aggregated = [object objectForKey:@"aggregated_pin_data"];
        NSNumber *comments = [aggregated isKindOfClass:[NSDictionary class]] ? [aggregated objectForKey:@"comment_count"] : nil;

        if ([comments isKindOfClass:[NSNumber class]] && [comments integerValue] > [[object objectForKey:@"comment_count"] integerValue]) {
            if (!mapped) {
                mapped = [object mutableCopy];
            }
            [mapped setObject:comments forKey:@"comment_count"];
        }
    }

    NSNumber *reactionByMe = [object objectForKey:@"reaction_by_me"];
    if ([reactionByMe isKindOfClass:[NSNumber class]]) {
        if (!mapped) {
            mapped = [object mutableCopy];
        }
        [mapped setObject:[NSNumber numberWithBool:[reactionByMe integerValue] != 0] forKey:@"liked_by_me"];

        NSNumber *totalReactions = [object objectForKey:@"total_reaction_count"];
        if ([totalReactions isKindOfClass:[NSNumber class]]) {
            [mapped setObject:totalReactions forKey:@"like_count"];
        }
    }

    return mapped ?: object;
}


static NSDictionary *pinterestFixUsersFromReactions(NSDictionary *response) {
    NSArray *reactions = [response objectForKey:@"data"];
    if (![reactions isKindOfClass:[NSArray class]]) {
        return response;
    }

    NSMutableArray *users = [NSMutableArray arrayWithCapacity:[reactions count]];
    for (id reaction in reactions) {
        id user = [reaction isKindOfClass:[NSDictionary class]] ? [reaction objectForKey:@"user"] : nil;
        if (![user isKindOfClass:[NSDictionary class]] || ![user objectForKey:@"id"]) {
            continue;
        }

        NSMutableDictionary *typedUser = [user mutableCopy];
        if (![typedUser objectForKey:@"type"]) {
            [typedUser setObject:@"user" forKey:@"type"];
        }
        [users addObject:typedUser];
    }

    NSMutableDictionary *mapped = [response mutableCopy];
    [mapped setObject:users forKey:@"data"];
    return mapped;
}

static NSDictionary *pinterestFixCommentsFromAggregatedComments(NSDictionary *response) {
    NSArray *comments = [response objectForKey:@"data"];
    if (![comments isKindOfClass:[NSArray class]]) {
        return response;
    }

    NSMutableArray *mappedComments = [NSMutableArray arrayWithCapacity:[comments count]];
    for (id comment in comments) {
        if (![comment isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSMutableDictionary *mappedComment = [comment mutableCopy];
        id user = [comment objectForKey:@"user"];
        if (user && ![comment objectForKey:@"commenter"]) {
            [mappedComment setObject:user forKey:@"commenter"];
        }
        [mappedComment setObject:@"comment" forKey:@"type"];

        [mappedComments addObject:mappedComment];
    }

    NSMutableDictionary *mapped = [response mutableCopy];
    [mapped setObject:mappedComments forKey:@"data"];
    return mapped;
}


static NSString *pinterestFixPinIdForCommentsURL(NSURL *url) {
    NSArray *components = [[url path] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    components = [components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];

    if (![[[url host] lowercaseString] hasSuffix:@"api.pinterest.com"] || [components count] != 4) {
        return nil;
    }

    BOOL isCommentsPath = [[components objectAtIndex:0] isEqualToString:@"v3"]
        && [[components objectAtIndex:1] isEqualToString:@"pins"]
        && [[components objectAtIndex:3] isEqualToString:@"comments"];

    return isCommentsPath ? [components objectAtIndex:2] : nil;
}



static NSString *pinterestFixQueryValue(NSURL *url, NSString *name) {
    for (NSString *pair in [[url query] componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location != NSNotFound && [[pair substringToIndex:equals.location] isEqualToString:name]) {
            return [pair substringFromIndex:equals.location + 1];
        }
    }
    return nil;
}

static BOOL pinterestFixIsTrackingURL(NSURL *url) {
    NSString *host = [[url host] lowercaseString];
    if ([host hasSuffix:@"flurry.com"] || [host hasSuffix:@"crittercism.com"]) {
        return YES;
    }

    NSString *path = [url path];
    return [host hasSuffix:@"api.pinterest.com"] && ([path hasPrefix:@"/v3/log/"] || [path hasPrefix:@"/v3/register/track_action/"]);
}


@interface PinterestFixCommentsLoader : NSURLProtocol
@property (strong, nonatomic) NSThread *clientThread;
@end

@implementation PinterestFixCommentsLoader

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:PinterestFixHandledRequestKey inRequest:request]) {
        return NO;
    }
    return [[request HTTPMethod] isEqualToString:@"GET"] && pinterestFixPinIdForCommentsURL([request URL]) != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (NSMutableURLRequest *)handledRequestWithURL:(NSURL *)url {
    NSMutableURLRequest *request = [[self request] mutableCopy];
    [request setURL:url];
    [NSURLProtocol setProperty:@YES forKey:PinterestFixHandledRequestKey inRequest:request];
    return request;
}

- (void)startLoading {
    self.clientThread = [NSThread currentThread];

    NSURL *url = [[self request] URL];
    NSString *pinId = pinterestFixPinIdForCommentsURL(url);
    NSString *aggregatedId = pinterestFixAggregatedPinIdForPinId(pinId);

    if (aggregatedId) {
        [self loadCommentsForAggregatedId:aggregatedId];
        return;
    }

    NSString *token = pinterestFixQueryValue(url, @"access_token");
    NSString *lookup = [NSString stringWithFormat:@"https://api.pinterest.com/v3/pins/%@/?fields=pin.id,pin.aggregated_pin_data(),aggregatedpindata.id%@",
        pinId, token ? [@"&access_token=" stringByAppendingString:token] : @""];

    NSMutableURLRequest *lookupRequest = [self handledRequestWithURL:[NSURL URLWithString:lookup]];
    [NSURLConnection sendAsynchronousRequest:lookupRequest queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSDictionary *pin = data ? [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] objectForKey:@"data"] : nil;
        NSDictionary *aggregated = [pin isKindOfClass:[NSDictionary class]] ? [pin objectForKey:@"aggregated_pin_data"] : nil;
        id foundId = [aggregated isKindOfClass:[NSDictionary class]] ? [aggregated objectForKey:@"id"] : nil;

        if (foundId) {
            pinterestFixRememberAggregatedPinIdForPinId(pinId, [foundId description]);
        }
        [self loadCommentsForAggregatedId:foundId ? [foundId description] : nil];
    }];
}

- (void)loadCommentsForAggregatedId:(NSString *)aggregatedId {
    NSURL *url = [[self request] URL];

    if (aggregatedId) {
        NSString *query = [url query] ? [@"?" stringByAppendingString:[url query]] : @"";
        url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.pinterest.com/v3/aggregated_pin_data/%@/comments/%@", aggregatedId, query]];
    }

    [NSURLConnection sendAsynchronousRequest:[self handledRequestWithURL:url] queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSDictionary *result = @{
            @"response": response ?: [NSNull null],
            @"data": data ?: [NSData data],
            @"error": error ?: [NSNull null],
        };
        [self performSelector:@selector(finishWithResult:) onThread:self.clientThread withObject:result waitUntilDone:NO];
    }];
}

- (void)finishWithResult:(NSDictionary *)result {
    id error = [result objectForKey:@"error"];
    id response = [result objectForKey:@"response"];

    if ([error isKindOfClass:[NSError class]] || ![response isKindOfClass:[NSURLResponse class]]) {
        NSError *failure = [error isKindOfClass:[NSError class]] ? error : [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:nil];
        [[self client] URLProtocol:self didFailWithError:failure];
        return;
    }

    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [[self client] URLProtocol:self didLoadData:[result objectForKey:@"data"]];
    [[self client] URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end


@interface PinterestFixTrackingBlocker : NSURLProtocol
@end

@implementation PinterestFixTrackingBlocker

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return pinterestFixIsTrackingURL([request URL]);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSData *body = [@"{\"status\":\"success\",\"code\":0,\"data\":null}" dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[[self request] URL]
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"application/json"}];

    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [[self client] URLProtocol:self didLoadData:body];
    [[self client] URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end


@interface CBLPinterestClient : NSObject
- (void)postPath:(NSString *)path parameters:(NSDictionary *)parameters success:(id)success failure:(id)failure;
- (void)deletePath:(NSString *)path parameters:(NSDictionary *)parameters success:(id)success failure:(id)failure;
@end

%hook CBLPinterestClient

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters {
    NSString *reactionsPath = pinterestFixReactionsPathForLikesPath(path);
    if (reactionsPath) {
        NSMutableDictionary *reactionParameters = parameters ? [parameters mutableCopy] : [NSMutableDictionary dictionary];
        [reactionParameters setObject:PinterestFixReactionUserFields forKey:@"fields"];

        path = reactionsPath;
        parameters = reactionParameters;
    }

    NSString *relatedModulesPath = pinterestFixRelatedModulesPathForRelatedPinsPath(path);
    if (relatedModulesPath) {
        path = relatedModulesPath;
    }

    parameters = pinterestFixParametersWithReactionFields(path, parameters);

    if (pinterestFixIsPinCommentsPath(path)) {
        NSMutableDictionary *commentParameters = parameters ? [parameters mutableCopy] : [NSMutableDictionary dictionary];
        NSString *addFields = [commentParameters objectForKey:@"add_fields"];

        addFields = [addFields length] > 0 ? [NSString stringWithFormat:@"%@,%@", addFields, PinterestFixCommentUserFields] : PinterestFixCommentUserFields;
        [commentParameters setObject:addFields forKey:@"add_fields"];
        parameters = commentParameters;
    }

    NSMutableURLRequest *request = %orig(method, path, parameters);
    pinterestFixAddMissingClientHeaders(request);

    if (pinterestFixIsLoginPath(path)) {
        NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
        if (userAgent) {
            [request setValue:pinterestFixLoginUserAgent(userAgent) forHTTPHeaderField:@"User-Agent"];
        }
    }

    return request;
}

- (void)putPath:(NSString *)path parameters:(NSDictionary *)parameters success:(id)success failure:(id)failure {
    NSString *reactPath = pinterestFixReactPathForLikePath(path);
    if (!reactPath) {
        %orig;
        return;
    }

    NSMutableDictionary *reactParameters = parameters ? [parameters mutableCopy] : [NSMutableDictionary dictionary];
    [reactParameters setObject:@1 forKey:@"reaction_type"];

    [self postPath:reactPath parameters:reactParameters success:success failure:failure];
}

- (void)deletePath:(NSString *)path parameters:(NSDictionary *)parameters success:(id)success failure:(id)failure {
    NSString *reactPath = pinterestFixReactPathForLikePath(path);
    if (!reactPath) {
        %orig;
        return;
    }

    %orig(reactPath, parameters, success, failure);
}

%end


%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id result = %orig;
    if (![result isKindOfClass:[NSDictionary class]] || ![result objectForKey:@"endpoint_name"]) {
        return result;
    }

    id endpoint = [result objectForKey:@"endpoint_name"];
    if ([endpoint isEqual:@"v3_get_reactions_on_pin"]) {
        result = pinterestFixUsersFromReactions(result);
    } else if ([endpoint isEqual:@"v3_get_aggregated_pin_data_comments"]) {
        result = pinterestFixCommentsFromAggregatedComments(result);
    }

    return pinterestFixMapResponse(result);
}

%end


%ctor {
    pinterestFixLoadPreferences();
    pinterestFixSpoofInfoDictionary();

    [NSURLProtocol registerClass:[PinterestFixCommentsLoader class]];
    if (pinterestFixBlockTracking) {
        [NSURLProtocol registerClass:[PinterestFixTrackingBlocker class]];
    }
}
