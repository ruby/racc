This post follows from [Overview of rexical part 2](https://github.com/tenderlove/rexical/wiki/Overview-of-rexical-part-2). Taken from Jeff Nyman's [blog post](http://webcache.googleusercontent.com/search?q=cache:http://testerstories.com/2012/06/a-tester-learns-rex-and-racc-part-3/&num=1&strip=1&vwsrc=0).

# Combining rexical and racc

Assuming you’ve been following along, you’ve broken your input into a stream of tokens. Now you need some way to recognize higher-level patterns. This is where Racc comes in: Racc lets you describe what you want to do with those tokens. That’s what I’ll be covering here: how the parser works with the lexer.

You already know that you define a lexer specification with a rex file. This generates a lexer class. In a very similar fashion, you define a grammar with a racc file. This generates a parser class. If you want your own parser, you have to write grammar file. In the last post we started creating a new simple language to handle calculations of numbers. The language will consist of `ADD (+)`, `SUBTRACT (-)`, `MULTIPLY (*)`, and `DIVISION (/)`. Those operators are given as the symbol identifier as well as the actual symbol that maps to that identifier. The language also supports the notion of `DIGIT`. A `DIGIT` token must come before and after an operator. So there’s our language. Now we want to try to evaluate the code of this new language.

You have to create a grammar file. The first part of this file, as with the Rex specification file, is a class block. In your project directory, create a file called `test_language.y`. This will be our grammar file. As with the start of our Rex file, we’ll use our class:
``` ruby
class TestLanguage
 
end
```
Then you will have a grammar block. In Rex, the grammar block is a way to specify the patterns for specific symbols. In Racc, the grammar block describes grammar that can be understood by the parser. As with Rex specification files, we’ll eventually add a rule clause to signify our grammar block. In fact, this clause will mark the start of what are called the “production rules.” To fill in these rules, you have to understand the Racc grammar. So let’s just look at the basics before we try to fill in our nascent grammar file.

A grammar rule has the form:

```
some  :  THING  ;
```
The symbols produced by a lexer are called terminals or tokens. The things assembled from them are called non-terminals. So in this schematic, ‘some’ represents a non-terminal while ‘THING’ is a terminal. So ‘THING’ must have been produced by the lexer and ‘some’ can only be created by assembling it from terminals. Here’s an example:

```
value : DIGIT ;
```
This means a construct called a value (a non-terminal) can be built up from a DIGIT (a terminal). Here’s another example:

```
expression : value '+' value ;
```
Here an expression can be built up from two values (which we know are DIGITS) and a plus sign. You can specify alternatives as well:

```
expression : value '+' value | value '-' value ;
```
Some people like to space all this out for better readability:

```
expression
  :
    value '+' value
  | value '-' value
;
```
There’s a lot of terminology coming your way here so, for now, just understand that terminals are all the basic symbols or tokens of which a given language is composed. Non-terminals are the syntactic variables in the grammar which represent a set of strings that the grammar is composed of. The general style used is to have all terminals in uppercase and all non-terminals in lowercase.

As with Rex grammar, you can write actions inside curly braces. These actions are, once again, Ruby code. Since Racc needs tokens upon which to operate, Racc expects to call a method that yields tokens, where each token is a two element array with the first element being the type of token (matching the token declaration) and the second element the actual value of the token, which will usually be the actual text. This is a lot easier to show than talk about, although in reality it’s not so different from what you’ve seen with Rex files. So here’s an example:
```
expression : value '+' value { puts "Performing addition." }
```

But I could also do this:
```
expression : value '+' value { result = val[0] + val[2] }
```

If you ever read documentation on yacc, you’ll see mention of variables like `$$` and `$1` and so on. The equivalent of the above in yacc would be:
```
expression : value '+' value { $$ = $1 + $3; }
```

Here yacc’s `$$` is racc’s `result`, while yacc’s `$0`, `$1` would be the array `val`. Since Ruby is zero based, that’s why `$1` is `val[0]`. Okay, so let’s put this stuff to use. Change your grammar file so it looks like this:
``` ruby
class TestLanguage
  rule
    expression : DIGIT
    | DIGIT ADD DIGIT    { return val[0] + val[2] }
end
```
What I’m basically saying here is that something I want to call an “expression” can be recognized if it’s a `DIGIT` or a `DIGIT ADD DIGIT`. From the lexer file, we know that `DIGIT` is going to correspond to an array like this: `[:DIGIT, text.to_i]`. We know that `ADD` is going to correspond to an array like this `[:ADD, text]`. Further, we know that `DIGIT` means `\d+` (i.e., any group of numbers) and `ADD` means `\+` (i.e., the literal plus sign). I’m also saying that when `DIGIT` is encountered nothing should happen. There is no action provided for that. But if `DIGIT ADD DIGIT` is encountered, then I want a return value provided, which is the addition of the first `DIGIT` with the second `DIGIT`.

In order to compile this file, you can use the following command:
```
racc test_language.y -o parser.rb
```

To make that process more streamlined, let’s add a task to our Rakefile:
``` ruby
desc "Generate Parser"
task :parser do
  `racc test_language.y -o parser.rb`
end
```

Now you can just type `rake parser` to generate the parser just as you can type `rake lexer` to generate the lexer. In fact, you might always want to force both things to happen, in which case you can add this task:
``` ruby
desc "Generate Lexer and Parser"
task :generate => [:lexer, :parser]
```

So how do we test this? Let’s create a file in our spec directory called `language_parser_spec.rb` and add the following to it:
``` ruby
require './parser.rb'
 
class TestLanguageParser
  describe 'Testing the Parser' do
    before do
      @evaluator = TestLanguage.new
    end
    
    it 'tests for a digit' do
      @result = @evaluator.parse("2")
      @result.should == 2
    end
  end
end
```

Structurally you can see that this is similar to the test format we established in our `language_lexer_spec.rb` file. Running this test will tell you that there is no parse method. That’s true. Just as we added a tokenize method to our rex specification, we have to add a parse method to our grammar file. Here’s how you can do that:
``` ruby
class TestLanguage
rule
  expression : DIGIT
  | DIGIT ADD DIGIT   { return val[0] + val[2] }
end
 
---- inner
  def parse(input)
    scan_str(input)
  end
```

Once again, we use an inner section just as we did with our rex specification. Notice a few major differences here, though. First, you must preface the section with four hyphens (-). Also, notice that the inner section is **OUTSIDE** of the class block. This is different from the rex specification where the inner section was inside the class block. Make sure to regenerate your files and then run the test again. Now you will be told that the `scan_str` method is undefined. This method is defined in the lexer and so you have to add another section to your grammar file:
``` ruby
class TestLanguage
rule
  expression : DIGIT
  | DIGIT ADD DIGIT   { return val[0] + val[2] }
end
 
---- header
  require_relative 'lexer'
 
---- inner
  def parse(input)
    scan_str(input)
  end
```

If you regenerate and run your test, the parser test should pass. However, we have not made it do a calculation yet. So add the following test:
``` ruby
...
    it 'tests for addition' do
      @result = @evaluator.parse("2+2")
      @result.should == 4
    end
...
```

If that’s working for you, congratulations! You now have the start of a working language. Granted, it’s just a calculator example but let’s not leave it just doing addition. You can fill out the rest of the grammar file as such:

``` ruby
class TestLanguage
rule
  expression : DIGIT
  | DIGIT ADD DIGIT       { return val[0] + val[2] }
  | DIGIT SUBTRACT DIGIT  { return val[0] - val[2] }
  | DIGIT MULTIPLY DIGIT  { return val[0] * val[2] }
  | DIGIT DIVIDE DIGIT    { return val[0] / val[2] }
end
 
---- header
  require_relative 'lexer'
 
---- inner
  def parse(input)
    scan_str(input)
  end
```

I’ll leave it as an exercise to fill in the existing tests to prove that the grammar for all calculation types is being read and processed correctly.

This simple example still leaves a lot open. For example, while `2+2` will work `2 + 2` (with spaces) will not. This is because your lexer did not specify any white space and thus the parser does not know how to recognize it. Also, what about more complicated expressions? Can I do `2+2+2`? Try it and you’ll find that it does not. And even if I could support that, how would I handle operator precedence? For example would `2+3*2` give me `8`, as it should, or would it instead give me `10`?

Keep in mind that in order to solve problems like this, you have to account for how your grammar can be constructed. For example, to allow for spaces, you just have to indicate that (1) blank spaces are allowed and (2) that no action occurs when a blank space is matched. In fact, you’ve already seen this in prior examples here. Just add the following to your rex specification file (`test_language.rex`):
``` ruby
class TestLanguage
macro
  BLANK     [\ \t]+
  DIGIT     \d+
  ADD       \+
  SUBTRACT  \-
  MULTIPLY  \*
  DIVIDE    \/
 
rule
  {BLANK}      # no action
  {DIGIT}      { [:DIGIT, text.to_i] }
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

That simple bit of extra information allows your parser to handle `2 + 2` as well as it does `2+2`. The other problems are a little more involved. And with that, perhaps you can see now that even with a simple calculator, it takes some work to get it to do what you want in terms of a language. And yet all programming languages that you work with are ultimately constructed of grammar specified just in the way we have been doing it here.

I’ve learned a lot by trying to figure out how these tools work. One of my goals is to see if I can build an alternative to Gherkin, the language that is used by Cucumber to create what are called feature files. I think this will be a challenging exercise. Beyond that, I can see some good exercises here for constructing test grammars for test description languages. Playing around with concepts like these could, perhaps, lead to some interesting notions about how we communicate about tests.