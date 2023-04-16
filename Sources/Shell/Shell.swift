@_exported import Foundation
@_exported import Core
@_exported import Extensions
@_exported import Files
import Regex

var args = CommandLine.arguments
public let command = args.removeFirst()
public var arguments = [String](args[1 ..< args.endIndex])
/// - Note: This should be replaced if the expected parser has the help command
public var help: String?

public enum Bin: String {
 case cd,
      cp,
      cat,
      env,
      bash,
      zsh,
      sh,
      date,
      sync,
      exec,
      node,
      trap,
      echo,
      grep,
      git,
      head,
      tail,
      kill,
      brew,
      sudo,
      chmod,
      make,
      exit,
      history,
      clear,
      install,
      parallell,
      ls,
      ln,
      mkdir,
      ditto,
      rmdir,
      mv,
      man,
      sleep,
      open,
      jobs,
      rm,
      pwd,
      pkill,
      which,
      swift,
      locate,
      less,
      compgen,
      touch,
      timer,
      xcodebuild,
      xcodeselect = "xcode-select",
      xcrun

 public func callAsFunction(_ args: String...) -> String {
  rawValue.appending(arguments: args)
 }
}

#if os(macOS) || os(Linux)
 @discardableResult
 public func execute(
  command: String,
  _ args: some Sequence<String>,
  inputHandle: FileHandle? = nil,
  outputHandle: FileHandle? = nil,
  errorHandle: FileHandle? = nil,
  process task: Process = Process(), pipe: Pipe = Pipe(),
  silent: Bool = false
 ) throws -> String {
  task.launchPath = task.shell
  task.arguments = ["-c", command.appending(arguments: args)]
  // https://www.tekramer.com/observing-real-time-ouput-from-shell-commands-in-a-swift-script
  /*  var output = ""
    let pipe = Pipe()
    task.standardOutput = pipe
    let outputHandler = pipe.fileHandleForReading
    outputHandler.waitForDataInBackgroundAndNotify()

    var dataObserver: NSObjectProtocol!
    let notificationCenter = NotificationCenter.default
    let dataNotificationName = NSNotification.Name.NSFileHandleDataAvailable
    dataObserver = notificationCenter.addObserver(
     forName: dataNotificationName, object: outputHandler, queue: nil
    ) { [unowned dataObserver] _ in
     let data = outputHandler.availableData
     guard data.count > 0 else {
      if let dataObserver { notificationCenter.removeObserver(dataObserver) }
      return
     }
     if let line = String(data: data, encoding: .utf8) {
      if !silent {
       print(line)
      }
      output = output + line
     }
     outputHandler.waitForDataInBackgroundAndNotify()
    }

    task.launch()
   task.waitUntilExit()*/
  // return output//(output, task.terminationStatus)

  // Because FileHandle's readabilityHandler might be called from a
  // different queue from the calling queue, avoid a data race by
  // protecting reads and writes to outputData and errorData on
  // a single dispatch queue.
  let inputQueue = DispatchQueue(label: "bash-input-queue")
  let outputQueue = DispatchQueue(label: "bash-output-queue")

  var inputData = Data()
  var outputData = Data()
  var errorData = Data()

  let inputPipe = Pipe()
  task.standardInput = inputPipe

  let outputPipe = pipe
  task.standardOutput = outputPipe

  let errorPipe = Pipe()
  task.standardError = errorPipe

  #if !os(Linux)
   inputPipe.fileHandleForReading.readabilityHandler = { handler in
    let data = handler.availableData
    inputQueue.async {
     inputData.append(data)
     inputHandle?.write(data)
    }
   }

   if !silent {
    outputPipe.fileHandleForReading.readabilityHandler = { handler in
     let data = handler.availableData
     outputQueue.async {
      outputData.append(data)
      outputHandle?.write(data)
     }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handler in
     let data = handler.availableData
     outputQueue.async {
      errorData.append(data)
      errorHandle?.write(data)
     }
    }
   }
  #endif

  task.launch()

  #if os(Linux)
   inputQueue.sync {
    inputData = inputPipe.fileHandleForReading.readDataToEndOfFile()
   }
   if !silent {
    outputQueue.sync {
     outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
     errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    }
   }
  #endif

  task.waitUntilExit()

  if let handle = inputHandle, !handle.isStandard {
   handle.closeFile()
  }

  if !silent {
   if let handle = outputHandle, !handle.isStandard {
    handle.closeFile()
   }

   if let handle = errorHandle, !handle.isStandard {
    handle.closeFile()
   }

   #if !os(Linux)
    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
   #endif
  }
  // Block until all writes have occurred to outputData and errorData,
  // and then read the data back out.
  return try outputQueue.sync {
   if task.terminationStatus != 0 {
    throw Error(
     terminationStatus: task.terminationStatus,
     errorData: errorData,
     inputData: inputData,
     outputData: outputData
    )
   }
   return outputData.shellOutput()
  }
 }

 @discardableResult
 public func execute(
  _ command: Bin,
  _ arguments: some Sequence<String>,
  inputHandle: FileHandle? = nil,
  outputHandle: FileHandle? = nil,
  errorHandle: FileHandle? = nil,
  process task: Process = Process(), pipe: Pipe = Pipe(),
  silent: Bool = false
 ) throws -> String {
  try execute(
   command: command.rawValue, arguments,
   inputHandle: inputHandle,
   outputHandle: outputHandle,
   errorHandle: errorHandle, process: task, pipe: pipe, silent: silent
  )
 }

 @discardableResult
 public func execute(
  _ command: String,
  with arguments: some Sequence<String> = [],
  inputHandle: FileHandle? = nil,
  outputHandle: FileHandle? = nil,
  errorHandle: FileHandle? = nil,
  process task: Process = Process(), pipe: Pipe = Pipe(),
  silent: Bool = false
 ) throws -> String {
  try execute(
   command: command, arguments,
   inputHandle: inputHandle,
   outputHandle: outputHandle,
   errorHandle: errorHandle, process: task, pipe: pipe, silent: silent
  )
 }

