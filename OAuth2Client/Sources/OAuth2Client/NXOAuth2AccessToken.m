//
//  NXOAuth2AccessToken.m
//  OAuth2Client
//
//  Created by Ullrich Schäfer on 27.08.10.
//
//  Copyright 2010 nxtbgthng. All rights reserved. 
//
//  Licenced under the new BSD-licence.
//  See README.md in this repository for 
//  the full licence.
//

#import "NXOAuth2AccessToken.h"

#import "NSString+NXOAuth2.h"


@implementation NXOAuth2AccessToken

#pragma mark Lifecycle

+ (id)tokenWithResponseBody:(NSString *)theResponseBody;
{
	// do we really need a JSON dependency? We can easily split this up ourselfs
	NSString *normalizedRsponseBody = [[[theResponseBody stringByReplacingOccurrencesOfString:@"{" withString:@""]
                                        stringByReplacingOccurrencesOfString:@"}" withString:@""]
                                       stringByReplacingOccurrencesOfString:@"\"" withString:@""];
	NSMutableDictionary *jsonDict = [NSMutableDictionary dictionary];
	for (NSString *keyValuePair in [normalizedRsponseBody componentsSeparatedByString:@","]) {
		NSArray *keyAndValue = [keyValuePair componentsSeparatedByString:@":"];
		if (keyAndValue.count == 2) {
			NSString *key = [keyAndValue objectAtIndex:0];
			NSString *value = [keyAndValue objectAtIndex:1];
			key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		    [jsonDict setObject:value forKey:key];
		}
	}
	NSString *expiresIn = [jsonDict objectForKey:@"expires_in"];
	NSString *anAccessToken = [jsonDict objectForKey:@"access_token"];
	NSString *aRefreshToken = [jsonDict objectForKey:@"refresh_token"];
	NSString *scopeString = [jsonDict objectForKey:@"scope"];
	
	NSSet *scope = nil;
	if (scopeString) {
		scope = [NSSet setWithArray:[scopeString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	}

	NSDate *expiryDate = nil;
	if (expiresIn) {
		expiryDate = [NSDate dateWithTimeIntervalSinceNow:[expiresIn integerValue]];
	}
	return [[[[self class] alloc] initWithAccessToken:anAccessToken
										 refreshToken:aRefreshToken
											expiresAt:expiryDate
												scope:scope
                                         responseBody:theResponseBody] autorelease];
}

- (id)initWithAccessToken:(NSString *)anAccessToken;
{
	return [self initWithAccessToken:anAccessToken refreshToken:nil expiresAt:nil];
}

- (id)initWithAccessToken:(NSString *)anAccessToken refreshToken:(NSString *)aRefreshToken expiresAt:(NSDate *)anExpiryDate;
{
	return [[[self class] alloc] initWithAccessToken:anAccessToken
                                        refreshToken:aRefreshToken
                                           expiresAt:anExpiryDate
                                               scope:nil];
}

- (id)initWithAccessToken:(NSString *)anAccessToken refreshToken:(NSString *)aRefreshToken expiresAt:(NSDate *)anExpiryDate scope:(NSSet *)aScope;
{
	return [[[self class] alloc] initWithAccessToken:anAccessToken
                                        refreshToken:aRefreshToken
                                           expiresAt:anExpiryDate
                                               scope:aScope
                                        responseBody:nil];
}

- (id)initWithAccessToken:(NSString *)anAccessToken refreshToken:(NSString *)aRefreshToken expiresAt:(NSDate *)anExpiryDate scope:(NSSet *)aScope responseBody:(NSString *)aResponseBody;
{
	self = [super init];
	if (self) {
		accessToken  = [anAccessToken copy];
		refreshToken = [aRefreshToken copy];
		expiresAt    = [anExpiryDate copy];
		scope        = aScope ? [aScope copy] : [[NSSet alloc] init];
        responseBody = [aResponseBody copy];
	}
	return self;
}

- (void)dealloc;
{
	[accessToken release];
	[refreshToken release];
	[expiresAt release];
	[scope release];
    [responseBody release];
	[super dealloc];
}


#pragma mark Accessors

@synthesize accessToken;
@synthesize refreshToken;
@synthesize expiresAt;
@synthesize scope;
@synthesize responseBody;

- (BOOL)doesExpire;
{
	return (expiresAt != nil);
}

- (BOOL)hasExpired;
{
	return ([[NSDate date] earlierDate:expiresAt] == expiresAt);
}


- (NSString *)description;
{
	return [NSString stringWithFormat:@"<NXOAuth2Token token:%@ refreshToken:%@ expiresAt:%@>", self.accessToken, self.refreshToken, self.expiresAt];
}


#pragma mark NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:accessToken forKey:@"accessToken"];
	[aCoder encodeObject:refreshToken forKey:@"refreshToken"];
	[aCoder encodeObject:expiresAt forKey:@"expiresAt"];
    [aCoder encodeObject:scope forKey:@"scope"];
    [aCoder encodeObject:responseBody forKey:@"responseBody"];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
	if (self) {
		accessToken = [[aDecoder decodeObjectForKey:@"accessToken"] copy];
		refreshToken = [[aDecoder decodeObjectForKey:@"refreshToken"] copy];
		expiresAt = [[aDecoder decodeObjectForKey:@"expiresAt"] copy];
        scope = [[aDecoder decodeObjectForKey:@"scope"] copy];
        responseBody = [[aDecoder decodeObjectForKey:@"responseBody"] copy];
	}
	return self;
}


#pragma mark Keychain Support

+ (NSString *)serviceNameWithProvider:(NSString *)provider;
{
	NSString *appName = [[NSBundle mainBundle] bundleIdentifier];
	
	return [NSString stringWithFormat:@"%@::OAuth2::%@", appName, provider];
}

#if TARGET_OS_IPHONE

+ (id)tokenFromDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	NSDictionary *result = nil;
	NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
						   (NSString *)kSecClassGenericPassword, kSecClass,
						   serviceName, kSecAttrService,
						   kCFBooleanTrue, kSecReturnAttributes,
						   nil];
	OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&result);
	[result autorelease];
	
	if (status != noErr) {
		NSAssert1(status == errSecItemNotFound, @"unexpected error while fetching token from keychain: %d", status);
		return nil;
	}
	
	return [NSKeyedUnarchiver unarchiveObjectWithData:[result objectForKey:(NSString *)kSecAttrGeneric]];
}

