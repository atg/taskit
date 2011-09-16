# Taskit — Simpler NSTask

**Taskit** is a reimplementation of `NSTask` with a simplified and block-ready interface.

```objective-c
    Taskit *task = [Taskit task];
    task.launchPath = @"/bin/echo";
    [task.arguments addObject:@"Hello World"];
    task.receivedOutputString = ^void(NSString *output) {
        NSLog(@"%@", output);
    };
    
    [task launch];
```

## License

Taskit is licensed under the [WTFPL](http://sam.zoy.org/wtfpl/).
