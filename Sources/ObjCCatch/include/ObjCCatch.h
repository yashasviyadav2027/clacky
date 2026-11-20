#import <Foundation/Foundation.h>

/// Runs `block`, catching any Objective-C exception (AVFAudio raises these instead of
/// returning errors). Returns the exception's reason, or nil if the block finished normally.
NSString * _Nullable ClackyCatchException(void (NS_NOESCAPE ^ _Nonnull block)(void));
