# Advanced Topics

This document covers advanced Racc features and techniques for experienced users.

## Table of Contents

- [Operator Precedence](#operator-precedence)
- [Error Recovery](#error-recovery)
- [Embedded Actions](#embedded-actions)
- [Token Symbol Conversion](#token-symbol-conversion)
- [Performance Optimization](#performance-optimization)
- [Grammar Design Patterns](#grammar-design-patterns)
- [Integration with Lexers](#integration-with-lexers)
- [Runtime Options](#runtime-options)

## Operator Precedence

Operator precedence is a powerful mechanism for resolving shift/reduce conflicts in expression grammars.

### The Problem: Expression Ambiguity

Consider this grammar:

```ruby
rule
  exp: exp '+' exp
     | exp '*' exp
     | NUMBER
end
```

For input `2 + 3 * 4`, this grammar is ambiguous:
- Could parse as `(2 + 3) * 4` = 20
- Could parse as `2 + (3 * 4)` = 14

Racc reports this as a shift/reduce conflict.

### The Solution: Precedence Declarations

```ruby
class Calculator
  prechigh
    left '*' '/'
    left '+' '-'
  preclow
rule
  exp: exp '+' exp
     | exp '*' exp
     | exp '/' exp
     | exp '-' exp
     | NUMBER
end
```

This declares:
- Multiplication and division have higher precedence
- Addition and subtraction have lower precedence
- Both levels are left-associative

### Precedence Rules

#### Declaration Syntax

```ruby
prechigh
  nonassoc '++' '--'        # Highest precedence
  left     '*' '/' '%'
  left     '+' '-'
  right    '='              # Lowest precedence
preclow
```

Or reversed:

```ruby
preclow
  right    '='
  left     '+' '-'
  left     '*' '/' '%'
  nonassoc '++' '--'
prechigh
```

#### Associativity Types

Left Associative (`left`):

```ruby
a - b - c  =>  (a - b) - c
```

Most arithmetic operators are left-associative.

Right Associative (`right`):

```ruby
a = b = c  =>  a = (b = c)
```

Assignment operators are typically right-associative.

Non-Associative (`nonassoc`):

```ruby
a < b < c  =>  ERROR
```

Comparison operators are often non-associative.

### How Precedence Works

When a shift/reduce conflict occurs:

1. Racc determines the rule's precedence (from the rightmost terminal)
2. Racc compares this with the lookahead token's precedence
3. Higher precedence wins
4. If equal, associativity decides:
   - `left`: reduce
   - `right`: shift
   - `nonassoc`: error

### Rule Precedence Override

Sometimes you need to override the default precedence for a specific rule:

```ruby
prechigh
  nonassoc UMINUS      # Unary minus
  left '*' '/'
  left '+' '-'
preclow

rule
  exp: exp '+' exp
     | exp '-' exp
     | exp '*' exp
     | exp '/' exp
     | '-' exp  = UMINUS    # Use UMINUS precedence, not '-'
     | NUMBER
end
```

The `= UMINUS` syntax (equivalent to yacc's `%prec`) assigns UMINUS precedence to the unary minus rule, making it higher than multiplication.

### Complete Example

```ruby
class Calculator
  prechigh
    nonassoc UMINUS
    right    ''          # Exponentiation
    left     '*' '/' '%'
    left     '+' '-'
    nonassoc '<' '>' '<=' '>='
    nonassoc '==' '!='
    right    '='
  preclow

rule
  exp: exp '=' exp
     | exp '+' exp
     | exp '-' exp
     | exp '*' exp
     | exp '/' exp
     | exp '%' exp
     | exp '' exp
     | exp '==' exp
     | exp '!=' exp
     | exp '<' exp
     | exp '>' exp
     | exp '<=' exp
     | exp '>=' exp
     | '-' exp = UMINUS
     | '(' exp ')'
     | NUMBER
end
```

## Error Recovery

Racc supports automatic error recovery using the special `error` token, similar to yacc.

### Basic Error Recovery

```ruby
rule
  statements: statement
            | statements statement
            | statements error statement
              {
                puts "Error recovered"
                yyerrok  # Exit error recovery mode
              }
end
```

### How Error Recovery Works

1. Parser detects a syntax error
2. Calls `on_error` method
3. If `on_error` returns normally, enters error recovery mode
4. Pops states from stack until a state with an `error` transition is found
5. Discards tokens until parsing can continue
6. Resumes normal parsing after successfully reducing an `error` rule

### Error Recovery Strategies

#### Strategy 1: Statement-Level Recovery

Recover at statement boundaries:

```ruby
rule
  program: statements

  statements: statement
            | statements statement
            | statements error ';'
              {
                # Synchronize at semicolon
                yyerrok
              }

  statement: IDENT '=' exp ';'
           | IF exp THEN statements END
           | WHILE exp DO statements END
end
```

#### Strategy 2: Expression-Level Recovery

Recover within expressions:

```ruby
rule
  expression: term
            | expression '+' term
            | expression error term
              {
                puts "Recovered from expression error"
                yyerrok
              }
end
```

#### Strategy 3: Block-Level Recovery

Recover at block boundaries:

```ruby
rule
  block: '{' statements '}'
       | '{' error '}'
         {
           puts "Skipped invalid block"
           yyerrok
         }
end
```

### Error Recovery Methods

#### `yyerror` - Enter Error Recovery

Call from within an action to manually enter error recovery:

```ruby
statement: IDENT '=' expression
  {
    if reserved_word?(val[0])
      puts "Cannot assign to reserved word"
      yyerror
    end
    result = [:assign, val[0], val[2]]
  }
```

#### `yyerrok` - Exit Error Recovery

Call to exit error recovery mode and resume normal parsing:

```ruby
error_recovery: error ';'
  {
    yyerrok
  }
```

#### `on_error` - Custom Error Handling

Override for custom error messages:

```ruby
def on_error(token_id, value, value_stack)
  token_name = token_to_str(token_id)
  @errors << "Syntax error at #{token_name}: #{value}"
  # Return normally to enter error recovery mode
end
```

### Error Reporting Example

```ruby
class MyParser
  def initialize
    @errors = []
  end

  def parse(input)
    @errors.clear
    result = do_parse
    if @errors.empty?
      result
    else
      puts "Parse completed with errors:"
      @errors.each { |e| puts "  #{e}" }
      nil
    end
  end

  def on_error(token_id, value, value_stack)
    line = @lexer.line_number
    @errors << "Line #{line}: unexpected #{token_to_str(token_id)}"
  end
end
```

### Best Practices

1. Place error rules strategically at synchronization points (statement ends, block boundaries)
2. Always call `yyerrok` when you've recovered
3. Collect errors rather than aborting on first error
4. Provide helpful messages in `on_error`
5. Test error paths as thoroughly as success paths

## Embedded Actions

Embedded actions allow you to execute code at any point during a rule match, not just at the end.

### Basic Syntax

```ruby
target: A B { puts "Seen A and B" } C D { result = "complete" }
```

### Embedded Action Values

Embedded actions produce values accessible via `val`:

```ruby
target: A { result = 1 } B { p val[1] }  # Prints 1
#       ^----- val[0]    ^------ val[1]   val[2]
```

Note: `val[1]` is the embedded action's value, not B's value!

### Use Cases

#### 1. Setting Context

```ruby
function_def: TYPE IDENT { @return_type = val[0] } '(' params ')' body
  {
    result = [:function, val[1], val[3], val[5], @return_type]
  }
```

#### 2. Opening Scopes

```ruby
block: '{' { enter_scope } statements '}' { exit_scope }
```

#### 3. Mid-Rule Validation

```ruby
assignment: IDENT '=' { check_identifier(val[0]) } expression
```

#### 4. Semantic Predicates

```ruby
qualified_name: IDENT { check_imported(val[0]) } '.' IDENT
```

### Implementation Details

Embedded actions are equivalent to empty rule non-terminals:

```ruby
# This:
target: A { result = 1 } B

# Is equivalent to:
target: A @1 B
@1: /* empty */ { result = 1 }
```

### Limitations

Embedded actions add states to the parser, which can:
- Increase parser size
- Create additional conflicts
- Affect performance

Use them judiciously for clarity, but prefer end-of-rule actions when possible.

## Token Symbol Conversion

By default, Racc uses symbols for unquoted tokens and strings for quoted tokens. You can customize this.

### Default Behavior

```ruby
# Grammar:
rule
  statement: IDENT '=' NUMBER
end

# Lexer must produce:
[:IDENT, "x"]      # Unquoted -> symbol
['=', '=']         # Quoted -> string
[:NUMBER, 42]      # Unquoted -> symbol
```

### Custom Token Symbols

Use the `convert` block to change token representations:

```ruby
convert
  PLUS  'PlusClass'
  MINUS 'MinusClass'
  IF    'IfKeyword'
end
```

Now the lexer should produce:

```ruby
[PlusClass, '+']
[MinusClass, '-']
[IfKeyword, 'if']
```

### String Tokens

To use strings as token symbols, quote carefully:

```ruby
convert
  PLUS  '"plus"'              # Token symbol is "plus"
  MINUS '"minus\n"'           # Token symbol is "minus\n"
  IDENT "\"id_#{val}\""       # Token symbol is "id_#{val}"
end
```

### Why Use Custom Tokens?

1. Integrating existing lexers that use different token representations
2. Type-safe tokens using classes instead of symbols
3. Rich token objects with metadata

### Example: Token Classes

```ruby
# Grammar:
convert
  NUMBER 'NumberToken'
  IDENT  'IdentToken'
end

# Lexer:
class NumberToken
  attr_reader :value
  def initialize(value)
    @value = value
  end
end

class IdentToken
  attr_reader :name
  def initialize(name)
    @name = name
  end
end

def tokenize(input)
  tokens = []
  # ...
  tokens << [NumberToken, NumberToken.new(42)]
  tokens << [IdentToken, IdentToken.new("x")]
  tokens
end
```

### Restrictions

Cannot use `false` or `nil` as token symbols - they cause parse errors.

## Performance Optimization

### Optimization Strategies

#### 1. Use the C Extension

Ensure `cparse.so` is available:

```ruby
require 'racc/parser'  # Automatically loads C extension if available
```

Speed improvement: 2-5x faster than pure Ruby.

#### 2. Avoid `-E` Embedded Mode in Production

```bash
# Development/distribution:
racc -E grammar.y    # Slower, standalone

# Production (if runtime available):
racc grammar.y       # Faster, uses C extension
```

#### 3. Optimize Actions

```ruby
# Slow - creates unnecessary arrays:
expression: term '+' term
  {
    temp = []
    temp << val[0]
    temp << val[2]
    result = temp[0] + temp[1]
  }

# Fast - direct computation:
expression: term '+' term
  {
    result = val[0] + val[2]
  }
```

#### 4. Use `options omit_action_call`

```ruby
options omit_action_call

rule
  # Empty actions don't generate method calls
  statement: expression
end
```

#### 5. Optimize the Lexer

The lexer is often the bottleneck:

```ruby
# Slow - repeated string matching:
def tokenize(input)
  tokens = []
  while !input.empty?
    if input =~ /\A\d+/
      tokens << [:NUMBER, $&.to_i]
      input = $'
    elsif input =~ /\A[a-z]+/
      # ...
    end
  end
  tokens
end

# Fast - use StringScanner:
require 'strscan'

def tokenize(input)
  ss = StringScanner.new(input)
  tokens = []
  until ss.eos?
    case
    when ss.scan(/\d+/)
      tokens << [:NUMBER, ss.matched.to_i]
    when ss.scan(/[a-z]+/)
      tokens << [:IDENT, ss.matched]
    when ss.scan(/\s+/)
      # skip
    end
  end
  tokens
end
```

#### 6. Minimize Parser Size

- Fewer rules = smaller state machine
- Simpler grammar = faster parsing
- Avoid excessive embedded actions

### Profiling

Profile to find bottlenecks:

```ruby
require 'ruby-prof'

RubyProf.start
parser.parse(large_input)
result = RubyProf.stop

printer = RubyProf::GraphPrinter.new(result)
printer.print(STDOUT, {})
```

Usually shows lexer is the bottleneck, not the parser.

## Grammar Design Patterns

### Pattern 1: Lists

Comma-separated list:

```ruby
list: element
    | list ',' element
```

List with optional trailing comma:

```ruby
list: elements
    | elements ','

elements: element
        | elements ',' element
```

Zero-or-more items:

```ruby
list: /* empty */
    | list element
```

### Pattern 2: Optional Elements

```ruby
optional_else: /* empty */
             | ELSE statements
```

Or with better naming:

```ruby
else_clause: /* empty */ { result = nil }
           | ELSE statements { result = val[1] }
```

### Pattern 3: Repetition

One or more:

```ruby
statements: statement
          | statements statement
```

Zero or more:

```ruby
statements: /* empty */
          | statements statement
```

### Pattern 4: Grouping with Parentheses

```ruby
primary: NUMBER
       | IDENT
       | '(' expression ')'
```

### Pattern 5: Block Structures

```ruby
block: BEGIN statements END
     | BEGIN END

statements: statement
          | statements statement
```

### Pattern 6: Operator Chains

```ruby
# Comparison chains: a < b < c
comparisons: expression relop expression
           | comparisons relop expression

relop: '<' | '>' | '<=' | '>='
```

## Integration with Lexers

### Racc + Rexical

Rexical is a lexer generator for Ruby that works well with Racc.

Rexical specification (calc.rex):

```ruby
class Calculator
macro
  BLANK  /\s+/
  DIGIT  /\d+/

rule
  {BLANK}  # ignore
  {DIGIT}  { [:NUMBER, text.to_i] }
  /\+/     { [:PLUS, text] }
  /\*/     { [:MULT, text] }
end
```

Racc grammar (calc.y):

```ruby
class Calculator
rule
  exp: exp '+' exp { result = val[0] + val[2] }
     | exp '*' exp { result = val[0] * val[2] }
     | NUMBER
end

---- header
  require_relative 'calc.rex.rb'

---- inner
  def parse(input)
    scan_str(input)
  end
```

Generate both:

```bash
rex calc.rex -o calc.rex.rb
racc calc.y -o calc.y.rb
```

### Racc + StringScanner

For custom lexers without Rexical:

```ruby
require 'strscan'

class MyParser
  def parse(input)
    @ss = StringScanner.new(input)
    do_parse
  end

  def next_token
    return [false, '$'] if @ss.eos?

    case
    when @ss.scan(/\s+/)
      next_token  # Skip whitespace, get next token
    when @ss.scan(/\d+/)
      [:NUMBER, @ss.matched.to_i]
    when @ss.scan(/[+\-*\/]/)
      [@ss.matched, @ss.matched]
    when @ss.scan(/\w+/)
      [:IDENT, @ss.matched]
    else
      raise "Unexpected character: #{@ss.getch}"
    end
  end
end
```

## Runtime Options

### Parser Generation Options

Set in grammar file:

```ruby
options omit_action_call result_var
```

Available options:

- `omit_action_call` / `no_omit_action_call`: Optimize empty actions
- `result_var` / `no_result_var`: Use `result` variable in actions

### Runtime Debugging

Enable at runtime:

```ruby
parser = MyParser.new
parser.instance_variable_set(:@yydebug, true)
parser.instance_variable_set(:@racc_debug_out, STDERR)
```

### Custom Parser State

Track custom state in instance variables:

```ruby
class MyParser
  def initialize
    @symbol_table = {}
    @scope_depth = 0
  end

  # Use @symbol_table and @scope_depth in actions
end
```

## Advanced Error Handling

### Multiple Error Collection

```ruby
class MyParser
  def initialize
    @errors = []
  end

  def parse(input)
    @errors.clear
    result = do_parse
    raise ParseError, @errors.join("\n") unless @errors.empty?
    result
  end

  def on_error(token_id, value, value_stack)
    @errors << "Error at #{token_to_str(token_id)}: #{value}"
    # Don't raise - let error recovery continue
  end
end
```

### Context-Aware Errors

```ruby
def on_error(token_id, value, value_stack)
  context = value_stack.last(3).map(&:inspect).join(" ")
  raise ParseError, "Expected #{expected_tokens.join(' or ')} " \
                    "after #{context}, got #{token_to_str(token_id)}"
end
```

## Summary

Advanced Racc features enable:

1. Precedence - Clean, unambiguous expression grammars
2. Error Recovery - Robust parsers that report multiple errors
3. Embedded Actions - Fine-grained semantic control
4. Token Conversion - Integration with existing lexers
5. Optimization - Fast parsing with proper techniques

Master these techniques to build production-quality parsers for complex languages.
