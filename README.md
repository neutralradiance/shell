# Shell ⌘

Command line utilities for scripting with swift and `swift-sh`

__Note:__ Tested on macOS, building on iOS

### Installing [`swift-sh`](https://github.com/mxcl/swift-sh) ⇥
```
$ brew install swift-sh
```

## Using Shell ⇢
```swift
#!/usr/bin/swift sh
import Shell // neutralradiance/shell

let str = "Hello World!"
echo(str, color: .green, style: .bold)
```

### Example script to check if certain file or folders exist ⏎
```swift
#!/usr/bin/swift sh
import Shell // neutralradiance/shell

guard arguments.notEmpty else {
 exit(1, "expected at least one input path")
}

help =
 """
 checks whether or not a folder or file exists
 usage: exists [flags] [locations]
 
 flags:
 -d directory, all locations must be directories (doesn't seem to work)
 -f file, all locations must be files
 
 returns: true or false
 """

var requireFolder = false
var requireFile = false

arguments.removeAll(where: { argument in
 if argument.hasPrefix("-") {
  switch argument.dropFirst() {
  case "h", "help": exit()
  case "d", "directory":
   requireFolder = true
   return true
  case "f", "file":
   requireFile = true
   return true
  default: return false
  }
 } else { return false }
})

let files = FileManager.default
print(
 arguments.allSatisfy {
  var isFolder: ObjCBool = false
  guard files.fileExists(atPath: $0, isDirectory: &isFolder) else { return false }
  return
   requireFolder ? isFolder.boolValue :
   requireFile ? !isFolder.boolValue : true
 }
 .description
)
```

## Credits
- [mxcl](https://github.com/mxcl) for creating swift-sh and [chalk](https://github.com/mxcl/Chalk)
- [Files](https://github.com/JohnSundell/Files) for making it easier to handle files in scripts
