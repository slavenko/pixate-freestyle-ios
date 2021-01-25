/*
 * Copyright 2012-present Pixate, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//
//  NSObject+Swizzle.m
//  PXStyleKit
//
//  Created by Pixate on 1/7/12.
//  Copyright (c) 2012 Pixate, Inc. All rights reserved.
//

#import "NSObject+PXSubclass.h"
#import "NSObject+PXClass.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import "objc.h"
#include "TargetConditionals.h"

static BOOL respondsToSelectorIMP(id self, SEL _cmd, SEL selector);

void PXForceLoadNSObjectPXSubclass() {}

@implementation NSObject (PXSubclass)

#if __IPHONE_OS_VERSION_MAX_ALLOWED <= __IPHONE_5_1
#define IMPL_BLOCK_CAST	(__bridge void *)
#else
#define IMPL_BLOCK_CAST
#endif

// object is the instance of a UIView that we need to 'subclass' (e.g. UIButton)
// 'self' here is Pixate class (e.g. PXUIButton)
+ (void)subclassInstance:(id)object
{
    // Safety check for nil
    if (object == nil)
    {
        return;
    }
    
    // Grab the object's class (??? why 'superclass')
    Class superClass = object_getClass(object);

    // Return if we have already dynamically subclassed this class (by checking for our pxClass method)
    if (class_getInstanceMethod(superClass, @selector(pxClass)) != NULL) {
        return;
    }

    // 'self' is a Pixate class, so we're checking that the object passed in is not a Pixate class
	if (![object isKindOfClass:[self superclass]]) {
		NSAssert(NO, @"Class %@ doesn't fit for subclassing.", [superClass description]);
		return;
	}

    // creating the new classname by prefixing with the Pixate class name
	const char *className = [[NSString stringWithFormat:@"%@_%@", [self description], [superClass description]] UTF8String];

    // Check to see if the new Pixate class as already been created
	Class newClass = objc_getClass(className);

    // If the class hasn't been created before, let's do so now
    if (newClass == nil)
    {
        // The number of bytes to allocate for indexed ivars at the end of the class and metaclass objects
        size_t extraSize = 64;

        // Create the new class
        newClass = objc_allocateClassPair(superClass, className, extraSize);

        // Copy all of the methods from the Pixate class over to the newly created 'newClass'
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(self, &mcount);
		for (unsigned int index = 0; index < mcount; ++index)
        {
            Method method = methods[index];
            class_addMethod(newClass, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method));
        }
        free(methods);

        // Add a 'class' method to new class to override the NSObject implementation
		Method classMethod = class_getInstanceMethod(superClass, @selector(class));
		IMP classMethodIMP = imp_implementationWithBlock(IMPL_BLOCK_CAST(^(id _self, SEL _sel){
            return class_getSuperclass(object_getClass(_self));
        }));
		class_addMethod(newClass, method_getName(classMethod), classMethodIMP, method_getTypeEncoding(classMethod));

        // pxClass
        IMP pxClassMethodIMP = imp_implementationWithBlock(IMPL_BLOCK_CAST(^(id _self, SEL _sel){
            return superClass;
        }));
        class_addMethod(newClass, @selector(pxClass), pxClassMethodIMP, method_getTypeEncoding(classMethod));

		// respondsToSelector:
        Method respondsToSelectorMethod = class_getInstanceMethod(superClass, @selector(respondsToSelector:));
        class_addMethod(newClass, method_getName(respondsToSelectorMethod), (IMP)respondsToSelectorIMP, method_getTypeEncoding(respondsToSelectorMethod));

        // Registers a class that was allocated using objc_allocateClassPair
        objc_registerClassPair(newClass);

        // Copy any extra indexed ivars (see objc_allocateClassPair)
        copyIndexedIvars(superClass, newClass, extraSize);

        // Check to make sure that the two classes (new and original) are the same size
        if (class_getInstanceSize(superClass) != class_getInstanceSize(newClass))
        {
            NSAssert(NO, @"Class %@ doesn't fit for subclassing.", [superClass description]);
            return;
        }
    }
    else if (object_getClass(object) == newClass)
    {
        return;
    }

    object_setClass(object, newClass);
}

static BOOL classRespondsToSelectorRAW(Class class, SEL selector)
{
	if (@available(iOS 8.0, *)) {
		NSString *className = NSStringFromClass([class class]);
		if(
		   [className containsString:@"pxuiview_uiwebbrowserview"] ||
		   [className containsString:@"pxuiview_uikeyboardautomatic"] ||
		   [className containsString:@"pxuitoolbar_uitoolbar"] ||
		   [className containsString:@"nfi_pxuibutton__uimodernbarbutton"] ||
		   [className containsString:@"pxuiview__uibuttonbarbutton"] ||
		   [className containsString:@"pxuiview__uibuttonbarstackview"]
		   ) {
			return NO;
		}
	}

    if (class != Nil)
    {
        return class_getInstanceMethod(class, selector) != NULL;
    }
    return NO;
}

static BOOL respondsToSelectorRAW(id self, SEL selector)
{
    if (self)
    {
        return classRespondsToSelectorRAW(object_getClass(self), selector);
    }
    return NO;
}

#if (TARGET_IPHONE_SIMULATOR && TARGET_CPU_X86_64)

static BOOL classHierarchyRespondsToSelector(Class class, SEL selector)
{
    if (class)
    {
        if (classRespondsToSelectorRAW(class, selector))
        {
            return YES;
        }
        else
        {
            return classHierarchyRespondsToSelector(class_getSuperclass(class), selector);
        }
    }

    return NO;
}

#endif

static BOOL respondsToSelectorIMP(id self, SEL _cmd, SEL selector)
{
    // iOS 9 x64 simulators crashes with UITextFiled styling
    // For more detail see https://github.com/Pixate/pixate-freestyle-ios/issues/186
#if (TARGET_IPHONE_SIMULATOR && TARGET_CPU_X86_64)
    // Use RAW implementation
    BOOL pxClassRespondsToSelector = classHierarchyRespondsToSelector([self pxClass], selector);
#else
    BOOL pxClassRespondsToSelector = ((BOOL)callSuper1v(self, [self pxClass], _cmd, selector));
#endif

    return pxClassRespondsToSelector || respondsToSelectorRAW(self, selector);
}

@end
