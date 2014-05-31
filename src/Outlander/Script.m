//
//  Script.m
//  Outlander
//
//  Created by Joseph McBride on 5/26/14.
//  Copyright (c) 2014 Joe McBride. All rights reserved.
//

#import "Script.h"
#import "TSMutableDictionary.h"
#import <PEGKit/PEGKit.h>
#import "OutlanderParser.h"
#import "TextTag.h"
#import "CommandContext.h"
#import "CommandHandler.h"
#import "GameCommandRelay.h"
#import "VariableReplacer.h"
#import "NSString+Categories.h"

@interface Script () {
    id<InfoStream> _gameStream;
    id<CommandRelay> _commandRelay;
    GameContext *_context;
    OutlanderParser *_parser;
    NSMutableArray *_scriptLines;
    VariableReplacer *_varReplacer;
}

@property (nonatomic, strong) TSMutableDictionary *labels;
@property (nonatomic, assign) NSUInteger lineNumber;

@end

@implementation Script

- (instancetype)initWith:(GameContext *)context and:(NSString *)data {
    self = [super init];
    if(!self) return nil;
    
    _context = context;
    
    _labels = [[TSMutableDictionary alloc] initWithName:[NSString stringWithFormat:@"com.outlander.script.labels.%@", self.uuid]];
    _localVars = [[TSMutableDictionary alloc] initWithName:[NSString stringWithFormat:@"com.outlander.script.localvars.%@", self.uuid]];
    
    _parser = [[OutlanderParser alloc] initWithDelegate:self];
    _commandRelay = [[GameCommandRelay alloc] init];
    _pauseCondition = [[NSCondition alloc] init];
    _varReplacer = [[VariableReplacer alloc] init];
    
    [self setData:data];
    
    return self;
}

- (void)setGameStream:(id<InfoStream>)stream {
    _gameStream = stream;
}

- (void)setCommandRelay:(id<CommandRelay>)relay {
    _commandRelay = relay;
}

- (void)setData:(NSString *)data {
    
    _lineNumber = 0;
    
    NSArray *lines = [data componentsSeparatedByString:@"\n"];
    
    _scriptLines = [[NSMutableArray alloc] initWithArray:lines];
}

- (void)process {
    NSLog(@"%@ :: script running", [self description]);
    
    if(_lineNumber >= _scriptLines.count) {
        NSLog(@"End of script!");
        [self cancel];
        return;
    }
    
    NSString *line = _scriptLines[_lineNumber];
   
    NSError *err;
    PKAssembly *result = [_parser parseString:line error:&err];
    
    if(err) {
        NSLog(@"err: %@", [err localizedDescription]);
        [self cancel];
        return;
    }
    
    NSLog(@"Script line result: %@", [result description]);
    
    _lineNumber++;
}

- (void)parser:(PKParser *)p didMatchWaitForStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
   
    __block BOOL gotSignal = NO;
    __block RACDisposable *signal = nil;
    
    NSString *matchText = [self popCommandsToString:a];
    
    signal = [_gameStream.subject.signal subscribeNext:^(NSArray *arr) {
        
        [arr enumerateObjectsUsingBlock:^(TextTag *obj, NSUInteger idx, BOOL *stop) {
            
            if([obj.text containsString:matchText]){
                *stop = YES;
                gotSignal = YES;
                [signal dispose];
                [self.pauseCondition signal];
                [self sendScriptDebug:[NSString stringWithFormat:@"matched %@", obj.text]];
            }
        }];
        
    }];
    
    [self sendScriptDebug:[NSString stringWithFormat:@"waitfor %@", matchText]];
    
    [self.pauseCondition lock];
    
    while(!gotSignal) {
        [self.pauseCondition wait];
    }
    
    [self.pauseCondition unlock];
}

- (void)parser:(PKParser *)p didMatchWaitStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
   
    __block BOOL gotSignal = NO;
    __block RACDisposable *signal = nil;
    
    signal = [_gameStream.subject.signal subscribeNext:^(id x) {
        gotSignal = YES;
        [signal dispose];
        [self.pauseCondition signal];
        [self sendScriptDebug:@"prompt recieved"];
    }];
    
    [self sendScriptDebug:@"waiting for prompt"];
    
    [self.pauseCondition lock];
    
    while(!gotSignal) {
        [self.pauseCondition wait];
    }
    
    [self.pauseCondition unlock];
}

- (void)parser:(PKParser *)p didMatchMoveStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
   
    __block BOOL gotRoom = NO;
    __block RACDisposable *signal = nil;
    
    signal = [_gameStream.room.signal subscribeNext:^(id x) {
        gotRoom = YES;
        [signal dispose];
        [self.pauseCondition signal];
    }];
    
    PKToken *direction = [a pop];
    PKToken *command = [a pop];
    
    if([[command stringValue] isEqualToString:@"move"]) {
        [self sendCommand:[self replaceVars:[direction stringValue]]];
    }
    
    [self sendScriptDebug:[NSString stringWithFormat:@"%@ - waiting for room description", [command stringValue]]];
    
    [self.pauseCondition lock];
    
    while(!gotRoom) {
        [self.pauseCondition wait];
    }
    
    [self.pauseCondition unlock];
}