// https://github.com/JohnSundell/ShellOut/blob/master/Sources/ShellOut.swift

 public struct Error: Swift.Error {
  /// The termination status of the command that was run
  public let terminationStatus: Int32
  /// The error message as a UTF8 string, as returned through `STDERR`
  public var message: String { errorData.shellOutput() }
  /// The raw error buffer data, as returned through `STDERR`
  public let errorData: Data
  /// The raw input buffer data, as retuned through `STDIN`
  public let inputData: Data
  /// The raw output buffer data, as retuned through `STDOUT`
  public let outputData: Data
  /// The output of the command as a UTF8 string, as returned through `STDIN`
  public var input: String { inputData.shellOutput() }
  /// The output of the command as a UTF8 string, as returned through `STDOUT`
  public var output: String { outputData.shellOutput() }
 }

 extension Error: CustomStringConvertible {
  public var description: String {
   """
   \(input) terminated with status \(terminationStatus)
   \(message)
   \(output)
   """
  }
 }

 extension Error: LocalizedError {
  public var errorDescription: String? { description }
 }

 private extension FileHandle {
  var isStandard: Bool {
   self === FileHandle.standardOutput ||
    self === FileHandle.standardError ||
    self === FileHandle.standardInput
  }
 }

 private extension Data {
  func shellOutput() -> String {
   guard let output = String(data: self, encoding: .utf8) else {
    return ""
   }

   guard !output.hasSuffix("\n") else {
    let endIndex = output.index(before: output.endIndex)
    return String(output[..<endIndex])
   }

   return output
  }
 }

 public extension Process {
  @inline(__always)
  var shell: String { environment?["SHELL"] ?? "/bin/sh" }
  @inline(__always)
  convenience init(_ command: String, args: some Sequence<String> = []) {
   self.init()
   self.launchPath = shell
   self.arguments = ["-c", command.appending(arguments: args)]
  }
 }

 @inline(__always) public func process(
  command: String,
  _ args: some Sequence<String> = []
 ) throws {
  let process = Process(command, args: args)
  try process.run()
  process.waitUntilExit()
 }

 @inline(__always)
 public func process(
  _ command: String, with args: some Sequence<String> = []
 ) throws {
  try process(command: command, args)
 }

 @inline(__always)
 public func process(_ command: Bin, _ args: some Sequence<String>) throws {
  try process(command: command.rawValue, args)
 }
#endif

