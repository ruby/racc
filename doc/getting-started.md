# Getting Started with Racc

This guide will walk you through creating your first parser with Racc, from basic concepts to a working calculator.

## Prerequisites

- Basic understanding of Ruby
- Ruby 1.6 or later installed
- Racc installed (included with Ruby 1.8+, or install via `gem install racc`)

## Understanding the Basics

### What is a Parser?

A parser analyzes input according to grammar rules and extracts structure and meaning. Racc generates parser classes from grammar specifications, similar to how yacc generates C parsers.

### The Parsing Process

Parsing typically happens in two stages:

1. Lexical Analysis (Tokenization): Breaking input into tokens
2. Syntax Analysis (Parsing): Recognizing patterns in token sequences

### Tokens: The Building Blocks

A token is a pair: `[symbol, value]`

- Symbol: The token type (e.g., `:NUMBER`, `:PLUS`, `:IDENT`)
- Value: The actual data (e.g., `42`, `"+"`, `"variable_name"`)

Convention:
- Terminal symbols (tokens): UPPERCASE
- Non-terminal symbols (grammar constructs): lowercase

## Your First Grammar: A Simple Calculator

Let's build a calculator that handles basic arithmetic: addition, subtraction, multiplication, and division.

### Step 1: Create the Lexer

First, we need a lexer to convert input strings into tokens. Create `test_language.rex`:

```ruby
class TestLanguage
macro
  BLANK     [\ \t]+
  NUMBER    \d+
  ADD       \+
  SUBTRACT  \-
  MULTIPLY  \*
  DIVIDE    \/

rule
  {BLANK}      # no action (ignore whitespace)
  {NUMBER}     { [:NUMBER, text.to_i] }
  {ADD}        { [:ADD, text] }
  {SUBTRACT}   { [:SUBTRACT, text] }
  {MULTIPLY}   { [:MULTIPLY, text] }
  {DIVIDE}     { [:DIVIDE, text] }

inner
  def tokenize(code)
    scan_setup(code)
    tokens = []
    while token = next_token
      tokens << token
    end
    tokens
  end
end
```

Generate the lexer:

```bash
rex test_language.rex -o lexer.rb
```

### Step 2: Create the Grammar File

Create `test_language.y`:

```ruby
class TestLanguage
rule
  expression : NUMBER
             | NUMBER ADD NUMBER       { result = val[0] + val[2] }
             | NUMBER SUBTRACT NUMBER  { result = val[0] - val[2] }
             | NUMBER MULTIPLY NUMBER  { result = val[0] * val[2] }
             | NUMBER DIVIDE NUMBER    { result = val[0] / val[2] }
end

---- header
  require_relative 'lexer'

---- inner
  def parse(input)
    scan_str(input)
  end
```

### Step 3: Generate the Parser

```bash
racc test_language.y -o parser.rb
```

### Step 4: Test Your Parser

Create a test file `test_parser.rb`:

```ruby
require './parser'

parser = TestLanguage.new

# Test basic operations
puts parser.parse("2 + 2")    # => 4
puts parser.parse("10 - 3")   # => 7
puts parser.parse("4 * 5")    # => 20
puts parser.parse("15 / 3")   # => 5
```

## Understanding the Grammar Syntax

### Rule Structure

```ruby
rule
  target: SYMBOL another_symbol
        | SYMBOL different_symbol
        | SYMBOL
end
```

- target: Non-terminal symbol (left-hand side)
- |: Alternative productions (OR)
- SYMBOL: Terminal or non-terminal symbols
- { ... }: Actions (Ruby code)

### Actions

Actions are Ruby code blocks that execute when a rule matches:

```ruby
expression: NUMBER '+' NUMBER { result = val[0] + val[2] }
```

Special Variables in Actions:

