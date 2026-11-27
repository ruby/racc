# Racc Grammar File Reference

This document provides a complete reference for Racc grammar file syntax.

## Version Compatibility Notes

Changes from previous versions:

- v1.2.5: When concatenating user code, embedded code is now concatenated before external files
- v1.1.5: Meaning of reserved word `token` changed
- v0.14: Semicolons at the end of rules are now optional; `token`, `prechigh` are no longer reserved words
- v0.12: `prepare` renamed to `header`, `driver` renamed to `footer` (old names work until 2.0)
- v0.10: Removed `end` corresponding to `class`
- v0.9: Changed from period-based syntax to brace-based syntax `{ }`

## File Structure

A Racc grammar file consists of two top-level sections:

1. Class Block: Grammar and parser class definition
2. User Code Block: Custom Ruby code to embed in output

The user code block MUST come after the class block.

```
┌─────────────────────────────────┐
│ Class Block                     │
│  - class definition             │
│  - operator precedence          │
│  - token declarations           │
│  - options                      │
│  - grammar rules                │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│ User Code Block                 │
│  - header                       │
│  - inner                        │
│  - footer                       │
└─────────────────────────────────┘
```

## Comments

Two comment styles are supported:

```ruby
# Ruby-style comment (to end of line)

/* C-style comment
   can span multiple lines */
```

Comments can be placed almost anywhere in the file, with a few exceptions (e.g., inside strings).

## Class Block

### Basic Structure

```ruby
class ClassName [< SuperClass]
  [precedence table]
  [token declarations]
  [expect]
  [options]
  [semantic value conversion]
  [start rule]
rule
  grammar rules
end
```

### Class Name

The class name becomes the name of the generated parser class:

```ruby
class MyParser
```

For namespaced classes, use `::`:

```ruby
class MyModule::MyParser
```

This generates:

```ruby
module MyModule
  class MyParser < Racc::Parser
    # ...
  end
end
```

### Superclass Specification

You can optionally specify a superclass:

```ruby
class MyParser < CustomParserBase
```

Warning: Specifying a superclass can significantly affect parser behavior. Only use this if you have a specific need. This feature is reserved for future extensions.

## Grammar Rules

### Basic Syntax

Grammar rules define the structure your parser will recognize:

```ruby
rule
  target: symbol symbol symbol action
        | symbol symbol action
        | symbol action

  another: SYMBOL
         | SYMBOL SYMBOL
end
```

Components:
- Left-hand side (target): Non-terminal symbol being defined
- Colon (`:`): Separates left-hand side from right-hand side
- Right-hand side: Sequence of symbols (terminals and non-terminals)
- Pipe (`|`): Alternative productions (OR)
- Action: Ruby code block in `{ }` braces

### Example

```ruby
rule
  goal: definition rules source { result = val }

  definition: /* none */         { result = [] }
            | definition startdesig  { result[0] = val[1] }
            | definition precrule    { result[1] = val[1] }

  startdesig: START TOKEN
end
```

### Empty Productions

Empty (epsilon) productions allow optional elements:

```ruby
optional_then: THEN
             |         # empty production - THEN is optional
```

## Actions

Actions are Ruby code blocks executed when a rule is reduced.

### Syntax

```ruby
expression: term '+' term { result = val[0] + val[2] }
```

### Special Variables

Inside actions, you have access to these special variables:

#### `result` (equivalent to yacc's `$$`)

The value of the left-hand side. Default value is `val[0]`.

```ruby
expression: NUMBER { result = val[0] * 2 }
```

#### `val` (equivalent to yacc's `$1, $2, $3, ...`)

An array containing the values of right-hand side symbols (zero-indexed):

```ruby
expression: term '+' term { result = val[0] + val[2] }
#           val[0] val[1] val[2]
```

#### `_values` (equivalent to yacc's `..., $-2, $-1, $0`)

The value stack used internally by Racc. DO NOT MODIFY unless you fully understand the parser internals.

### Return Values

The value of the left-hand side can be set in two ways:

Default behavior (with `result` variable):

```ruby
expression: term '+' term
  {
    result = val[0] + val[2]
  }
```

With `no_result_var` option:

```ruby
options no_result_var

rule
  expression: term '+' term { val[0] + val[2] }  # last expression is the value
```

### Omitting Actions