public extension String {
 var escapingSpaces: String {
  replacingOccurrences(of: " ", with: #"\ "#)
 }

 var escapingParentheses: String {
  replacingOccurrences(of: "(", with: #"\("#)
   .replacingOccurrences(of: ")", with: #"\)"#)
 }

 var escapingAmpersand: String {
  replacingOccurrences(of: #"&"#, with: #"\&"#)
 }

 var escapingAll: String {
  escapingSpaces.escapingParentheses.escapingAmpersand
 }

 var fixingDoubleSlashes: String {
  replacingOccurrences(of: #"\\"#, with: "\\")
 }

 var doubleQuoted: String { "\"\"\(self)\"\"" }
 var quoted: String { "\"\(self)\"" }

 @inline(__always)
 func contains(regex pattern: KeyPath<Regex, String>) -> Bool {
  range(
   of: Self.regex[keyPath: pattern], options: [.regularExpression]
  ) != nil
 }

 @inline(__always)
 // https://leetcode.com/problems/wildcard-matching/solutions/272598/Swift-solution/
 func contains(wildcard: String) -> Bool {
//  var i = startIndex
//  var j = wildcard.startIndex
//  var match = startIndex
//  var star = wildcard.endIndex
//
//  while i != endIndex {
//   if j < wildcard.endIndex, self[i] == wildcard[j] || wildcard[j] == "?" {
//    i = index(after: i)
//    j = wildcard.index(after: j)
//   } else if j != wildcard.endIndex, wildcard[j] == "*" {
//    star = j
//    match = i
//    j = index(after: j)
//   } else if star != wildcard.endIndex {
//    j = index(after: star)
//    match = index(after: match)
//    i = match
//   } else {
//    return false
//   }
//  }
//
//  while j < wildcard.endIndex, wildcard[j] == "*" {
//   j = wildcard.index(after: j)
//  }
//  return j == wildcard.endIndex

//   let s = self
  let p = wildcard
  let m = count
  let n = p.count
  var dp = [[Bool]](repeating: [Bool](repeating: false, count: n + 1), count: m + 1)
  dp[0][0] = true
  for i in 0 ... m {
   for j in 1 ... n {
    if p[p.index(p.startIndex, offsetBy: j - 1)] == "*" {
     dp[i][j] = dp[i][j - 1] || (i > 0 && dp[i - 1][j])
    } else {
     dp[i][j] = i > 0 && dp[i - 1][j - 1] &&
      (p[p.index(p.startIndex, offsetBy: j - 1)] == "?" ||
       p[p.index(p.startIndex, offsetBy: j - 1)] ==
       self[index(startIndex, offsetBy: i - 1)])
    }
   }
  }
  return dp[m][n]
 }
}

private extension String {
 func appending(argument: String) -> String {
  "\(self) \"\(argument)\""
 }

 func appending(arguments: some Sequence<String>) -> String {
  appending(argument: arguments.joined(separator: "\" \""))
 }

 mutating func append(argument: String) {
  self = appending(argument: argument)
 }

 mutating func append(arguments: some Sequence<String>) {
  self = appending(arguments: arguments)
 }
}

@_exported import Chalk

public func echo(
 _ items: Any..., color: Color, style: Style = [],
 separator: String = " ", terminator: String = "\n"
) {
 print(
  items.map { "\($0, color: color, style: style)" }
   .joined(separator: separator), terminator: terminator
 )
}

public func echo(
 _ items: Any..., style: Style = [],
 separator: String = " ", terminator: String = "\n"
) {
 print(
  items.map { "\($0, style: style)" }
   .joined(separator: separator), terminator: terminator
 )
}

/// Exits the process with either `help` variable, error, or optional reason
public func exit(_ status: Int32 = 0, _ reason: Any? = nil) -> Never {
 if status == 0, let help { echo(help, style: .bold) } else if let reason {
  echo(
   "\(status == .zero ? "" : status > 1 ? "fault: " : "error: ")\(reason)",
   color: status == .zero ? .green : status > 1 ? .red : .yellow, style: .bold
  )
  if let help { print(help) }
 }
 return exit(status)
}

public enum Verbosity: Int {
 public init?(rawValue: Int) {
  switch rawValue {
   case 0: self = .none
   case 1: self = .some
   case 2: self = .optional
   case 3: self = .required
   default: return nil
  }
 }
 case none, some, optional, required
}

extension Verbosity: Comparable {
 public static func < (lhs: Self, rhs: Self) -> Bool {
  lhs.rawValue < rhs.rawValue
 }
}

extension Verbosity: ExpressibleByIntegerLiteral {
 public init(integerLiteral value: Int) { self.init(rawValue: value)! }
}