- (void)parser:(PKParser *)p didMatchCommandsStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    NSMutableString *commandString = [self popCommandsToString:a];
    
    [commandString insertString:@"#" atIndex:0];
    [self sendCommand:commandString];
}

- (void)parser:(PKParser *)p didMatchVarStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    PKToken *rh = [a pop];
    PKToken *lh = [a pop];
    
    [self.localVars setCacheObject:[rh stringValue] forKey:[lh stringValue]];
}

- (void)parser:(PKParser *)p didMatchEchoStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    NSString *echoString = [self popCommandsToString:a];
    
    [self sendEcho:echoString];
}

- (void)parser:(PKParser *)p didMatchPutStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    NSString *putString = [self popCommandsToString:a];
    
    [self sendCommand:putString];
}

- (void)parser:(PKParser *)p didMatchPauseStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    PKToken *token = [a pop];
    
    // ignore pause in #script statements
    if([[token stringValue] isEqualToString:@"script"])
        return;
    
    NSTimeInterval interval = 1.0;
    if(token) {
        interval = [token doubleValue];
        if(interval < 1) {
            interval = 1.0;
        }
    }
    
    NSString *debug = [NSString stringWithFormat:@"pausing for %#2.0f", interval];
    [self sendScriptDebug:debug];
    
    [NSThread sleepForTimeInterval:interval];
}

- (void)parser:(PKParser *)p didMatchLabelStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    PKToken *label = [a pop];
    
    NSLog(@"Label: %@", [label stringValue]);
    
    [_labels setCacheObject:@(_lineNumber) forKey:[label stringValue]];
}

- (void)parser:(PKParser *)p didMatchGotoStmt:(PKAssembly *)a {
    NSLog(@"%s %@", __PRETTY_FUNCTION__, a);
    
    PKToken *labelToken = [a pop];
    
    NSString *label = [self replaceVars:[labelToken stringValue]];
    
    [self sendScriptDebug:[NSString stringWithFormat:@"goto %@", label]];
    
    NSNumber *gotoObj = [_labels cacheObjectForKey:label];
    
    if(!gotoObj) {
        [self sendScriptDebug:[NSString stringWithFormat:@"unknown label %@", label]];
        [self cancel];
        return;
    }
    
    _lineNumber = [gotoObj integerValue];
}

- (void)sendCommand:(NSString *)command {
    
    CommandContext *ctx = [[CommandContext alloc] init];
    ctx.command = [command trimWhitespaceAndNewline];
    ctx.tag = [TextTag tagFor:[NSString stringWithFormat:@"[%@]: %@\n", _name, command] mono:YES];
    ctx.tag.color = @"#0066CC";
    
    [_commandRelay sendCommand:ctx];
}

- (void)sendEcho:(NSString *)echo {
    TextTag *tag = [TextTag tagFor:[NSString stringWithFormat:@"[%@]: %@\n", _name, [echo trimWhitespaceAndNewline]] mono:YES];
    tag.color = @"#0066CC";
   
    [_commandRelay sendEcho:tag];
}

- (void)sendScriptDebug:(NSString *)msg {
    TextTag *tag = [TextTag tagFor:[NSString stringWithFormat:@"[%@ (%lu)]: %@\n", _name, (unsigned long)_lineNumber, msg] mono:YES];
    tag.color = @"#0066CC";
    
    [_commandRelay sendEcho:tag];
}

- (NSMutableString *)popCommandsToString:(PKAssembly *)a {
    
    NSMutableString *str = [[NSMutableString alloc] init];
    
    PKToken *token = [a pop];
    
    while(token) {
        
        NSString *space = [str length] > 0 ? @" " : @"";
        NSString *tokenVal = [token stringValue];
        
        if([tokenVal hasPrefix:@"%"] || [tokenVal hasPrefix:@"$"] || [tokenVal hasPrefix:@"."]) {
            space = @"";
        }
        
        if([str hasPrefix:@"."]) {
            space = @"";
        }
        
        NSString *val = [NSString stringWithFormat:@"%@%@", tokenVal, space];
        
        [str insertString:val atIndex:0];
        
        token = [a pop];
    }
    
    return [[self replaceVars:str] mutableCopy];
}

- (NSString *)replaceVars:(NSString *)str {
    NSString *replaced = [_varReplacer replace:str withContext:_context];
    return [_varReplacer replaceLocalVars:replaced withVars:_localVars];
}

@end
