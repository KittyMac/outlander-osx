//
//  VitalsViewController.h
//  Outlander
//
//  Created by Joseph McBride on 2/3/14.
//  Copyright (c) 2014 Joe McBride. All rights reserved.
//

#import "MyView.h"

@interface VitalsViewController : NSViewController

-(void)updateColor:(NSString *)key foreground:(NSString *)foregroundColor background:(NSString *) backgroundColor;
-(void)updateValue:(NSString *)key text:(NSString*)text value:(float)value;

@end
