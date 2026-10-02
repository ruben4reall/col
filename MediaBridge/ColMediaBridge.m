// ColMediaBridge: reads what is playing on the Mac and forwards media commands.
//
// Since macOS 15.4 the MediaRemote framework only answers processes Apple has entitled. /usr/bin/perl is one of them,
// so Col runs this library inside perl (see media-bridge.pl): perl loads it and calls col_media_run, which never
// returns. The library writes one JSON object per line on stdout and reads one command per line on stdin, so a single
// long-lived process serves both directions.
//
// Output, one line per change:
//   {"playing":true,"title":"…","artist":"…","album":"…","duration":231.4,"elapsed":12.1,"timestamp":1790000000.5,
//    "rate":1,"pid":123,"artwork":"<base64>"}
// "artwork" is present only when the artwork changed; an empty string means there is none any more.
// {"idle":true} means nothing is playing and no player is left.
//
// Input, one line per command: play, pause, toggle, next, previous, seek <seconds>.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

static RegisterFn registerForNotifications;
static GetInfoFn getInfo;
static GetPlayingFn getPlaying;
static GetPIDFn getPID;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;

static dispatch_queue_t queue;
static NSUInteger lastArtworkHash;
static NSString *lastTrack;
static NSDictionary *lastState;

static void write_line(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id value(NSDictionary *info, NSString *key) {
    id found = info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:key]];
    return found == [NSNull null] ? nil : found;
}

static void refresh(void) {
    getInfo(queue, ^(CFDictionaryRef raw) {
        NSDictionary *info = (__bridge NSDictionary *)raw;
        getPlaying(queue, ^(Boolean playing) {
            getPID(queue, ^(int pid) {
                if (info.count == 0 && pid == 0) {
                    lastArtworkHash = 0;
                    lastTrack = nil;
                    if (![lastState isEqual:@{ @"idle": @YES }]) {
                        lastState = @{ @"idle": @YES };
                        write_line(lastState);
                    }
                    return;
                }
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                out[@"pid"] = @(pid);
                for (NSString *key in @[ @"Title", @"Artist", @"Album" ]) {
                    id text = value(info, key);
                    if ([text isKindOfClass:[NSString class]]) out[key.lowercaseString] = text;
                }
                NSNumber *duration = value(info, @"Duration");
                NSNumber *elapsed = value(info, @"ElapsedTime");
                NSNumber *rate = value(info, @"PlaybackRate");
                NSDate *timestamp = value(info, @"Timestamp");
                if ([duration isKindOfClass:[NSNumber class]]) out[@"duration"] = duration;
                if ([elapsed isKindOfClass:[NSNumber class]]) out[@"elapsed"] = elapsed;
                if ([rate isKindOfClass:[NSNumber class]]) out[@"rate"] = rate;
                if ([timestamp isKindOfClass:[NSDate class]]) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);

                // The framework sends partial updates, often without the artwork. Artwork is cleared only when the
                // track itself changes, and travels only when it is new.
                NSString *track = [NSString stringWithFormat:@"%@\n%@\n%@", out[@"title"] ?: @"", out[@"artist"] ?: @"", out[@"album"] ?: @""];
                BOOL newTrack = ![track isEqualToString:lastTrack];
                lastTrack = track;
                NSString *artworkField = nil;
                NSData *artwork = value(info, @"ArtworkData");
                if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
                    NSUInteger hash = artwork.length ^ [[artwork subdataWithRange:NSMakeRange(0, MIN(artwork.length, 4096))] hash];
                    if (hash != lastArtworkHash) {
                        lastArtworkHash = hash;
                        artworkField = [artwork base64EncodedStringWithOptions:0];
                    }
                } else if (newTrack && lastArtworkHash != 0) {
                    lastArtworkHash = 0;
                    artworkField = @"";
                }
                // The framework often repeats itself; only real changes cross the pipe.
                if (artworkField == nil && [out isEqual:lastState]) return;
                lastState = [out copy];
                if (artworkField) out[@"artwork"] = artworkField;
                write_line(out);
            });
        });
    });
}

static void handle(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    // MRMediaRemoteCommand values.
    if ([command isEqualToString:@"play"]) sendCommand(0, NULL);
    else if ([command isEqualToString:@"pause"]) sendCommand(1, NULL);
    else if ([command isEqualToString:@"toggle"]) sendCommand(2, NULL);
    else if ([command isEqualToString:@"next"]) sendCommand(4, NULL);
    else if ([command isEqualToString:@"previous"]) sendCommand(5, NULL);
    else if ([command isEqualToString:@"seek"] && parts.count > 1) setElapsed(parts[1].doubleValue);
    else if ([command isEqualToString:@"refresh"]) { lastState = nil; lastArtworkHash = 0; refresh(); }
}

static BOOL load(void) {
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!framework) return NO;
    registerForNotifications = dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
    getInfo = dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = dlsym(framework, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(framework, "MRMediaRemoteSetElapsedTime");
    return registerForNotifications && getInfo && getPlaying && getPID && sendCommand && setElapsed;
}

__attribute__((visibility("default")))
void col_media_run(void) {
    @autoreleasepool {
        if (!load()) {
            fprintf(stderr, "MediaRemote is unavailable\n");
            exit(69);
        }
        queue = dispatch_queue_create("ch.rubencatalao.islet.media", DISPATCH_QUEUE_SERIAL);
        registerForNotifications(queue);
        for (NSString *name in @[
                 @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
             ]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(queue, ^{ refresh(); });
            }];
        }
        dispatch_async(queue, ^{ refresh(); });

        // Commands arrive on stdin. When Col goes away the pipe closes, and so does this process.
        dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
        NSMutableData *buffer = [NSMutableData data];
        dispatch_source_set_event_handler(input, ^{
            char chunk[512];
            ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
            if (count <= 0) exit(0);
            [buffer appendBytes:chunk length:(NSUInteger)count];
            while (true) {
                NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
                if (newline.location == NSNotFound) break;
                NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
                [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
                NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
                if (line.length) handle(line);
            }
        });
        dispatch_resume(input);
        CFRunLoopRun();
    }
}
