//
//  Measure.m
//  Music Editor
//
//  Created by Konstantine Prevas on 5/4/06.
//  Copyright 2006 Konstantine Prevas. All rights reserved.
//

#import "Measure.h"
#import "Note.h"
#import "Chord.h"
#import "Clef.h"
#import "Staff.h"
#import "TimeSignature.h"
@class MeasureDraw;
@class MeasureController;

@implementation Measure

- (id)initWithStaff:(Staff *)_staff{
	if((self = [super init])){
		notes = [[NSMutableArray array] retain];
		staff = _staff;
	}
	return self;
}

- (Staff *)getStaff{
	return staff;
}

- (NSUndoManager *)undoManager{
	return [[[[self getStaff] getSong] document] undoManager];
}

- (void)sendChangeNotification{
	[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"modelChanged" object:self]];
}

- (NSMutableArray *)getNotes{
	return notes;
}

- (NoteBase *)getFirstNote{
	return [notes objectAtIndex:0];
}

- (void)prepUndo{
	[[[self undoManager] prepareWithInvocationTarget:self] setNotes:[NSMutableArray arrayWithArray:notes]];	
}

- (void)setNotes:(NSMutableArray *)_notes{
	[self prepUndo];
	if(![notes isEqual:_notes]){
		[notes release];
		notes = [_notes retain];
		[staff cleanEmptyMeasures];
	}
	[self sendChangeNotification];
}

- (float)getTotalDuration{
	float totalDuration = 0;
	NSEnumerator *notesEnum = [notes objectEnumerator];
	id note;
	while(note = [notesEnum nextObject]){
		totalDuration += [note getEffectiveDuration];
	}
	return totalDuration;
}

- (void)addNote:(NoteBase *)_note atIndex:(float)index tieToPrev:(BOOL)tieToPrev{
	[self prepUndo];
	if(fabs(index - round(index)) < 0.25){
		[[self undoManager] setActionName:@"changing note to chord"];
		[self addNote:_note toChordAtIndex:index];
		return;
	} else{
		Note *note = [self addNotes:[NSArray arrayWithObject:_note] atIndex:index];
		Measure *measure = [staff getMeasureContainingNote:note];
		if(tieToPrev){
			Note *tie = [staff findPreviousNoteMatching:note inMeasure:measure];
			[note tieFrom:tie];
			[tie tieTo:note];
		}
		if([measure isFull]) [staff getMeasureAfter:measure];
	}
}

- (NoteBase *)addNotes:(NSArray *)_notes atIndex:(float)index{
	NSEnumerator *notesEnum = [_notes reverseObjectEnumerator];
	NoteBase *note;
	index = ceil(index);
	
	// break tie if necessary
	Note *prevNote = nil, *nextNote = nil;
	if(index-1 >= 0){
		prevNote = [notes objectAtIndex:index-1];
		nextNote = [prevNote getTieTo];
	} else if(index < [notes count]){
		nextNote = [notes objectAtIndex:index];
		prevNote = [nextNote getTieFrom];		
	}
	if(prevNote != nil && nextNote != nil){
		if([prevNote isEqualTo:[_notes objectAtIndex:0]]){
			[prevNote tieTo:[_notes objectAtIndex:0]];
			[[_notes objectAtIndex:0] tieFrom:prevNote];
		} else{
			[prevNote tieTo:nil];
		}
		if([nextNote isEqualTo:[_notes lastObject]]){
			[[_notes lastObject] tieTo:nextNote];
			[nextNote tieFrom:[_notes lastObject]];
		} else{
			[nextNote tieFrom:nil];
		}
	}
	
	while(note = [notesEnum nextObject]){
		[notes insertObject:note atIndex:index];
	}
	if(index >= [notes count]) return nil;
	NoteBase *rtn = [notes objectAtIndex:index];
	return [self refreshNotes:rtn];
}

- (NoteBase *)refreshNotes:(NoteBase *)rtn{
	float totalDuration = [self getTotalDuration];
	float maxDuration = [[self getEffectiveTimeSignature] getMeasureDuration];
	while(totalDuration > maxDuration){
		Note *note = [notes lastObject];
		NSMutableArray *_notes = [NSMutableArray arrayWithObject:note];
		totalDuration -= [note getEffectiveDuration];
		if(totalDuration < maxDuration){
			float durationToFill = maxDuration - totalDuration;
			_notes = [note removeDuration:(durationToFill)];
			int index = [notes count] - 1;
			NoteBase *lastNote = note;
			while(durationToFill > 0){
				Note *fill = [NoteBase tryToFill:durationToFill copyingNote:note];
				[notes insertObject:fill atIndex:index];
				[fill tieTo:lastNote];
				[lastNote tieFrom:fill];
				if(rtn == lastNote) rtn = fill;
				lastNote = fill;
				totalDuration += [fill getEffectiveDuration];
				durationToFill -= [fill getEffectiveDuration];
			}
		}
		[notes removeLastObject];
		Measure *nextMeasure = [staff getMeasureAfter:self];
		[nextMeasure prepUndo];
		[nextMeasure addNotes:_notes atIndex:0];
	}
	return rtn;
}

