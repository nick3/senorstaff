//
//  NSPopUpButton+Images.m
//  Señor Staff
//
//  Created by Konstantine Prevas on 11/26/06.
//  Copyright 2006 Konstantine Prevas. All rights reserved.
//

#import "NSPopUpButton+Images.h"


@implementation NSPopUpButton(Images)

- (void)insertImages{
	NSEnumerator *items = [[self itemArray] objectEnumerator];
	id item;
	while(item = [items nextObject]){
		NSString *title = [item title];
		if([title characterAtIndex:0] == '{'){
			NSRange endIndex = [title rangeOfString:@"}"];
			NSString *filename = [title substringWithRange:NSMakeRange(1, endIndex.location - 1)];
			NSString *titleText = [title substringFromIndex:(endIndex.length + endIndex.location)];
			NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
			NSCell *cell = [attachment attachmentCell];
			NSImage *icon = [NSImage imageNamed:filename];
			[cell setImage:icon];
			NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
			NSDictionary *attr = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, nil];
			NSAttributedString *attrString = [[[NSAttributedString alloc] initWithString:titleText attributes:attr] autorelease];
			NSMutableAttributedString *attrTitle = [NSMutableAttributedString attributedStringWithAttachment:attachment];
			[attrTitle appendAttributedString:attrString];
			[item setAttributedTitle:attrTitle];
		}
	}
}

@end