- (void)storeInDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self];
	NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
						   (NSString *)kSecClassGenericPassword, kSecClass,
						   serviceName, kSecAttrService,
						   @"OAuth 2 Access Token", kSecAttrLabel,
						   data, kSecAttrGeneric,
						   nil];
	[self removeFromDefaultKeychainWithServiceProviderName:provider];
	OSStatus __attribute__((unused)) err = SecItemAdd((CFDictionaryRef)query, NULL);
	NSAssert1(err == noErr, @"error while adding token to keychain: %d", err);
}

- (void)removeFromDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
						   (NSString *)kSecClassGenericPassword, kSecClass,
						   serviceName, kSecAttrService,
						   nil];
	OSStatus __attribute__((unused)) err = SecItemDelete((CFDictionaryRef)query);
	NSAssert1((err == noErr || err == errSecItemNotFound), @"error while deleting token from keychain: %d", err);
}

#else

+ (id)tokenFromDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	
	SecKeychainItemRef item = nil;
	OSStatus err = SecKeychainFindGenericPassword(NULL,
												  strlen([serviceName UTF8String]),
												  [serviceName UTF8String],
												  0,
												  NULL,
												  NULL,
												  NULL,
												  &item);
	if (err != noErr) {
		NSAssert1(err == errSecItemNotFound, @"unexpected error while fetching token from keychain: %d", err);
		return nil;
	}
    
    // from Advanced Mac OS X Programming, ch. 16
    UInt32 length;
    char *password;
	NSData *result = nil;
    SecKeychainAttribute attributes[8];
    SecKeychainAttributeList list;
	
    attributes[0].tag = kSecAccountItemAttr;
    attributes[1].tag = kSecDescriptionItemAttr;
    attributes[2].tag = kSecLabelItemAttr;
    attributes[3].tag = kSecModDateItemAttr;
    
    list.count = 4;
    list.attr = attributes;
    
    err = SecKeychainItemCopyContent(item, NULL, &list, &length, (void **)&password);
    if (err == noErr) {
        if (password != NULL) {
			result = [NSData dataWithBytes:password length:length];
        }
        SecKeychainItemFreeContent(&list, password);
    } else {
		// TODO find out why this always works in i386 and always fails on ppc
		NSLog(@"Error from SecKeychainItemCopyContent: %ld", err);
        return nil;
    }
    CFRelease(item);
	return [NSKeyedUnarchiver unarchiveObjectWithData:result];
}

- (void)storeInDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	[self removeFromDefaultKeychainWithServiceProviderName:provider];
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self];
	
	OSStatus __attribute__((unused))err = SecKeychainAddGenericPassword(NULL,
																		strlen([serviceName UTF8String]),
																		[serviceName UTF8String],
																		0,
																		NULL,
																		[data length],
																		[data bytes],
																		NULL);
	
	NSAssert1(err == noErr, @"error while adding token to keychain: %d", err);
}

- (void)removeFromDefaultKeychainWithServiceProviderName:(NSString *)provider;
{
	NSString *serviceName = [[self class] serviceNameWithProvider:provider];
	SecKeychainItemRef item = nil;
	OSStatus err = SecKeychainFindGenericPassword(NULL,
												  strlen([serviceName UTF8String]),
												  [serviceName UTF8String],
												  0,
												  NULL,
												  NULL,
												  NULL,
												  &item);
	NSAssert1((err == noErr || err == errSecItemNotFound), @"error while deleting token from keychain: %d", err);
	if (err == noErr) {
		err = SecKeychainItemDelete(item);
	}
	if (item) {
		CFRelease(item);	
	}
	NSAssert1((err == noErr || err == errSecItemNotFound), @"error while deleting token from keychain: %d", err);
}

#endif

@end
