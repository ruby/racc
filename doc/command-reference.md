# Racc Command Reference

Complete reference for the `racc` command-line tool.

## Synopsis

```bash
racc [options] grammarfile
```

## Basic Usage

Generate a parser from a grammar file:

```bash
racc mygrammar.y
```

This creates `mygrammar.tab.rb` by default.

## Options

### Output Control

#### `-o FILENAME`, `--output-file=FILENAME`

Specify the output filename:

```bash
racc calc.y -o calculator.rb
```

Default: `<grammarfile>.tab.rb`

#### `-O FILENAME`, `--log-file=FILENAME`

Specify the log file name (used with `-v`):

```bash
racc calc.y -v -O calc.log
```

Default: `<grammarfile>.output`

### Code Generation Options

#### `-E`, `--embedded`

Generate a standalone parser with embedded runtime:

```bash
racc mygrammar.y -E -o standalone_parser.rb
```

Use case: When distributing parsers to environments without the Racc runtime installed.

Note: The generated file will be larger, and the C extension (`cparse.so`) cannot be used, resulting in slower parsing.

#### `-F`, `--frozen`

Add `frozen_string_literal: true` magic comment:

```bash
racc mygrammar.y -F
```

Generates:

```ruby
# frozen_string_literal: true
class MyParser < Racc::Parser
  # ...
end
```

#### `-e RUBYPATH`, `--executable=RUBYPATH`

Generate an executable parser with shebang:

```bash
racc calc.y -e /usr/bin/ruby
```

To use the current Ruby interpreter:

```bash
racc calc.y -e ruby
```

Generates:

```ruby
#!/usr/bin/ruby
# Parser code...
```

Don't forget to make it executable:

```bash
chmod +x calc.tab.rb
```

### Line Number Conversion

#### `-l`, `--no-line-convert`

Disable line number conversion:

```bash
racc mygrammar.y -l
```

Background: By default, Racc converts line numbers in error messages to refer to the grammar file rather than the generated parser. This option disables that conversion.

Use case: When debugging issues in Ruby 1.4.3 or earlier, which had bugs with constant references.

#### `-c`, `--line-convert-all`

Convert line numbers for `header` and `footer` blocks in addition to actions and `inner`:

```bash
racc mygrammar.y -c
```

Warning: Don't use this if your header and footer blocks are concatenated from multiple sources.

### Action Generation

#### `-a`, `--no-omit-actions`

Generate method definitions and calls for all actions, even empty ones:

```bash
racc mygrammar.y -a
```

Default: Racc omits method calls for empty actions to improve performance.

### Debugging and Information

#### `-v`, `--verbose`

Output detailed parsing information to a log file:

```bash
racc calc.y -v
```

Generates `calc.output` with:
- State transition table
- Shift/reduce conflicts
- Reduce/reduce conflicts
- Detailed state information

Example output:

```
State 0

    0:  $start -> . target $end

    NUMBER    shift, goto 1
    target    goto 2

State 1

    3:  target -> NUMBER .

    $end    reduce using rule 3 (target -> NUMBER)
```

#### `-g`, `--debug`

Generate parser with debugging code:

```bash
racc calc.y -g -o calc.rb
```

To use debug output:

```ruby
parser = Calculator.new
parser.instance_variable_set(:@yydebug, true)
result = parser.parse(input)
```

Note: Using `-g` alone doesn't enable debugging; you must also set `@yydebug = true` at runtime.

Debug output shows:
- Token shifts
- Rule reductions
- State transitions
- Value stack contents

#### `-S`, `--output-status`

Output progress information during generation:

```bash
racc mygrammar.y -S
```

Shows real-time progress:

```
Parsing grammar file...
Calculating states...
Resolving conflicts...
Generating parser...
Done.
```

### Validation

#### `-C`, `--check-only`

Check grammar syntax without generating a parser:

```bash
racc mygrammar.y -C
```

Use case: Quick validation during grammar development.

### Information

#### `--version`

Display Racc version:

```bash
racc --version
```

#### `--copyright`

Display copyright information:

```bash
racc --copyright
```

#### `--help`

Display brief option summary:

```bash
racc --help
```

## Common Workflows

### Development Workflow

During grammar development, use verbose mode to understand conflicts:

```bash
racc -v calc.y
cat calc.output  # Review state transitions
```

Enable debugging for runtime troubleshooting:

```bash
racc -g calc.y -o calc.rb
```

### Distribution Workflow

For distribution to environments with Racc runtime (Ruby 1.8+):

```bash
racc mygrammar.y -o myparser.rb
```

For standalone distribution (no runtime required):

```bash
racc -E mygrammar.y -o myparser.rb
```

