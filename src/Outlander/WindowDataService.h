//
//  WindowDataService.h
//  Outlander
//
//  Created by Joseph McBride on 5/1/14.
//  Copyright (c) 2014 Joe McBride. All rights reserved.
//

#import "Mantle.h"
#import "WindowData.h"
#import "GameContext.h"

@interface WindowDataService : NSObject

- (NSDictionary *)jsonFor:(NSString *) windowName Window:(NSRect) location;
- (WindowData *)dataFor:(NSDictionary *)json;
- (NSArray *)readWindowJson:(GameContext *)context;
- (void)write:(GameContext *)context WindowJson:(NSArray *)windows;
@end