//
//  KeySignatureController.m
//  Señor Staff
//
//  Created by Konstantine Prevas on 9/4/06.
//  Copyright 2006 Konstantine Prevas. All rights reserved.
//

#import "KeySignatureController.h"
#import "KeySignature.h"

@implementation KeySignatureController

+ (float) widthOf:(KeySignature *)keySig{
	if(keySig == nil){
		return 10.0;
	}
	int numSymbols = [keySig getNumSharps] + [keySig getNumFlats];
	if(numSymbols == 0){		
		return 10.0;
	}
	return numSymbols * 10.0;	
}

+ (void)handleMouseClick:(NSEvent *)event at:(NSPoint)location on:(KeySigTarget *)sig mode:(NSDictionary *)mode view:(ScoreView *)view{
	[view showKeySigPanelFor:[sig measure]];
}

@end