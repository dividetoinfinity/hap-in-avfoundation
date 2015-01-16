#import "HapDecoderFrame.h"
#import "HapCodecSubTypes.h"
#import "PixelFormats.h"
#import "HapPlatform.h"
#import "Utility.h"
#import "hap.h"
#import "CMBlockBufferPool.h"



/*
void CMBlockBuffer_FreeHapDecoderFrame(void *refCon, void *doomedMemoryBlock, size_t sizeInBytes)	{
	//	'refCon' is the HapDecoderFrame instance which contains the data that is backing this block buffer...
	[(id)refCon release];
}
*/
void CVPixelBuffer_FreeHapDecoderFrame(void *releaseRefCon, const void *baseAddress)	{
	//	'releaseRefCon' is the HapDecoderFrame instance which contains the data that is backing this pixel buffer...
	[(id)releaseRefCon release];
}

#define FourCCLog(n,f) NSLog(@"%@, %c%c%c%c",n,(int)((f>>24)&0xFF),(int)((f>>16)&0xFF),(int)((f>>8)&0xFF),(int)((f>>0)&0xFF))




@implementation HapDecoderFrame


+ (void) initialize	{
	//	make sure the CMMemoryPool used by this framework exists
	OSSpinLockLock(&_HIAVFMemPoolLock);
	if (_HIAVFMemPool==NULL)
		_HIAVFMemPool = CMMemoryPoolCreate(NULL);
	if (_HIAVFMemPoolAllocator==NULL)
		_HIAVFMemPoolAllocator = CMMemoryPoolGetAllocator(_HIAVFMemPool);
	OSSpinLockUnlock(&_HIAVFMemPoolLock);
}
- (id) initWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [self initEmptyWithHapSampleBuffer:sb];
	dxtData = CFAllocatorAllocate(_HIAVFMemPoolAllocator, dxtMinDataSize, 0);
	dxtDataSize = dxtMinDataSize;
	userInfo = (id)CFDataCreateWithBytesNoCopy(NULL, dxtData, dxtMinDataSize, _HIAVFMemPoolAllocator);
	return self;
}
- (id) initEmptyWithHapSampleBuffer:(CMSampleBufferRef)sb	{
	self = [super init];
	if (self != nil)	{
		hapSampleBuffer = NULL;
		codecSubType = 0;
		imgSize = NSMakeSize(0,0);
		dxtData = nil;
		dxtMinDataSize = 0;
		dxtDataSize = 0;
		dxtPixelFormat = 0;
		dxtImgSize = NSMakeSize(0,0);
		dxtTextureFormat = 0;
		rgbData = nil;
		rgbMinDataSize = 0;
		rgbDataSize = 0;
		rgbPixelFormat = kCVPixelFormatType_32BGRA;
		rgbImgSize = NSMakeSize(0,0);
		atomicLock = OS_SPINLOCK_INIT;
		userInfo = nil;
		decoded = NO;
		
		hapSampleBuffer = sb;
		if (hapSampleBuffer==NULL)	{
			NSLog(@"\t\terr, bailing- hapSampleBuffer nil in %s",__func__);
			goto BAIL;
		}
		CFRetain(hapSampleBuffer);
		
		//NSLog(@"\t\tthis frame's time is %@",[(id)CMTimeCopyDescription(kCFAllocatorDefault, CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer)) autorelease]);
		CMFormatDescriptionRef	desc = (sb==NULL) ? NULL : CMSampleBufferGetFormatDescription(sb);
		if (desc==NULL)	{
			NSLog(@"\t\terr, bailing- desc nil in %s",__func__);
			if (!CMSampleBufferIsValid(sb))
				NSLog(@"\t\terr: as a note, the sample buffer wasn't valid in %s",__func__);
			goto BAIL;
		}
		//NSLog(@"\t\textensions are %@",CMFormatDescriptionGetExtensions(desc));
		CGSize			tmpSize = CMVideoFormatDescriptionGetPresentationDimensions(desc, true, false);
		imgSize = NSMakeSize(tmpSize.width, tmpSize.height);
		dxtImgSize = NSMakeSize(roundUpToMultipleOf4(imgSize.width), roundUpToMultipleOf4(imgSize.height));
		rgbDataSize = 32 * tmpSize.width * tmpSize.height / 8;
		rgbImgSize = imgSize;
		//NSLog(@"\t\timgSize is %f x %f",imgSize.width,imgSize.height);
		//NSLog(@"\t\tdxtImgSize is %f x %f",dxtImgSize.width,dxtImgSize.height);
		codecSubType = CMFormatDescriptionGetMediaSubType(desc);
		switch (codecSubType)	{
		case kHapCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_RGB_DXT1;
			break;
		case kHapAlphaCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_RGBA_DXT5;
			break;
		case kHapYCoCgCodecSubType:
			dxtPixelFormat = kHapCVPixelFormat_YCoCg_DXT5;
			break;
		}
		dxtMinDataSize = dxtBytesForDimensions(dxtImgSize.width, dxtImgSize.height, codecSubType);
		rgbMinDataSize = 32 * tmpSize.width * tmpSize.height / 8;
	}
	return self;
	BAIL:
	[self release];
	return nil;
}
- (void) dealloc	{
	if (hapSampleBuffer != nil)	{
		CFRelease(hapSampleBuffer);
		hapSampleBuffer = NULL;
	}
	dxtData = NULL;
	rgbData = NULL;
	if (userInfo != nil)	{
		[userInfo release];
		userInfo = nil;
	}
	[super dealloc];
}
- (NSString *) description	{
	if (hapSampleBuffer==nil)
		return @"<HapDecoderFrame>";
	CMTime		presentationTime = CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer);
	return [NSString stringWithFormat:@"<HapDecoderFrame, %d, %f x %f, %@>",dxtTextureFormat,dxtImgSize.width,dxtImgSize.height,[(id)CMTimeCopyDescription(kCFAllocatorDefault,presentationTime) autorelease]];
}
- (CMSampleBufferRef) hapSampleBuffer	{
	return hapSampleBuffer;
}
- (OSType) codecSubType	{
	return codecSubType;
}
- (NSSize) imgSize	{
	return imgSize;
}
- (void) setDXTData:(void *)n	{
	dxtData = n;
}
- (size_t) dxtMinDataSize	{
	return dxtMinDataSize;
}
- (void) setDXTDataSize:(size_t)n	{
	dxtDataSize = n;
}
- (void *) dxtData	{
	return dxtData;
}
- (size_t) dxtDataSize	{
	return dxtDataSize;
}
- (OSType) dxtPixelFormat	{
	return dxtPixelFormat;
}
- (NSSize) dxtImgSize	{
	return dxtImgSize;
}
- (void) setDXTTextureFormat:(enum HapTextureFormat)n	{
	dxtTextureFormat = n;
}
- (enum HapTextureFormat) dxtTextureFormat	{
	return dxtTextureFormat;
}
- (void) setRGBData:(void *)n	{
	rgbData = n;
}
- (void *) rgbData	{
	return rgbData;
}
- (size_t) rgbMinDataSize	{
	return rgbDataSize;
}
- (void) setRGBDataSize:(size_t)n	{
	rgbDataSize = n;
}
- (size_t) rgbDataSize	{
	return rgbDataSize;
}
- (void) setRGBPixelFormat:(OSType)n	{
	if (n!=kCVPixelFormatType_32BGRA && n!=kCVPixelFormatType_32RGBA)	{
		NSString		*errFmtString = [NSString stringWithFormat:@"\t\tERR in %s, can't use new format:",__func__];
		FourCCLog(errFmtString,n);
		return;
	}
	rgbPixelFormat = n;
}
- (OSType) rgbPixelFormat	{
	return rgbPixelFormat;
}
- (void) setRGBImgSize:(NSSize)n	{
	rgbImgSize = n;
}
- (NSSize) rgbImgSize	{
	return rgbImgSize;
}
- (CMTime) presentationTime	{
	return ((hapSampleBuffer==NULL) ? kCMTimeInvalid : CMSampleBufferGetPresentationTimeStamp(hapSampleBuffer));
}