Actions can be omitted. The default action is `{ result = val[0] }`:

```ruby
expression: term      # equivalent to: term { result = val[0] }
```

### Embedded Actions

Actions can be embedded within the right-hand side of a rule:

```ruby
target: A B { puts 'seen A B' } C D { result = val[3] }
```

Embedded actions execute at that point in the parse and return a value accessible via `val`:

```ruby
target: A { result = 1 } B { p val[1] }  # prints 1 (not B's value!)
```

Semantically, embedded actions are equivalent to empty rule non-terminals:

```ruby
# These are equivalent:
target: A { result = 1 } B
# Same as:
target: A nonterm B
nonterm: /* empty */ { result = 1 }
```

### Action Restrictions

Some Ruby syntax is not supported in actions:

- Here documents (`<<EOF`)
- `=begin ... =end` comments
- Regular expressions starting with whitespace
- `%` literals (in rare cases; usually fine with proper spacing)

## Operator Precedence

Operator precedence resolves shift/reduce conflicts.

### Syntax

```ruby
prechigh
  nonassoc PLUSPLUS
  left     '*' '/'
  left     '+' '-'
  right    '='
preclow
```

Or in reverse:

```ruby
preclow
  right    '='
  left     '+' '-'
  left     '*' '/'
  nonassoc PLUSPLUS
prechigh
```

### Associativity

- `left`: Left-associative (e.g., `a - b - c` = `(a - b) - c`)
- `right`: Right-associative (e.g., `a = b = c` = `a = (b = c)`)
- `nonassoc`: Non-associative (e.g., `a < b < c` is an error)

### Precedence Override

Override a rule's precedence with `= SYMBOL`:

```ruby
prechigh
  nonassoc UMINUS
  left '*' '/'
  left '+' '-'
preclow

rule
  exp: exp '*' exp
     | exp '-' exp
     | '-' exp  = UMINUS    # use UMINUS precedence instead of '-'
```

This is equivalent to yacc's `%prec`.

### How It Works

When a shift/reduce conflict occurs:

1. Racc finds the precedence of the rule (the precedence of the rightmost terminal)
2. If no precedence is set, a conflict warning is issued
3. If precedence is set, Racc compares it with the lookahead token's precedence
4. The operation with higher precedence wins
5. If precedence is equal, associativity determines the action

## Token Declarations

Declaring tokens helps catch typos and undefined tokens.

### Syntax

```ruby
token TOKEN_ONE TOKEN_TWO TOKEN_THREE
      TOKEN_FOUR TOKEN_FIVE
```

Token declarations can span multiple lines.

### Warnings

Racc will warn about:
- Declared tokens that are never used
- Tokens used but not declared

Note: This is optional and generates warnings only (not errors).

## Options

Configure parser generation with the `options` directive:

```ruby
options omit_action_call result_var
```

### Available Options

#### `omit_action_call`

Omit empty action calls for better performance.

#### `no_omit_action_call`

Always generate action calls (even for empty actions).

#### `result_var`

Use the `result` local variable for left-hand side values.

#### `no_result_var`

Don't use `result` variable; last expression in action is the value.

### Negation

Prefix with `no_` to invert the meaning:

```ruby
options no_result_var    # Don't use result variable
```

## expect Directive

Declare the expected number of shift/reduce conflicts:

```ruby
class MyParser
  expect 3
rule
  # ...
end
```

If the actual number of shift/reduce conflicts differs from 3, a warning is issued. This helps catch unintended conflicts.

Notes:
- Only suppresses warnings if the count matches exactly
- Does not suppress reduce/reduce conflict warnings
- Similar to Bison's `%expect` directive

## Converting Token Symbols

By default, token symbols are represented as:

- Unquoted symbols (TOKEN, IDENT, etc.) → Ruby symbols (`:TOKEN`, `:IDENT`)
- Quoted strings (`':'`, `'.'`, etc.) → Same string (`':'`, `'.'`)

### The `convert` Block

Override default token representation:

```ruby
convert
  PLUS 'PlusClass'       # PLUS token is represented by PlusClass
  MIN  'MinusClass'      # MIN token is represented by MinusClass
end
```

### Using Strings as Tokens

Special care is required for string tokens:

```ruby
convert
  PLUS '"plus"'              # Results in "plus"
  MIN  "\"minus#{val}\""     # Results in \"minus#{val}\"
end
```

