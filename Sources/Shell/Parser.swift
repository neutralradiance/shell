protocol CommandProtocol: OptionalStringConvertible {}
protocol Command: CommandProtocol, CustomStringConvertible {
 /// an optional property that determines the level of text
 /// none, some, optional, required
 /// none is silent, some is information, optional is warning, and required is fatal
 var verbosity: Verbosity { get }
 var version: Float? { get }
 init()
 func callAsFunction(_ execute: (Self) throws -> Void) throws
}

import Foundation
extension Command {
 var verbosity: Verbosity { .none }
 var version: Float? { .none }
 func exit(_ code: Int32, help: String? = nil) {
  if code > 0 {
   print(
    "\(description == nil ? "\(name), " : "\(self)")",
    version == nil ? .empty : ", " +
     version.unsafelyUnwrapped.description, terminator: ""
   )
  }
  if let help { echo(help) }
  Foundation.exit(code)
 }

 func callAsFunction(_ execute: (Self) throws -> Void) throws {
  let command = self
  // find the properties that can be altered
  print("compiling command \(command.name)")
  print(command)
  do {
   throw FlagError<Bool>.empty("-alala")
  } catch let error as any CommandError {
   if verbosity > .none, verbosity < .required {
    echo("\(name)Error: \(error.reason)", color: .red, style: .bold)
   }
   command.exit(1)
  } catch {
   if verbosity > .none {
    echo("\(error)", color: .red, style: .bold)
   }
   command.exit(2)
  }
  do { try execute(self) }
  catch {
   throw error
  }
 }

 static func callAsFunction(_ execute: (Self) throws -> Void) throws {
  let command = Self()
  do { try command.callAsFunction(execute) }
  catch {
   throw error
  }
 }
}

extension Command {
 var name: String { "\(Self.self)" }
 var description: String { self.description ?? name }
}

protocol CommandError: Swift.Error, OptionalStringConvertible {
 associatedtype Context: CommandProtocol
 var context: Context? { get }
 var reason: String { get }
}

extension CommandError {
 var description: String { description ?? "\(reason)" }
}

protocol CommandProperty: CommandProtocol {
 associatedtype Value
 var wrappedValue: Value { get set }
}

protocol Negatable { mutating func toggle() }
extension Bool: Negatable {}
@propertyWrapper struct CommandFlag<Value: Negatable>: CommandProperty {
 var wrappedValue: Value
 var description: String?
 // TODO: this should be switched if the internal conditions of a command don't align
 var required: Bool

 init(wrappedValue: Value, _ description: String? = nil, required: Bool = false) {
  self.wrappedValue = wrappedValue
  self.description = description
  self.required = required
 }
}

extension CommandFlag where Value: Infallible {
 init(
  wrappedValue: Value = .defaultValue,
  _ description: String? = nil, required: Bool = false
 ) {
  self.required = required
  self.wrappedValue = wrappedValue
  self.description = description
 }
}

enum FlagError<Value: Negatable>: CommandError {
 typealias Context = CommandFlag<Value>
 case
  duplicate(Context, String),
  character(Context, String),
  missing(Context, String),
  empty(_ after: String)

 var context: Context? {
  switch self {
  case let .duplicate(context, _): return context
  case let .character(context, _): return context
  case let .missing(context, _): return context
  default: return nil
  }
 }

 var reason: String {
  switch self {
  case let .duplicate(_, flag): return "duplicate flag '\(flag)'"
  case let .character(_, characters): return "invalid characters \(characters)"
  case let .missing(_, flag): return "missing flag '\(flag)'"
  case let .empty(after): return "empty flag after '\(after)'"
  }
 }
}

@propertyWrapper struct CommandOption<Input: LosslessStringConvertible> {
 /// the expected flag, will read arguments up to the next flag or valid range if necessary
 /// although, arguments will be split by areas where the prefix "-" doesn't exist
 let count: Int
 // nil by default to read the input but can provide a default
 var wrappedValue: Input?

 init(wrappedValue: Input? = nil, count: Int = 1) {
  self.wrappedValue = wrappedValue
  self.count = count
 }
}

@propertyWrapper struct CommandInputs<Input: LosslessStringConvertible>: CommandProperty {
 /// processes the arguments array to create a contiguous array of values when calling
 /// a command
 var wrappedValue: [Input] = .empty
 var description: String?
 /// throws an error that's readable if conforming to ``CommandError``
 var filter: (() throws -> Void)?
 init(
  wrappedValue: [Input] = .empty,
  _ description: String? = nil,
  filter: (() throws -> Void)? = nil
 ) {
  self.wrappedValue = wrappedValue
  self.description = description
  self.filter = filter
 }
}

extension Command {
 typealias Flag<Value> = CommandFlag<Value> where Value: Negatable
 typealias Option<Input> = CommandOption<Input>
  where Input: LosslessStringConvertible
 typealias Inputs<Input> = CommandInputs<Input>
  where Input: LosslessStringConvertible
}