- (CMSampleBufferRef) allocCMSampleBufferFromRGBData	{
	//NSLog(@"%s ... %@",__func__,self);
	//	if there's no RGB data, bail immediately
	if (rgbData==nil)	{
		NSLog(@"\t\terr: no RGB data, can't alloc a CMSampleBufferRef, %s",__func__);
		return NULL;
	}
	CMSampleBufferRef		returnMe = NULL;
	//	make a CVPixelBufferRef from my RGB data
	CVReturn				cvErr = kCVReturnSuccess;
	NSDictionary			*pixelBufferAttribs = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInteger:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
		[NSNumber numberWithInteger:(NSUInteger)rgbImgSize.width], kCVPixelBufferWidthKey,
		[NSNumber numberWithInteger:(NSUInteger)rgbImgSize.height], kCVPixelBufferHeightKey,
		[NSNumber numberWithInteger:rgbDataSize/(NSUInteger)rgbImgSize.height], kCVPixelBufferBytesPerRowAlignmentKey,
		nil];
	CVPixelBufferRef		cvPixRef = NULL;
	cvErr = CVPixelBufferCreateWithBytes(NULL,
		(size_t)rgbImgSize.width,
		(size_t)rgbImgSize.height,
		rgbPixelFormat,
		rgbData,
		rgbDataSize/(size_t)rgbImgSize.height,
		CVPixelBuffer_FreeHapDecoderFrame,
		self,
		(CFDictionaryRef)pixelBufferAttribs,
		&cvPixRef);
	if (cvErr!=kCVReturnSuccess || cvPixRef==NULL)	{
		NSLog(@"\t\terr %d at CVPixelBufferCreateWithBytes() in %s",cvErr,__func__);
		NSLog(@"\t\tattribs were %@",pixelBufferAttribs);
		NSLog(@"\t\tsize was %ld x %ld",(size_t)rgbImgSize.width,(size_t)rgbImgSize.height);
		NSLog(@"\t\trgbPixelFormat passed to method is %u",(unsigned int)rgbPixelFormat);
	}
	else	{
		//	retain self, to ensure that this HapDecoderFrame instance will persist at least until the CVPixelBufferRef frees it!
		[self retain];
		
		//	make a CMFormatDescriptionRef that describes the RGB data
		CMFormatDescriptionRef		desc = NULL;
		//NSDictionary				*bufferExtensions = [NSDictionary dictionaryWithObjectsAndKeys:
		//	[NSNumber numberWithUnsignedLong:rgbDataSize/(size_t)rgbImgSize.height], @"CVBytesPerRow",
			//@"SMPTE_C", @"CVImageBufferColorPrimaries",
			//[NSNumber numberWithDouble:2.199996948242188], kCMFormatDescriptionExtension_GammaLevel,
			//kCVImageBufferTransferFunction_UseGamma, kCVImageBufferTransferFunctionKey,
			//kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVImageBufferYCbCrMatrixKey,
			//[NSNumber numberWithInt:2], kCMFormatDescriptionExtension_Version,
		//	nil];
		OSStatus					osErr = CMVideoFormatDescriptionCreateForImageBuffer(NULL,
			cvPixRef,
			&desc);
		if (osErr!=noErr || desc==NULL)
			NSLog(@"\t\terr %d at CMVideoFormatDescriptionCreate() in %s",(int)osErr,__func__);
		else	{
			//NSLog(@"\t\textensions of created fmt desc are %@",CMFormatDescriptionGetExtensions(desc));
			//FourCCLog(@"\t\tmedia sub-type of fmt desc is",CMFormatDescriptionGetMediaSubType(desc));
			//	get the timing info from the hap sample buffer
			CMSampleTimingInfo		timing;
			CMSampleBufferGetSampleTimingInfo(hapSampleBuffer, 0, &timing);
			timing.duration = kCMTimeInvalid;
			//timing.presentationTimeStamp = kCMTimeInvalid;
			timing.decodeTimeStamp = kCMTimeInvalid;
			//	make a CMSampleBufferRef from the CVPixelBufferRef
			osErr = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
				cvPixRef,
				desc,
				&timing,
				&returnMe);
			if (osErr!=noErr || returnMe==NULL)
				NSLog(@"\t\terr %d at CMSampleBufferCreateForImageBuffer() in %s",osErr,__func__);
			else	{
				//NSLog(@"\t\tsuccessfully allocated a CMSampleBuffer from the RGB data in me! %@/%s",self,__func__);
			}
			
			
			CFRelease(desc);
			desc = NULL;
		}
		
		
		CVPixelBufferRelease(cvPixRef);
		cvPixRef = NULL;
	}
	
	return returnMe;
}


- (void) setUserInfo:(id)n	{
	OSSpinLockLock(&atomicLock);
	if (n!=userInfo)	{
		if (userInfo!=nil)
			[userInfo release];
		userInfo = n;
		if (userInfo!=nil)
			[userInfo retain];
	}
	OSSpinLockUnlock(&atomicLock);
}
- (id) userInfo	{
	id		returnMe = nil;
	OSSpinLockLock(&atomicLock);
	returnMe = userInfo;
	OSSpinLockUnlock(&atomicLock);
	return returnMe;
}
- (void) setDecoded:(BOOL)n	{
	OSSpinLockLock(&atomicLock);
	decoded = n;
	OSSpinLockUnlock(&atomicLock);
}
- (BOOL) decoded	{
	BOOL		returnMe = NO;
	OSSpinLockLock(&atomicLock);
	returnMe = decoded;
	OSSpinLockUnlock(&atomicLock);
	return returnMe;
}


@end