- (void)grabNotesFromNextMeasure{
	if([staff getLastMeasure] == self) return;
	Measure *nextMeasure = [staff getMeasureAfter:self];
	[nextMeasure prepUndo];
	float totalDuration = [self getTotalDuration];
	float maxDuration = [[self getEffectiveTimeSignature] getMeasureDuration];
	while(totalDuration < maxDuration && ![nextMeasure isEmpty]){
		float durationToFill = maxDuration - totalDuration;
		NoteBase *nextNote = [nextMeasure getFirstNote];
		[nextMeasure removeNoteAtIndex:0 temporary:YES];
		if([nextNote getEffectiveDuration] <= durationToFill){
			[notes addObject:nextNote];
			totalDuration += [nextNote getEffectiveDuration];
		} else{
			NSMutableArray *_notes = [nextNote removeDuration:durationToFill];
			[nextMeasure addNotes:_notes atIndex:0];
			[nextMeasure grabNotesFromNextMeasure];
			Note *tieFrom = [nextNote getTieFrom];
			Note *note = nextNote;
			Note *lastNote = note;
			while(durationToFill > 0){
				note = [NoteBase tryToFill:durationToFill copyingNote:note];
				[notes addObject:note];
				[note tieTo:lastNote];
				[note tieFrom:tieFrom];
				[tieFrom tieTo:note];
				tieFrom = nil;
				[lastNote tieFrom:note];
				lastNote = note;
				totalDuration += [note getEffectiveDuration];
				durationToFill -= [note getEffectiveDuration];			
			}
			totalDuration = [self getTotalDuration];
		}
	}
}

- (void)removeNoteAtIndex:(float)x temporary:(BOOL)temp{
	[self prepUndo];
	NoteBase *note = [notes objectAtIndex:floor(x)];
	if(!temp){
		[note prepareForDelete];
	}
	[notes removeObjectAtIndex:floor(x)];
	[self grabNotesFromNextMeasure];
	if(!temp){
		[staff cleanEmptyMeasures];
		[self sendChangeNotification];
	}
}

- (void)addNote:(NoteBase *)newNote toChordAtIndex:(float)index{
	NoteBase *note = [notes objectAtIndex:index];
	if([note isKindOfClass:[Chord class]]){
		[note addNote:newNote];
	} else{
		[newNote setDuration:[note getDuration]];
		[newNote setDotted:[note getDotted]];
		NSMutableArray *chordNotes = [NSMutableArray arrayWithObjects:note, newNote, nil];
		Chord *chord = [[[Chord alloc] initWithStaff:staff withNotes:chordNotes] autorelease];
		[notes replaceObjectAtIndex:index withObject:chord];
	}
}

- (void)removeNote:(NoteBase *)note fromChordAtIndex:(float)index{
	NoteBase *chord = [notes objectAtIndex:index];
	if([chord isKindOfClass:[Chord class]]){
		if([[chord getNotes] containsObject:note]){
			if([[chord getNotes] count] > 2){
				[chord removeNote:note];
			} else{
				Note *otherNote = nil;
				NSEnumerator *chordNotes = [[chord getNotes] objectEnumerator];
				while(otherNote = [chordNotes nextObject]){
					if(otherNote != note){
						[notes replaceObjectAtIndex:index withObject:otherNote];
						break;
					}
				}
			}
		}
	} else{
		[self removeNoteAtIndex:index temporary:NO];
	}
}

- (BOOL)isEmpty{
	return [notes count] == 0;
}

- (BOOL)isFull{
	float totalDuration = 0.0;
	NSEnumerator *notesEnum = [notes objectEnumerator];
	id note;
	while(note = [notesEnum nextObject]){
		totalDuration += [note getEffectiveDuration];
	}
	return totalDuration == [[self getEffectiveTimeSignature] getMeasureDuration];
}

- (Clef *)getClef{
	return clef;
}

- (Clef *)getEffectiveClef{
	return [staff getClefForMeasure:self];
}

- (void)setClef:(Clef *)_clef{
	if(![clef isEqual:_clef]){
		[[[self undoManager] prepareWithInvocationTarget:self] setClef:clef];
		[clef release];
		clef = [_clef retain];
		[self sendChangeNotification];
	}
}

