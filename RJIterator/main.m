//
//  main.m
//  RJIterator
//
//  Created by renjinkui on 2018/4/13.
//  Copyright © 2018年 renjinkui. All rights reserved.
//
#if 1
#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <mach-o/dyld.h>

int main(int argc, char * argv[]) {
//    uint32_t cnt = _dyld_image_count();
//    for (int i =0 ;i < cnt; ++i) {
//        char *name = _dyld_get_image_name(i);
//        struct mach_header *header = _dyld_get_image_header(i);
//        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
//        NSLog(@"name: %s, header:%p, slide:%u", name, header, slide);
//    }
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
#else

#include <stdlib.h>

#include <pthread.h>
#include <unistd.h>

#include <stdio.h>

/* The key used to associate a log file pointer with each thread. */

static pthread_key_t thread_log_key;

/* Write MESSAGE to the log file for the current thread. */

void write_to_thread_log (const char* message)

{
    char * thread_log = (char*) pthread_getspecific (thread_log_key);
    
    printf ("=== %s\n", thread_log);
}

/* Close the log file pointer THREAD_LOG. */

void close_thread_log (void* thread_log)

{
    printf("close_thread_log: %s\n", (char *)thread_log);
    free(thread_log);
    //fclose ((FILE*) thread_log);
}

void* thread_function (void* args)

{
    char *thread_log_filename = calloc(1, 20);
//
//    FILE* thread_log;
//
//    /* Generate the filename for this thread’s log file. */
//
    sleep(arc4random() % 4 + 1);
    
    sprintf (thread_log_filename, "thread%d.log", (int) pthread_self ());
//
//    /* Open the log file. */
//
//    thread_log = fopen (thread_log_filename, "w");
    
    /* Store the file pointer in thread-specific data under thread_log_key. */
    
    pthread_setspecific (thread_log_key, thread_log_filename);
    
    write_to_thread_log ("Thread starting.");
    
    /* Do work here... */
    
    return NULL;
}

int main ()

{
    
    int i;
    
    pthread_t threads[5];
    
    /* Create a key to associate thread log file pointers in
     
     thread-specific data. Use close_thread_log to clean up the file
     
     pointers. */
    
    pthread_key_create (&thread_log_key, close_thread_log);
    
    /* Create threads to do the work. */
    
    for (i = 0; i < 5; ++i)
        
        pthread_create (&(threads[i]), NULL, thread_function, NULL);
    
    /* Wait for all threads to finish. */
    
    for (i = 0; i < 5; ++i)
        
        pthread_join (threads[i], NULL);
    
    return 0;
    
}
#endif
