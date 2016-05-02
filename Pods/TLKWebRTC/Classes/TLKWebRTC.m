//
//  TLKWebRTC.m
//  Copyright (c) 2014 &yet, LLC and TLKWebRTC contributors
//

#import "TLKWebRTC.h"

#import <AVFoundation/AVFoundation.h>

#import "RTCPeerConnectionFactory.h"
#import "RTCPeerConnection.h"
#import "RTCICEServer.h"
#import "RTCPair.h"
#import "RTCMediaConstraints.h"
#import "RTCSessionDescription.h"
#import "RTCSessionDescriptionDelegate.h"
#import "RTCPeerConnectionDelegate.h"
#import "RTCDataChannel.h"

#import "RTCAudioTrack.h"
#import "RTCAVFoundationVideoSource.h"
#import "RTCVideoTrack.h"

@interface TLKWebRTC () <
RTCSessionDescriptionDelegate,
RTCDataChannelDelegate,
RTCPeerConnectionDelegate>

@property (readwrite, nonatomic) RTCMediaStream *localMediaStream;

@property (nonatomic, strong) RTCPeerConnectionFactory *peerFactory;
@property (nonatomic, strong) NSMutableDictionary *peerConnections;
@property (nonatomic, strong) NSMutableDictionary *peerToRoleMap;
@property (nonatomic, strong) NSMutableDictionary *peerToICEMap;
@property (nonatomic, strong) RTCDataChannel *dataChannel;
@property (nonatomic) BOOL allowVideo;
@property (nonatomic, strong) AVCaptureDevice *videoDevice;

@property (nonatomic, strong) NSMutableArray *iceServers;

@end

static NSString * const TLKPeerConnectionRoleInitiator = @"TLKPeerConnectionRoleInitiator";
static NSString * const TLKPeerConnectionRoleReceiver = @"TLKPeerConnectionRoleReceiver";
static NSString * const TLKWebRTCSTUNHostname = @"stun:stun.l.google.com:19302";
static NSString * const TLKWebRTCDataChannelLabel = @"respokeDataChannel" ;

@implementation TLKWebRTC

#pragma mark - object lifecycle

- (instancetype)initWithVideoDevice:(AVCaptureDevice *)device {
    self = [super init];
    if (self) {
        if (device) {
            _allowVideo = YES;
            _videoDevice = device;
        }
        [self _commonSetup];
    }
    return self;
}

- (instancetype)initWithVideo:(BOOL)allowVideo {
    // Set front camera as the default device
    AVCaptureDevice* frontCamera;
    if (allowVideo) {
        frontCamera = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] lastObject];
    }
    return [self initWithVideoDevice:frontCamera];
}

- (instancetype)init {
    // Use default device
    return [self initWithVideo:YES];
}

- (void)_commonSetup {
    _peerFactory = [[RTCPeerConnectionFactory alloc] init];
    _peerConnections = [NSMutableDictionary dictionary];
    _peerToRoleMap = [NSMutableDictionary dictionary];
    _peerToICEMap = [NSMutableDictionary dictionary];
    
    self.iceServers = [NSMutableArray new];
    RTCICEServer *defaultStunServer = [[RTCICEServer alloc] initWithURI:[NSURL URLWithString:TLKWebRTCSTUNHostname] username:@"" password:@""];
    [self.iceServers addObject:defaultStunServer];
    
    [RTCPeerConnectionFactory initializeSSL];
    
    [self _createLocalStream];
}

- (void)_createLocalStream {
    self.localMediaStream = [self.peerFactory mediaStreamWithLabel:[[NSUUID UUID] UUIDString]];
    
    RTCAudioTrack *audioTrack = [self.peerFactory audioTrackWithID:[[NSUUID UUID] UUIDString]];
    [self.localMediaStream addAudioTrack:audioTrack];
    
    if (self.allowVideo) {
        RTCAVFoundationVideoSource *videoSource = [[RTCAVFoundationVideoSource alloc] initWithFactory:self.peerFactory constraints:nil];
        videoSource.useBackCamera = NO;
        RTCVideoTrack *videoTrack = [[RTCVideoTrack alloc] initWithFactory:self.peerFactory source:videoSource trackId:[[NSUUID UUID] UUIDString]];
        [self.localMediaStream addVideoTrack:videoTrack];
    }
}