- (KeySignature *)getKeySignature{
	return keySig;
}

- (KeySignature *)getEffectiveKeySignature{
	return [staff getKeySignatureForMeasure:self];
}

- (void)setKeySignature:(KeySignature *)_sig{
	if(![keySig isEqual:_sig]){
		[[[self undoManager] prepareWithInvocationTarget:self] setKeySignature:keySig];
		[keySig release];
		keySig = [_sig retain];
		[self updateKeySigPanel];
		[self sendChangeNotification];
	}
}

- (TimeSignature *)getTimeSignature{
	return [staff getTimeSignatureForMeasure:self];
}

- (BOOL)hasTimeSignature{
	return ![[self getTimeSignature] isKindOfClass:[NSNull class]];
}

- (TimeSignature *)getEffectiveTimeSignature{
	return [staff getEffectiveTimeSignatureForMeasure:self];
}

- (void)timeSignatureChangedFrom:(float)oldTotal to:(float)newTotal top:(int)top bottom:(int)bottom{
	if(newTotal < oldTotal){
		[self prepUndo];
		[self refreshNotes:nil];
	} else{
		[self prepUndo];
		[self grabNotesFromNextMeasure];
	}
	[timeSigTopStep setIntValue:top];
	[timeSigTopText setIntValue:top];
	[timeSigBottom selectItemWithTitle:[NSString stringWithFormat:@"%d", bottom]];
	[[timeSigPanel superview] setNeedsDisplay:YES];
}

- (BOOL)isShowingKeySigPanel{
	return keySigPanel != nil && ![keySigPanel isHidden];
}

- (NSView *)getKeySigPanel{
	if(keySigPanel == nil){
		[NSBundle loadNibNamed:@"KeySigPanel" owner:self];
		[keySigPanel setHidden:YES];
	}
	return keySigPanel;
}

- (BOOL)isShowingTimeSigPanel{
	return timeSigPanel != nil && ![timeSigPanel isHidden];
}

- (NSView *)getTimeSigPanel{
	if(timeSigPanel == nil){
		[NSBundle loadNibNamed:@"TimeSigPanel" owner:self];
		[timeSigPanel setHidden:YES];
	}
	return timeSigPanel;
}

- (NoteBase *)getNoteBefore:(NoteBase *)source{
	int index = [notes indexOfObject:source];
	if(index != NSNotFound && index > 0){
		return [notes objectAtIndex:index-1];
	}
	return nil;
}

- (float)getNoteStartDuration:(NoteBase *)note{
	float start = 0;
	NSEnumerator *notesEnum = [notes objectEnumerator];
	id currNote;
	while((currNote = [notesEnum nextObject]) && currNote != note){
		start += [currNote getEffectiveDuration];
	}
	return start;
}

- (float)getNoteEndDuration:(NoteBase *)note{
	return [self getNoteStartDuration:note] + [note getEffectiveDuration];
}

- (int)getNumberOfNotesStartingAfter:(float)startDuration before:(float)endDuration{
	float duration = 0;
	int count = 0;
	NSEnumerator *notesEnum = [notes objectEnumerator];
	id currNote;
	while((currNote = [notesEnum nextObject]) && duration < endDuration){
		if(duration > startDuration){
			count++;
		}
		duration += [currNote getEffectiveDuration];
	}
	return count;
}

- (void)transposeBy:(int)transposeAmount{
	NSEnumerator *notesEnum = [notes objectEnumerator];
	id note;
	while(note = [notesEnum nextObject]){
		[note transposeBy:transposeAmount];
	}
}

- (IBAction)keySigChanged:(id)sender{
	[[self undoManager] setActionName:@"changing key signature"];
	KeySignature *newSig;
	if([[[keySigMajMin selectedItem] title] isEqual:@"major"]){
		newSig = [KeySignature getMajorSignatureAtIndexFromA:[keySigLetter indexOfSelectedItem]];
		if(newSig == nil){
			newSig = [KeySignature getMinorSignatureAtIndexFromA:[keySigLetter indexOfSelectedItem]];
			[keySigMajMin selectItemWithTitle:@"minor"];
		}
	} else{
		newSig = [KeySignature getMinorSignatureAtIndexFromA:[keySigLetter indexOfSelectedItem]];
		if(newSig == nil){
			newSig = [KeySignature getMajorSignatureAtIndexFromA:[keySigLetter indexOfSelectedItem]];
			[keySigMajMin selectItemWithTitle:@"major"];
		}
	}
	[self setKeySignature:newSig];
	[[keySigPanel superview] setNeedsDisplay:YES];
}