### Production Workflow

Generate optimized, frozen parser:

```bash
racc -F mygrammar.y -o myparser.rb
```

## Examples

### Example 1: Basic Parser Generation

```bash
racc calculator.y
# Generates: calculator.tab.rb
```

### Example 2: Custom Output Name

```bash
racc calculator.y -o calc_parser.rb
```

### Example 3: Debugging Shift/Reduce Conflicts

```bash
racc calculator.y -v
less calculator.output  # Review conflicts
```

### Example 4: Standalone Parser

```bash
racc calculator.y -E -o standalone_calc.rb
# No racc runtime required to use standalone_calc.rb
```

### Example 5: Executable Parser

```bash
racc calculator.y -e ruby -o calc
chmod +x calc
./calc input.txt
```

### Example 6: Full Debug Setup

```bash
racc -g -v calculator.y -o calc.rb
```

Then in your code:

```ruby
require './calc'

parser = Calculator.new
parser.instance_variable_set(:@yydebug, true)

# This will print detailed debug output
result = parser.parse("2 + 3 * 4")
```

### Example 7: Grammar Validation Only

```bash
racc -C mygrammar.y
# Checks syntax, doesn't generate parser
```

### Example 8: Frozen String Literal Parser

```bash
racc -F calculator.y -o calc.rb
```

## Understanding Conflicts

When Racc reports conflicts:

```
5 shift/reduce conflicts
```

Use `-v` to generate a detailed report:

```bash
racc -v grammar.y
```

Then examine `grammar.output`:

```
State 42

    15: exp -> exp . '+' exp
    15: exp -> exp . '-' exp
    16: exp -> exp '+' exp .

    '*'    shift, goto 8
    '+'    shift, goto 9
    '-'    shift, goto 10
    $end   reduce using rule 16 (exp -> exp '+' exp)

    '*': shift/reduce conflict (shift 8, reduce 16)
```

This helps identify where to add precedence declarations.

## Error Messages

### Common Errors

"syntax error"
- Grammar file has syntax errors
- Check the line number indicated
- Common causes: unmatched braces, missing colons

"token X is declared but not used"
- Token declared but never appears in grammar
- Warning only, not fatal

"token X is used but not declared"
- Token used in grammar but not declared with `token` directive
- Warning only, not fatal

"X shift/reduce conflicts"
- Grammar has ambiguities
- Use `-v` to investigate
- Consider adding precedence declarations or using `expect`

"X reduce/reduce conflicts"
- Serious grammar ambiguity
- Grammar may need restructuring
- Cannot be suppressed with `expect`

## Performance Considerations

### Generation Performance

- Larger grammars take longer to process
- Use `-S` to monitor progress on large grammars

### Runtime Performance

- Fastest: Normal mode (uses `cparse.so` if available)
- Slower: `-E` embedded mode (pure Ruby, no C extension)
- Slowest: Debug mode with `@yydebug = true`

## Environment Variables

Racc does not use any special environment variables. Ruby's standard environment variables apply:

- `RUBYLIB` - Additional load paths
- `RUBYOPT` - Default Ruby options

## Exit Status

- 0: Success
- 1: Error (syntax error, file not found, etc.)

## Files

### Input File

- Grammar file: `.y` extension by convention (not required)

### Output Files

- Parser file: `.tab.rb` by default, or specified with `-o`
- Log file: `.output` with `-v`, or specified with `-O`

## Notes

### Ruby Version Compatibility

- Ruby 1.6: Supported, use `-E` for standalone parsers
- Ruby 1.7: Supported
- Ruby 1.8+: Recommended, includes runtime by default
- Ruby 1.9+: Fully supported
- Ruby 2.x+: Fully supported
- Ruby 3.x+: Fully supported with `-F` for frozen strings

### File Naming Conventions

While not required, these conventions are recommended:

- Grammar files: `.y` extension (e.g., `calc.y`)
- Generated parsers: `_parser.rb` suffix (e.g., `calc_parser.rb`)
- Log files: `.output` extension (e.g., `calc.output`)

### Integration with Build Systems

#### Makefile

```makefile
%.rb: %.y
	racc -o $@ $<

calc_parser.rb: calc.y
	racc -o calc_parser.rb calc.y
```

#### Rake

```ruby
desc "Generate parser"
task :parser do
  sh "racc calc.y -o calc_parser.rb"
end
```

#### Bundler/Gem

In your gemspec:

```ruby
Gem::Specification.new do |s|
  s.extensions = ['ext/extconf.rb']
  # Add parser generation to build process
end
```

---

For detailed grammar syntax, see [Grammar Reference](grammar-reference.md).