- (RTCMediaConstraints *)_mediaConstraints {
    RTCPair *audioConstraint = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    RTCPair *videoConstraint = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:self.allowVideo ? @"true" : @"false"];
    RTCPair *sctpConstraint = [[RTCPair alloc] initWithKey:@"internalSctpDataChannels" value:@"true"];
    RTCPair *dtlsConstraint = [[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"];
    
    return [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:@[sctpConstraint]];
}

#pragma mark - ICE server

- (void)addICEServer:(RTCICEServer *)server {
    BOOL isStun = [server.URI.scheme isEqualToString:@"stun"];
    if (isStun) {
        // Array of servers is always stored with stun server in first index, and we only want one,
        // so if this is a stun server, replace it
        [self.iceServers replaceObjectAtIndex:0 withObject:server];
    }
    else {
        [self.iceServers addObject:server];
    }
}

#pragma mark - Peer Connections

- (NSString *)identifierForPeer:(RTCPeerConnection *)peer {
    NSArray *keys = [self.peerConnections allKeysForObject:peer];
    return (keys.count == 0) ? nil : keys[0];
}

- (void)addPeerConnectionForID:(NSString *)identifier caller: (BOOL)isCaller{
    NSLog(@"addPeerConnectionForID 11177 ?");
    RTCPeerConnection *peer = [self.peerFactory peerConnectionWithICEServers:[self iceServers] constraints:[self _mediaConstraints] delegate:self];
    if(isCaller){
        RTCDataChannelInit *initData = [[RTCDataChannelInit alloc] init];
        self.dataChannel = [peer createDataChannelWithLabel:@"baipingyang" config:initData];
        self.dataChannel.delegate = self;
        NSLog(@"Caller");
    }else{
        NSLog(@"Answer");
    }
    [peer addStream:self.localMediaStream];
    [self.peerConnections setObject:peer forKey:identifier];
}

- (void)removePeerConnectionForID:(NSString *)identifier {
    RTCPeerConnection* peer = self.peerConnections[identifier];
    [self.peerConnections removeObjectForKey:identifier];
    [self.peerToRoleMap removeObjectForKey:identifier];
    [peer close];
}

#pragma mark -

- (void)createOfferForPeerWithID:(NSString *)peerID {
    RTCPeerConnection *peerConnection = [self.peerConnections objectForKey:peerID];
    [self.peerToRoleMap setObject:TLKPeerConnectionRoleInitiator forKey:peerID];
    [peerConnection createOfferWithDelegate:self constraints:[self _mediaConstraints]];
}

- (void)setRemoteDescription:(RTCSessionDescription *)remoteSDP forPeerWithID:(NSString *)peerID receiver:(BOOL)isReceiver {
    RTCPeerConnection *peerConnection = [self.peerConnections objectForKey:peerID];
    if (isReceiver) {
        [self.peerToRoleMap setObject:TLKPeerConnectionRoleReceiver forKey:peerID];
    }
    [peerConnection setRemoteDescriptionWithDelegate:self sessionDescription:remoteSDP];
}

- (void)addICECandidate:(RTCICECandidate*)candidate forPeerWithID:(NSString *)peerID {
    RTCPeerConnection *peerConnection = [self.peerConnections objectForKey:peerID];
    if (peerConnection.iceGatheringState == RTCICEGatheringNew) {
        NSMutableArray *candidates = [self.peerToICEMap objectForKey:peerID];
        if (!candidates) {
            candidates = [NSMutableArray array];
            [self.peerToICEMap setObject:candidates forKey:peerID];
        }
        [candidates addObject:candidate];
    } else {
        [peerConnection addICECandidate:candidate];
    }
}

#pragma mark - RTCSessionDescriptionDelegate

// Note: all these delegate calls come back on a random background thread inside WebRTC,
// so all are bridged across to the main thread

- (void)peerConnection:(RTCPeerConnection *)peerConnection didCreateSessionDescription:(RTCSessionDescription *)sdp error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        //RTCSessionDescription* sessionDescription = [[RTCSessionDescription alloc] initWithType:sdp.type sdp:sdp.description];
        RTCSessionDescription* sessionDescription = [[RTCSessionDescription alloc] initWithType:sdp.type sdp:[[self class] preferISAC:sdp.description]];
        NSLog(@"Change SDP");
        [peerConnection setLocalDescriptionWithDelegate:self sessionDescription:sessionDescription];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didSetSessionDescriptionWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (peerConnection.iceGatheringState == RTCICEGatheringGathering) {
            NSArray *keys = [self.peerConnections allKeysForObject:peerConnection];
            if ([keys count] > 0) {
                NSArray *candidates = [self.peerToICEMap objectForKey:keys[0]];
                for (RTCICECandidate* candidate in candidates) {
                    [peerConnection addICECandidate:candidate];
                }
                [self.peerToICEMap removeObjectForKey:keys[0]];
            }
        }
        
        if (peerConnection.signalingState == RTCSignalingHaveLocalOffer) {
            NSArray *keys = [self.peerConnections allKeysForObject:peerConnection];
            if ([keys count] > 0) {
                [self.delegate webRTC:self didSendSDPOffer:peerConnection.localDescription forPeerWithID:keys[0]];
            }
        } else if (peerConnection.signalingState == RTCSignalingHaveRemoteOffer) {
            [peerConnection createAnswerWithDelegate:self constraints:[self _mediaConstraints]];
        } else if (peerConnection.signalingState == RTCSignalingStable) {
            NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
            if ([keys count] > 0) {
                NSString* role = [self.peerToRoleMap objectForKey:keys[0]];
                if (role == TLKPeerConnectionRoleReceiver) {
                    [self.delegate webRTC:self didSendSDPAnswer:peerConnection.localDescription forPeerWithID:keys[0]];
                }
            }
        }
    });
}

