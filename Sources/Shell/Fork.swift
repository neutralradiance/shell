#if os(Linux)
 import Glibc
 private let sfork = Glibc.fork
#else
 import Darwin
 @_silgen_name("fork") private func sfork() -> Int32
#endif

/// Creates a daemon in a specified working directory and kick off a given
/// routine.
///
/// - Note: [reference](shorturl.at/zKRXY)
public func fork(
 with dir: String, foreground: Bool = false, perform: @escaping () throws -> Void
) rethrows {
 // fork off the parent process
 var ret = sfork()
 if ret < 0 { fatalError("sfork returned error: \(ret)") }
 else if ret > 0 { exit(EXIT_SUCCESS) }

 if !foreground {
  // change file mode mask (umask)
  umask(0)
  // create a unique Session ID (SID)
  ret = setsid()
  if ret < 0 { exit(EXIT_FAILURE) }

  // change the current working directory to a safe place
  ret = chdir(dir)
  if ret < 0 { exit(EXIT_FAILURE) }

  // close standard file descriptors, instead we redirect everything to "null"
  let nfd = open("/dev/null", O_RDWR)
  if nfd < 0 { exit(EXIT_FAILURE) }

  close(0)

  ret = dup2(nfd, 1)
  if ret < 0 { exit(EXIT_FAILURE) }

  dup2(nfd, 2)
  if ret < 0 { exit(EXIT_FAILURE) }

  close(nfd)
 }

 // start routine
 try perform()
}

// inspired by
// https://github.com/ruby/ruby/blob/trunk/process.c
// https://github.com/kylef/Curassow/blob/master/Sources/Curassow/Arbiter.swift#L54
public func fork() {
 let devnull = open("/dev/null", O_RDWR)
 if devnull == -1 { fatalError("can't open /dev/null") }

 let pid = sfork()
 if pid < 0 { fatalError("can't fork") }
 else if pid != 0 { exit(0) }

 if setsid() < 0 { fatalError("can't create session") }

 for descriptor in Int32(0) ..< Int32(3) { dup2(devnull, descriptor) }
}

#if os(macOS) || os(Linux)
 @inline(__always) public func forkProcess(
  _ command: String, with args: some Sequence<String> = []
 ) throws {
  try process(command, with: args)
  fork()
 }

 @inline(__always)
 public func forkProcess(_ command: Bin, _ args: some Sequence<String>) throws {
  try forkProcess(command.rawValue, with: args)
 }
#endif