- `result`: The return value (similar to `$$` in yacc). Default is `val[0]`
- `val`: Array of right-hand side values (similar to `$1, $2, $3...` in yacc)
- `_values`: The value stack (do not modify unless you know what you're doing)

Example:

```ruby
expression: term '+' term { result = val[0] + val[2] }
#           val[0]   val[1]  val[2]
```

### Empty Productions

Use empty productions for optional elements:

```ruby
optional_else: ELSE statements
             |                    # empty - else clause is optional
```

## Building a Better Calculator

The simple calculator above can only handle single operations. Let's improve it to handle complex expressions with proper precedence.

### Enhanced Grammar with Precedence

Create `calculator.y`:

```ruby
class Calculator
  prechigh
    nonassoc UMINUS
    left '*' '/'
    left '+' '-'
  preclow

rule
  target: expression

  expression: expression '+' expression { result = val[0] + val[2] }
            | expression '-' expression { result = val[0] - val[2] }
            | expression '*' expression { result = val[0] * val[2] }
            | expression '/' expression { result = val[0] / val[2] }
            | '(' expression ')'        { result = val[1] }
            | '-' expression =UMINUS    { result = -val[1] }
            | NUMBER
end

---- header
  require_relative 'calc_lexer'

---- inner
  def parse(input)
    scan_str(input)
  end
```

This grammar now supports:
- Multiple operations in one expression
- Parentheses for grouping
- Unary minus
- Proper operator precedence

## User Code Blocks

Racc grammar files support three user code blocks:

### header

Code placed before the class definition (for require statements):

```ruby
---- header
  require 'strscan'
  require_relative 'lexer'
```

### inner

Code placed inside the class definition (for methods):

```ruby
---- inner
  def parse(input)
    @tokens = tokenize(input)
    do_parse
  end

  def next_token
    @tokens.shift
  end
```

### footer

Code placed after the class definition (for helper classes):

```ruby
---- footer
  class Token
    attr_accessor :type, :value
  end
```

## Implementing Token Feeding

Racc supports two methods for feeding tokens to the parser:

### Method 1: Using `do_parse` and `next_token`

```ruby
---- inner
  def parse(input)
    @tokens = [
      [:NUMBER, 1],
      [:ADD, '+'],
      [:NUMBER, 2],
      [false, '$']  # End of input marker
    ]
    do_parse
  end

  def next_token
    @tokens.shift
  end
```

The `next_token` method must:
- Return `[symbol, value]` for each token
- Return `[false, anything]` or `nil` when input is exhausted

### Method 2: Using `yyparse` with yield

```ruby
def parse(input, scanner)
  yyparse(scanner, :scan_tokens)
end

# In scanner object:
def scan_tokens
  until end_of_file
    # Process and yield each token
    yield [:NUMBER, 42]
    yield [:ADD, '+']
  end
  yield [false, '$']  # End marker
end
```

## Writing the Scanner

While you can write scanners manually in Ruby, the `strscan` library (included with Ruby 1.8+) provides efficient scanning:

```ruby
require 'strscan'

class MyScanner
  def initialize(input)
    @ss = StringScanner.new(input)
  end

  def tokenize
    tokens = []
    until @ss.eos?
      case
      when @ss.scan(/\s+/)
        # Skip whitespace
      when text = @ss.scan(/\d+/)
        tokens << [:NUMBER, text.to_i]
      when text = @ss.scan(/[+\-*\/]/)
        tokens << [text, text]
      end
    end
    tokens << [false, '$']
    tokens
  end
end
```

## Next Steps

Now that you understand the basics:

1. Read the [Grammar Reference](grammar-reference.md) for complete syntax details
2. Learn about [operator precedence](advanced-topics.md#operator-precedence)
3. Explore [error recovery](advanced-topics.md#error-recovery) mechanisms
4. Study the [Parser Class Reference](parser-class-reference.md) for available methods
5. Review [Debugging](debugging.md) techniques for troubleshooting

## Common Pitfalls

1. Forgetting the end-of-input marker: Always return `[false, anything]` when tokens are exhausted
2. Incorrect token format: Tokens must always be `[symbol, value]` pairs
3. Modifying the value stack: Don't modify `_values` unless you understand the internals
4. Off-by-one errors: Remember `val` is zero-indexed (`val[0]`, not `val[1]` for the first element)
5. Not handling whitespace: Lexers must explicitly handle or ignore whitespace

## Example: Complete Working Parser

Here's a complete, working example that ties everything together:

```ruby
# file: simple_calc.y
class SimpleCalc
rule
  target: exp

  exp: exp '+' exp { result = val[0] + val[2] }
     | exp '-' exp { result = val[0] - val[2] }
     | NUMBER
end

---- inner
  def parse(str)
    @q = []
    until str.empty?
      case str
      when /\A\s+/
        # Skip whitespace
      when /\A\d+/
        @q.push [:NUMBER, $&.to_i]
      when /\A.{1}/
        @q.push [$&, $&]
      end
      str = $'
    end
    @q.push [false, '$']
    do_parse
  end

  def next_token
    @q.shift
  end
```

Generate and use:

```bash
racc simple_calc.y -o simple_calc.rb
ruby -r ./simple_calc -e "puts SimpleCalc.new.parse('1 + 2 + 3')"  # => 6
```

---

Continue to [Grammar Reference](grammar-reference.md) for detailed grammar syntax documentation.