#pragma mark - String utilities

- (NSString *)stringForSignalingState:(RTCSignalingState)state {
    NSString *signalingStateString = nil;
    switch (state) {
        case RTCSignalingStable:
            signalingStateString = @"Stable";
            break;
        case RTCSignalingHaveLocalOffer:
            signalingStateString = @"Have Local Offer";
            break;
        case RTCSignalingHaveRemoteOffer:
            signalingStateString = @"Have Remote Offer";
            break;
        case RTCSignalingClosed:
            signalingStateString = @"Closed";
            break;
        default:
            signalingStateString = @"Other state";
            break;
    }
    
    return signalingStateString;
}

- (NSString *)stringForConnectionState:(RTCICEConnectionState)state {
    NSString *connectionStateString = nil;
    switch (state) {
        case RTCICEConnectionNew:
            connectionStateString = @"New";
            break;
        case RTCICEConnectionChecking:
            connectionStateString = @"Checking";
            break;
        case RTCICEConnectionConnected:
            connectionStateString = @"Connected";
            break;
        case RTCICEConnectionCompleted:
            connectionStateString = @"Completed";
            break;
        case RTCICEConnectionFailed:
            connectionStateString = @"Failed";
            break;
        case RTCICEConnectionDisconnected:
            connectionStateString = @"Disconnected";
            break;
        case RTCICEConnectionClosed:
            connectionStateString = @"Closed";
            break;
        default:
            connectionStateString = @"Other state";
            break;
    }
    return connectionStateString;
}

- (NSString *)stringForGatheringState:(RTCICEGatheringState)state {
    NSString *gatheringState = nil;
    switch (state) {
        case RTCICEGatheringNew:
            gatheringState = @"New";
            break;
        case RTCICEGatheringGathering:
            gatheringState = @"Gathering";
            break;
        case RTCICEGatheringComplete:
            gatheringState = @"Complete";
            break;
        default:
            gatheringState = @"Other state";
            break;
    }
    return gatheringState;
}

