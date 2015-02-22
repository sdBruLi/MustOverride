//
//  MustOverride.m
//
//  Version 1.0
//
//  Created by Nick Lockwood on 22/02/2015.
//  Copyright (c) 2015 Nick Lockwood
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/MustOverride
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "MustOverride.h"

#import <dlfcn.h>
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

@interface MustOverride : NSObject

@end

#ifdef __LP64__
typedef uint64_t MustOverrideValue;
typedef struct section_64 MustOverrideSection;
#define GetSectByNameFromHeader getsectbynamefromheader_64
#else
typedef uint32_t MustOverrideValue;
typedef struct section MustOverrideSection;
#define GetSectByNameFromHeader getsectbynamefromheader
#endif

@implementation MustOverride

static BOOL ClassOverridesMethod(Class cls, SEL selector)
{
    unsigned int numberOfMethods;
    Method *methods = class_copyMethodList(cls, &numberOfMethods);
    for (unsigned int i = 0; i < numberOfMethods; i++)
    {
        if (method_getName(methods[i]) == selector)
        {
            free(methods);
            return YES;
        }
    }
    return NO;
}

static NSArray *SubclassesOfClass(Class baseClass)
{
    NSMutableArray *subclasses = [NSMutableArray array];
    unsigned int classCount;
    Class *classes = objc_copyClassList(&classCount);
    for (unsigned int i = 0; i < classCount; i++)
    {
        Class cls = classes[i];
        Class superclass = class_getSuperclass(cls);
        if (!superclass) continue; // No superclass - probably something weird

        if ([cls isSubclassOfClass:baseClass])
        {
            [subclasses addObject:cls];
        }
    }
    free(classes);
    return subclasses;
}

static void CheckOverrides(void)
{
    Dl_info info;
    dladdr(&CheckOverrides, &info);

    const MustOverrideValue mach_header = (MustOverrideValue)info.dli_fbase;
    const MustOverrideSection *section = GetSectByNameFromHeader((void *)mach_header, "__DATA", "MustOverride");
    if (section == NULL) return;

    for (MustOverrideValue addr = section->offset; addr < section->offset + section->size; addr += sizeof(const char **))
    {
        NSString *entry = @(*(const char **)(mach_header + addr));
        NSArray *parts = [[entry substringWithRange:NSMakeRange(2, entry.length - 3)] componentsSeparatedByString:@" "];

        BOOL isClassMethod = [entry characterAtIndex:0] == '+';
        Class cls = NSClassFromString(parts[0]);
        SEL selector = NSSelectorFromString(parts[1]);

        for (Class subclass in SubclassesOfClass(cls))
        {
            NSCAssert(ClassOverridesMethod(isClassMethod ? object_getClass(subclass) : subclass, selector),
                      @"Class '%@' does not implement required method '%@'", subclass, parts[1]);
        }
    }
}

+ (void)load
{
    CheckOverrides();
}

@end