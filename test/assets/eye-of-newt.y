class EyeOfNewt::Parser
token WORD NUMBER UNIT TEXT OF OR A TO_TASTE UNIT_MODIFIER
rule
  ingredient
    : quantity ingredient_names style note
    | quantity ingredient_names note
    | ingredient_names to_taste style note
    | ingredient_names to_taste note
    | ingredient_names style note
    | ingredient_names note
    | quantity ingredient_names style
    | quantity ingredient_names
    | ingredient_names to_taste style
    | ingredient_names to_taste
    | ingredient_names style
    | ingredient_names
    ;
  ingredient_names
    : ingredient_name OR ingredient_names
    | ingredient_name
    ;
  ingredient_name
    : ingredient_words { @ingredient.names << result }
    ;
  quantity
    : amount unit_modifier unit OF
    | amount unit_modifier unit
    | amount unit OF
    | amount unit
    | amount unit_modifier OF
    | amount unit_modifier
    | amount OF
    | amount
    | unit_modifier unit OF
    | unit_modifier unit
    | unit OF
    | unit
    ;
  amount
    : numerical_amount { @ingredient.amount = result }
    | numerical_range { @ingredient.amount = result }
    | A { @ingredient.amount = 1 }
    ;
  unit : UNIT { @ingredient.unit = to_unit(result) } ;
  to_taste : TO_TASTE { @ingredient.unit = to_unit(result) } ;
  style : ',' text { @ingredient.style = val[1] } ;
  note : '(' text ')' { @ingredient.note = val[1] } ;
  unit_modifier
    : UNIT_MODIFIER { @ingredient.unit_modifier = val[0] }
    | '(' text ')' { @ingredient.unit_modifier = val[1] }
    ;
  numerical_range
    : numerical_amount '-' numerical_amount { result = [val[0], val[2]] }
    | numerical_amount '–' numerical_amount { result = [val[0], val[2]] }
    ;
  numerical_amount
    : number
    | number fraction { result = val[0] + val[1] }
    | fraction
    | decimal
    ;
  ingredient_words
    : ingredient_word ingredient_words { result = val.join(' ') }
    | ingredient_word
    ;
  text : TEXT ;
  ingredient_word : WORD | A | OF | UNIT_MODIFIER ;
  number : NUMBER { result = val[0].to_i } ;
  fraction : NUMBER '/' NUMBER { result = val[0].to_f / val[2].to_f } ;
  decimal : NUMBER '.' NUMBER { result = val.join.to_f } ;
end

---- inner

  def initialize(tokenizer, units:, ingredient: nil)
    @tokenizer = tokenizer
    @units = units
    @ingredient = ingredient || default_ingredient
    super()
  end

  def next_token
    @tokenizer.next_token
  end

  def parse
    do_parse
    @ingredient
  rescue Racc::ParseError
    raise InvalidIngredient, @tokenizer.string
  end

  def to_unit(u)
    @units[u]
  end

  def default_ingredient
    EyeOfNewt::Ingredient.new(amount: 1, unit: @units.default)
  end