- (IBAction)keySigClose:(id)sender{
	[keySigPanel setHidden:YES withFade:YES blocking:(sender != nil)];
	if([keySigPanel superview] != nil){
		[keySigPanel removeFromSuperview];
	}
}

- (void)updateKeySigPanel{
	int index;
	BOOL minor;
	KeySignature *sig = [self getEffectiveKeySignature];
	[keySigLetter selectItemAtIndex:[sig getIndexFromA]];
	if([sig isMinor]){
		[keySigMajMin selectItemAtIndex:1];
	} else{
		[keySigMajMin selectItemAtIndex:0];
	}
}

- (IBAction)timeSigTopChanged:(id)sender{
	[[self undoManager] setActionName:@"changing time signature"];
	int value = [sender intValue];
	if(value < 1) value = 1;
	[timeSigTopStep setIntValue:value];
	[timeSigTopText setIntValue:value];
	[staff timeSigChangedAtMeasure:self top:[timeSigTopText intValue] bottom:[[[timeSigBottom selectedItem] title] intValue]];
}

- (IBAction)timeSigBottomChanged:(id)sender{
	[[self undoManager] setActionName:@"changing time signature"];
	[staff timeSigChangedAtMeasure:self top:[timeSigTopText intValue] bottom:[[[timeSigBottom selectedItem] title] intValue]];
}

- (IBAction)timeSigClose:(id)sender{
	[timeSigPanel setHidden:YES withFade:YES blocking:(sender != nil)];
	if([timeSigPanel superview] != nil){
		[timeSigPanel removeFromSuperview];
	}
}

- (void)cleanPanels{
	[self timeSigClose:nil];
	[self keySigClose:nil];
}

- (float)addToMIDITrack:(MusicTrack *)musicTrack atPosition:(float)pos onChannel:(int)channel{
	float initPos = pos;
	NSEnumerator *noteEnum = [notes objectEnumerator];
	NSMutableDictionary *accidentals = [NSMutableDictionary dictionary];
	id note;
	while(note = [noteEnum nextObject]){
		pos += [note addToMIDITrack:musicTrack atPosition:pos withKeySignature:[self getEffectiveKeySignature]
				accidentals:accidentals onChannel:channel];
	}
	return pos - initPos;
}

- (void)encodeWithCoder:(NSCoder *)coder{
	[coder encodeObject:staff forKey:@"staff"];
	if(clef == [Clef trebleClef]){
		[coder encodeObject:@"treble" forKey:@"clef"];
	}
	if(clef == [Clef bassClef]){
		[coder encodeObject:@"bass" forKey:@"clef"];
	}
	if(keySig != nil){
		[coder encodeInt:[keySig getNumFlats] forKey:@"keySigFlats"];
		[coder encodeInt:[keySig getNumSharps] forKey:@"keySigSharps"];
		[coder encodeBool:[keySig isMinor] forKey:@"keySigMinor"];
		if([keySig getNumFlats] == 0 && [keySig getNumSharps] == 0){
			[coder encodeBool:YES forKey:@"keySigC"];
		}
	}
	[coder encodeObject:notes forKey:@"notes"];
}

- (id)initWithCoder:(NSCoder *)coder{
	if(self = [super init]){
		staff = [coder decodeObjectForKey:@"staff"];
		id deClef = [coder decodeObjectForKey:@"clef"];
		if([deClef isEqualToString:@"treble"]){
			[self setClef:[Clef trebleClef]];
		} else if([deClef isEqualToString:@"bass"]){
			[self setClef:[Clef bassClef]];
		}
		int flats = [coder decodeIntForKey:@"keySigFlats"];
		int sharps = [coder decodeIntForKey:@"keySigSharps"];
		BOOL minor = [coder decodeBoolForKey:@"keySigMinor"];
		if(flats > 0){
			[self setKeySignature:[KeySignature getSignatureWithFlats:flats minor:minor]];
		} else if(sharps > 0){
			[self setKeySignature:[KeySignature getSignatureWithSharps:sharps minor:minor]];
		} else if([coder decodeBoolForKey:@"keySigC"]){
			[self setKeySignature:[KeySignature getSignatureWithFlats:0 minor:NO]];
		}
		[self setNotes:[coder decodeObjectForKey:@"notes"]];
	}
	return self;
}

- (void)dealloc{
	[clef release];
	[keySig release];
	[notes release];
	[anim release];
	clef = nil;
	keySig = nil;
	notes = nil;
	anim = nil;
	[super dealloc];
}

- (Class)getViewClass{
	return [MeasureDraw class];
}

- (Class)getControllerClass{
	return [MeasureController class];
}

@end