// Mangle |origSDP| to prefer the ISAC/16k audio codec.
+ (NSString*)preferISAC:(NSString*)origSDP
{
    int mLineIndex = -1;
    NSString* isac16kRtpMap = nil;
    NSArray* lines = [origSDP componentsSeparatedByString:@"\n"];
    NSRegularExpression* isac16kRegex = [NSRegularExpression regularExpressionWithPattern:@"^a=rtpmap:(\\d+) ISAC/16000[\r]?$" options:0 error:nil];
    
    for (int i = 0; (i < [lines count]) && (mLineIndex == -1 || isac16kRtpMap == nil); ++i)
    {
        NSString* line = [lines objectAtIndex:i];
        
        if ([line hasPrefix:@"m=audio "])
        {
            mLineIndex = i;
            continue;
        }
        
        isac16kRtpMap = [self firstMatch:isac16kRegex withString:line];
    }
    
    if (mLineIndex == -1)
    {
        NSLog(@"No m=audio line, so can't prefer iSAC");
        return origSDP;
    }
    
    if (isac16kRtpMap == nil)
    {
        NSLog(@"No ISAC/16000 line, so can't prefer iSAC");
        return origSDP;
    }
    
    NSArray* origMLineParts = [[lines objectAtIndex:mLineIndex] componentsSeparatedByString:@" "];
    NSMutableArray* newMLine = [NSMutableArray arrayWithCapacity:[origMLineParts count]];
    int origPartIndex = 0;
    
    // Format is: m=<media> <port> <proto> <fmt> ...
    [newMLine addObject:[origMLineParts objectAtIndex:origPartIndex++]];
    [newMLine addObject:[origMLineParts objectAtIndex:origPartIndex++]];
    [newMLine addObject:[origMLineParts objectAtIndex:origPartIndex++]];
    [newMLine addObject:isac16kRtpMap];
    
    for (; origPartIndex < [origMLineParts count]; ++origPartIndex)
    {
        if (![isac16kRtpMap isEqualToString:[origMLineParts objectAtIndex:origPartIndex]])
        {
            [newMLine addObject:[origMLineParts objectAtIndex:origPartIndex]];
        }
    }
    
    NSMutableArray* newLines = [NSMutableArray arrayWithCapacity:[lines count]];
    [newLines addObjectsFromArray:lines];
    [newLines replaceObjectAtIndex:mLineIndex withObject:[newMLine componentsJoinedByString:@" "]];
    return [newLines componentsJoinedByString:@"\n"];
}

// Match |pattern| to |string| and return the first group of the first
// match, or nil if no match was found.
+ (NSString*)firstMatch:(NSRegularExpression*)pattern withString:(NSString*)string
{
    NSTextCheckingResult* result = [pattern firstMatchInString:string options:0 range:NSMakeRange(0, [string length])];
    
    if (!result)
        return nil;
    
    return [string substringWithRange:[result rangeAtIndex:1]];
}
#pragma mark - RTCPeerConnectionDelegate

// Note: all these delegate calls come back on a random background thread inside WebRTC,
// so all are bridged across to the main thread

- (void)peerConnectionOnError:(RTCPeerConnection *)peerConnection {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"peerConnectionOnError ?");
        });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection signalingStateChanged:(RTCSignalingState)stateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        // I'm seeing this, but not sure what to do with it yet
        NSLog(@"signalingStateChanged ?");
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection addedStream:(RTCMediaStream *)stream {
    dispatch_async(dispatch_get_main_queue(), ^{
        //[self.delegate webRTC:self addedStream:stream forPeerWithID:[self identifierForPeer:peerConnection]];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection removedStream:(RTCMediaStream *)stream {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webRTC:self removedStream:stream forPeerWithID:[self identifierForPeer:peerConnection]];
    });
}