### Restrictions

- Cannot use `false` or `nil` as token symbols (causes parse errors)
- All other Ruby values are acceptable

## Start Rule

Specify which rule is the start rule:

```ruby
start real_target
```

If omitted, the first rule in the grammar is used as the start rule.

Note: `start` must appear at the beginning of a line.

## User Code Blocks

Embed custom Ruby code in the generated parser.

### Syntax

User code blocks begin with four or more hyphens (`----`) followed by a block name:

```ruby
---- header
  Ruby code here

---- inner
  Ruby code here

---- footer
  Ruby code here
```

### The Three Blocks

#### `header`

Code placed before the class definition:

```ruby
---- header
  require 'strscan'
  require_relative 'my_lexer'

  SOME_CONSTANT = 42
```

Generates:

```ruby
require 'strscan'
require_relative 'my_lexer'

SOME_CONSTANT = 42

class MyParser < Racc::Parser
  # ...
end
```

#### `inner`

Code placed inside the class definition:

```ruby
---- inner
  def parse(input)
    @tokens = tokenize(input)
    do_parse
  end

  def next_token
    @tokens.shift
  end

  private

  def tokenize(input)
    # ...
  end
```

Generates:

```ruby
class MyParser < Racc::Parser
  # Racc-generated code ...

  def parse(input)
    @tokens = tokenize(input)
    do_parse
  end

  # ...
end
```

#### `footer`

Code placed after the class definition:

```ruby
---- footer
  class Token
    attr_accessor :type, :value
  end

  if __FILE__ == $0
    # Test code
  end
```

Generates:

```ruby
class MyParser < Racc::Parser
  # ...
end

class Token
  attr_accessor :type, :value
end

if __FILE__ == $0
  # Test code
end
```

### Multiple Blocks

You can have multiple blocks of the same type:

```ruby
---- header
  require 'foo'

---- inner
  def method1
  end

---- header      # Another header block
  require 'bar'

---- inner       # Another inner block
  def method2
  end
```

All blocks of the same type are concatenated in the order they appear.

### External Files

You can include code from external files:

```ruby
---- header
  require_relative 'my_header.rb'

---- inner
---- inner my_methods.rb
```

## Reserved Names

Avoid these reserved prefixes in your code:

- Constants: `Racc_` prefix
- Methods: `racc_` and `_racc_` prefixes

Using these may cause the parser to malfunction.

## Complete Example

Here's a complete grammar file demonstrating all major features:

```ruby
# Grammar for a simple calculator

class Calculator
  # Operator precedence (highest to lowest)
  prechigh
    nonassoc UMINUS
    left '*' '/'
    left '+' '-'
  preclow

  # Token declarations
  token NUMBER LPAREN RPAREN

  # Expected conflicts
  expect 0

  # Options
  options no_result_var

rule
  # Start rule
  target: expressions

  expressions: expression
             | expressions ';' expression { [val[0], val[2]].flatten }

  expression: expression '+' expression { val[0] + val[2] }
            | expression '-' expression { val[0] - val[2] }
            | expression '*' expression { val[0] * val[2] }
            | expression '/' expression { val[0] / val[2] }
            | LPAREN expression RPAREN    { val[1] }
            | '-' expression =UMINUS      { -val[1] }
            | NUMBER                      { val[0] }
end

---- header
  require 'strscan'

---- inner
  def parse(str)
    @ss = StringScanner.new(str)
    @tokens = []

    until @ss.eos?
      case
      when @ss.scan(/\s+/)
        # ignore
      when @ss.scan(/\d+/)
        @tokens << [:NUMBER, @ss.matched.to_i]
      when @ss.scan(/[+\-*\/();]/)
        @tokens << [@ss.matched, @ss.matched]
      else
        raise "Unknown token: #{@ss.getch}"
      end
    end

    @tokens << [false, '$']
    do_parse
  end

  def next_token
    @tokens.shift
  end

  def on_error(token_id, value, value_stack)
    raise ParseError, "Parse error on token #{token_to_str(token_id)} (#{value})"
  end

---- footer
  if __FILE__ == $0
    calc = Calculator.new
    puts calc.parse("1 + 2 * 3")  # => 7
    puts calc.parse("(1 + 2) * 3")  # => 9
  end
```