- (void)peerConnectionOnRenegotiationNeeded:(RTCPeerConnection *)peerConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        //    [self.peerConnection createOfferWithDelegate:self constraints:[self mediaConstraints]];
        // Is this delegate called when creating a PC that is going to *receive* an offer and return an answer?
        NSLog(@"peerConnectionOnRenegotiationNeeded ?");
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceConnectionChanged:(RTCICEConnectionState)newState {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate webRTC:self didObserveICEConnectionStateChange:newState forPeerWithID:[self identifierForPeer:peerConnection]];
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection iceGatheringChanged:(RTCICEGatheringState)newState {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"peerConnection iceGatheringChanged?");
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection gotICECandidate:(RTCICECandidate *)candidate {
    dispatch_async(dispatch_get_main_queue(), ^{
        
        NSArray* keys = [self.peerConnections allKeysForObject:peerConnection];
        if ([keys count] > 0) {
            [self.delegate webRTC:self didSendICECandidate:candidate forPeerWithID:keys[0]];
        }
    });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel {
    NSLog(@"peerConnectionOnRenegotiationNeeded before ?");
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"peerConnection didOpenDataChannel?");
        self.dataChannel = dataChannel;
        self.dataChannel.delegate = self;
    });
}

- (BOOL)isActive
{
    return (self.dataChannel && (self.dataChannel.state == kRTCDataChannelStateOpen));
}

- (void)sendMessage:(NSData*)messageData successHandler:(void (^)(void))successHandler errorHandler:(void (^)(NSString*))errorHandler
{
    if ([self isActive])
    {
        RTCDataBuffer *data = [[RTCDataBuffer alloc] initWithData:messageData isBinary:NO];
        if ([self.dataChannel sendData:data])
        {
            successHandler();
        }
        else
        {
            errorHandler(@"Message failed to send");
        }
    }
    else
    {
        errorHandler(@"dataChannel not in an open state.");
    }
}
// RTCDataChannelDelegate methods


- (void)channelDidChangeState:(RTCDataChannel*)channel
{
    
    switch (channel.state)
    {
        case kRTCDataChannelStateConnecting:
            NSLog(@"Direct connection CONNECTING");
            break;
            
        case kRTCDataChannelStateOpen:
        {
            NSLog(@"Direct connection OPEN");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate webRTC:self  onDataChannelOpen: channel];
            });
        }
            break;
            
        case kRTCDataChannelStateClosing:
        {
            NSLog(@"Direct connection CLOSING");
            //[self sendMessage: @"Hello Barry." successHandler: nil errorHandler:nil];
        }
            break;
            
        case kRTCDataChannelStateClosed:
        {
            NSLog(@"Direct connection CLOSED");
            //dataChannel = nil;
            //[call directConnectionDidClose:self];
            //dispatch_async(dispatch_get_main_queue(), ^{
            //[self.delegate onClose:self];
            //});
        }
            break;
    }
}


- (void)channel:(RTCDataChannel*)channel didReceiveMessageWithBuffer:(RTCDataBuffer*)buffer
{
    id message = nil;
    NSError *error;
    
    id jsonResult = [NSJSONSerialization JSONObjectWithData:buffer.data options:0 error:&error];
    if (error)
    {
        // Could not parse JSON data, so just pass it as it is
        message = buffer.data;
        NSLog(@"Direct Message received (binary)");
        dispatch_async(dispatch_get_main_queue(), ^{
            //[self.delegate onMessage:message sender:self];
        });
    }
    else
    {
        if (jsonResult && ([jsonResult isKindOfClass:[NSDictionary class]]))
        {
            NSDictionary *dict = (NSDictionary*)jsonResult;
            NSString *messageText = [dict objectForKey:@"message"];
            
            if (messageText)
            {
                NSLog(@"Direct Message received: [%@]", messageText);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate webRTC:self onMessage:messageText];
                });
            }
        }
    }
}

@end
